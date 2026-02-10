//
//  AudioEnergyAnalyzer.swift
//  MeetingSonar
//
//  Created by MeetingSonar Team.
//  Copyright © 2024 MeetingSonar. All rights reserved.
//

import Foundation
import AVFoundation
import Accelerate

/// Analyzes audio file energy to find optimal split points (Silence Detection).
/// Uses Accelerate vDSP for high-performance RMS calculation.
class AudioEnergyAnalyzer {

    // MARK: - Configuration

    /// Analysis constants
    enum AnalysisConstants {
        /// RMS threshold to consider a segment as "Silence"
        /// -60dB is a typical noise floor for quiet recordings
        /// This is relative to full scale (1.0)
        static let silenceThreshold: Float = 0.001  // Approx -60dB
        /// Window duration for silence detection (100ms)
        static let windowDuration: TimeInterval = 0.1
        /// Half window duration (for finding midpoint of silence)
        static var halfWindowDuration: TimeInterval { windowDuration / 2.0 }
    }

    /// RMS threshold to consider a segment as "Silence".
    /// -60dB is a typical noise floor for quiet recordings.
    /// This is relative to full scale (1.0).
    private let silenceThreshold: Float = AnalysisConstants.silenceThreshold

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
        
        // Prepare Buffer
        let sampleRate = file.processingFormat.sampleRate
        let channelCount = file.processingFormat.channelCount
        
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
        
        // Analyze
        // We analyze in small windows to find the quietest window
        let windowFrames = AVAudioFrameCount(AnalysisConstants.windowDuration * sampleRate)
        
        var minRMS: Float = Float.greatestFiniteMagnitude
        var bestFrameOffset: AVAudioFramePosition = frameCount // Default to end (relative)
        
        // If stereo, we mix down to mono for analysis or just analyze first channel
        // For simplicity and speed, let's analyze channel 0. Most meetings are mono or near-similar stereo.
        guard let channelData = buffer.floatChannelData?[0] else {
            return searchRange.upperBound
        }
        
        let framesToProcess = Int(buffer.frameLength)
        let step = Int(windowFrames)
        
        // Stride through the buffer
        for offset in stride(from: 0, to: framesToProcess - step, by: step) {
            var rms: Float = 0
            // Calculate RMS of this window using vDSP
            vDSP_rmsqv(channelData + offset, 1, &rms, vDSP_Length(step))
            
            // Check if this is the quietest so far
            if rms < minRMS {
                minRMS = rms
                bestFrameOffset = AVAudioFramePosition(offset)
                
                // Optimization: If we find "true silence" (below threshold), stop early?
                // No, we want the *best* point in the range, a little later might be better.
                // But for meeting constraints, earlier split is safer? 
                // Let's stick to finding absolute minimum in range.
            }
        }
        
        // Calculate absolute time
        // The split point should be at the MIDDLE of the quiet window, not the start
        let halfWindowOffset = AVAudioFramePosition(windowFrames) / 2
        let bestRelativeTime = Double(bestFrameOffset + halfWindowOffset) / sampleRate
        let bestAbsoluteTime = searchRange.lowerBound + bestRelativeTime
        
        LoggerService.shared.log(category: .general, message: "[AudioEnergyAnalyzer] Best split found at \(String(format: "%.2f", bestAbsoluteTime))s with RMS: \(minRMS)")
        
        return bestAbsoluteTime
    }
}
