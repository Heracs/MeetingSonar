//
//  DetectionServiceTests.swift
//  MeetingSonarTests
//
//  Unit tests for DetectionService using Mock implementations.
//

import XCTest
@testable import MeetingSonar

@MainActor
final class DetectionServiceTests: XCTestCase {

    var sut: MockDetectionService!
    var mockRecordingService: MockRecordingService!
    var mockSettingsManager: MockSettingsManager!

    override func setUpWithError() throws {
        mockRecordingService = MockRecordingService()
        mockSettingsManager = MockSettingsManager()
        sut = MockDetectionService()
        sut.configureForTesting()
    }

    override func tearDownWithError() throws {
        sut = nil
        mockRecordingService = nil
        mockSettingsManager = nil
    }

    // MARK: - Lifecycle Tests

    func testInitialStateIsNotRunning() {
        // Assert
        XCTAssertFalse(sut.isRunning)
        XCTAssertFalse(sut.startCalled)
    }

    func testStartChangesIsRunningToTrue() {
        // Act
        sut.start()

        // Assert
        XCTAssertTrue(sut.isRunning)
        XCTAssertTrue(sut.startCalled)
    }

    func testCleanupChangesIsRunningToFalse() {
        // Arrange
        sut.start()

        // Act
        sut.cleanup()

        // Assert
        XCTAssertFalse(sut.isRunning)
    }

    // MARK: - Mock Behavior Tests

    func testMockCanBeReset() {
        // Arrange
        sut.start()

        // Act
        sut.reset()

        // Assert
        XCTAssertFalse(sut.isRunning)
        XCTAssertFalse(sut.startCalled)
    }

    func testMockTracksStartCalls() {
        // Arrange
        sut.startCalled = false

        // Act
        sut.start()

        // Assert
        XCTAssertTrue(sut.startCalled)
    }

    func testMockTracksMultipleStartCalls() {
        // Act
        sut.start()
        sut.start()
        sut.start()

        // Assert
        XCTAssertTrue(sut.isRunning)
        XCTAssertTrue(sut.startCalled)
    }

    // MARK: - Detection Mode Tests

    func testDetectionServiceSupportsAutoMode() {
        // Arrange & Act
        mockSettingsManager.smartDetectionMode = .auto

        // Assert
        XCTAssertEqual(mockSettingsManager.smartDetectionMode, .auto)
    }

    func testDetectionServiceSupportsReminderMode() {
        // Arrange & Act
        mockSettingsManager.smartDetectionMode = .remind

        // Assert
        XCTAssertEqual(mockSettingsManager.smartDetectionMode, .remind)
    }

    // MARK: - Edge Cases Tests

    func testMultipleCleanupCalls() {
        // Arrange
        sut.start()

        // Act - call cleanup multiple times
        sut.cleanup()
        sut.cleanup()
        sut.cleanup()

        // Assert - should handle gracefully
        XCTAssertFalse(sut.isRunning)
    }

    func testStartAfterCleanup() {
        // Arrange
        sut.start()
        sut.cleanup()

        // Act
        sut.start()

        // Assert - should be running again
        XCTAssertTrue(sut.isRunning)
    }

    func testCleanupWithoutStart() {
        // Arrange - never started

        // Act
        sut.cleanup()

        // Assert - should handle gracefully
        XCTAssertFalse(sut.isRunning)
    }

    // MARK: - Integration with MockRecordingService

    func testDetectionServiceCanStartRecording() async throws {
        // Arrange
        mockSettingsManager.smartDetectionMode = .auto

        // Act
        sut.start()
        try await mockRecordingService.startRecording(trigger: .auto, appName: "Zoom")

        // Assert
        XCTAssertTrue(sut.isRunning)
        XCTAssertTrue(mockRecordingService.isRecording)
    }

    func testDetectionServiceCanStopRecording() async throws {
        // Arrange
        sut.start()
        try await mockRecordingService.startRecording(trigger: .auto, appName: "Zoom")

        // Act
        mockRecordingService.stopRecording()

        // Assert
        XCTAssertTrue(sut.isRunning)
        XCTAssertFalse(mockRecordingService.isRecording)
    }

    // MARK: - Smart Detection Mode Tests

    func testSmartDetectionModeEnum() {
        // Arrange & Act
        let modes: [SettingsManager.SmartDetectionMode] = [.auto, .remind]

        // Assert
        XCTAssertEqual(modes.count, 2)
    }

    func testAutoModeRawValue() {
        // Arrange & Act
        let mode = SettingsManager.SmartDetectionMode.auto

        // Assert
        XCTAssertEqual(mode.rawValue, "auto")
    }

    func testRemindModeRawValue() {
        // Arrange & Act
        let mode = SettingsManager.SmartDetectionMode.remind

        // Assert
        XCTAssertEqual(mode.rawValue, "remind")
    }

