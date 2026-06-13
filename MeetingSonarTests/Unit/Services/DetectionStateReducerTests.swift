import XCTest
@testable import MeetingSonar

@MainActor
final class DetectionStateReducerTests: XCTestCase {
    private let zoom = ApplicationMonitor.MonitoredApp(
        bundleIdentifier: "us.zoom.xos",
        processName: "zoom.us",
        logProcessAliases: ["zoom.us", "Zoom", "aomhost"],
        meetingWindowPatterns: ["Zoom Meeting", "Zoom Webinar", "Zoom会议"],
        excludeWindowPatterns: []
    )

    func testConfirmedMeetingInAutoModeStartsRecording() {
        let reducer = DetectionStateReducer()
        let result = reducer.reduce(
            state: .monitoringAll(suppressedApps: []),
            event: .meetingStartConfirmed(
                app: zoom,
                source: .windowTitle,
                participantCount: 1,
                confidence: .high
            ),
            environment: DetectionReducerEnvironment(
                mode: .auto,
                smartDetectionEnabled: true,
                isRecording: false,
                now: Date(timeIntervalSince1970: 1)
            )
        )

        guard case .recordingLocked(let context) = result.state else {
            return XCTFail("Expected recordingLocked")
        }
        XCTAssertEqual(context.triggerAppBundleID, "us.zoom.xos")
        XCTAssertEqual(context.participantCount, 1)
        XCTAssertEqual(result.actions, [.startRecording(context)])
    }

    func testCandidateDoesNotStartRecording() {
        let reducer = DetectionStateReducer()
        let result = reducer.reduce(
            state: .monitoringAll(suppressedApps: []),
            event: .meetingStartCandidate(app: zoom, reason: "mic_active_requires_debounce"),
            environment: DetectionReducerEnvironment(
                mode: .auto,
                smartDetectionEnabled: true,
                isRecording: false,
                now: Date()
            )
        )

        XCTAssertEqual(result.state, .monitoringAll(suppressedApps: []))
        XCTAssertEqual(
            result.actions,
            [.logCandidate(bundleID: "us.zoom.xos", reason: "mic_active_requires_debounce")]
        )
    }

    func testManualStopSuppressesTriggerApp() {
        let context = RecordingContext(
            triggerAppBundleID: "us.zoom.xos",
            triggerAppName: "zoom.us",
            triggerSource: .windowTitle,
            triggerTimestamp: Date(timeIntervalSince1970: 1)
        )
        let reducer = DetectionStateReducer()

        let result = reducer.reduce(
            state: .recordingLocked(context),
            event: .manualStopRequested,
            environment: DetectionReducerEnvironment(
                mode: .auto,
                smartDetectionEnabled: true,
                isRecording: true,
                now: Date(timeIntervalSince1970: 30)
            )
        )

        guard case .cooldown(let cooldown) = result.state else {
            return XCTFail("Expected cooldown")
        }
        XCTAssertEqual(cooldown.reason, .manualStop)
        XCTAssertEqual(cooldown.suppressedApps, ["us.zoom.xos"])
        XCTAssertEqual(result.actions, [.stopRecording(.manualStop), .scheduleCooldown(cooldown)])
    }

    func testStopReasonSuppressionMatchesManualStopReducerSemantics() {
        XCTAssertEqual(
            DetectionStateReducer.suppressedApps(for: .manualStop, triggerAppBundleID: "com.microsoft.teams2"),
            ["com.microsoft.teams2"]
        )
        XCTAssertEqual(
            DetectionStateReducer.suppressedApps(for: .appCrashed, triggerAppBundleID: "com.microsoft.teams2"),
            ["com.microsoft.teams2"]
        )
        XCTAssertEqual(
            DetectionStateReducer.suppressedApps(for: .appDisabled, triggerAppBundleID: "com.microsoft.teams2"),
            ["com.microsoft.teams2"]
        )
        XCTAssertEqual(
            DetectionStateReducer.suppressedApps(for: .autoStop, triggerAppBundleID: "com.microsoft.teams2"),
            []
        )
        XCTAssertEqual(
            DetectionStateReducer.suppressedApps(for: .maxDuration, triggerAppBundleID: "com.microsoft.teams2"),
            []
        )
    }

