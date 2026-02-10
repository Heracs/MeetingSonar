//
//  MockRecordingService.swift
//  MeetingSonar
//
//  Mock implementation of RecordingServiceProtocol for testing.
//

import Foundation
import AVFoundation

/// Mock recording service for unit testing
///
/// ## Usage
/// ```swift
/// let mockRecorder = MockRecordingService()
/// mockRecorder.startRecording(trigger: .manual, appName: "Test")
/// XCTAssertEqual(mockRecorder.recordingState, .recording)
/// ```
@MainActor
final class MockRecordingService: RecordingServiceProtocol {

    // MARK: - Properties

    var recordingState: RecordingState = .idle
    var isRecording: Bool { recordingState == .recording }
    var currentDuration: TimeInterval = 0
    var adjustedDuration: TimeInterval = 0
    var recordingTrigger: RecordingTrigger = .manual

    /// Whether startRecording was called
    var startRecordingCalled = false
    /// Whether stopRecording was called
    private(set) var stopRecordingCalled = false
    /// Whether pauseRecording was called
    private(set) var pauseRecordingCalled = false
    /// Whether resumeRecording was called
    private(set) var resumeRecordingCalled = false

    /// Last trigger passed to startRecording
    private(set) var lastStartTrigger: RecordingTrigger?
    /// Last app name passed to startRecording
    private(set) var lastAppName: String?

    /// Error to throw from startRecording (nil for success)
    var startRecordingError: Error?

    // MARK: - Recording Control

    func startRecording(trigger: RecordingTrigger, appName: String?) async throws {
        startRecordingCalled = true
        lastStartTrigger = trigger
        lastAppName = appName

        if let error = startRecordingError {
            throw error
        }

        recordingState = .recording
        recordingTrigger = trigger
    }

    func stopRecording() {
        stopRecordingCalled = true
        recordingState = .idle
    }

    func pauseRecording() {
        pauseRecordingCalled = true
        recordingState = .paused
    }

    func resumeRecording() {
        resumeRecordingCalled = true
        recordingState = .recording
    }

    // MARK: - Test Helpers

    /// Configure for testing (clears all state)
    func configureForTesting() {
        reset()
    }

    /// Set current duration (for testing)
    func setCurrentDuration(_ duration: TimeInterval) {
        currentDuration = duration
    }

    /// Reset all tracking state
    func reset() {
        recordingState = .idle
        currentDuration = 0
        adjustedDuration = 0
        recordingTrigger = .manual
        startRecordingCalled = false
        stopRecordingCalled = false
        pauseRecordingCalled = false
        resumeRecordingCalled = false
        lastStartTrigger = nil
        lastAppName = nil
        startRecordingError = nil
    }

    /// Simulate recording progress
    /// - Parameter duration: The duration to set
    func simulateRecordingProgress(duration: TimeInterval) {
        currentDuration = duration
        adjustedDuration = duration
    }
}

// MARK: - Async Throw Validation

extension MockRecordingService {
    /// Validates that startRecording was called with specific parameters
    /// - Parameters:
    ///   - trigger: Expected trigger type
    ///   - appName: Expected app name (optional)
    /// - Returns: true if called with matching parameters
    func wasStartedWith(trigger: RecordingTrigger, appName: String? = nil) -> Bool {
        return startRecordingCalled &&
               lastStartTrigger == trigger &&
               lastAppName == appName
    }
}
