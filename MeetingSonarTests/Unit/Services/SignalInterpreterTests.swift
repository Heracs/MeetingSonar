import XCTest
@testable import MeetingSonar

@MainActor
final class SignalInterpreterTests: XCTestCase {
    private let teamsNew = ApplicationMonitor.MonitoredApp(
        bundleIdentifier: "com.microsoft.teams2",
        processName: "MSTeams",
        logProcessAliases: ["MSTeams", "Microsoft Teams ModuleHost", "Microsoft Teams WebView Helper"],
        meetingWindowPatterns: [],
        excludeWindowPatterns: []
    )
    private let zoom = ApplicationMonitor.MonitoredApp(
        bundleIdentifier: "us.zoom.xos",
        processName: "zoom.us",
        logProcessAliases: ["zoom.us", "Zoom", "aomhost"],
        meetingWindowPatterns: ["Zoom Meeting", "Zoom Webinar", "Zoom会议"],
        excludeWindowPatterns: []
    )
    private let feishu = ApplicationMonitor.MonitoredApp(
        bundleIdentifier: "com.electron.lark.iron",
        processName: "Feishu",
        logProcessAliases: ["Feishu", "Lark", "Lark Helper", "Lark Helper (Iron)", "com.electron.lark.iron"],
        meetingWindowPatterns: ["飞书会议"],
        excludeWindowPatterns: []
    )

    func testMicOnlyAppDoesNotConfirmBeforeDebounce() {
        var interpreter = SignalInterpreter()
        let policy = DetectionPolicy.defaultPolicy(for: teamsNew)
        let first = snapshot(mic: .active, at: Date(timeIntervalSince1970: 100))

        let event = interpreter.startEvent(for: first, policy: policy)

        XCTAssertEqual(event, .meetingStartCandidate(app: teamsNew, reason: "weak_window_or_mic_requires_debounce"))
    }

    func testActiveMicStartCandidateSchedulesReevaluation() {
        let activeSnapshot = snapshot(mic: .active, at: Date(timeIntervalSince1970: 100))
        let inactiveSnapshot = snapshot(mic: .inactive, at: Date(timeIntervalSince1970: 100))
        let event = DetectionBusinessEvent.meetingStartCandidate(
            app: teamsNew,
            reason: "mic_active_requires_debounce"
        )

        XCTAssertTrue(StartCandidateReevaluationDecision.shouldSchedule(event: event, snapshot: activeSnapshot))
        XCTAssertFalse(StartCandidateReevaluationDecision.shouldSchedule(event: event, snapshot: inactiveSnapshot))
    }

    func testPendingSuppressionClearSchedulesMonitoringReevaluation() {
        XCTAssertTrue(
            MonitoringReevaluationDecision.shouldSchedule(
                needsStartCandidateReevaluation: false,
                pendingSuppressionClearCandidateCounts: ["com.microsoft.teams2": 1]
            )
        )
        XCTAssertTrue(
            MonitoringReevaluationDecision.shouldSchedule(
                needsStartCandidateReevaluation: true,
                pendingSuppressionClearCandidateCounts: [:]
            )
        )
        XCTAssertFalse(
            MonitoringReevaluationDecision.shouldSchedule(
                needsStartCandidateReevaluation: false,
                pendingSuppressionClearCandidateCounts: [:]
            )
        )
    }

    func testMicOnlyAppConfirmsAfterDebounce() {
        var interpreter = SignalInterpreter()
        let policy = DetectionPolicy.defaultPolicy(for: teamsNew)

        _ = interpreter.startEvent(
            for: snapshot(mic: .active, at: Date(timeIntervalSince1970: 100)),
            policy: policy
        )
        let event = interpreter.startEvent(
            for: snapshot(mic: .active, at: Date(timeIntervalSince1970: 106)),
            policy: policy
        )

        XCTAssertEqual(
            event,
            .meetingStartConfirmed(
                app: teamsNew,
                source: .micUsage,
                participantCount: nil,
                confidence: nil
            )
        )
    }

    func testMicOnlyConfirmationClearsCandidateDebounceForNextSession() {
        var interpreter = SignalInterpreter()
        let policy = DetectionPolicy.defaultPolicy(for: teamsNew)

        _ = interpreter.startEvent(
            for: snapshot(mic: .active, at: Date(timeIntervalSince1970: 100)),
            policy: policy
        )
        _ = interpreter.startEvent(
            for: snapshot(mic: .active, at: Date(timeIntervalSince1970: 106)),
            policy: policy
        )
        let nextSessionEvent = interpreter.startEvent(
            for: snapshot(mic: .active, at: Date(timeIntervalSince1970: 107)),
            policy: policy
        )

        XCTAssertEqual(
            nextSessionEvent,
            .meetingStartCandidate(app: teamsNew, reason: "weak_window_or_mic_requires_debounce")
        )
    }

    func testRecentTerminationBlocksMicStart() {
        var interpreter = SignalInterpreter()
        let policy = DetectionPolicy.defaultPolicy(for: teamsNew)
        let snapshot = AppSignalSnapshot(
            app: teamsNew,
            isRunning: true,
            processID: 789,
            windowState: .none,
            micState: .active,
            participantCount: nil,
            lastProcessEvent: .terminated(Date(timeIntervalSince1970: 199)),
            timestamp: Date(timeIntervalSince1970: 200)
        )

        let event = interpreter.startEvent(for: snapshot, policy: policy)

        XCTAssertEqual(event, .meetingStartCandidate(app: teamsNew, reason: "recent_process_event_guard"))
    }

