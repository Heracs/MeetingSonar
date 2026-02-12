//
//  RecordingService.swift
//  MeetingSonar
//
//  Main recording controller that orchestrates audio capture, mixing, and encoding.
//
//  v0.2 Updates:
//  - Added pause/resume support for sleep/lock
//  - Added recording trigger type (manual vs smart reminder)
//  - Added adjusted duration calculation
//

import Foundation
import AVFoundation
import CoreMedia
import UserNotifications

// MARK: - Recording Trigger Type

/// Indicates how a recording was started
enum RecordingTrigger: Equatable {
    /// User manually clicked "Start Recording"
    case manual

    /// Triggered by detection (Auto mode)
    case auto

    /// Triggered by smart reminder notification
    case smartReminder
}

// MARK: - Recording State

/// Represents the current recording state
enum RecordingState: Equatable {
    /// Not recording
    case idle
    
    /// Actively recording
    case recording
    
    /// Recording is paused (e.g., during sleep/lock)
    case paused
}

// MARK: - Notification Names

/// Notification names for recording events
extension Notification.Name {
    static let recordingDidStart = Notification.Name("recordingDidStart")
    static let recordingDidStop = Notification.Name("recordingDidStop")
    static let recordingDidPause = Notification.Name("recordingDidPause")
    static let recordingDidResume = Notification.Name("recordingDidResume")
    static let recordingError = Notification.Name("recordingError")

    // New for v0.3.1
    static let stopRecordingRequested = Notification.Name("StopRecordingRequested")
    static let recordingTimerUpdate = Notification.Name("RecordingTimerUpdate")

    // For remind overlay display
    static let showRemindOverlay = Notification.Name("showRemindOverlay")
}

/// Main service for controlling meeting audio recording
///
/// Orchestrates:
/// - AudioCaptureService (system audio via ScreenCaptureKit)
/// - MicrophoneService (microphone input via AVCaptureSession)
/// - AudioMixerService (real-time mixing)
/// - AVAssetWriter (file encoding)
///
/// - Important: Requires macOS 13.0 or newer for system audio capture.
@available(macOS 13.0, *)
@MainActor
final class RecordingService: RecordingServiceProtocol {

    // MARK: - Audio Encoding Constants

    /// Audio format constants for recording
    enum AudioFormatConstants {
        /// Target sample rate (48kHz - standard for digital audio)
        static let sampleRate: Double = 48000.0
        /// Number of audio channels (stereo)
        static let channelCount: Int = 2
        /// Bytes per Float32 sample
        static let bytesPerFloat: Int = 4
        /// Bits per Float32 sample
        static let bitsPerFloat: Int = 32
        /// Bytes per packet (channels * bytes per float)
        static var bytesPerPacket: Int { channelCount * bytesPerFloat }
        /// Bytes per frame (same as bytes per packet for PCM)
        static var bytesPerFrame: Int { bytesPerPacket }
    }

    // MARK: - Singleton

    static let shared = RecordingService()

    // MARK: - Properties

    /// System audio capture service
    private let audioCaptureService: AudioCaptureService

    /// Microphone capture service
    private let microphoneService: MicrophoneService

    /// Audio mixer service
    private let audioMixerService: AudioMixerService

    /// Test mode flag (for dependency injection)
    private let testMode: Bool

    // MARK: - Initialization

    /// Standard initialization (production use)
    private init() {
        // Create default instances
        self.audioCaptureService = AudioCaptureService()
        self.microphoneService = MicrophoneService()
        self.audioMixerService = AudioMixerService()
        self.testMode = false

        setupObservers()
    }

    /// Test initialization with dependency injection
    ///
    /// - Parameters:
    ///   - audioCaptureService: Mock or real audio capture service
    ///   - microphoneService: Mock or real microphone service
    ///   - audioMixerService: Mock or real audio mixer service
    /// - Important: Only use this in unit tests
    static func createForTesting(
        audioCaptureService: AudioCaptureService = AudioCaptureService(),
        microphoneService: MicrophoneService = MicrophoneService(),
        audioMixerService: AudioMixerService = AudioMixerService()
    ) -> RecordingService {
        let instance = RecordingService(
            audioCaptureService: audioCaptureService,
            microphoneService: microphoneService,
            audioMixerService: audioMixerService,
            testMode: true
        )
        return instance
    }

