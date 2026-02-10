//
//  DetectionServiceProtocol.swift
//  MeetingSonar
//
//  Protocol defining smart detection service capabilities.
//  Abstracts the concrete implementation of the detection service.
//

import Foundation

/// Protocol defining smart detection service capabilities
///
/// ## Requirements
/// - Monitor meeting applications for active state
/// - Monitor microphone usage via system logs
/// - Trigger recording based on detection rules
/// - Support debounce delay before stopping
///
/// ## Usage
/// ```swift
/// class MockDetectionService: DetectionServiceProtocol {
///     func start() { }
///     func cleanup() { }
///     // ...
/// }
/// ```
@MainActor
protocol DetectionServiceProtocol: AnyObject {

    // MARK: - Control

    /// Starts monitoring for meeting activity
    ///
    /// - Important: No-op if already monitoring
    func start()

    /// Stops monitoring and cleans up resources
    ///
    /// - Important: Safe to call multiple times
    func cleanup()
}

// MARK: - Supporting Types

/// Reminder notification trigger
enum ReminderTrigger {
    case notification
    case button
}

/// Detection source
enum DetectionSource {
    case windowTitle
    case microphoneUsage
}

/// Delegate protocol for detection service events
protocol DetectionServiceDelegate: AnyObject {

    /// Called when a meeting is detected
    ///
    /// - Parameters:
    ///   - detected: Whether a meeting is detected
    ///   - source: The detection source (window title or microphone)
    func meetingDetectionDidChange(detected: Bool, source: DetectionSource)

    /// Called when detection should trigger recording
    func detectionShouldTriggerRecording()

    /// Called when detection fails
    /// - Parameter error: The error that occurred
    func detectionDidFail(error: MeetingSonarError)
}

// MARK: - Default Implementations

extension DetectionServiceDelegate {

    func meetingDetectionDidChange(detected: Bool, source: DetectionSource) {
        LoggerService.shared.log(
            category: .detection,
            level: detected ? .info : .debug,
            message: "[DetectionService] Meeting detection changed: \(detected), source: \(source)"
        )
    }

    func detectionShouldTriggerRecording() {
        LoggerService.shared.log(
            category: .detection,
            level: .info,
            message: "[DetectionService] Detection triggered recording"
        )
    }

    func detectionDidFail(error: MeetingSonarError) {
        // Error is automatically logged
        LoggerService.shared.log(
            category: .detection,
            level: .error,
            message: "[DetectionService] Detection failed: \(error.errorDescription ?? "Unknown error")"
        )
    }
}
