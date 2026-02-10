//
//  AudioMixerService.swift
//  MeetingSonar
//
//  Real-time audio mixer for combining system audio and microphone input.
//  
//  v3.0 - Proper mixing with time-aligned buffers
//

import Foundation
import AVFoundation
import CoreMedia
import Accelerate

/// Protocol for receiving mixed audio samples
protocol AudioMixerDelegate: AnyObject {
    func audioMixer(_ mixer: AudioMixerService, didMixSampleBuffer sampleBuffer: CMSampleBuffer)
}

/// Service for mixing two audio streams in real-time
///
/// Combines system audio (from ScreenCaptureKit) and microphone audio
/// into a single mixed audio stream for recording.
final class AudioMixerService {

    // MARK: - Audio Constants

    /// Audio configuration constants
    enum AudioConstants {
        /// Standard sample rate for digital audio (48kHz)
        static let sampleRate: Double = 48000.0
        /// Target channel count (stereo)
        static let channelCount: Int = 2
        /// Mono channel count
        static let monoChannelCount: Int = 1
        /// Chunk duration in seconds (20ms)
        static let chunkDuration: TimeInterval = 0.020
        /// Frames per chunk (calculated: chunkDuration * sampleRate)
        static var framesPerChunk: Int { Int(chunkDuration * sampleRate) }
        /// Samples per chunk (calculated: framesPerChunk * channelCount)
        static var samplesPerChunk: Int { framesPerChunk * channelCount }
        /// Sample rate tolerance for resampling (Hz)
        static let sampleRateTolerance: Double = 100.0
        /// Maximum buffer duration (seconds)
        static let maxBufferDuration: TimeInterval = 1.0
    }

    /// Debug constants
    enum DebugConstants {
        /// Number of chunks to log at start
        static let initialChunkLogCount: Int = 5
    }

    /// Normalized audio range constants
    enum NormalizedRange {
        /// Minimum value for normalized float audio
        static let min: Float = -1.0
        /// Maximum value for normalized float audio
        static let max: Float = 1.0
        /// Maximum volume (full scale)
        static let maxVolume: Float = 1.0
    }

    // MARK: - Properties

    weak var delegate: AudioMixerDelegate?

    /// Volume level for system audio (0.0 - 1.0)
    var systemAudioVolume: Float = NormalizedRange.maxVolume

    /// Volume level for microphone audio (0.0 - 1.0)
    var microphoneVolume: Float = NormalizedRange.maxVolume

    /// Target sample rate for output
    private let targetSampleRate: Double = AudioConstants.sampleRate

    /// Target channel count for output
    private let targetChannelCount: Int = AudioConstants.channelCount

    /// Samples per mixing chunk (20ms at 48kHz = 960 frames = 1920 samples for stereo)
    private let framesPerChunk: Int = AudioConstants.framesPerChunk
    private var samplesPerChunk: Int { AudioConstants.samplesPerChunk }
    
    /// Whether mixing is active
    private(set) var isActive = false
    
    /// Whether mixing is paused (v0.2)
    private(set) var isPaused = false
    
    /// Processing queue for thread safety
    private let processingQueue = DispatchQueue(label: "com.meetingsonar.audiomixer", qos: .userInteractive)
    
    /// Circular buffers for each source (in target format: 48kHz stereo float)
    private var systemBuffer: [Float] = []
    private var micBuffer: [Float] = []
    
    /// Lock for thread-safe buffer access
    private let bufferLock = NSLock()
    
    /// Output format description
    private var outputFormatDescription: CMAudioFormatDescription?
    
    /// Frame counter for continuous timestamps (in frames, not samples)
    private var frameCounter: Int64 = 0
    
    /// Mixing timer
    private var mixTimer: DispatchSourceTimer?
    
    /// Statistics
    private var totalChunksOutput: Int = 0
    private var systemBuffersReceived: Int = 0
    private var micBuffersReceived: Int = 0

    /// Debug
    private var debugLogEnabled = true

    // MARK: - Dynamic Source Management (v1.0 - Recording Scenario Optimization)

