//
//  AudioCaptureProtocol.swift
//  MeetingSonar
//
//  Protocol defining audio capture capabilities.
//  Abstracts the concrete implementation of audio capture services.
//

import Foundation
import AVFoundation
import ScreenCaptureKit

/// Protocol defining audio capture capabilities
///
/// ## Requirements
/// - Capture system audio using ScreenCaptureKit
/// - Support pause/resume operations
/// - Provide audio sample buffers via callback
///
/// ## Usage
/// ```swift
/// class MockAudioCapture: AudioCaptureProtocol {
///     var isCapturing = false
///     func startCapture(targetApp:) async throws { isCapturing = true }
///     // ...
/// }
/// ```
protocol AudioCaptureProtocol: AnyObject {

    // MARK: - Properties

    /// Whether audio capture is currently active
    var isCapturing: Bool { get }

    /// Audio format being captured
    var audioFormat: AVAudioFormat? { get }

    // MARK: - Control

    /// Starts capturing system audio
    ///
    /// - Parameter targetApp: Optional specific application to capture audio from
    /// - Throws: `MeetingSonarError.recording(.permissionDenied)` if screen recording permission not granted
    /// - Throws: `MeetingSonarError.recording(.captureFailed)` if capture cannot start
    func startCapture(targetApp: SCRunningApplication?) async throws

    /// Stops capturing audio
    ///
    /// - Important: This method should be safe to call multiple times
    func stopCapture()

    /// Pauses audio capture without releasing resources
    ///
    /// - Important: Can be resumed later with `resumeCapture()`
    func pauseCapture()

    /// Resumes audio capture after pause
    func resumeCapture()

    // MARK: - Delegate

    /// Delegate for receiving captured audio samples
    var audioDelegate: AudioCaptureDelegate? { get set }

    /// Session for ScreenCaptureKit integration
    var scStream: SCStream? { get }
}

/// Audio source types
enum AudioSource {
    case systemAudio
    case microphone
    case mixed
}

// MARK: - Default Implementations

extension AudioCaptureDelegate {

    func audioCaptureDidOutput(sampleBuffer: CMSampleBuffer, source: AudioSource) {
        // Default implementation does nothing
    }

    func audioCaptureDidFail(error: Error) {
        LoggerService.shared.log(
            category: .audio,
            level: .error,
            message: "[AudioCaptureDelegate] Capture failed: \(error.localizedDescription)"
        )
    }
}