    /// Private initializer with dependency injection
    private init(
        audioCaptureService: AudioCaptureService,
        microphoneService: MicrophoneService,
        audioMixerService: AudioMixerService,
        testMode: Bool
    ) {
        self.audioCaptureService = audioCaptureService
        self.microphoneService = microphoneService
        self.audioMixerService = audioMixerService
        self.testMode = testMode

        setupObservers()
    }
    
    /// Asset writer for encoding
    private var assetWriter: AVAssetWriter?
    
    /// Audio input for asset writer
    private var audioInput: AVAssetWriterInput?
    
    /// Current recording file URL
    private(set) var currentRecordingURL: URL?
    
    /// Whether recording is currently active (recording or paused)
    var isRecording: Bool {
        recordingState != .idle
    }
    
    /// Current recording state (v0.2)
    private(set) var recordingState: RecordingState = .idle
    
    /// How this recording was started (v0.2)
    private(set) var recordingTrigger: RecordingTrigger = .manual

    /// Current recording audio source configuration (v1.0 - Recording Scenario Optimization)
    /// Tracks the configuration used for the current recording to support real-time toggling
    private(set) var currentRecordingConfig: AudioSourceConfig = .default
    
    /// Recording start time
    private var recordingStartTime: Date?
    
    /// Accumulated paused duration (v0.2)
    private var pausedDuration: TimeInterval = 0
    
    /// Time when pause started (v0.2)
    private var pauseStartTime: Date?
    
    /// Current recording duration (includes paused time)
    var currentDuration: TimeInterval {
        guard let startTime = recordingStartTime, recordingState != .idle else {
            return 0
        }
        return Date().timeIntervalSince(startTime)
    }
    
    /// Adjusted duration excluding paused time (v0.2)
    var adjustedDuration: TimeInterval {
        guard let startTime = recordingStartTime, recordingState != .idle else {
            return 0
        }
        let totalElapsed = Date().timeIntervalSince(startTime)
        let currentPauseDuration = pauseStartTime.map { Date().timeIntervalSince($0) } ?? 0
        return totalElapsed - pausedDuration - currentPauseDuration
    }
    
    /// Settings manager
    private let settings = SettingsManager.shared
    
    /// Permission manager
    private let permissionManager = PermissionManager.shared
    
    // MARK: - Public Methods
    
    // MARK: - Integration
    
    private let logger = LoggerService.shared
    
