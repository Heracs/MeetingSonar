import XCTest
@testable import MeetingSonar

@MainActor
final class DetectionPolicyTests: XCTestCase {
    private let zoom = ApplicationMonitor.MonitoredApp(
        bundleIdentifier: "us.zoom.xos",
        processName: "zoom.us",
        logProcessAliases: ["zoom.us", "Zoom", "aomhost"],
        meetingWindowPatterns: ["Zoom Meeting", "Zoom Webinar", "Zoom会议"],
        excludeWindowPatterns: []
    )
    private let teamsNew = ApplicationMonitor.MonitoredApp(
        bundleIdentifier: "com.microsoft.teams2",
        processName: "MSTeams",
        logProcessAliases: ["MSTeams", "Microsoft Teams ModuleHost", "Microsoft Teams WebView Helper"],
        meetingWindowPatterns: ["| Microsoft Teams"],
        excludeWindowPatterns: ["Calendar | Microsoft Teams", "Chat | Microsoft Teams"]
    )
    private let tencent = ApplicationMonitor.MonitoredApp(
        bundleIdentifier: "com.tencent.meeting",
        processName: "TencentMeeting",
        logProcessAliases: ["TencentMeeting", "腾讯会议", "wemeet", "com.tencent.meeting"],
        meetingWindowPatterns: [],
        excludeWindowPatterns: []
    )
    private let feishu = ApplicationMonitor.MonitoredApp(
        bundleIdentifier: "com.electron.lark.iron",
        processName: "Feishu",
        logProcessAliases: ["Feishu", "Lark", "Lark Helper", "Lark Helper (Iron)", "com.electron.lark.iron"],
        meetingWindowPatterns: ["飞书会议"],
        excludeWindowPatterns: []
    )

    func testZoomMeetingUIWithOneParticipantIsConfirmed() {
        let policy = DetectionPolicy.defaultPolicy(for: zoom)
        let snapshot = AppSignalSnapshot(
            app: zoom,
            isRunning: true,
            processID: 123,
            windowState: .meetingUI,
            micState: .inactive,
            participantCount: ParticipantCountObservation(
                bundleIdentifier: "us.zoom.xos",
                count: 1,
                rawText: "Open participants panel, closed, 1 participants",
                confidence: .high,
                timestamp: Date()
            ),
            lastProcessEvent: nil,
            timestamp: Date()
        )

        XCTAssertEqual(
            policy.evidence(for: snapshot),
            .meetingConfirmed(participantCount: 1, confidence: .high)
        )
    }

    func testZoomPreJoinDoesNotConfirmMeeting() {
        let policy = DetectionPolicy.defaultPolicy(for: zoom)
        let snapshot = AppSignalSnapshot(
            app: zoom,
            isRunning: true,
            processID: 123,
            windowState: .preJoin,
            micState: .inactive,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date()
        )

        XCTAssertEqual(policy.evidence(for: snapshot), .notMeeting)
    }

    func testMicOnlySingleActiveIsCandidate() {
        let weChat = ApplicationMonitor.MonitoredApp(
            bundleIdentifier: "com.tencent.xinWeChat",
            processName: "WeChat",
            logProcessAliases: ["WeChat", "微信"],
            meetingWindowPatterns: [],
            excludeWindowPatterns: []
        )
        let policy = DetectionPolicy.defaultPolicy(for: weChat)
        let snapshot = AppSignalSnapshot(
            app: weChat,
            isRunning: true,
            processID: 456,
            windowState: .none,
            micState: .active,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date()
        )

        XCTAssertEqual(policy.evidence(for: snapshot), .candidate(reason: "mic_active_requires_debounce"))
    }

    func testMicSignalFromNotRunningAppIsNotMeeting() {
        let weChat = ApplicationMonitor.MonitoredApp(
            bundleIdentifier: "com.tencent.xinWeChat",
            processName: "WeChat",
            logProcessAliases: ["WeChat", "微信"],
            meetingWindowPatterns: [],
            excludeWindowPatterns: []
        )
        let policy = DetectionPolicy.defaultPolicy(for: weChat)
        let snapshot = AppSignalSnapshot(
            app: weChat,
            isRunning: false,
            processID: nil,
            windowState: .none,
            micState: .active,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date()
        )

        XCTAssertEqual(policy.evidence(for: snapshot), .notMeeting)
    }

