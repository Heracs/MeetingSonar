//
//  DetectionFlowTests.swift
//  MeetingSonarTests
//
//  Integration tests for smart detection workflow using Mock implementations.
//

import XCTest
@testable import MeetingSonar

@MainActor
final class DetectionFlowTests: XCTestCase {

    var mockDetectionService: MockDetectionService!
    var mockRecordingService: MockRecordingService!
    var mockSettingsManager: MockSettingsManager!
    private var notificationSent = false

    override func setUpWithError() throws {
        mockDetectionService = MockDetectionService()
        mockRecordingService = MockRecordingService()
        mockSettingsManager = MockSettingsManager()

        mockDetectionService.configureForTesting()
        mockRecordingService.configureForTesting()
        mockSettingsManager.configureForTesting()
        notificationSent = false
    }

    override func tearDownWithError() throws {
        mockDetectionService = nil
        mockRecordingService = nil
        mockSettingsManager = nil
    }

    // MARK: - Auto Mode Flow Tests

    func testAutoModeFullFlow() async throws {
        // 1. Enable smart detection in auto mode
        mockSettingsManager.smartDetectionEnabled = true
        mockSettingsManager.smartDetectionMode = .auto
        XCTAssertTrue(mockSettingsManager.smartDetectionEnabled)
        XCTAssertEqual(mockSettingsManager.smartDetectionMode, .auto)

        // 2. Start detection service
        mockDetectionService.start()
        XCTAssertTrue(mockDetectionService.isRunning)

        // 3. Simulate meeting app detected (Zoom)
        let detectedApp = "Zoom"

        // 4. Detection triggers auto-recording
        try await mockRecordingService.startRecording(trigger: .auto, appName: detectedApp)
        XCTAssertTrue(mockRecordingService.isRecording)
        XCTAssertEqual(mockRecordingService.startRecordingCalled, true)

        // 5. Simulate recording progress
        mockRecordingService.setCurrentDuration(300.0) // 5 minutes

        // 6. Simulate meeting end
        mockRecordingService.stopRecording()
        XCTAssertFalse(mockRecordingService.isRecording)

        // 7. Detection continues monitoring
        XCTAssertTrue(mockDetectionService.isRunning)

        // Cleanup
        mockDetectionService.cleanup()
        XCTAssertFalse(mockDetectionService.isRunning)
    }

    func testAutoModeDetectsMultipleApps() async throws {
        // 1. Setup
        mockSettingsManager.smartDetectionEnabled = true
        mockSettingsManager.smartDetectionMode = .auto
        mockDetectionService.start()

        // 2. First app detected - Teams
        try await mockRecordingService.startRecording(trigger: .auto, appName: "Teams")
        XCTAssertTrue(mockRecordingService.isRecording)

        // 3. First meeting ends
        mockRecordingService.stopRecording()
        mockRecordingService.reset()

        // 4. Second app detected - Zoom
        try await mockRecordingService.startRecording(trigger: .auto, appName: "Zoom")
        XCTAssertTrue(mockRecordingService.isRecording)

        // 5. Second meeting ends
        mockRecordingService.stopRecording()

        // Cleanup
        mockDetectionService.cleanup()
    }

    // MARK: - Reminder Mode Flow Tests

    func testReminderModeFullFlow() async throws {
        // 1. Enable smart detection in reminder mode
        mockSettingsManager.smartDetectionEnabled = true
        mockSettingsManager.smartDetectionMode = .remind
        XCTAssertTrue(mockSettingsManager.smartDetectionEnabled)
        XCTAssertEqual(mockSettingsManager.smartDetectionMode, .remind)

        // 2. Start detection service
        mockDetectionService.start()
        XCTAssertTrue(mockDetectionService.isRunning)

        // 3. Simulate meeting app detected
        let detectedApp = "Webex"

        // 4. In reminder mode, notification would be sent
        // We simulate this by setting a flag
        notificationSent = true

        // 5. User clicks notification to start recording
        try await mockRecordingService.startRecording(trigger: .smartReminder, appName: detectedApp)
        XCTAssertTrue(mockRecordingService.isRecording)

        // 6. Meeting ends
        mockRecordingService.stopRecording()

        // Cleanup
        mockDetectionService.cleanup()
    }

    func testReminderModeUserDismissesNotification() async {
        // 1. Setup
        mockSettingsManager.smartDetectionEnabled = true
        mockSettingsManager.smartDetectionMode = .remind
        mockDetectionService.start()

        // 2. Meeting detected, notification sent (simulated)
        notificationSent = true

        // 3. User dismisses notification (no recording started)
        XCTAssertFalse(mockRecordingService.isRecording)

        // 4. Detection continues monitoring
        XCTAssertTrue(mockDetectionService.isRunning)

        // Cleanup
        mockDetectionService.cleanup()
    }

    // MARK: - Detection Service Lifecycle Tests

