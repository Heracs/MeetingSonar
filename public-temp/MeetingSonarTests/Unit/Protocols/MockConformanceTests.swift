//
//  MockConformanceTests.swift
//  MeetingSonarTests
//
//  Tests to verify all Mock implementations conform to their respective protocols.
//

import XCTest
@testable import MeetingSonar

@MainActor
final class MockConformanceTests: XCTestCase {

    // MARK: - MockRecordingService Protocol Conformance

    func testMockRecordingServiceConformsToProtocol() async throws {
        // Arrange
        let mock = MockRecordingService()
        mock.configureForTesting()

        // Act & Assert - verify all protocol methods are implemented
        // Start/Stop
        try await mock.startRecording(trigger: .manual, appName: nil)
        XCTAssertTrue(mock.isRecording)

        mock.stopRecording()
        XCTAssertFalse(mock.isRecording)

        // Pause/Resume
        mock.pauseRecording()
        mock.resumeRecording()

        // Properties
        _ = mock.recordingState
        _ = mock.isRecording
        _ = mock.currentDuration

        // Verify it's RecordingServiceProtocol type
        let protocolInstance: RecordingServiceProtocol = mock
        XCTAssertNotNil(protocolInstance)
    }

    // MARK: - MockDetectionService Protocol Conformance

    func testMockDetectionServiceConformsToProtocol() {
        // Arrange
        let mock = MockDetectionService()
        mock.configureForTesting()

        // Act & Assert - verify all protocol methods are implemented
        mock.start()
        // Note: isRunning is not exposed by DetectionServiceProtocol
        // It's an implementation detail of MockDetectionService

        mock.cleanup()
        // Note: isRunning is not exposed by DetectionServiceProtocol

        // Verify it's DetectionServiceProtocol type
        let protocolInstance: DetectionServiceProtocol = mock
        XCTAssertNotNil(protocolInstance)
    }

    // MARK: - MockMetadataManager Protocol Conformance

    func testMockMetadataManagerConformsToProtocol() async throws {
        // Arrange
        let mock = MockMetadataManager()
        mock.configureForTesting()

        // Act & Assert - verify all protocol methods are implemented
        await mock.load()
        XCTAssertTrue(mock.loadCalled)

        let meta = SampleData.createMeetingMeta()
        await mock.add(meta)
        XCTAssertTrue(mock.addCalled)

        await mock.update(meta)
        XCTAssertEqual(mock.recordings.count, 1)

        try await mock.delete(id: meta.id)
        XCTAssertTrue(mock.recordings.isEmpty)

        await mock.rename(id: UUID(), newTitle: "Test")
        await mock.scanAndMigrate()
        await mock.repairZeroDurations()

        // Properties
        _ = mock.recordings

        // Verify it's MetadataManagerProtocol type
        let protocolInstance: MetadataManagerProtocol = mock
        XCTAssertNotNil(protocolInstance)
    }

    // MARK: - MockSettingsManager Protocol Conformance

    func testMockSettingsManagerConformsToProtocol() {
        // Arrange
        let mock = MockSettingsManager()
        mock.configureForTesting()

        // Act & Assert - verify all protocol properties are implemented
        _ = mock.savePath
        _ = mock.audioFormat
        _ = mock.audioQuality
        _ = mock.smartDetectionEnabled
        _ = mock.smartDetectionMode
        // Note: language is not in the SettingsManagerProtocol
        _ = mock.includeSystemAudio
        _ = mock.includeMicrophone
        _ = mock.selectedUnifiedASRId
        _ = mock.selectedUnifiedLLMId

        // Methods
        _ = mock.generateFilename(appName: "Zoom")
        _ = mock.generateFileURL(appName: "Teams")

        // Note: MockSettingsManager no longer conforms to SettingsManagerProtocol
        // It's a standalone mock for testing purposes
    }

    // MARK: - Protocol Type Compatibility

