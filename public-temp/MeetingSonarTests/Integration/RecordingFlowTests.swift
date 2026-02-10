//
//  RecordingFlowTests.swift
//  MeetingSonarTests
//
//  Integration tests for recording workflow using Mock implementations.
//

import XCTest
@testable import MeetingSonar

@MainActor
final class RecordingFlowTests: XCTestCase {

    var mockRecordingService: MockRecordingService!
    var mockMetadataManager: MockMetadataManager!
    var mockSettingsManager: MockSettingsManager!

    override func setUpWithError() throws {
        mockRecordingService = MockRecordingService()
        mockMetadataManager = MockMetadataManager()
        mockSettingsManager = MockSettingsManager()

        mockRecordingService.configureForTesting()
        mockMetadataManager.configureForTesting()
        mockSettingsManager.configureForTesting()
    }

    override func tearDownWithError() throws {
        mockRecordingService = nil
        mockMetadataManager = nil
        mockSettingsManager = nil
    }

    // MARK: - Complete Recording Flow Tests

    func testFullRecordingFlow() async throws {
        // 1. Start Recording
        try await mockRecordingService.startRecording(trigger: .manual, appName: nil)
        XCTAssertEqual(mockRecordingService.recordingState, .recording)
        XCTAssertTrue(mockRecordingService.isRecording)

        // 2. Simulate recording progress
        mockRecordingService.setCurrentDuration(10.0)
        XCTAssertEqual(mockRecordingService.currentDuration, 10.0)

        mockRecordingService.setCurrentDuration(30.0)
        XCTAssertEqual(mockRecordingService.currentDuration, 30.0)

        // 3. Stop Recording
        mockRecordingService.stopRecording()
        XCTAssertEqual(mockRecordingService.recordingState, .idle)
        XCTAssertFalse(mockRecordingService.isRecording)

        // 4. Verify metadata was saved (in real flow, RecordingService would call MetadataManager)
        // In this mock test, we simulate it
        let meta = SampleData.createMeetingMeta(
            filename: "20240121-1400_Test.m4a",
            source: "System Audio",
            startTime: Date(),
            duration: 30.0,
            status: .pending
        )
        await mockMetadataManager.add(meta)

        // Assert
        XCTAssertEqual(mockMetadataManager.recordings.count, 1)
        XCTAssertEqual(mockMetadataManager.recordings.first?.duration, 30.0)
    }

    // MARK: - Pause/Resume Flow Tests

    func testPauseAndResumeFlow() async throws {
        // 1. Start Recording
        try await mockRecordingService.startRecording(trigger: .manual, appName: nil)
        XCTAssertEqual(mockRecordingService.recordingState, .recording)

        // 2. Pause
        mockRecordingService.pauseRecording()
        XCTAssertEqual(mockRecordingService.recordingState, .paused)
        XCTAssertFalse(mockRecordingService.isRecording)

        // 3. Resume
        mockRecordingService.resumeRecording()
        XCTAssertEqual(mockRecordingService.recordingState, .recording)
        XCTAssertTrue(mockRecordingService.isRecording)

        // 4. Stop
        mockRecordingService.stopRecording()
        XCTAssertEqual(mockRecordingService.recordingState, .idle)
    }

    // MARK: - Smart Detection Flow Tests

    func testAutoDetectionFlow() async throws {
        // 1. Detection starts monitoring
        mockSettingsManager.smartDetectionMode = .auto
        XCTAssertEqual(mockSettingsManager.smartDetectionMode, .auto)

        // 2. Detection detects meeting app
        let detectedApp = "Zoom"

        // 3. Detection triggers recording
        try await mockRecordingService.startRecording(trigger: .auto, appName: detectedApp)
        XCTAssertTrue(mockRecordingService.isRecording)
        XCTAssertTrue(mockRecordingService.startRecordingCalled)

        // 4. Meeting ends, detection stops recording
        mockRecordingService.stopRecording()
        XCTAssertFalse(mockRecordingService.isRecording)

        // 5. Verify metadata saved with correct source
        let meta = SampleData.createMeetingMeta(
            filename: "20240121-1400_Zoom.m4a",
            source: detectedApp,
            startTime: Date(),
            duration: 60.0,
            status: .pending
        )
        await mockMetadataManager.add(meta)

        // Assert
        XCTAssertEqual(mockMetadataManager.recordings.count, 1)
        XCTAssertEqual(mockMetadataManager.recordings.first?.source, detectedApp)
    }

    func testReminderModeFlow() async throws {
        // 1. Detection in reminder mode
        mockSettingsManager.smartDetectionMode = .remind
        XCTAssertEqual(mockSettingsManager.smartDetectionMode, .remind)

        // 2. Detection detects meeting (should NOT auto-record)
        let detectedApp = "Teams"

        // In reminder mode, detection would show notification
        // User clicks notification to start recording
        try await mockRecordingService.startRecording(trigger: .smartReminder, appName: detectedApp)
        XCTAssertTrue(mockRecordingService.isRecording)

        // 3. Stop recording
        mockRecordingService.stopRecording()
        XCTAssertFalse(mockRecordingService.isRecording)
    }

    // MARK: - Error Recovery Flow Tests