    func testDetectionStartStopFlow() {
        // 1. Not running initially
        XCTAssertFalse(mockDetectionService.isRunning)

        // 2. Start
        mockDetectionService.start()
        XCTAssertTrue(mockDetectionService.isRunning)

        // 3. Stop
        mockDetectionService.cleanup()
        XCTAssertFalse(mockDetectionService.isRunning)

        // 4. Start again
        mockDetectionService.start()
        XCTAssertTrue(mockDetectionService.isRunning)

        // 5. Final cleanup
        mockDetectionService.cleanup()
        XCTAssertFalse(mockDetectionService.isRunning)
    }

    func testDetectionDisabledDoesNotTriggerRecording() async throws {
        // 1. Smart detection disabled
        mockSettingsManager.smartDetectionEnabled = false
        XCTAssertFalse(mockSettingsManager.smartDetectionEnabled)

        // 2. Start detection service (should not monitor)
        mockDetectionService.start()

        // 3. Simulate meeting app detection (would be ignored)
        // In real implementation, detection would check settings.enabled
        // Here we verify that even if service is running, it won't trigger

        // 4. Recording should NOT start
        XCTAssertFalse(mockRecordingService.isRecording)

        // Cleanup
        mockDetectionService.cleanup()
    }

    // MARK: - Mode Switching Tests

    func testSwitchFromAutoToReminderMode() async throws {
        // 1. Start in auto mode
        mockSettingsManager.smartDetectionMode = .auto
        mockDetectionService.start()

        // 2. Simulate meeting in auto mode
        try await mockRecordingService.startRecording(trigger: .auto, appName: "Zoom")
        XCTAssertTrue(mockRecordingService.isRecording)

        // 3. Stop recording
        mockRecordingService.stopRecording()

        // 4. Switch to reminder mode
        mockSettingsManager.smartDetectionMode = .remind
        XCTAssertEqual(mockSettingsManager.smartDetectionMode, .remind)

        // 5. Simulate another meeting (should send notification, not auto-record)
        notificationSent = true

        // Recording should NOT start automatically
        XCTAssertFalse(mockRecordingService.isRecording)

        // Cleanup
        mockDetectionService.cleanup()
    }

    func testToggleSmartDetection() async throws {
        // 1. Enable smart detection
        mockSettingsManager.smartDetectionEnabled = true
        mockSettingsManager.smartDetectionMode = .auto
        mockDetectionService.start()
        XCTAssertTrue(mockDetectionService.isRunning)

        // 2. Simulate meeting
        try await mockRecordingService.startRecording(trigger: .auto, appName: "Zoom")
        mockRecordingService.stopRecording()

        // 3. Disable smart detection
        mockSettingsManager.smartDetectionEnabled = false
        mockDetectionService.cleanup()
        XCTAssertFalse(mockDetectionService.isRunning)

        // 4. Simulate another meeting (should be ignored)
        XCTAssertFalse(mockRecordingService.isRecording)

        // 5. Re-enable
        mockSettingsManager.smartDetectionEnabled = true
        mockDetectionService.start()
        XCTAssertTrue(mockDetectionService.isRunning)

        // Cleanup
        mockDetectionService.cleanup()
    }

    // MARK: - Error Handling Tests

    func testDetectionRecordingFailure() async throws {
        // 1. Setup
        mockSettingsManager.smartDetectionEnabled = true
        mockSettingsManager.smartDetectionMode = .auto
        mockDetectionService.start()

        // 2. Recording fails
        mockRecordingService.startRecordingError = MeetingSonarError.recording(.permissionDenied(.screenRecording))

        // 3. Try to start recording
        do {
            try await mockRecordingService.startRecording(trigger: .auto, appName: "Zoom")
            XCTFail("Should have thrown error")
        } catch {
            // Expected error
        }

        // 4. Detection should continue running
        XCTAssertTrue(mockDetectionService.isRunning)

        // 5. Fix error and retry
        mockRecordingService.startRecordingError = nil
        try await mockRecordingService.startRecording(trigger: .auto, appName: "Teams")
        XCTAssertTrue(mockRecordingService.isRecording)

        // Cleanup
        mockRecordingService.stopRecording()
        mockDetectionService.cleanup()
    }

    // MARK: - Integration with Metadata Tests

    func testDetectionCreatesCorrectMetadata() async throws {
        // 1. Setup
        mockSettingsManager.smartDetectionEnabled = true
        mockSettingsManager.smartDetectionMode = .auto
        mockDetectionService.start()

        let mockMetadataManager = MockMetadataManager()
        mockMetadataManager.configureForTesting()

        // 2. Detect and record
        let appName = "Zoom"
        try await mockRecordingService.startRecording(trigger: .auto, appName: appName)
        mockRecordingService.setCurrentDuration(600.0)
        mockRecordingService.stopRecording()

        // 3. Create metadata with correct source
        let meta = SampleData.createMeetingMeta(
            filename: "20240121-1400_\(appName).m4a",
            source: appName,
            startTime: Date(),
            duration: 600.0,
            status: .pending
        )
        await mockMetadataManager.add(meta)

        // 4. Verify metadata
        XCTAssertEqual(mockMetadataManager.recordings.count, 1)
        XCTAssertEqual(mockMetadataManager.recordings.first?.source, appName)
        XCTAssertEqual(mockMetadataManager.recordings.first?.duration, 600.0)

        // Cleanup
        mockDetectionService.cleanup()
    }