    // v0.3.1 Timer for UI updates
    private var statusTimer: Timer?
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(forName: .stopRecordingRequested, object: nil, queue: .main) { [weak self] _ in
            self?.stopRecording()
        }
    }

    // MARK: - Public Methods
    
    /// Start recording meeting audio
    /// - Parameters:
    ///   - trigger: How this recording was started (manual only for v0.1)
    ///   - appName: Optional application name for filename
    func startRecording(trigger: RecordingTrigger = .manual, appName: String? = nil) async throws {
        guard recordingState == .idle else {
            logger.log(category: .recording, level: .warning, message: "Already recording or paused")
            return
        }

        // Store trigger type
        recordingTrigger = trigger

        // MARK: - Get scenario-based configuration (v1.0 - Recording Scenario Optimization)
        //
        // This is the key change: use scenario-specific default configs based on trigger type
        // - .auto and .smartReminder use autoRecordingDefaultConfig (meeting scenario)
        // - .manual uses manualRecordingDefaultConfig (video/music capture scenario)
        let config = await MainActor.run {
            let cfg = settings.defaultConfig(for: trigger)
            // Update settings' current active config for backward compatibility
            settings.setCurrentActiveConfig(cfg)
            return cfg
        }
        currentRecordingConfig = config

        // Check permissions
        let (screenOK, micOK) = await permissionManager.checkAllPermissions()

        // Log permission metric
        logger.logMetric(event: "permission_check_before_record", attributes: [
            "screen": screenOK,
            "mic": micOK
        ])

        // Validate at least one audio source is enabled
        guard config.isValid() else {
            throw RecordingError.noAudioSource
        }

        // Check required permissions based on configuration
        if !screenOK && config.includeSystemAudio {
            throw PermissionError.screenCaptureNotAuthorized
        }

        if !micOK && config.includeMicrophone {
            throw PermissionError.microphoneNotAuthorized
        }

        // Generate output file URL (F-4.7 Standardized Naming)
        let sourceName = appName ?? (trigger == .auto ? "Auto" : "Manual")
        let outputURL = PathManager.shared.generateRecordingURL(source: sourceName)
        currentRecordingURL = outputURL

        // Setup asset writer
        try await setupAssetWriter(url: outputURL)

        // Setup delegates
        audioCaptureService.delegate = self
        microphoneService.delegate = self
        audioMixerService.delegate = self

        // MARK: - Start services based on configuration
        //
        // Only start services that are enabled in the config to avoid unnecessary resource usage
        audioMixerService.start()

        // Configure mixer with initial audio source states
        audioMixerService.setSystemAudioEnabled(config.includeSystemAudio)
        audioMixerService.setMicrophoneEnabled(config.includeMicrophone)

        if config.includeSystemAudio {
            try await audioCaptureService.startCapture()
        }

        if config.includeMicrophone {
            try microphoneService.startCapture()
        }

        // Start writing
        assetWriter?.startWriting()
        assetWriter?.startSession(atSourceTime: .zero)

        recordingState = .recording
        recordingStartTime = Date()
        pausedDuration = 0
        pauseStartTime = nil

        NotificationCenter.default.post(
            name: .recordingDidStart,
            object: self,
            userInfo: ["trigger": trigger]
        )

        startStatusTimer()

        // Log Metric
        logger.logMetric(event: "recording_started", attributes: [
            "trigger": trigger,
            "filename": outputURL.lastPathComponent,
            "systemAudio": config.includeSystemAudio,
            "microphone": config.includeMicrophone
        ])

        // F-6.0: Add to Metadata Index
        let meta = MeetingMeta(
            id: UUID(),
            filename: outputURL.lastPathComponent,
            title: nil,
            source: sourceName,
            startTime: Date(),
            duration: 0,
            status: .recording
        )
        await MetadataManager.shared.add(meta)
    }
    
    /// Pause recording (for sleep/lock events)
    func pauseRecording() {
        guard recordingState == .recording else { return }
        
        recordingState = .paused
        pauseStartTime = Date()
        
        audioMixerService.pause()
        microphoneService.pauseCapture()
        Task {
            await audioCaptureService.pauseCapture()
        }
        
        NotificationCenter.default.post(name: .recordingDidPause, object: self)
        logger.log(category: .recording, message: "Recording paused")
    }
    
    /// Resume recording after pause
    func resumeRecording() {
        guard recordingState == .paused else { return }
        
        if let pauseStart = pauseStartTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
        }
        pauseStartTime = nil
        
        recordingState = .recording
        
        audioMixerService.resume()
        microphoneService.resumeCapture()
        Task {
            await audioCaptureService.resumeCapture()
        }
        
        NotificationCenter.default.post(name: .recordingDidResume, object: self)
        logger.log(category: .recording, message: "Recording resumed")
    }
    
    /// Stop recording and save the file
    func stopRecording() {
        guard recordingState != .idle else { return }
        
        let finalDuration = adjustedDuration
        let wasState = recordingState
        recordingState = .idle
        
        // Stop capture services
        Task {
            await audioCaptureService.stopCapture()
        }
        microphoneService.stopCapture()
        audioMixerService.stop()
        
        statusTimer?.invalidate()
        statusTimer = nil
        
        // Finish writing
        audioInput?.markAsFinished()
        
        assetWriter?.finishWriting { [weak self] in
            guard let self = self else { return }
            
            if let error = self.assetWriter?.error {
                self.logger.log(category: .recording, level: .error, message: "Writing finished with error: \(error.localizedDescription)")
                NotificationCenter.default.post(name: .recordingError, object: self, userInfo: ["error": error])
            } else {
                // CRITICAL FIX: Guard against nil URL to prevent incorrect file size display
                guard let url = self.currentRecordingURL else {
                    self.logger.log(category: .recording, level: .error, message: "Recording URL is nil after finishing")
                    return
                }

                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

                self.logger.logMetric(event: "recording_finished", attributes: [
                    "file_path": url.path,
                    "duration_sec": String(format: "%.2f", finalDuration),
                    "size_bytes": size,
                    "result": "success"
                ])

                // F-6.0: Update Metadata Index
                let filename = url.lastPathComponent
                Task {
                    // Update status to pending (waiting for AI or User) and save final duration
                    // We need to fetch the existing meta to update it, or just update fields we know.
                    // Since MetadataManager is an actor, we can't easily "fetch-modify-save" without a specific method unless we expose one.
                    // Let's assume we can update by ID if we stored it, or by filename if unique.
                    // Added `updateStatus` by filename in Manager. Also need to update duration.
                    // For MVP v0.6.0, let's just use a specialized update method or re-scan?
                    // Better: MetadataManager.shared.updateRecording(filename: ..., status: .pending, duration: finalDuration)
                    // Since we didn't add that specific method, let's do:
                    await MetadataManager.shared.updateRecordingEnd(filename: filename, duration: finalDuration, status: .pending)
                }

                // FIX: Post notification so AppDelegate knows to trigger AI
                // v0.5.1 FIX: Restore missing notification
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .recordingDidStop,
                        object: self,
                        userInfo: ["url": url]
                    )
                }
            }
            
            self.cleanup()

        }
    }
    
    // MARK: - Private Methods
    
    // MARK: - Constants
    
    /// Maximum recording duration (2 hours) - F-1.1
    private let maxDuration: TimeInterval = 7200
    
    // ...

    private func startStatusTimer() {
        statusTimer?.invalidate()
        // Ensure timer is scheduled on Main RunLoop
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                
                let duration = self.adjustedDuration
                
                // F-1.1: Max Duration Safeguard
                if duration >= self.maxDuration {
                    self.handleMaxDurationReached(duration: duration)
                    return
                }
                
                NotificationCenter.default.post(name: .recordingTimerUpdate, object: self, userInfo: ["duration": duration])
            }
        }
    }
    
    /// Handle max duration reached event
    private func handleMaxDurationReached(duration: TimeInterval) {
        logger.log(
            category: .recording,
            level: .warning,
            message: "[RecordingService] Auto-stopping: Max duration reached (\(Int(duration))s >= \(Int(maxDuration))s)"
        )
        
        // Stop recording
        stopRecording()
        
        // Notify user
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "录音已停止"
        content.body = "录音时长已达到上限（2小时）并自动保存。"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "MaxDurationReached", content: content, trigger: nil)

        // Use callback-based API for compatibility with non-async context
        center.add(request) { error in
            if let error = error {
                self.logger.log(category: .recording, level: .warning, message: "[RecordingService] Failed to post max duration notification: \(error.localizedDescription)")
            } else {
                self.logger.log(category: .recording, level: .debug, message: "[RecordingService] Max duration notification posted successfully")
            }
        }
    }
    
    /// Setup AVAssetWriter for encoding audio
    private func setupAssetWriter(url: URL) async throws {
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        
        // Create asset writer - always use M4A for reliability
        assetWriter = try AVAssetWriter(outputURL: url, fileType: .m4a)
        
        let quality = await MainActor.run { settings.audioQuality }
        
        // Configure audio output settings for AAC encoding
        // Input will be Float32 PCM at 48kHz stereo from mixer
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: AudioFormatConstants.sampleRate,
            AVNumberOfChannelsKey: AudioFormatConstants.channelCount,
            AVEncoderBitRateKey: quality.bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        // Source format hint for Float32 PCM input
        var inputASBD = AudioStreamBasicDescription(
            mSampleRate: AudioFormatConstants.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(AudioFormatConstants.bytesPerPacket),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(AudioFormatConstants.bytesPerFrame),
            mChannelsPerFrame: UInt32(AudioFormatConstants.channelCount),
            mBitsPerChannel: UInt32(AudioFormatConstants.bitsPerFloat),
            mReserved: 0
        )
        
        var sourceFormat: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &inputASBD,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &sourceFormat
        )

        // Check if format description creation succeeded
        if status != noErr || sourceFormat == nil {
            logger.log(category: .recording, level: .warning, message: """
                [RecordingService] CMAudioFormatDescriptionCreate failed with status: \(status)
                Audio input will be created without source format hint (may affect compatibility).
                """)
        }

        // Create audio input with source format hint (may be nil if creation failed above)
        audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioSettings,
            sourceFormatHint: sourceFormat
        )
        audioInput?.expectsMediaDataInRealTime = true
        
        guard let input = audioInput, assetWriter?.canAdd(input) == true else {
            throw RecordingError.assetWriterSetupFailed
        }

        assetWriter?.add(input)

        LoggerService.shared.log(category: .recording, level: .debug, message: "[RecordingService] AssetWriter configured: 48kHz stereo AAC @ \(quality.bitRate/1000)kbps")
    }
    
    /// Clean up after recording stops
    private func cleanup() {
        assetWriter = nil
        audioInput = nil
        recordingStartTime = nil
        sessionStartTime = nil
        writeCount = 0
        pausedDuration = 0
        pauseStartTime = nil
        recordingTrigger = .manual
    }
    
    /// Session time for sample buffer timing
    private var sessionStartTime: CMTime?
    
    /// Debug counter for logging
    private var writeCount = 0
    
    /// Write a sample buffer to the asset writer
    private func writeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let input = audioInput,
              input.isReadyForMoreMediaData else {
            return
        }
        
        // Adjust timing relative to session start
        if sessionStartTime == nil {
            sessionStartTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if let startTime = sessionStartTime {
                LoggerService.shared.log(category: .recording, level: .debug, message: "[RecordingService] Session start time: \(CMTimeGetSeconds(startTime))s")
            }
        }

        // Create a new sample buffer with adjusted timing
        if let adjustedBuffer = adjustSampleBufferTiming(sampleBuffer) {
            // Log first few writes
            writeCount += 1
            if writeCount <= 10 {
                let originalPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let adjustedPTS = CMSampleBufferGetPresentationTimeStamp(adjustedBuffer)
                let frameCount = CMSampleBufferGetNumSamples(adjustedBuffer)
                LoggerService.shared.log(category: .recording, level: .debug, message: "[RecordingService] Write #\(writeCount): frames=\(frameCount), originalPTS=\(String(format: "%.3f", CMTimeGetSeconds(originalPTS)))s, adjustedPTS=\(String(format: "%.3f", CMTimeGetSeconds(adjustedPTS)))s")
            }
            
            input.append(adjustedBuffer)
        }
    }
    
    /// Adjust sample buffer timing to be relative to session start
    private func adjustSampleBufferTiming(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let startTime = sessionStartTime else {
            return sampleBuffer
        }
        
        let originalTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let adjustedTime = CMTimeSubtract(originalTime, startTime)
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: adjustedTime,
            decodeTimeStamp: .invalid
        )
        
        var adjustedBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &adjustedBuffer
        )

        // Log if buffer creation failed (should not happen with valid input)
        if status != noErr || adjustedBuffer == nil {
            logger.log(category: .recording, level: .error, message: """
                [RecordingService] CMSampleBufferCreateCopyWithNewTiming failed with status: \(status)
                Sample buffer will be dropped.
                """)
        }

        return adjustedBuffer
    }

    // MARK: - Real-time Audio Source Toggling (v1.0 - Recording Scenario Optimization)

    /// 切换系统音频状态
    /// - Parameter enabled: 是否启用系统音频
    /// - Note: 仅在录音状态下有效，暂停状态下调用会被忽略
    ///
    /// 调用场景：
    /// - 用户在 StatusPillView 菜单中切换"系统音频"选项
    /// - 其他需要动态控制音频源的场景
    func toggleSystemAudio(_ enabled: Bool) async {
        // Safety check: only allow toggling while recording
        guard recordingState == .recording else {
            logger.log(category: .recording, level: .warning, message: "Cannot toggle system audio: not recording")
            return
        }

        // Check current state to avoid redundant operations
        let isCurrentlyEnabled = audioCaptureService.isCapturing

        guard isCurrentlyEnabled != enabled else {
            return // State unchanged, no action needed
        }

        do {
            if enabled {
                // Start system audio capture
                // Need to check screen recording permission
                let (screenOK, _) = await permissionManager.checkAllPermissions()
                guard screenOK else {
                    logger.log(category: .recording, level: .error, message: "Cannot enable system audio: no screen recording permission")
                    return
                }

                try await audioCaptureService.startCapture()
                logger.log(category: .recording, message: "System audio enabled during recording")
            } else {
                // Stop system audio capture
                await audioCaptureService.stopCapture()
                logger.log(category: .recording, message: "System audio disabled during recording")
            }

            // Update Mixer state
            // Even if capture service stops, Mixer continues outputting (silence or mic only)
            audioMixerService.setSystemAudioEnabled(enabled)

            // Update current config
            currentRecordingConfig.includeSystemAudio = enabled

            // Post notification for UI updates
            NotificationCenter.default.post(
                name: .recordingAudioSourceChanged,
                object: self,
                userInfo: ["systemAudio": enabled, "microphone": currentRecordingConfig.includeMicrophone]
            )

        } catch {
            logger.log(category: .recording, level: .error, message: "Failed to toggle system audio: \(error.localizedDescription)")
        }
    }

    /// 切换麦克风状态
    /// - Parameter enabled: 是否启用麦克风
    /// - Note: 仅在录音状态下有效，暂停状态下调用会被忽略
    ///
    /// 调用场景：
    /// - 用户在 StatusPillView 菜单中切换"麦克风"选项
    /// - 其他需要动态控制音频源的场景
    func toggleMicrophone(_ enabled: Bool) async {
        // Safety check: only allow toggling while recording
        guard recordingState == .recording else {
            logger.log(category: .recording, level: .warning, message: "Cannot toggle microphone: not recording")
            return
        }

        // Check current state to avoid redundant operations
        let isCurrentlyEnabled = microphoneService.isCapturing

        guard isCurrentlyEnabled != enabled else {
            return // State unchanged, no action needed
        }

        do {
            if enabled {
                // Start microphone capture
                // Need to check microphone permission
                let hasPermission = await PermissionManager.shared.checkMicrophonePermission()
                guard hasPermission else {
                    logger.log(category: .recording, level: .error, message: "Cannot enable microphone: no microphone permission")
                    return
                }

                try microphoneService.startCapture()
                logger.log(category: .recording, message: "Microphone enabled during recording")
            } else {
                // Stop microphone capture
                microphoneService.stopCapture()
                logger.log(category: .recording, message: "Microphone disabled during recording")
            }

            // Update Mixer state
            audioMixerService.setMicrophoneEnabled(enabled)

            // Update current config
            currentRecordingConfig.includeMicrophone = enabled

            // Post notification for UI updates
            NotificationCenter.default.post(
                name: .recordingAudioSourceChanged,
                object: self,
                userInfo: ["systemAudio": currentRecordingConfig.includeSystemAudio, "microphone": enabled]
            )

        } catch {
            logger.log(category: .recording, level: .error, message: "Failed to toggle microphone: \(error.localizedDescription)")
        }
    }

    /// 获取当前音频源状态
    /// - Returns: 包含当前系统音频和麦克风状态的 AudioSourceConfig
    ///
    /// 使用场景：
    /// - StatusPillView 需要显示当前音频源状态
    /// - 其他需要查询当前状态的 UI 组件
    var currentAudioSourceState: AudioSourceConfig {
        AudioSourceConfig(
            includeSystemAudio: audioCaptureService.isCapturing,
            includeMicrophone: microphoneService.isCapturing
        )
    }
}