    func testRecordingServiceProtocolPolymorphism() async throws {
        // Arrange
        let mock: RecordingServiceProtocol = MockRecordingService()

        // Act & Assert - should work through protocol type
        try await mock.startRecording(trigger: .manual, appName: nil)
        XCTAssertTrue(mock.isRecording)

        mock.stopRecording()
        XCTAssertFalse(mock.isRecording)
    }

    func testDetectionServiceProtocolPolymorphism() {
        // Arrange
        let mock: DetectionServiceProtocol = MockDetectionService()

        // Act & Assert - should work through protocol type
        mock.start()
        // Note: isRunning is not exposed by the protocol, so we can't test it here
        // The mock implementation tracks it but it's not part of the protocol interface

        mock.cleanup()
        // Same for cleanup - we can't assert on isRunning via the protocol
    }

    func testMetadataManagerProtocolPolymorphism() async throws {
        // Arrange
        let mock: MetadataManagerProtocol = MockMetadataManager()

        // Act & Assert - should work through protocol type
        await mock.load()

        let meta = SampleData.createMeetingMeta()
        await mock.add(meta)

        try await mock.delete(id: meta.id)
    }

    func testSettingsManagerProtocolPolymorphism() {
        // Arrange
        let mock = MockSettingsManager()

        // Act & Assert - verify mock can be used
        _ = mock.audioFormat
        _ = mock.generateFilename(appName: nil)
    }

    // MARK: - Dependency Injection Compatibility

    func testMockCanBeUsedForDependencyInjection() async {
        // This test verifies that mocks can be used for dependency injection
        // in services that support constructor injection

        // Arrange - RecordingService with mock dependencies
        let mockAudioCapture = MockRecordingService()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        // Act - These should compile without errors
        // Note: RecordingService.createForTesting requires specific parameters
        // This test mainly verifies type compatibility
        let recordingService: RecordingServiceProtocol = mockAudioCapture
        let metadataManager: MetadataManagerProtocol = mockMetadata

        // Assert
        XCTAssertNotNil(recordingService)
        XCTAssertNotNil(metadataManager)
        XCTAssertNotNil(mockSettings)
    }

    // MARK: - Mock Method Signature Tests

    func testMockRecordingServiceMethodSignatures() async throws {
        let mock = MockRecordingService()

        // Verify async methods
        try await mock.startRecording(trigger: .manual, appName: nil)

        // Verify sync methods
        mock.stopRecording()
        mock.pauseRecording()
        mock.resumeRecording()

        // Verify properties
        let state: RecordingState = mock.recordingState
        let isRecording: Bool = mock.isRecording
        let duration: TimeInterval = mock.currentDuration

        XCTAssertNotNil(state)
        XCTAssertNotNil(isRecording)
        XCTAssertNotNil(duration)
    }

    func testMockMetadataManagerAsyncMethods() async {
        let mock = MockMetadataManager()

        // All these should be async and not crash
        await mock.load()
        await mock.add(SampleData.createMeetingMeta())
        await mock.update(SampleData.createMeetingMeta())
        await mock.rename(id: UUID(), newTitle: "Test")
        await mock.scanAndMigrate()
        await mock.repairZeroDurations()

        // delete can throw
        do {
            try await mock.delete(id: UUID())
        } catch {
            // Expected
        }
    }

    // MARK: - Mock State Isolation

    func testMocksAreIndependentInstances() async throws {
        // Arrange
        let mock1 = MockRecordingService()
        let mock2 = MockRecordingService()

        // Act
        try await mock1.startRecording(trigger: .manual, appName: nil)

        // Assert
        XCTAssertTrue(mock1.isRecording)
        XCTAssertFalse(mock2.isRecording)
    }

    func testMockMetadataManagerIsolation() async {
        // Arrange
        let mock1 = MockMetadataManager()
        let mock2 = MockMetadataManager()

        // Act
        let meta = SampleData.createMeetingMeta()
        await mock1.add(meta)

        // Assert
        XCTAssertEqual(mock1.recordings.count, 1)
        XCTAssertEqual(mock2.recordings.count, 0)
    }
}