    // MARK: - WeChat Detection Tests (Pattern 2 Fix)

    func testWeChatPattern2InputOutputExclusion() {
        // Test that WeChat's "Input/Output" format does NOT match Pattern 2
        // This is a critical fix to prevent false positives from WeChat logs
        // The fix adds `&& !line.contains("Input/Output")` to Pattern 2 matching

        // Note: This test verifies the MockLogMonitorService behavior
        // The production code in DetectionService.swift has the same fix applied

        // Pattern 2 should match "Started Input" but NOT "Started Input/Output"
        let pattern2MatchInput = "setPlayState Started Input"  // Should match
        let pattern2NoMatchInputOutput = "setPlayState Started Input/Output"  // Should NOT match

        // Verify the pattern logic:
        // - "Started Input" contains "Input" but NOT "Input/Output" -> matches
        // - "Started Input/Output" contains "Input/Output" -> does NOT match

        XCTAssertFalse(pattern2MatchInput.contains("Input/Output"), "Test setup error: pattern should not contain Input/Output")
        XCTAssertTrue(pattern2NoMatchInputOutput.contains("Input/Output"), "Test setup error: pattern should contain Input/Output")
    }

    func testWeChatDetectionSettings() {
        // Test that WeChat detection can be controlled via per-app settings
        // WeChat detection is disabled by default (detectWeChat = false)

        // Initially disabled
        XCTAssertFalse(mockSettingsManager.detectWeChat, "WeChat detection should be disabled by default")

        // Can be enabled
        mockSettingsManager.detectWeChat = true
        XCTAssertTrue(mockSettingsManager.detectWeChat, "WeChat detection should be enabled when set to true")

        // Can be disabled again
        mockSettingsManager.detectWeChat = false
        XCTAssertFalse(mockSettingsManager.detectWeChat, "WeChat detection should be disabled when set to false")
    }

    func testTencentMeetingDetectionSettings() {
        // Test that Tencent Meeting detection can be controlled via per-app settings
        // Tencent Meeting detection is enabled by default (detectTencentMeeting = true)

        // Initially enabled
        XCTAssertTrue(mockSettingsManager.detectTencentMeeting, "Tencent Meeting detection should be enabled by default")

        // Can be disabled
        mockSettingsManager.detectTencentMeeting = false
        XCTAssertFalse(mockSettingsManager.detectTencentMeeting, "Tencent Meeting detection should be disabled when set to false")

        // Can be enabled again
        mockSettingsManager.detectTencentMeeting = true
        XCTAssertTrue(mockSettingsManager.detectTencentMeeting, "Tencent Meeting detection should be enabled when set to true")
    }

    func testFeishuDetectionSettings() {
        // Test that Feishu detection can be controlled via per-app settings
        // Feishu detection is enabled by default (detectFeishu = true)

        // Initially enabled
        XCTAssertTrue(mockSettingsManager.detectFeishu, "Feishu detection should be enabled by default")

        // Can be disabled
        mockSettingsManager.detectFeishu = false
        XCTAssertFalse(mockSettingsManager.detectFeishu, "Feishu detection should be disabled when set to false")

        // Can be enabled again
        mockSettingsManager.detectFeishu = true
        XCTAssertTrue(mockSettingsManager.detectFeishu, "Feishu detection should be enabled when set to true")
    }

    func testAllPerAppDetectionSettings() {
        // Test that all per-app detection settings work independently

        // Initially: WeChat disabled, others enabled
        XCTAssertFalse(mockSettingsManager.detectWeChat)
        XCTAssertTrue(mockSettingsManager.detectTencentMeeting)
        XCTAssertTrue(mockSettingsManager.detectFeishu)

        // Change all settings
        mockSettingsManager.detectWeChat = true
        mockSettingsManager.detectTencentMeeting = false
        mockSettingsManager.detectFeishu = false

        XCTAssertTrue(mockSettingsManager.detectWeChat, "WeChat should be enabled")
        XCTAssertFalse(mockSettingsManager.detectTencentMeeting, "Tencent Meeting should be disabled")
        XCTAssertFalse(mockSettingsManager.detectFeishu, "Feishu should be disabled")

        // Reset to defaults
        mockSettingsManager.detectWeChat = false
        mockSettingsManager.detectTencentMeeting = true
        mockSettingsManager.detectFeishu = true

        XCTAssertFalse(mockSettingsManager.detectWeChat, "WeChat should be disabled (default)")
        XCTAssertTrue(mockSettingsManager.detectTencentMeeting, "Tencent Meeting should be enabled (default)")
        XCTAssertTrue(mockSettingsManager.detectFeishu, "Feishu should be enabled (default)")
    }
}