    /// 系统音频启用状态
    /// 用于控制是否处理系统音频输入
    private(set) var isSystemAudioEnabled: Bool = true

    /// 麦克风启用状态
    /// 用于控制是否处理麦克风输入
    private(set) var isMicrophoneEnabled: Bool = true
    
    // MARK: - Initialization
    
    init() {
        setupOutputFormat()
    }
    
    // MARK: - Setup
    
    private func setupOutputFormat() {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: targetSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size * targetChannelCount),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size * targetChannelCount),
            mChannelsPerFrame: UInt32(targetChannelCount),
            mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
            mReserved: 0
        )
        
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &outputFormatDescription
        )
    }
    
    // MARK: - Public Methods
    
    func start() {
        guard !isActive else { return }
        isActive = true
        frameCounter = 0
        totalChunksOutput = 0
        systemBuffersReceived = 0
        micBuffersReceived = 0
        
        bufferLock.lock()
        systemBuffer.removeAll()
        micBuffer.removeAll()
        bufferLock.unlock()
        
        // Start mixing timer (fires every 20ms to output mixed audio)
        mixTimer = DispatchSource.makeTimerSource(queue: processingQueue)
        mixTimer?.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(20))
        mixTimer?.setEventHandler { [weak self] in
            self?.outputMixedChunk()
        }
        mixTimer?.resume()

        LoggerService.shared.log(category: .audio, level: .debug, message: "[AudioMixerService] Started - Target: \(Int(targetSampleRate))Hz, \(targetChannelCount)ch, \(framesPerChunk) frames/chunk")
    }
    
    func stop() {
        guard isActive else { return }

        // CRITICAL FIX: If timer is suspended (paused), it MUST be resumed before cancellation/release
        // otherwise it causes a crash (EXC_BREAKPOINT)
        // Additionally, we must guard against nil timer to prevent crashes
        guard let timer = mixTimer else {
            // Timer is nil, just update state and return
            isActive = false
            isPaused = false
            return
        }

        if isPaused {
            timer.resume()
        }

        isActive = false
        isPaused = false

        timer.cancel()
        mixTimer = nil
        
        // Output any remaining data
        outputMixedChunk()
        
        bufferLock.lock()
        systemBuffer.removeAll()
        micBuffer.removeAll()
        bufferLock.unlock()

        let durationSec = Double(frameCounter) / targetSampleRate
        LoggerService.shared.log(category: .audio, level: .debug, message: "[AudioMixerService] Stopped - Chunks output: \(totalChunksOutput)")
        LoggerService.shared.log(category: .audio, level: .debug, message: "[AudioMixerService] System buffers: \(systemBuffersReceived), Mic buffers: \(micBuffersReceived)")
        LoggerService.shared.log(category: .audio, level: .debug, message: "[AudioMixerService] Total frames: \(frameCounter), Duration: \(String(format: "%.2f", durationSec))s")
    }

    /// Pause mixing (v0.2 - for sleep/lock events)
    func pause() {
        guard isActive, !isPaused else { return }
        isPaused = true

        // Suspend the mix timer
        mixTimer?.suspend()

        // Clear buffers to prevent stale audio when resuming
        bufferLock.lock()
        systemBuffer.removeAll()
        micBuffer.removeAll()
        bufferLock.unlock()

        LoggerService.shared.log(category: .audio, level: .debug, message: "[AudioMixerService] Paused")
    }

    /// Resume mixing (v0.2 - after sleep/lock)
    func resume() {
        guard isActive, isPaused else { return }
        isPaused = false

        // Resume the mix timer
        mixTimer?.resume()

        LoggerService.shared.log(category: .audio, level: .debug, message: "[AudioMixerService] Resumed")
    }
    
    // MARK: - Dynamic Source Control (v1.0 - Recording Scenario Optimization)

    /// 设置系统音频启用状态
    /// - Parameter enabled: 是否启用
    /// - Note: 当禁用时，Mixer 会继续输出静音数据以保持时间连续性
    ///
    /// 为什么需要保持输出：
    /// 如果 Mixer 停止输出，AVAssetWriter 会停止接收数据，
    /// 导致录音文件在切换点出现时间跳跃或损坏
    func setSystemAudioEnabled(_ enabled: Bool) {
        processingQueue.async { [weak self] in
            self?.isSystemAudioEnabled = enabled

            if !enabled {
                // Clear system audio buffer to avoid residual audio
                // This prevents playing cached audio when re-enabled
                self?.bufferLock.lock()
                self?.systemBuffer.removeAll()
                self?.bufferLock.unlock()
            }

            LoggerService.shared.log(
                category: .audio,
                message: "[AudioMixerService] System audio \(enabled ? "enabled" : "disabled")"
            )
        }
    }

    /// 设置麦克风启用状态
    /// - Parameter enabled: 是否启用
    func setMicrophoneEnabled(_ enabled: Bool) {
        processingQueue.async { [weak self] in
            self?.isMicrophoneEnabled = enabled

            if !enabled {
                // Clear microphone buffer
                self?.bufferLock.lock()
                self?.micBuffer.removeAll()
                self?.bufferLock.unlock()
            }

            LoggerService.shared.log(
                category: .audio,
                message: "[AudioMixerService] Microphone \(enabled ? "enabled" : "disabled")"
            )
        }
    }

    /// Add system audio samples to the mixer
    /// - Parameter sampleBuffer: System audio sample buffer
    /// - Note: If system audio is disabled, this method returns immediately without processing
    func addSystemAudioSamples(_ sampleBuffer: CMSampleBuffer) {
        // Check service state and individual audio source enabled state
        guard isActive, !isPaused, isSystemAudioEnabled else { return }

        processingQueue.async { [weak self] in
            self?.processInput(sampleBuffer: sampleBuffer, isSystemAudio: true)
        }
    }

    /// Add microphone audio samples to the mixer
    /// - Parameter sampleBuffer: Microphone audio sample buffer
    /// - Note: If microphone is disabled, this method returns immediately without processing
    func addMicrophoneSamples(_ sampleBuffer: CMSampleBuffer) {
        // Check service state and individual audio source enabled state
        guard isActive, !isPaused, isMicrophoneEnabled else { return }

        processingQueue.async { [weak self] in
            self?.processInput(sampleBuffer: sampleBuffer, isSystemAudio: false)
        }
    }
    
    // MARK: - Private Methods
    
    /// Process incoming audio and add to appropriate buffer
    private func processInput(sampleBuffer: CMSampleBuffer, isSystemAudio: Bool) {
        let source = isSystemAudio ? "System" : "Mic"

        // Extract audio data
        do {
            let (samples, sourceRate, sourceChannels) = try extractAudioData(from: sampleBuffer)
            processExtractedAudio(samples, sourceRate: sourceRate, sourceChannels: sourceChannels, isSystemAudio: isSystemAudio)
        } catch {
            // CRITICAL FIX: Log the error instead of silently failing
            // This helps diagnose format compatibility issues
            LoggerService.shared.log(category: .audio, level: .warning, message: "[AudioMixerService] Failed to extract \(source) audio data: \(error.localizedDescription)")
            // Continue processing - don't stop the entire mixing pipeline
        }
    }

    /// Process extracted audio data
    private func processExtractedAudio(_ samples: [Float], sourceRate: Double, sourceChannels: Int, isSystemAudio: Bool) {
        let source = isSystemAudio ? "System" : "Mic"

        // Convert to target format (48kHz stereo)
        var processedSamples = samples
        
        // Resample if needed
        if abs(sourceRate - targetSampleRate) > AudioConstants.sampleRateTolerance {
            processedSamples = resample(samples, fromRate: sourceRate, toRate: targetSampleRate, channels: sourceChannels)
        }

        // Convert mono to stereo if needed
        if sourceChannels == AudioConstants.monoChannelCount && targetChannelCount == AudioConstants.channelCount {
            processedSamples = monoToStereo(processedSamples)
        }

        // Apply volume
        let volume = isSystemAudio ? systemAudioVolume : microphoneVolume
        if volume != NormalizedRange.maxVolume {
            var vol = volume
            vDSP_vsmul(processedSamples, 1, &vol, &processedSamples, 1, vDSP_Length(processedSamples.count))
        }

        // Add to buffer
        bufferLock.lock()
        if isSystemAudio {
            systemBuffer.append(contentsOf: processedSamples)
            systemBuffersReceived += 1
            // Limit buffer size (max 1 second)
            let maxSize = Int(targetSampleRate * AudioConstants.maxBufferDuration) * targetChannelCount
            if systemBuffer.count > maxSize {
                systemBuffer.removeFirst(systemBuffer.count - maxSize)
            }
        } else {
            micBuffer.append(contentsOf: processedSamples)
            micBuffersReceived += 1
            let maxSize = Int(targetSampleRate * AudioConstants.maxBufferDuration) * targetChannelCount
            if micBuffer.count > maxSize {
                micBuffer.removeFirst(micBuffer.count - maxSize)
            }
        }
        bufferLock.unlock()

        // Debug log first few
        if debugLogEnabled && (isSystemAudio ? systemBuffersReceived : micBuffersReceived) <= 3 {
            LoggerService.shared.log(category: .audio, level: .debug, message: "[\(source)] Added \(processedSamples.count/targetChannelCount) frames to buffer")
        }
    }

    /// Output a mixed chunk of audio
    ///
    /// Modified for v1.0 - Recording Scenario Optimization:
    /// 1. Check if each source is enabled and has enough data
    /// 2. If both sources are disabled, still output silence to maintain time continuity
    /// 3. Only mix enabled sources' data
    private func outputMixedChunk() {
        bufferLock.lock()

        // Check if each source is enabled and has enough data
        let hasSystemData = isSystemAudioEnabled && systemBuffer.count >= samplesPerChunk
        let hasMicData = isMicrophoneEnabled && micBuffer.count >= samplesPerChunk

        // If both sources are disabled, still output silence to maintain time continuity
        // This is a key modification: ensures that even if all sources are disabled,
        // the recording file's timeline remains continuous
        let shouldOutputSilence = !isSystemAudioEnabled && !isMicrophoneEnabled

        guard hasSystemData || hasMicData || shouldOutputSilence else {
            bufferLock.unlock()
            return
        }

        // Create output buffer (initialized to 0, which is silence)
        var mixedSamples = [Float](repeating: 0, count: samplesPerChunk)

        // Add system audio if enabled and has data
        if hasSystemData {
            let systemChunk = Array(systemBuffer.prefix(samplesPerChunk))
            systemBuffer.removeFirst(samplesPerChunk)
            vDSP_vadd(mixedSamples, 1, systemChunk, 1, &mixedSamples, 1, vDSP_Length(samplesPerChunk))
        }

        // Add microphone audio if enabled and has data
        if hasMicData {
            let micChunk = Array(micBuffer.prefix(samplesPerChunk))
            micBuffer.removeFirst(samplesPerChunk)
            vDSP_vadd(mixedSamples, 1, micChunk, 1, &mixedSamples, 1, vDSP_Length(samplesPerChunk))
        }

        bufferLock.unlock()

        // Clamp to prevent clipping (if both sources are loud)
        var minVal = NormalizedRange.min
        var maxVal = NormalizedRange.max
        vDSP_vclip(mixedSamples, 1, &minVal, &maxVal, &mixedSamples, 1, vDSP_Length(samplesPerChunk))

        // Create and output CMSampleBuffer
        if let outputBuffer = createOutputSampleBuffer(from: mixedSamples) {
            totalChunksOutput += 1

            if debugLogEnabled && totalChunksOutput <= DebugConstants.initialChunkLogCount {
                let pts = CMSampleBufferGetPresentationTimeStamp(outputBuffer)
                LoggerService.shared.log(category: .audio, level: .debug, message: "[Mixer] Output chunk #\(totalChunksOutput): \(framesPerChunk) frames, PTS: \(String(format: "%.3f", CMTimeGetSeconds(pts)))s")
            }
            
            delegate?.audioMixer(self, didMixSampleBuffer: outputBuffer)
        }
    }
    
    // MARK: - Audio Data Extraction

    /// Format information parsed from audio sample buffer
    private struct AudioFormatInfo {
        let sampleRate: Double
        let channels: Int
        let isFloat: Bool
        let isNonInterleaved: Bool
        let bitsPerChannel: UInt32
        let frameCount: CMItemCount
        let totalSamples: Int
    }

    /// Extract audio data from CMSampleBuffer
    ///
    /// Handles both interleaved and non-interleaved formats for:
    /// - Float32 (32-bit float)
    /// - Int16 (16-bit PCM)
    /// - Int32 (32-bit PCM)
    ///
    /// - Parameter sampleBuffer: The sample buffer to extract audio data from
    /// - Returns: A tuple containing samples array, sample rate, and channel count
    /// - Throws: AudioMixerError if the format is unsupported or data cannot be extracted
    private func extractAudioData(from sampleBuffer: CMSampleBuffer) throws -> (samples: [Float], sampleRate: Double, channels: Int) {
        // Step 1: Parse format information
        let formatInfo = try parseFormatInfo(from: sampleBuffer)

        // Step 2: Access buffer data
        let (pointer, length) = try accessBufferData(from: sampleBuffer)

        // Step 3: Extract samples based on format
        let floatSamples = try extractSamples(
            from: pointer,
            length: length,
            format: formatInfo
        )

        return (floatSamples, formatInfo.sampleRate, formatInfo.channels)
    }

    /// Parse audio format information from sample buffer
    private func parseFormatInfo(from sampleBuffer: CMSampleBuffer) throws -> AudioFormatInfo {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            throw AudioMixerError.invalidFormat(description: "Unable to get format description")
        }

        let sampleRate = asbd.mSampleRate
        let channels = Int(asbd.mChannelsPerFrame)
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let bitsPerChannel = asbd.mBitsPerChannel
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)

        guard frameCount > 0, channels > 0 else {
            throw AudioMixerError.emptyBuffer
        }

        let totalSamples = frameCount * channels
        return AudioFormatInfo(
            sampleRate: sampleRate,
            channels: channels,
            isFloat: isFloat,
            isNonInterleaved: isNonInterleaved,
            bitsPerChannel: bitsPerChannel,
            frameCount: frameCount,
            totalSamples: totalSamples
        )
    }

    /// Access buffer data pointer and validate
    ///
    /// - Parameter sampleBuffer: The sample buffer to access
    /// - Returns: Tuple of (data pointer, data length)
    /// - Throws: AudioMixerError if buffer access fails
    private func accessBufferData(from sampleBuffer: CMSampleBuffer) throws -> (UnsafeRawPointer, Int) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw AudioMixerError.bufferAccessFailed
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let pointer = dataPointer, length > 0 else {
            throw AudioMixerError.bufferAccessFailed
        }

        return (UnsafeRawPointer(pointer), length)
    }

    /// Extract samples based on format type
    ///
    /// - Parameters:
    ///   - pointer: Raw data pointer
    ///   - length: Data length in bytes
    ///   - format: Parsed audio format information
    /// - Returns: Array of normalized float samples
    /// - Throws: AudioMixerError if format is unsupported
    private func extractSamples(
        from pointer: UnsafeRawPointer,
        length: Int,
        format: AudioFormatInfo
    ) throws -> [Float] {
        if format.isFloat && format.bitsPerChannel == 32 {
            return try extractFloat32Samples(
                from: pointer,
                length: length,
                format: format
            )
        } else if !format.isFloat && format.bitsPerChannel == 16 {
            return try extractInt16Samples(
                from: pointer,
                length: length,
                format: format
            )
        } else if !format.isFloat && format.bitsPerChannel == 32 {
            return try extractInt32Samples(
                from: pointer,
                length: length,
                format: format
            )
        } else {
            throw AudioMixerError.unsupportedFormat(
                isFloat: format.isFloat,
                bitsPerChannel: format.bitsPerChannel,
                isNonInterleaved: format.isNonInterleaved
            )
        }
    }

    /// Extract Float32 samples
    private func extractFloat32Samples(
        from pointer: UnsafeRawPointer,
        length: Int,
        format: AudioFormatInfo
    ) throws -> [Float] {
        let totalFloats = length / MemoryLayout<Float>.size
        let floatPtr = pointer.bindMemory(to: Float.self, capacity: totalFloats)

        if format.isNonInterleaved && format.channels > 1 {
            // Non-interleaved: [L0, L1, ..., Ln, R0, R1, ..., Rn]
            // Convert to interleaved: [L0, R0, L1, R1, ..., Ln, Rn]
            return try convertNonInterleavedToInterleaved(
                from: floatPtr,
                channels: format.channels,
                frameCount: format.frameCount,
                totalSamples: format.totalSamples
            )
        } else {
            // Interleaved or mono: read directly
            let samplesToRead = min(totalFloats, format.totalSamples)
            return Array(UnsafeBufferPointer(start: floatPtr, count: samplesToRead))
        }
    }

    /// Extract Int16 samples and normalize to [-1.0, 1.0]
    private func extractInt16Samples(
        from pointer: UnsafeRawPointer,
        length: Int,
        format: AudioFormatInfo
    ) throws -> [Float] {
        let totalInt16 = length / MemoryLayout<Int16>.size
        let int16Ptr = pointer.bindMemory(to: Int16.self, capacity: totalInt16)
        let normalizer: Float = 1.0 / 32768.0

        if format.isNonInterleaved && format.channels > 1 {
            var floatSamples = [Float](repeating: 0, count: format.totalSamples)
            let samplesPerChannel = format.frameCount

            for frame in 0..<format.frameCount {
                for ch in 0..<format.channels {
                    let srcIndex = ch * samplesPerChannel + frame
                    let dstIndex = frame * format.channels + ch
                    if srcIndex < totalInt16 && dstIndex < format.totalSamples {
                        floatSamples[dstIndex] = Float(int16Ptr[srcIndex]) * normalizer
                    }
                }
            }
            return floatSamples
        } else {
            let samplesToRead = min(totalInt16, format.totalSamples)
            return (0..<samplesToRead).map { Float(int16Ptr[$0]) * normalizer }
        }
    }

    /// Extract Int32 samples and normalize to [-1.0, 1.0]
    private func extractInt32Samples(
        from pointer: UnsafeRawPointer,
        length: Int,
        format: AudioFormatInfo
    ) throws -> [Float] {
        let totalInt32 = length / MemoryLayout<Int32>.size
        let int32Ptr = pointer.bindMemory(to: Int32.self, capacity: totalInt32)
        let normalizer: Float = 1.0 / Float(Int32.max)

        if format.isNonInterleaved && format.channels > 1 {
            var floatSamples = [Float](repeating: 0, count: format.totalSamples)
            let samplesPerChannel = format.frameCount

            for frame in 0..<format.frameCount {
                for ch in 0..<format.channels {
                    let srcIndex = ch * samplesPerChannel + frame
                    let dstIndex = frame * format.channels + ch
                    if srcIndex < totalInt32 && dstIndex < format.totalSamples {
                        floatSamples[dstIndex] = Float(int32Ptr[srcIndex]) * normalizer
                    }
                }
            }
            return floatSamples
        } else {
            let samplesToRead = min(totalInt32, format.totalSamples)
            return (0..<samplesToRead).map { Float(int32Ptr[$0]) * normalizer }
        }
    }

    /// Convert non-interleaved audio to interleaved format
    ///
    /// Non-interleaved: [L0, L1, ..., Ln, R0, R1, ..., Rn]
    /// Interleaved:      [L0, R0, L1, R1, ..., Ln, Rn]
    ///
    /// - Parameters:
    ///   - source: Non-interleaved sample pointer
    ///   - channels: Number of audio channels
    ///   - frameCount: Number of frames per channel
    ///   - totalSamples: Total number of samples to output
    /// - Returns: Interleaved float samples array
    private func convertNonInterleavedToInterleaved(
        from source: UnsafePointer<Float>,
        channels: Int,
        frameCount: Int,
        totalSamples: Int
    ) -> [Float] {
        var floatSamples = [Float](repeating: 0, count: totalSamples)
        let samplesPerChannel = frameCount

        for frame in 0..<frameCount {
            for ch in 0..<channels {
                let srcIndex = ch * samplesPerChannel + frame
                let dstIndex = frame * channels + ch
                if srcIndex < totalSamples && dstIndex < totalSamples {
                    floatSamples[dstIndex] = source[srcIndex]
                }
            }
        }
        return floatSamples
    }

    
    /// Simple linear resampling
    private func resample(_ samples: [Float], fromRate: Double, toRate: Double, channels: Int) -> [Float] {
        let ratio = toRate / fromRate
        let inputFrames = samples.count / channels
        let outputFrames = Int(Double(inputFrames) * ratio)
        
        var output = [Float](repeating: 0, count: outputFrames * channels)
        
        for outFrame in 0..<outputFrames {
            let inPos = Double(outFrame) / ratio
            let inFrame = Int(inPos)
            let frac = Float(inPos - Double(inFrame))
            
            for ch in 0..<channels {
                let idx0 = min(inFrame, inputFrames - 1) * channels + ch
                let idx1 = min(inFrame + 1, inputFrames - 1) * channels + ch
                output[outFrame * channels + ch] = samples[idx0] * (1.0 - frac) + samples[idx1] * frac
            }
        }
        
        return output
    }
    
    /// Convert mono to stereo
    private func monoToStereo(_ mono: [Float]) -> [Float] {
        var stereo = [Float](repeating: 0, count: mono.count * 2)
        for i in 0..<mono.count {
            stereo[i * 2] = mono[i]
            stereo[i * 2 + 1] = mono[i]
        }
        return stereo
    }
    
    /// Create output CMSampleBuffer
    private func createOutputSampleBuffer(from samples: [Float]) -> CMSampleBuffer? {
        guard let formatDescription = outputFormatDescription, !samples.isEmpty else {
            return nil
        }
        
        let frameCount = samples.count / targetChannelCount
        guard frameCount > 0 else { return nil }
        
        var blockBuffer: CMBlockBuffer?
        let dataSize = samples.count * MemoryLayout<Float>.size
        
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard status == kCMBlockBufferNoErr, let buffer = blockBuffer else {
            return nil
        }
        
        status = CMBlockBufferReplaceDataBytes(
            with: samples,
            blockBuffer: buffer,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )
        
        guard status == kCMBlockBufferNoErr else {
            return nil
        }
        
        // Create timing info
        let presentationTime = CMTime(
            value: frameCounter,
            timescale: CMTimeScale(targetSampleRate)
        )
        frameCounter += Int64(frameCount)
        
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(targetSampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        return status == noErr ? sampleBuffer : nil
    }
}

// MARK: - Errors

/// Errors that can occur during audio mixing
enum AudioMixerError: LocalizedError {
    case invalidFormat(description: String)
    case unsupportedFormat(isFloat: Bool, bitsPerChannel: UInt32, isNonInterleaved: Bool)
    case emptyBuffer
    case bufferAccessFailed
    case insufficientData(expected: Int, actual: Int)
    case sampleBufferCreationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let desc):
            return "Invalid audio format: \(desc)"
        case .unsupportedFormat(let isFloat, let bits, let isNonInterleaved):
            let type = isFloat ? "Float" : "Int"
            let layout = isNonInterleaved ? "non-interleaved" : "interleaved"
            return "Unsupported audio format: \(type)\(bits) \(layout)"
        case .emptyBuffer:
            return "Empty audio buffer"
        case .bufferAccessFailed:
            return "Failed to access buffer data"
        case .insufficientData(let expected, let actual):
            return "Insufficient data: expected \(expected), got \(actual)"
        case .sampleBufferCreationFailed(let status):
            return "Failed to create sample buffer, status: \(status)"
        }
    }
}
