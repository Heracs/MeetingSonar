//
//  AudioCaptureService.swift
//  MeetingSonar
//
//  Captures system/application audio using ScreenCaptureKit.
//  This is the core module for capturing meeting audio without virtual drivers.
//
//  Note: Audio capture via ScreenCaptureKit requires macOS 13.0+
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

/// Protocol for receiving captured audio samples from system audio
@available(macOS 13.0, *)
protocol AudioCaptureDelegate: AnyObject {
    /// Called when a new audio sample buffer is captured
    /// - Parameters:
    ///   - service: The audio capture service instance
    ///   - sampleBuffer: The captured audio sample buffer
    func audioCaptureService(_ service: AudioCaptureService, didCaptureSampleBuffer sampleBuffer: CMSampleBuffer)
    
    /// Called when an error occurs during capture
    /// - Parameters:
    ///   - service: The audio capture service instance
    ///   - error: The error that occurred
    func audioCaptureService(_ service: AudioCaptureService, didEncounterError error: Error)
}

/// Service for capturing system audio using ScreenCaptureKit
///
/// Uses `SCStream` with `capturesAudio = true` to capture desktop audio.
/// This approach doesn't require any virtual audio drivers.
///
/// - Important: Requires macOS 13.0 or newer for audio capture support.
@available(macOS 13.0, *)
final class AudioCaptureService: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: AudioCaptureDelegate?
    
    /// Current capture stream
    private var stream: SCStream?
    
    /// Stream configuration
    private var streamConfig: SCStreamConfiguration?
    
    /// Content filter for capture
    private var contentFilter: SCContentFilter?
    
    /// Whether capture is currently active
    private(set) var isCapturing = false

    /// Whether capture is paused (v0.2)
    private(set) var isPaused = false

    /// Serial queue for thread-safe state management
    /// CRITICAL FIX: Prevents race conditions when checking/setting isCapturing flag
    private let stateQueue = DispatchQueue(label: "com.meetingsonar.audiocapture.state")
    
    /// Audio settings for capture
    private let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]
    
    // MARK: - Public Methods
    
    /// Start capturing system audio
    /// - Parameter targetApp: Optional specific application to capture (nil captures all desktop audio)
    func startCapture(targetApp: SCRunningApplication? = nil) async throws {
        // CRITICAL FIX: Use serial queue to prevent race condition
        // Without this, two concurrent calls could both pass the !isCapturing check
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async {
                guard !self.isCapturing else {
                    LoggerService.shared.log(category: .audio, level: .debug, message: "[AudioCaptureService] Already capturing")
                    continuation.resume()
                    return
                }

                // Mark as capturing before we exit the queue
                self.isCapturing = true

                // Continue with the rest of the setup
                Task {
                    do {
                        try await self.performStartCapture(targetApp: targetApp)
                        continuation.resume()
                    } catch {
                        // Rollback state on error
                        self.stateQueue.async {
                            self.isCapturing = false
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Internal method to perform the actual capture setup
    /// - Parameter targetApp: Optional specific application to capture
    private func performStartCapture(targetApp: SCRunningApplication? = nil) async throws {
        
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        
        // Create content filter
        // If target app specified, capture only that app's audio
        // Otherwise, capture entire display audio
        if let app = targetApp {
            contentFilter = SCContentFilter(desktopIndependentWindow: content.windows.first { $0.owningApplication?.bundleIdentifier == app.bundleIdentifier } ?? content.windows[0])
        } else if let display = content.displays.first {
            // Capture all audio from the main display
            contentFilter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        } else {
            throw AudioCaptureError.noDisplayAvailable
        }
        
        guard let filter = contentFilter else {
            throw AudioCaptureError.filterCreationFailed
        }
        
        // Configure stream
        streamConfig = SCStreamConfiguration()
        
        guard let config = streamConfig else {
            throw AudioCaptureError.configurationFailed
        }
        
        // Audio-only configuration
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true  // Don't capture our own audio
        config.sampleRate = 48000  // Use 48kHz for better compatibility
        config.channelCount = 2

        LoggerService.shared.log(category: .audio, level: .debug, message: "[AudioCaptureService] Configured: 48000Hz, 2ch")

        // Minimal video config (required but we won't use it)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 fps minimum
        config.showsCursor = false
        
        // Create and configure stream
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        guard let stream = stream else {
            throw AudioCaptureError.streamCreationFailed
        }
        
        // Add audio output
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.meetingsonar.audiocapture"))
        
        // Add video output to prevent "stream output NOT found" errors
        // Even though we don't use video, SCStream requires a video handler
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.meetingsonar.videocapture"))
        
        // Start capture
        try await stream.startCapture()

        // isCapturing was already set to true in startCapture() before calling this method
        LoggerService.shared.log(category: .audio, level: .info, message: "[AudioCaptureService] Started capturing system audio")
    }

    /// Stop capturing system audio
    func stopCapture() async {
        // CRITICAL FIX: Use serial queue to prevent race condition
        await withCheckedContinuation { continuation in
            stateQueue.async {
                guard self.isCapturing, let stream = self.stream else {
                    LoggerService.shared.log(category: .audio, level: .debug, message: "[AudioCaptureService] Not capturing")
                    continuation.resume()
                    return
                }

                // Mark as not capturing before we exit the queue
                self.isCapturing = false

                // Continue with the rest of the cleanup
                Task {
                    do {
                        try await stream.stopCapture()
                    } catch {
                        LoggerService.shared.log(category: .audio, level: .error, message: "[AudioCaptureService] Error stopping capture: \(error.localizedDescription)")
                    }

                    await self.performStopCapture()
                    continuation.resume()
                }
            }
        }
    }

    /// Internal method to perform the actual capture cleanup
    private func performStopCapture() async {
        self.stream = nil
        self.contentFilter = nil
        self.streamConfig = nil
        isPaused = false

        LoggerService.shared.log(category: .audio, level: .info, message: "[AudioCaptureService] Stopped capturing system audio")
    }

    /// Pause capturing (v0.2 - for sleep/lock events)
    func pauseCapture() async {
        // CRITICAL FIX: Use serial queue for thread-safe state access
        await withCheckedContinuation { continuation in
            stateQueue.async {
                guard self.isCapturing, !self.isPaused else {
                    continuation.resume()
                    return
                }
                self.isPaused = true
                LoggerService.shared.log(category: .audio, level: .debug, message: "[AudioCaptureService] Capture paused")
                continuation.resume()
            }
        }
    }

    /// Resume capturing (v0.2 - after sleep/lock)
    func resumeCapture() async {
        // CRITICAL FIX: Use serial queue for thread-safe state access
        await withCheckedContinuation { continuation in
            stateQueue.async {
                guard self.isCapturing, self.isPaused else {
                    continuation.resume()
                    return
                }
                self.isPaused = false
                LoggerService.shared.log(category: .audio, level: .debug, message: "[AudioCaptureService] Capture resumed")
                continuation.resume()
            }
        }
    }
    
    /// Get list of running applications that can be captured
    func getAvailableApplications() async throws -> [SCRunningApplication] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.applications
    }
}

// MARK: - SCStreamDelegate

@available(macOS 13.0, *)
extension AudioCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        LoggerService.shared.log(category: .audio, level: .error, message: "[AudioCaptureService] Stream stopped with error: \(error.localizedDescription)")
        // CRITICAL FIX: Use serial queue for thread-safe state access
        stateQueue.async {
            self.isCapturing = false
        }
        delegate?.audioCaptureService(self, didEncounterError: error)
    }
}

// MARK: - SCStreamOutput

@available(macOS 13.0, *)
extension AudioCaptureService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Skip if paused (v0.2)
        guard !isPaused else { return }
        
        // Only process audio, ignore video frames
        switch type {
        case .audio:
            delegate?.audioCaptureService(self, didCaptureSampleBuffer: sampleBuffer)
        case .screen, .microphone:
            // Silently discard video/microphone frames from SCStream - we handle mic separately
            break
        @unknown default:
            break
        }
    }
}

// MARK: - Errors

/// Errors that can occur during audio capture
enum AudioCaptureError: LocalizedError {
    case noDisplayAvailable
    case filterCreationFailed
    case configurationFailed
    case streamCreationFailed
    case captureNotStarted
    
    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display available for capture"
        case .filterCreationFailed:
            return "Failed to create content filter for capture"
        case .configurationFailed:
            return "Failed to configure stream settings"
        case .streamCreationFailed:
            return "Failed to create capture stream"
        case .captureNotStarted:
            return "Capture has not been started"
        }
    }
}

