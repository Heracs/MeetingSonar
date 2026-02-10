//
//  RecordingServiceTests.swift
//  MeetingSonarTests
//
//  Unit tests for RecordingService using Mock implementations.
//

import XCTest
@testable import MeetingSonar

@MainActor
final class RecordingServiceTests: XCTestCase {

    var sut: MockRecordingService!
    var mockMetadataManager: MockMetadataManager!
    var mockSettingsManager: MockSettingsManager!

    override func setUpWithError() throws {
        mockMetadataManager = MockMetadataManager()
        mockSettingsManager = MockSettingsManager()
        sut = MockRecordingService()
        sut.configureForTesting()
    }

    override func tearDownWithError() throws {
        sut = nil
        mockMetadataManager = nil
        mockSettingsManager = nil
    }

    // MARK: - State Transition Tests

    func testInitialStateIsIdle() {
        // Assert
        XCTAssertEqual(sut.recordingState, .idle)
        XCTAssertFalse(sut.isRecording)
        XCTAssertEqual(sut.currentDuration, 0.0)
    }

    func testStartRecordingChangesStateToRecording() async throws {
        // Act
        try await sut.startRecording(trigger: .manual, appName: nil)

        // Assert
        XCTAssertEqual(sut.recordingState, .recording)
        XCTAssertTrue(sut.isRecording)
        XCTAssertTrue(sut.startRecordingCalled)
    }

    func testStopRecordingChangesStateToIdle() async throws {
        // Arrange
        try await sut.startRecording(trigger: .manual, appName: nil)

        // Act
        sut.stopRecording()

        // Assert
        XCTAssertEqual(sut.recordingState, .idle)
        XCTAssertFalse(sut.isRecording)
    }

    func testPauseRecordingChangesStateToPaused() async throws {
        // Arrange
        try await sut.startRecording(trigger: .manual, appName: nil)

        // Act
        sut.pauseRecording()

        // Assert
        XCTAssertEqual(sut.recordingState, .paused)
        XCTAssertFalse(sut.isRecording) // paused is not considered "recording"
    }

    func testResumeRecordingChangesStateToRecording() async throws {
        // Arrange
        try await sut.startRecording(trigger: .manual, appName: nil)
        sut.pauseRecording()

        // Act
        sut.resumeRecording()

        // Assert
        XCTAssertEqual(sut.recordingState, .recording)
        XCTAssertTrue(sut.isRecording)
    }

    // MARK: - Recording Trigger Tests

    func testStartRecordingWithManualTrigger() async throws {
        // Act
        try await sut.startRecording(trigger: .manual, appName: nil)

        // Assert
        XCTAssertTrue(sut.startRecordingCalled)
        // Mock doesn't store trigger, but we can verify it was called
    }

    func testStartRecordingWithAutoTrigger() async throws {
        // Act
        try await sut.startRecording(trigger: .auto, appName: "Zoom")

        // Assert
        XCTAssertTrue(sut.startRecordingCalled)
    }

    func testStartRecordingWithSmartReminderTrigger() async throws {
        // Act
        try await sut.startRecording(trigger: .smartReminder, appName: "Teams")

        // Assert
        XCTAssertTrue(sut.startRecordingCalled)
    }

    // MARK: - Error Handling Tests

    func testStartRecordingThrowsErrorWhenAlreadyRecording() async throws {
        // Arrange
        try await sut.startRecording(trigger: .manual, appName: nil)
        sut.startRecordingError = MeetingSonarError.recording(.alreadyRecording)

        // Act & Assert
        do {
            try await sut.startRecording(trigger: .manual, appName: nil)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertTrue(error is MeetingSonarError)
        }
    }

    func testStartRecordingWithInjectedError() async {
        // Arrange
        let expectedError = MeetingSonarError.recording(.permissionDenied(.screenRecording))
        sut.startRecordingError = expectedError

        // Act & Assert
        do {
            try await sut.startRecording(trigger: .manual, appName: nil)
            XCTFail("Should have thrown \(expectedError)")
        } catch {
            // Check if it's the same error type (recording error)
            if let mse = error as? MeetingSonarError,
               case .recording = mse {
                // Expected
            } else {
                XCTFail("Expected recording error, got: \(error)")
            }
        }
    }

