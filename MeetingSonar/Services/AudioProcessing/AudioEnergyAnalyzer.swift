//
//  AudioEnergyAnalyzer.swift
//  MeetingSonar
//
//  Analyzes audio file energy to find optimal split points
//

import Foundation
import AVFoundation
import Accelerate

/// Analyzes audio file energy to find optimal split points (Silence Detection).
/// Uses Accelerate vDSP for high-performance RMS calculation.
class AudioEnergyAnalyzer {

    // MARK: - Configuration

    /// RMS threshold to consider a segment as "Silence".
    /// -60dB (0.001) is a typical noise floor for quiet recordings.
    private let silenceThreshold: Float = 0.001

    // MARK: - Public API

    /// Finds the best split point (lowest energy) within the given search range.
    /// - Parameters:
    ///   - file: The source audio file.
    ///   - searchRange: The time range to search within (e.g., 10s...28s).
    /// - Returns: The TimeInterval of the best split point. Returns `range.upperBound` if analysis fails.
    func findBestSplitPoint(in file: AVAudioFile, searchRange: Range<TimeInterval>) -> TimeInterval {
        // Validation
        guard searchRange.lowerBound < searchRange.upperBound,
              searchRange.upperBound <= Double(file.length) / file.processingFormat.sampleRate else {
            return searchRange.upperBound
        }

        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(searchRange.lowerBound * sampleRate)
        let endFrame = AVAudioFramePosition(searchRange.upperBound * sampleRate)
        let frameCount = AVAudioFrameCount(endFrame - startFrame)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            return searchRange.upperBound
        }

        // Read Audio
        do {
            file.framePosition = startFrame
            try file.read(into: buffer, frameCount: frameCount)
        } catch {
            LoggerService.shared.log(category: .general, message: "[AudioEnergyAnalyzer] Read failed: \(error.localizedDescription)")
            return searchRange.upperBound
        }

        return findBestSplitPoint(in: buffer, startTime: searchRange.lowerBound)
    }

    /// Internal logic for testing
    func findBestSplitPoint(in buffer: AVAudioPCMBuffer, startTime: TimeInterval) -> TimeInterval {
        let sampleRate = buffer.format.sampleRate
        let windowDuration: TimeInterval = 0.1 // 100ms
        let windowFrames = AVAudioFrameCount(windowDuration * sampleRate)

        var minRMS: Float = Float.greatestFiniteMagnitude
        var bestFrameOffset: AVAudioFramePosition = AVAudioFramePosition(buffer.frameLength) // Default to end

        guard let channelData = buffer.floatChannelData?[0] else {
            return startTime + Double(buffer.frameLength) / sampleRate
        }

        let framesToProcess = Int(buffer.frameLength)
        let step = Int(windowFrames)

        // Stride through the buffer
        for offset in stride(from: 0, to: framesToProcess - step, by: step) {
            var rms: Float = 0
            vDSP_rmsqv(channelData + offset, 1, &rms, vDSP_Length(step))

            if rms < minRMS {
                minRMS = rms
                bestFrameOffset = AVAudioFramePosition(offset)
            }
        }

        // Return time at middle of the quietest window
        let bestRelativeTime = Double(bestFrameOffset + AVAudioFramePosition(windowFrames / 2)) / sampleRate
        let bestAbsoluteTime = startTime + bestRelativeTime

        LoggerService.shared.log(category: .general, message: "[AudioEnergyAnalyzer] Best split found at \(String(format: "%.2f", bestAbsoluteTime))s with RMS: \(minRMS)")

        return bestAbsoluteTime
    }
}