    func testRemovedLegacyAppsUseUnavailablePolicy() {
        let teamsClassic = ApplicationMonitor.MonitoredApp(
            bundleIdentifier: "com.microsoft.teams",
            processName: "Microsoft Teams",
            logProcessAliases: ["Microsoft Teams"],
            meetingWindowPatterns: ["| Microsoft Teams", "Meeting"],
            excludeWindowPatterns: []
        )
        let webex = ApplicationMonitor.MonitoredApp(
            bundleIdentifier: "com.cisco.webex.webex",
            processName: "Webex",
            logProcessAliases: ["Webex"],
            meetingWindowPatterns: ["Webex Meeting"],
            excludeWindowPatterns: []
        )

        XCTAssertEqual(DetectionPolicy.defaultPolicy(for: teamsClassic).windowReliability, .unavailable)
        XCTAssertEqual(DetectionPolicy.defaultPolicy(for: webex).windowReliability, .unavailable)
    }

    func testTeamsNewMeetingWindowWithActiveMicIsConfirmed() {
        let policy = DetectionPolicy.defaultPolicy(for: teamsNew)
        let snapshot = AppSignalSnapshot(
            app: teamsNew,
            isRunning: true,
            processID: 456,
            windowState: .meetingUI,
            micState: .active,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date()
        )

        XCTAssertEqual(policy.evidence(for: snapshot), .meetingConfirmed(participantCount: nil, confidence: nil))
    }

    func testTeamsNewMainWindowWithActiveMicRequiresDebounce() {
        let policy = DetectionPolicy.defaultPolicy(for: teamsNew)
        let snapshot = AppSignalSnapshot(
            app: teamsNew,
            isRunning: true,
            processID: 456,
            windowState: .mainWindow,
            micState: .active,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date()
        )

        XCTAssertEqual(policy.evidence(for: snapshot), .candidate(reason: "weak_window_or_mic_requires_debounce"))
    }

    func testTencentMeetingUIConfirmsWithoutActiveMic() {
        let policy = DetectionPolicy.defaultPolicy(for: tencent)
        let snapshot = AppSignalSnapshot(
            app: tencent,
            isRunning: true,
            processID: 789,
            windowState: .meetingUI,
            micState: .inactive,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date()
        )

        XCTAssertEqual(policy.evidence(for: snapshot), .meetingConfirmed(participantCount: nil, confidence: nil))
    }

    func testTencentMainWindowWithActiveMicDoesNotConfirmMeeting() {
        let policy = DetectionPolicy.defaultPolicy(for: tencent)
        let snapshot = AppSignalSnapshot(
            app: tencent,
            isRunning: true,
            processID: 789,
            windowState: .mainWindow,
            micState: .active,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date()
        )

        XCTAssertEqual(policy.evidence(for: snapshot), .notMeeting)
    }

    func testFeishuMeetingUIWithoutActiveMicRequiresAudioSession() {
        let policy = DetectionPolicy.defaultPolicy(for: feishu)
        let snapshot = AppSignalSnapshot(
            app: feishu,
            isRunning: true,
            processID: 75383,
            windowState: .meetingUI,
            micState: .inactive,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date()
        )

        XCTAssertEqual(
            policy.evidence(for: snapshot),
            .candidate(reason: "meeting_window_requires_active_audio_session")
        )
    }

    func testFeishuMeetingUIWithActiveMicConfirmsMeeting() {
        let policy = DetectionPolicy.defaultPolicy(for: feishu)
        let snapshot = AppSignalSnapshot(
            app: feishu,
            isRunning: true,
            processID: 75383,
            windowState: .meetingUI,
            micState: .active,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date()
        )

        XCTAssertEqual(policy.evidence(for: snapshot), .meetingConfirmed(participantCount: nil, confidence: nil))
    }

    func testFeishuMainWindowWithActiveMicDoesNotConfirmMeeting() {
        let policy = DetectionPolicy.defaultPolicy(for: feishu)
        let snapshot = AppSignalSnapshot(
            app: feishu,
            isRunning: true,
            processID: 75383,
            windowState: .mainWindow,
            micState: .active,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date()
        )

        XCTAssertEqual(policy.evidence(for: snapshot), .notMeeting)
    }
}