    func testSuppressionClearedAllowsFutureStartForSameApp() {
        let reducer = DetectionStateReducer()

        let clearResult = reducer.reduce(
            state: .monitoringAll(suppressedApps: ["us.zoom.xos"]),
            event: .suppressionCleared(bundleID: "us.zoom.xos"),
            environment: DetectionReducerEnvironment(
                mode: .auto,
                smartDetectionEnabled: true,
                isRecording: false,
                now: Date(timeIntervalSince1970: 100)
            )
        )

        XCTAssertEqual(clearResult.state, .monitoringAll(suppressedApps: []))

        let startResult = reducer.reduce(
            state: clearResult.state,
            event: .meetingStartConfirmed(app: zoom, source: .windowTitle, participantCount: nil, confidence: nil),
            environment: DetectionReducerEnvironment(
                mode: .auto,
                smartDetectionEnabled: true,
                isRecording: false,
                now: Date(timeIntervalSince1970: 101)
            )
        )

        guard case .recordingLocked(let context) = startResult.state else {
            return XCTFail("Expected recordingLocked after suppression is cleared")
        }
        XCTAssertEqual(context.triggerAppBundleID, "us.zoom.xos")
    }

    func testCooldownSuppressesTriggerAppWhenResidualPersistsPastMaxWait() {
        let reducer = DetectionStateReducer()
        let cooldown = CooldownContext(
            reason: .autoStop,
            triggerAppBundleID: "us.zoom.xos",
            triggerAppName: "zoom.us",
            triggerType: .windowTitle,
            recordingDuration: 11,
            suppressedApps: [],
            cooldownStartTime: Date(timeIntervalSince1970: 100),
            cooldownDuration: 5
        )

        let result = reducer.reduce(
            state: .cooldown(cooldown),
            event: .residualSignalsStillPresent(bundleID: "us.zoom.xos"),
            environment: DetectionReducerEnvironment(
                mode: .auto,
                smartDetectionEnabled: true,
                isRecording: false,
                now: Date(timeIntervalSince1970: 125)
            )
        )

        XCTAssertEqual(result.state, .monitoringAll(suppressedApps: ["us.zoom.xos"]))
    }
}

@MainActor
final class ManualStopCooldownSuppressionReleaseDecisionTests: XCTestCase {
    private let teams = ApplicationMonitor.MonitoredApp(
        bundleIdentifier: "com.microsoft.teams2",
        processName: "MSTeams",
        logProcessAliases: ["MSTeams", "Microsoft Teams ModuleHost"],
        meetingWindowPatterns: ["| Microsoft Teams"],
        excludeWindowPatterns: ["Calendar | Microsoft Teams"]
    )
    private let weChat = ApplicationMonitor.MonitoredApp(
        bundleIdentifier: "com.tencent.xinWeChat",
        processName: "WeChat",
        logProcessAliases: ["WeChat", "微信"],
        meetingWindowPatterns: [],
        excludeWindowPatterns: []
    )