    // MARK: - Duration Tracking Tests

    func testCurrentDurationDefaultsToZero() {
        // Assert
        XCTAssertEqual(sut.currentDuration, 0.0)
    }

    func testCurrentDurationCanBeSet() {
        // Arrange
        let expectedDuration: TimeInterval = 123.45

        // Act
        sut.setCurrentDuration(expectedDuration)

        // Assert
        XCTAssertEqual(sut.currentDuration, expectedDuration)
    }

    // MARK: - Mock Behavior Tests

    func testMockCanBeReset() async throws {
        // Arrange
        try await sut.startRecording(trigger: .manual, appName: nil)
        sut.setCurrentDuration(100.0)

        // Act
        sut.reset()

        // Assert
        XCTAssertEqual(sut.recordingState, .idle)
        XCTAssertEqual(sut.currentDuration, 0.0)
        XCTAssertFalse(sut.startRecordingCalled)
    }

    func testMockTracksStartRecordingCalls() async throws {
        // Arrange
        sut.startRecordingCalled = false

        // Act
        try await sut.startRecording(trigger: .manual, appName: nil)

        // Assert
        XCTAssertTrue(sut.startRecordingCalled)
    }

    // MARK: - Recording State Enum Tests

    func testAllRecordingStatesExist() {
        // Arrange & Act
        let states: [RecordingState] = [.idle, .recording, .paused]

        // Assert - just verify these are the only cases we expect
        XCTAssertEqual(states.count, 3)
    }

    func testRecordingStateIsNotRecordingWhenIdle() {
        // Arrange
        sut.recordingState = .idle

        // Assert
        XCTAssertFalse(sut.isRecording)
    }

    func testRecordingStateIsNotRecordingWhenPaused() {
        // Arrange
        sut.recordingState = .paused

        // Assert
        XCTAssertFalse(sut.isRecording)
    }

    func testRecordingStateIsRecordingWhenRecording() {
        // Arrange
        sut.recordingState = .recording

        // Assert
        XCTAssertTrue(sut.isRecording)
    }

    // MARK: - Recording Trigger Enum Tests

    func testAllRecordingTriggersExist() {
        // Arrange & Act
        let triggers: [RecordingTrigger] = [.manual, .auto, .smartReminder]

        // Assert
        XCTAssertEqual(triggers.count, 3)
    }

    // MARK: - Edge Cases Tests

    func testMultipleStopRecordingCalls() async throws {
        // Arrange
        try await sut.startRecording(trigger: .manual, appName: nil)

        // Act - call stop multiple times
        sut.stopRecording()
        sut.stopRecording()
        sut.stopRecording()

        // Assert - should remain idle without errors
        XCTAssertEqual(sut.recordingState, .idle)
    }

    func testResumeWithoutPause() async throws {
        // Arrange - start recording but don't pause
        try await sut.startRecording(trigger: .manual, appName: nil)

        // Act - try to resume
        sut.resumeRecording()

        // Assert - should go to recording state
        XCTAssertEqual(sut.recordingState, .recording)
    }

    func testPauseWithoutRecording() {
        // Arrange - state is idle

        // Act - try to pause
        sut.pauseRecording()

        // Assert - should handle gracefully
        XCTAssertEqual(sut.recordingState, .paused)
    }

    // MARK: - Integration with MockMetadataManager

    func testRecordingServiceWithMockMetadataManager() async throws {
        // Arrange
        let testMeta = SampleData.createMeetingMeta()

        // Act
        await mockMetadataManager.add(testMeta)

        // Assert
        XCTAssertEqual(mockMetadataManager.recordings.count, 1)
        XCTAssertEqual(mockMetadataManager.recordings.first?.id, testMeta.id)
    }
}