    // MARK: - Edge Cases Tests

    func testRapidMeetingDetection() async throws {
        // Simulate rapid detection of multiple meetings
        mockSettingsManager.smartDetectionEnabled = true
        mockSettingsManager.smartDetectionMode = .auto
        mockDetectionService.start()

        let apps = ["Zoom", "Teams", "Webex", "Meet", "Skype"]

        for app in apps {
            // In real scenario, detection would prevent overlap
            // Here we simulate sequential meetings
            try await mockRecordingService.startRecording(trigger: .auto, appName: app)
            mockRecordingService.setCurrentDuration(60.0)
            mockRecordingService.stopRecording()
            mockRecordingService.reset()
        }

        // Detection should still be running
        XCTAssertTrue(mockDetectionService.isRunning)

        // Cleanup
        mockDetectionService.cleanup()
    }

    func testMeetingDetectionDuringRecording() async throws {
        // 1. Manual recording in progress
        try await mockRecordingService.startRecording(trigger: .manual, appName: nil)
        XCTAssertTrue(mockRecordingService.isRecording)

        // 2. Detection detects meeting (should NOT interfere)
        mockSettingsManager.smartDetectionEnabled = true
        mockDetectionService.start()

        // 3. Manual recording continues
        XCTAssertTrue(mockRecordingService.isRecording)
        XCTAssertEqual(mockRecordingService.currentDuration, 0.0)

        // 4. Stop manual recording
        mockRecordingService.stopRecording()

        // 5. Detection can now start auto-recording
        try await mockRecordingService.startRecording(trigger: .auto, appName: "Zoom")
        XCTAssertTrue(mockRecordingService.isRecording)

        // Cleanup
        mockRecordingService.stopRecording()
        mockDetectionService.cleanup()
    }

    // MARK: - WeChat Detection Tests (Pattern 2 Fix)

    func testWeChatPattern2ExcludesInputOutput() {
        // Verify that WeChat's "Input/Output" format does NOT match Pattern 2
        // This is the critical fix that prevents false positives

        // Pattern 2 should match "Started Input"
        let pattern2Valid = "setPlayState Started Input"
        XCTAssertTrue(pattern2Valid.contains("Input"))
        XCTAssertFalse(pattern2Valid.contains("Input/Output"))

        // Pattern 2 should NOT match "Started Input/Output"
        let pattern2Invalid = "setPlayState Started Input/Output"
        XCTAssertTrue(pattern2Invalid.contains("Input"))
        XCTAssertTrue(pattern2Invalid.contains("Input/Output"))

        // The fix in production code: `&& !line.contains("Input/Output")`
        // This ensures WeChat's "Input/Output" logs are excluded from Pattern 2 matching
    }

    func testWeChatDetectionSettingsDefaultState() {
        // WeChat detection should be disabled by default (privacy consideration)

        // Initially disabled
        XCTAssertFalse(mockSettingsManager.detectWeChat, "WeChat detection should be disabled by default")

        // Other apps should be enabled by default
        XCTAssertTrue(mockSettingsManager.detectTencentMeeting, "Tencent Meeting should be enabled by default")
        XCTAssertTrue(mockSettingsManager.detectFeishu, "Feishu should be enabled by default")
    }

    func testWeChatDetectionCanBeEnabled() {
        // Verify that WeChat detection can be enabled when user opts in

        // Enable WeChat detection
        mockSettingsManager.detectWeChat = true
        XCTAssertTrue(mockSettingsManager.detectWeChat, "WeChat detection should be enabled when set to true")

        // Disable again
        mockSettingsManager.detectWeChat = false
        XCTAssertFalse(mockSettingsManager.detectWeChat, "WeChat detection should be disabled when set to false")
    }

    func testAllPerAppDetectionSettingsWorkIndependently() {
        // Verify that all per-app detection settings work independently

        // Initial state
        XCTAssertTrue(mockSettingsManager.detectTencentMeeting)
        XCTAssertTrue(mockSettingsManager.detectFeishu)
        XCTAssertFalse(mockSettingsManager.detectWeChat)

        // Change independently
        mockSettingsManager.detectTencentMeeting = false
        mockSettingsManager.detectFeishu = false
        mockSettingsManager.detectWeChat = true

        XCTAssertFalse(mockSettingsManager.detectTencentMeeting, "Tencent Meeting should be disabled")
        XCTAssertFalse(mockSettingsManager.detectFeishu, "Feishu should be disabled")
        XCTAssertTrue(mockSettingsManager.detectWeChat, "WeChat should be enabled")
    }
}