    func testManualStopCooldownRequiresStableNonMeetingBoundaryBeforeReleasingSuppression() {
        let cooldown = CooldownContext(
            reason: .manualStop,
            triggerAppBundleID: "com.microsoft.teams2",
            triggerAppName: "MSTeams",
            triggerType: .combined,
            recordingDuration: 16,
            suppressedApps: ["com.microsoft.teams2"],
            cooldownStartTime: Date(timeIntervalSince1970: 100),
            cooldownDuration: 5
        )
        let snapshot = snapshot(windowState: .mainWindow, micState: .inactive)
        let policy = DetectionPolicy.defaultPolicy(for: teams)

        let first = ManualStopCooldownSuppressionReleaseDecision.evaluate(
            cooldown: cooldown,
            snapshot: snapshot,
            policy: policy,
            currentStableSampleCount: 0,
            requiredStableSamples: 2
        )
        XCTAssertFalse(first.shouldReleaseSuppression)
        XCTAssertEqual(first.nextStableSampleCount, 1)

        let second = ManualStopCooldownSuppressionReleaseDecision.evaluate(
            cooldown: cooldown,
            snapshot: snapshot,
            policy: policy,
            currentStableSampleCount: first.nextStableSampleCount,
            requiredStableSamples: 2
        )
        XCTAssertTrue(second.shouldReleaseSuppression)
        XCTAssertEqual(second.nextStableSampleCount, 0)
    }

    func testManualStopCooldownMeetingResidualResetsStableBoundaryCount() {
        let cooldown = CooldownContext(
            reason: .manualStop,
            triggerAppBundleID: "com.microsoft.teams2",
            triggerAppName: "MSTeams",
            triggerType: .combined,
            recordingDuration: 16,
            suppressedApps: ["com.microsoft.teams2"],
            cooldownStartTime: Date(timeIntervalSince1970: 100),
            cooldownDuration: 5
        )
        let snapshot = snapshot(windowState: .meetingUI, micState: .active)
        let policy = DetectionPolicy.defaultPolicy(for: teams)

        let result = ManualStopCooldownSuppressionReleaseDecision.evaluate(
            cooldown: cooldown,
            snapshot: snapshot,
            policy: policy,
            currentStableSampleCount: 1,
            requiredStableSamples: 2
        )

        XCTAssertFalse(result.shouldReleaseSuppression)
        XCTAssertEqual(result.nextStableSampleCount, 0)
    }

    func testManualStopCooldownMicOnlyPolicyReleasesAfterStableInactiveMic() {
        let cooldown = CooldownContext(
            reason: .manualStop,
            triggerAppBundleID: "com.tencent.xinWeChat",
            triggerAppName: "WeChat",
            triggerType: .micUsage,
            recordingDuration: 16,
            suppressedApps: ["com.tencent.xinWeChat"],
            cooldownStartTime: Date(timeIntervalSince1970: 100),
            cooldownDuration: 5
        )
        let snapshot = snapshot(app: weChat, windowState: .mainWindow, micState: .inactive)
        let policy = DetectionPolicy.defaultPolicy(for: weChat)

        let first = ManualStopCooldownSuppressionReleaseDecision.evaluate(
            cooldown: cooldown,
            snapshot: snapshot,
            policy: policy,
            currentStableSampleCount: 0,
            requiredStableSamples: 2
        )
        XCTAssertFalse(first.shouldReleaseSuppression)
        XCTAssertEqual(first.nextStableSampleCount, 1)

        let second = ManualStopCooldownSuppressionReleaseDecision.evaluate(
            cooldown: cooldown,
            snapshot: snapshot,
            policy: policy,
            currentStableSampleCount: first.nextStableSampleCount,
            requiredStableSamples: 2
        )
        XCTAssertTrue(second.shouldReleaseSuppression)
        XCTAssertEqual(second.nextStableSampleCount, 0)
    }

    private func snapshot(
        windowState: WindowSignalState,
        micState: MicSignalState
    ) -> AppSignalSnapshot {
        snapshot(app: teams, windowState: windowState, micState: micState)
    }

    private func snapshot(
        app: ApplicationMonitor.MonitoredApp,
        windowState: WindowSignalState,
        micState: MicSignalState
    ) -> AppSignalSnapshot {
        AppSignalSnapshot(
            app: app,
            isRunning: true,
            processID: 123,
            windowState: windowState,
            micState: micState,
            participantCount: nil,
            lastProcessEvent: nil,
            timestamp: Date(timeIntervalSince1970: 101)
        )
    }
}
