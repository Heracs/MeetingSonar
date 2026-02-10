//
//  RecordingServiceProtocol.swift
//  MeetingSonar
//
//  Protocol defining recording service capabilities.
//  Abstracts the concrete implementation of the recording service.
//

import Foundation
import AVFoundation

/// Protocol defining recording service capabilities
///
/// ## Requirements
/// - Manage recording lifecycle (start, stop, pause, resume)
/// - Handle multiple recording trigger types
/// - Provide recording state and duration tracking
/// - Support audio capture from multiple sources
///
/// ## Usage
/// ```swift
/// class MockRecordingService: RecordingServiceProtocol {
///     var recordingState: RecordingState = .idle
///     func startRecording(trigger:appName:) async throws { }
///     // ...
/// }
/// ```
protocol RecordingServiceProtocol: AnyObject {

    // MARK: - Properties

    /// Current recording state
    var recordingState: RecordingState { get }

    /// Whether currently recording
    var isRecording: Bool { get }

    /// Current recording duration in seconds
    var currentDuration: TimeInterval { get }

    /// Adjusted duration (excluding pause time)
    var adjustedDuration: TimeInterval { get }

    /// How this recording was started
    var recordingTrigger: RecordingTrigger { get }

    // MARK: - Recording Control

    /// Starts a new recording session
    ///
    /// - Parameters:
    ///   - trigger: What triggered the recording (manual, auto, reminder)
    ///   - appName: Optional application name for filename
    /// - Throws: `MeetingSonarError.recording(.alreadyRecording)` if already recording
    /// - Throws: `MeetingSonarError.recording(.permissionDenied)` if required permissions missing
    func startRecording(trigger: RecordingTrigger, appName: String?) async throws

    /// Stops the current recording session
    ///
    /// - Important: Safe to call even if not recording
    func stopRecording()

    /// Pauses the current recording
    ///
    /// - Note: Used when system goes to sleep
    func pauseRecording()

    /// Resumes a paused recording
    func resumeRecording()
}

/// Delegate protocol for recording service events
protocol RecordingServiceDelegate: AnyObject {

    /// Called when recording starts
    func recordingDidStart(trigger: RecordingTrigger)

    /// Called when recording stops
    /// - Parameter url: URL of the saved recording file
    func recordingDidStop(url: URL)

    /// Called when recording is paused
    func recordingDidPause()

    /// Called when recording resumes
    func recordingDidResume()

    /// Called when recording fails
    /// - Parameter error: The error that occurred
    func recordingDidFail(error: MeetingSonarError)
}

// MARK: - Default Implementations

extension RecordingServiceDelegate {

    func recordingDidStart(trigger: RecordingTrigger) {
        LoggerService.shared.log(
            category: .recording,
            level: .info,
            message: "[RecordingService] Recording started: \(trigger)"
        )
    }

    func recordingDidStop(url: URL) {
        LoggerService.shared.log(
            category: .recording,
            level: .info,
            message: "[RecordingService] Recording stopped: \(url.lastPathComponent)"
        )
    }

    func recordingDidPause() {
        LoggerService.shared.log(
            category: .recording,
            level: .info,
            message: "[RecordingService] Recording paused"
        )
    }

    func recordingDidResume() {
        LoggerService.shared.log(
            category: .recording,
            level: .info,
            message: "[RecordingService] Recording resumed"
        )
    }

    func recordingDidFail(error: MeetingSonarError) {
        // Error is automatically logged by the caller
        LoggerService.shared.log(
            category: .recording,
            level: .error,
            message: "[RecordingService] Recording failed: \(error.errorDescription ?? "Unknown error")"
        )
    }
}