// MARK: - Notification Names Extension

extension Notification.Name {
    /// Posted when audio source configuration changes during recording
    static let recordingAudioSourceChanged = Notification.Name("recordingAudioSourceChanged")
}

// MARK: - AudioCaptureDelegate

@available(macOS 13.0, *)
extension RecordingService: AudioCaptureDelegate {
    func audioCaptureService(_ service: AudioCaptureService, didCaptureSampleBuffer sampleBuffer: CMSampleBuffer) {
        audioMixerService.addSystemAudioSamples(sampleBuffer)
    }

    func audioCaptureService(_ service: AudioCaptureService, didEncounterError error: Error) {
        LoggerService.shared.log(category: .recording, level: .error, message: "[RecordingService] Audio capture error: \(error.localizedDescription)")
        // Continue recording with microphone only if system audio fails
    }
}

// MARK: - MicrophoneCaptureDelegate

extension RecordingService: MicrophoneCaptureDelegate {
    func microphoneService(_ service: MicrophoneService, didCaptureSampleBuffer sampleBuffer: CMSampleBuffer) {
        audioMixerService.addMicrophoneSamples(sampleBuffer)
    }

    func microphoneService(_ service: MicrophoneService, didEncounterError error: Error) {
        LoggerService.shared.log(category: .recording, level: .error, message: "[RecordingService] Microphone error: \(error.localizedDescription)")
        // Continue recording with system audio only if microphone fails
    }
}

// MARK: - AudioMixerDelegate

extension RecordingService: AudioMixerDelegate {
    func audioMixer(_ mixer: AudioMixerService, didMixSampleBuffer sampleBuffer: CMSampleBuffer) {
        writeSampleBuffer(sampleBuffer)
    }
}

// MARK: - Errors

/// Errors that can occur during recording
enum RecordingError: LocalizedError {
    case assetWriterSetupFailed
    case writingFailed
    case notRecording
    case noAudioSource  // v1.0: No audio source selected

    var errorDescription: String? {
        switch self {
        case .assetWriterSetupFailed:
            return "Failed to setup audio file writer"
        case .writingFailed:
            return "Failed to write audio data to file"
        case .notRecording:
            return "Recording is not active"
        case .noAudioSource:
            return String(localized: "recording.error.noAudioSource")
        }
    }
}