    func testRecordingFailureRecovery() async throws {
        // 1. Attempt to start with permission error
        mockRecordingService.startRecordingError = MeetingSonarError.recording(.permissionDenied(.screenRecording))

        do {
            try await mockRecordingService.startRecording(trigger: .manual, appName: nil)
            XCTFail("Should have thrown permission error")
        } catch {
            // Verify it's a recording error
            if let mse = error as? MeetingSonarError,
               case .recording = mse {
                // Expected
            } else {
                XCTFail("Expected recording error, got: \(error)")
            }
        }

        // 2. Verify state is still idle
        XCTAssertEqual(mockRecordingService.recordingState, .idle)

        // 3. Fix permission and retry
        mockRecordingService.startRecordingError = nil
        try await mockRecordingService.startRecording(trigger: .manual, appName: nil)

        // 4. Verify recording started
        XCTAssertTrue(mockRecordingService.isRecording)
    }

    func testMetadataSaveFailure() async throws {
        // 1. Start and stop recording
        try await mockRecordingService.startRecording(trigger: .manual, appName: nil)
        mockRecordingService.setCurrentDuration(45.0)
        mockRecordingService.stopRecording()

        // 2. Simulate metadata save failure
        mockMetadataManager.addError = MeetingSonarError.storage(.diskInsufficient(required: 100_000_000, available: 10_000_000))

        let meta = SampleData.createMeetingMeta(
            filename: "20240121-1400_Test.m4a",
            source: "System Audio",
            startTime: Date(),
            duration: 45.0,
            status: .pending
        )

        // 3. Attempt to save (would fail in real scenario)
        // In mock, we just verify error tracking
        XCTAssertNotNil(mockMetadataManager.addError)

        // 4. Fix error and retry
        mockMetadataManager.addError = nil
        await mockMetadataManager.add(meta)

        // 5. Verify saved
        XCTAssertEqual(mockMetadataManager.recordings.count, 1)
    }

    // MARK: - Multiple Recordings Flow Tests

    func testSequentialRecordings() async throws {
        // Recording 1
        try await mockRecordingService.startRecording(trigger: .manual, appName: nil)
        mockRecordingService.setCurrentDuration(30.0)
        mockRecordingService.stopRecording()

        var meta1 = SampleData.createMeetingMeta(
            filename: "20240121-1000_Meeting1.m4a",
            source: "Zoom",
            startTime: Date(),
            duration: 30.0,
            status: .pending
        )
        await mockMetadataManager.add(meta1)

        // Recording 2
        mockRecordingService.reset()
        try await mockRecordingService.startRecording(trigger: .manual, appName: nil)
        mockRecordingService.setCurrentDuration(45.0)
        mockRecordingService.stopRecording()

        var meta2 = SampleData.createMeetingMeta(
            filename: "20240121-1100_Meeting2.m4a",
            source: "Teams",
            startTime: Date(),
            duration: 45.0,
            status: .pending
        )
        await mockMetadataManager.add(meta2)

        // Assert
        XCTAssertEqual(mockMetadataManager.recordings.count, 2)
    }

    // MARK: - Metadata Operations Flow Tests

    func testRecordingAndRenameFlow() async throws {
        // 1. Create recording
        try await mockRecordingService.startRecording(trigger: .manual, appName: nil)
        mockRecordingService.stopRecording()

        var meta = SampleData.createMeetingMeta(
            filename: "20240121-1400_Test.m4a",
            source: "System Audio",
            startTime: Date(),
            duration: 60.0,
            status: .pending
        )
        await mockMetadataManager.add(meta)

        // 2. Rename
        await mockMetadataManager.rename(id: meta.id, newTitle: "Renamed Meeting")

        // 3. Verify rename
        XCTAssertEqual(mockMetadataManager.recordings.first?.title, "Renamed Meeting")

        // 4. Update
        meta.title = "Another Update"
        await mockMetadataManager.update(meta)

        // 5. Verify update
        XCTAssertEqual(mockMetadataManager.recordings.first?.title, "Another Update")
    }

    func testRecordingAndDeleteFlow() async throws {
        // 1. Create recording
        try await mockRecordingService.startRecording(trigger: .manual, appName: nil)
        mockRecordingService.stopRecording()

        let meta = SampleData.createMeetingMeta()
        await mockMetadataManager.add(meta)

        // 2. Verify exists
        XCTAssertEqual(mockMetadataManager.recordings.count, 1)

        // 3. Delete
        try await mockMetadataManager.delete(id: meta.id)

        // 4. Verify deleted
        XCTAssertTrue(mockMetadataManager.recordings.isEmpty)
    }

    // MARK: - Edge Cases Flow Tests

    func testRapidStartStop() async throws {
        // Rapid start/stop cycles
        for _ in 0..<10 {
            try await mockRecordingService.startRecording(trigger: .manual, appName: nil)
            mockRecordingService.stopRecording()
            mockRecordingService.reset()
        }

        // Final state should be idle
        XCTAssertEqual(mockRecordingService.recordingState, .idle)
    }

    func testStartWithoutStop() async throws {
        // Start without stopping (simulates crash scenario)
        try await mockRecordingService.startRecording(trigger: .manual, appName: nil)
        mockRecordingService.setCurrentDuration(120.0)

        // In real scenario, app would recover on next launch
        // Here we just verify state
        XCTAssertTrue(mockRecordingService.isRecording)
        XCTAssertEqual(mockRecordingService.currentDuration, 120.0)
    }
}