    func testMicOnlyRecordingDoesNotEndBeforeStopDebounce() {
        var interpreter = SignalInterpreter()
        let policy = DetectionPolicy.defaultPolicy(for: teamsNew)
        let context = RecordingContext(
            triggerAppBundleID: teamsNew.bundleIdentifier,
            triggerAppName: teamsNew.processName,
            triggerSource: .micUsage,
            triggerTimestamp: Date(timeIntervalSince1970: 100)
        )

        let event = interpreter.recordingEvent(
            for: snapshot(mic: .inactive, at: Date(timeIntervalSince1970: 120)),
            policy: policy,
            context: context
        )

        XCTAssertEqual(event, .meetingStillActive(app: teamsNew))
    }

    func testWeakMeetingWindowKeepsRecordingActiveWhenMicInactive() {
        var interpreter = SignalInterpreter()
        let policy = DetectionPolicy.defaultPolicy(for: teamsNew)
        let context = RecordingContext(
            triggerAppBundleID: teamsNew.bundleIdentifier,
            triggerAppName: teamsNew.processName,
            triggerSource: .combined,
            triggerTimestamp: Date(timeIntervalSince1970: 100)
        )
        let snapshot = AppSignalSnapshot(
            app: teamsNew,
            isRunning: true,
            processID: 789,
            windowState: .meetingUI,
            micState: .inactive,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date(timeIntervalSince1970: 120)
        )

        let event = interpreter.recordingEvent(for: snapshot, policy: policy, context: context)

        XCTAssertEqual(event, .meetingStillActive(app: teamsNew))
    }

    func testMicOnlyRecordingEndsAfterStopDebounce() {
        var interpreter = SignalInterpreter()
        let policy = DetectionPolicy.defaultPolicy(for: teamsNew)
        let context = RecordingContext(
            triggerAppBundleID: teamsNew.bundleIdentifier,
            triggerAppName: teamsNew.processName,
            triggerSource: .micUsage,
            triggerTimestamp: Date(timeIntervalSince1970: 100)
        )

        _ = interpreter.recordingEvent(
            for: snapshot(mic: .inactive, at: Date(timeIntervalSince1970: 120)),
            policy: policy,
            context: context
        )
        let event = interpreter.recordingEvent(
            for: snapshot(mic: .inactive, at: Date(timeIntervalSince1970: 131)),
            policy: policy,
            context: context
        )

        XCTAssertEqual(event, .meetingEndConfirmed(app: teamsNew))
    }

    func testReliableWindowMeetingStaysActiveWhenMicInactive() {
        var interpreter = SignalInterpreter()
        let policy = DetectionPolicy.defaultPolicy(for: zoom)
        let context = RecordingContext(
            triggerAppBundleID: zoom.bundleIdentifier,
            triggerAppName: zoom.processName,
            triggerSource: .windowTitle,
            triggerTimestamp: Date(timeIntervalSince1970: 1)
        )
        let snapshot = AppSignalSnapshot(
            app: zoom,
            isRunning: true,
            processID: 100,
            windowState: .meetingUI,
            micState: .inactive,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date(timeIntervalSince1970: 20)
        )

        let event = interpreter.recordingEvent(for: snapshot, policy: policy, context: context)

        XCTAssertEqual(event, .meetingStillActive(app: zoom))
    }

    func testFeishuMeetingWindowWithoutActiveMicDoesNotConfirmStart() {
        var interpreter = SignalInterpreter()
        let policy = DetectionPolicy.defaultPolicy(for: feishu)
        let snapshot = AppSignalSnapshot(
            app: feishu,
            isRunning: true,
            processID: 75383,
            windowState: .meetingUI,
            micState: .inactive,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date(timeIntervalSince1970: 200)
        )

        let event = interpreter.startEvent(for: snapshot, policy: policy)

        XCTAssertEqual(
            event,
            .meetingStartCandidate(
                app: feishu,
                reason: "meeting_window_requires_active_audio_session"
            )
        )
    }

    func testFeishuMeetingWindowWithActiveMicConfirmsCombinedStart() {
        var interpreter = SignalInterpreter()
        let policy = DetectionPolicy.defaultPolicy(for: feishu)
        let snapshot = AppSignalSnapshot(
            app: feishu,
            isRunning: true,
            processID: 75383,
            windowState: .meetingUI,
            micState: .active,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date(timeIntervalSince1970: 200)
        )

        let event = interpreter.startEvent(for: snapshot, policy: policy)

        XCTAssertEqual(
            event,
            .meetingStartConfirmed(
                app: feishu,
                source: .combined,
                participantCount: nil,
                confidence: nil
            )
        )
    }

    func testLeavingResidualMicIsCandidateNotConfirmed() {
        var interpreter = SignalInterpreter()
        let policy = DetectionPolicy.defaultPolicy(for: zoom)
        let snapshot = AppSignalSnapshot(
            app: zoom,
            isRunning: true,
            processID: 100,
            windowState: .none,
            micState: .active,
            participantCount: nil,
            lastProcessEvent: .terminated(Date(timeIntervalSince1970: 50)),
            timestamp: Date(timeIntervalSince1970: 51)
        )

        let event = interpreter.startEvent(for: snapshot, policy: policy)

        XCTAssertEqual(event, .meetingStartCandidate(app: zoom, reason: "recent_process_event_guard"))
    }

    private func snapshot(mic: MicSignalState, at date: Date) -> AppSignalSnapshot {
        AppSignalSnapshot(
            app: teamsNew,
            isRunning: true,
            processID: 789,
            windowState: .none,
            micState: mic,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: date
        )
    }
}
