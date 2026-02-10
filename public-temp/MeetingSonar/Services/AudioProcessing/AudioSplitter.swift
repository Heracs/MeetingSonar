//
//  AudioSplitter.swift
//  MeetingSonar
//
//  Audio splitting and format conversion for ASR processing
//

import Foundation
import AVFoundation
import Accelerate

/// Splits audio files into chunks for ASR processing
class AudioSplitter {
    private let analyzer = AudioEnergyAnalyzer()
    
    // Limits (Zhipu ASR: < 30s)
    private let minChunkDuration: TimeInterval = 10.0
    private let maxChunkDuration: TimeInterval = 28.0 // Leave 2s safety margin
    
    /// Splits the audio file into chunks respecting the max duration logic.
    /// Returns: List of tuples (Chunk URL, Start Time, Duration)
    func split(audioURL: URL) async throws -> [(url: URL, start: TimeInterval, duration: TimeInterval)] {
        let file = try AVAudioFile(forReading: audioURL)
        let totalDuration = Double(file.length) / file.processingFormat.sampleRate
        
        var chunks: [(URL, TimeInterval, TimeInterval)] = []
        var currentTime: TimeInterval = 0
        
        // Prepare Output Directory
        let chunkDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingSonar_Chunks", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: chunkDir, withIntermediateDirectories: true, attributes: nil)
        
        LoggerService.shared.log(category: .general, message: "[AudioSplitter] Starting split for \(audioURL.lastPathComponent) (\(String(format: "%.1f", totalDuration))s)")
        
        while currentTime < totalDuration {
            let remaining = totalDuration - currentTime
            
            // If remaining is small, just take it
            if remaining <= maxChunkDuration {
                let chunkURL = try await exportChunk(from: audioURL, start: currentTime, duration: remaining, outputDir: chunkDir, index: chunks.count)
                chunks.append((chunkURL, currentTime, remaining))
                break
            }
            
            // Search Window: [Current + 10s, Current + 28s]
            let searchStart = currentTime + minChunkDuration
            let searchEnd = min(currentTime + maxChunkDuration, totalDuration)
            
            // Find silence
            let splitPoint = analyzer.findBestSplitPoint(in: file, searchRange: searchStart..<searchEnd)
            
            // Safety: Ensure forward progress
            let actualSplitPoint = max(splitPoint, currentTime + minChunkDuration)
            let finalSplitPoint = min(actualSplitPoint, currentTime + maxChunkDuration)
            
            let chunkDuration = finalSplitPoint - currentTime
            let chunkURL = try await exportChunk(from: audioURL, start: currentTime, duration: chunkDuration, outputDir: chunkDir, index: chunks.count)
            chunks.append((chunkURL, currentTime, chunkDuration))
            
            currentTime = finalSplitPoint
        }
        
        LoggerService.shared.log(category: .general, message: "[AudioSplitter] Split complete. Generated \(chunks.count) chunks.")
        return chunks
    }
    
    private func exportChunk(from sourceURL: URL, start: TimeInterval, duration: TimeInterval, outputDir: URL, index: Int) async throws -> URL {
        let outputURL = outputDir.appendingPathComponent("chunk_\(index).wav")
        
        do {
            let fileBuffer = try readAudio(from: sourceURL, start: start, duration: duration)
            
            // Create output format: 16kHz, Int16, Mono
            guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false) else {
                throw NSError(domain: "AudioSplitter", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to create output format"])
            }
            
            // Fix: Use explicit init to set processing format to Int16
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings, commonFormat: .pcmFormatInt16, interleaved: false)
            
            // Convert
            if let convertedBuffer = convertToTargetFormat(buffer: fileBuffer, targetFormat: outputFormat) {
                if convertedBuffer.frameLength > 0 {
                    try outputFile.write(from: convertedBuffer)
                }
            } else {
                throw NSError(domain: "AudioSplitter", code: -3, userInfo: [NSLocalizedDescriptionKey: "Format conversion failed"])
            }
            
            return outputURL
        } catch {
            throw NSError(domain: "AudioSplitter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Export failed: \(error.localizedDescription)"])
        }
    }
    
    private func readAudio(from url: URL, start: TimeInterval, duration: TimeInterval) throws -> AVAudioPCMBuffer {
        // Read as Int16 PCM directly to match our desired output format as much as possible
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(start * sampleRate)
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        
        file.framePosition = startFrame
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            throw NSError(domain: "AudioSplitter", code: -4, userInfo: [NSLocalizedDescriptionKey: "Buffer allocation failed"])
        }
        
        try file.read(into: buffer, frameCount: frameCount)
        return buffer
    }

    private func convertToTargetFormat(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == targetFormat { return buffer }
        
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else { return nil }
        
        // Output buffer size calculation
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let targetFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else { return nil }
        
        var error: NSError? = nil
        var hasProvidedData = false
        
        let status = converter.convert(to: outputBuffer, error: &error) { packetCount, outStatus in
            if hasProvidedData {
                outStatus.pointee = .endOfStream
                return nil
            }
            hasProvidedData = true
            outStatus.pointee = .haveData
            return buffer
        }
        
        if status != .error {
            return outputBuffer
        }
        return nil
    }
}
