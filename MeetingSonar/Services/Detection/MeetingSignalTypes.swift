import Foundation

enum SignalConfidence: String, Codable, Equatable {
    case high
    case medium
    case low
}

enum WindowSignalState: Equatable {
    case none
    case mainWindow
    case preJoin
    case meetingUI
    case leavingConfirmation
    case unknownMatched(String)
}

enum MicSignalState: Equatable {
    case inactive
    case active
    case recentlyActive(until: Date)
    case unknown
}

enum ProcessLifecycleEvent: Equatable {
    case launched(Date)
    case terminated(Date)
}

struct ParticipantCountObservation: Equatable {
    let bundleIdentifier: String
    let count: Int?
    let rawText: String?
    let confidence: SignalConfidence
    let timestamp: Date
}

struct AppSignalSnapshot: Equatable {
    let app: ApplicationMonitor.MonitoredApp
    let isRunning: Bool
    let processID: pid_t?
    let windowState: WindowSignalState
    let micState: MicSignalState
    let participantCount: ParticipantCountObservation?
    let lastProcessEvent: ProcessLifecycleEvent?
    let timestamp: Date
}

struct AXWindowContentSnapshot: Equatable {
    let title: String
    let strings: [String]
}

enum MeetingWindowClassifier {
    static func windowState(
        for app: ApplicationMonitor.MonitoredApp,
        windows: [AXWindowContentSnapshot]
    ) -> WindowSignalState {
        guard !windows.isEmpty else { return .none }

        if app.bundleIdentifier == "com.tencent.meeting" {
            return tencentMeetingWindowState(windows)
        }

        return genericWindowState(for: app, windows: windows)
    }

    private static func genericWindowState(
        for app: ApplicationMonitor.MonitoredApp,
        windows: [AXWindowContentSnapshot]
    ) -> WindowSignalState {
        guard !app.meetingWindowPatterns.isEmpty else {
            return .mainWindow
        }

        for window in windows {
            guard app.meetingWindowPatterns.contains(where: { pattern in
                window.title.localizedCaseInsensitiveContains(pattern)
            }) else {
                continue
            }

            if app.excludeWindowPatterns.contains(where: { pattern in
                window.title.localizedCaseInsensitiveContains(pattern)
            }) {
                continue
            }

            return .meetingUI
        }

        return .mainWindow
    }

    private static func tencentMeetingWindowState(_ windows: [AXWindowContentSnapshot]) -> WindowSignalState {
        let allStrings = windows.flatMap { [$0.title] + $0.strings }

        if containsAny(allStrings, [
            "InMeetingLayoutContainerQtView",
            "SpeakingMembersStatic"
        ]) {
            return .meetingUI
        }

        if containsAny(allStrings, [
            "join_meeting_dialog",
            "WaittingRoomWnd",
            "加入会议"
        ]) {
            return .preJoin
        }

        if containsAny(allStrings, [
            "page/inmeeting_revision"
        ]) {
            return .preJoin
        }

        if containsAny(allStrings, [
            "page/home",
            "暂无会议",
            "腾讯会议"
        ]) {
            return .mainWindow
        }

        return .mainWindow
    }

    private static func containsAny(_ values: [String], _ needles: [String]) -> Bool {
        values.contains { value in
            needles.contains { needle in
                value.localizedCaseInsensitiveContains(needle)
            }
        }
    }
}

enum MeetingEvidence: Equatable {
    case notMeeting
    case candidate(reason: String)
    case meetingConfirmed(participantCount: Int?, confidence: SignalConfidence?)
    case stillActive
    case ending
    case ended
    case unknown(reason: String)
}

enum DetectionBusinessEvent: Equatable {
    case meetingStartConfirmed(
        app: ApplicationMonitor.MonitoredApp,
        source: TriggerSource,
        participantCount: Int?,
        confidence: SignalConfidence?
    )
    case meetingStartCandidate(app: ApplicationMonitor.MonitoredApp, reason: String)
    case meetingStillActive(app: ApplicationMonitor.MonitoredApp)
    case meetingEndConfirmed(app: ApplicationMonitor.MonitoredApp)
    case residualSignalsStillPresent(bundleID: String)
    case residualSignalsCleared(bundleID: String)
    case suppressionCleared(bundleID: String)
    case manualStopRequested
    case maxDurationReached
    case triggerAppTerminated(bundleID: String)
    case triggerAppDisabled(bundleID: String)
    case smartDetectionDisabled
}
