//
//  MockApplicationMonitor.swift
//  MeetingSonar
//
//  Mock implementation of ApplicationMonitor for testing.
//

import Foundation
import Combine

/// Mock application monitor for unit testing
///
/// ## Usage
/// ```swift
/// let mockMonitor = MockApplicationMonitor()
/// mockMonitor.simulateMeetingDetected(appName: "TencentMeeting")
/// XCTAssertEqual(mockMonitor.meetingState, .inMeeting(pid: 1234))
/// ```
@MainActor
final class MockApplicationMonitor: ObservableObject {

    // MARK: - Types

    enum MeetingState {
        case notRunning
        case running(pid: pid_t)
        case inMeeting(pid: pid_t)
    }

    struct MonitoredApp {
        let bundleIdentifier: String
        let processName: String
        let logProcessAliases: [String]
        let meetingWindowPatterns: [String]
    }

    // MARK: - Properties

    @Published private(set) var currentMeetingApp: MonitoredApp?
    @Published private(set) var meetingState: MeetingState = .notRunning

    /// Mock list of monitored apps (can be customized for tests)
    /// - Note: Uses a static property to avoid initialization order issues
    static var defaultMonitoredApps: [MonitoredApp] {
        [
            // Existing apps
            MonitoredApp(
                bundleIdentifier: "us.zoom.xos",
                processName: "zoom.us",
                logProcessAliases: ["zoom.us", "Zoom", "aomhost"],
                meetingWindowPatterns: ["Zoom Meeting", "Zoom Webinar"]
            ),
            MonitoredApp(
                bundleIdentifier: "com.microsoft.teams",
                processName: "Microsoft Teams",
                logProcessAliases: ["Microsoft Teams"],
                meetingWindowPatterns: ["| Microsoft Teams", "Meeting"]
            ),
            MonitoredApp(
                bundleIdentifier: "com.microsoft.teams2",
                processName: "MSTeams",
                logProcessAliases: ["MSTeams"],
                meetingWindowPatterns: []
            ),
            MonitoredApp(
                bundleIdentifier: "com.cisco.webex.webex",
                processName: "Webex",
                logProcessAliases: ["Webex"],
                meetingWindowPatterns: ["Webex Meeting"]
            ),
            // Phase 1: Tencent Meeting
            MonitoredApp(
                bundleIdentifier: "com.tencent.meeting",
                processName: "TencentMeeting",
                logProcessAliases: ["TencentMeeting", "wemeet", "com.tencent.meeting"],
                meetingWindowPatterns: ["腾讯会议", "Tencent Meeting"]
            ),
            // Phase 2: Feishu/Lark Meeting
            MonitoredApp(
                bundleIdentifier: "com.electron.lark.iron",
                processName: "Feishu",
                logProcessAliases: ["Feishu", "Lark", "Lark Helper", "com.electron.lark.iron"],
                meetingWindowPatterns: ["视频会议", "语音通话", "会议中", "Video Meeting", "Voice Call", "Meeting"]
            ),
            // Phase 3: WeChat Voice Call
            MonitoredApp(
                bundleIdentifier: "com.tencent.xinWeChat",
                processName: "WeChat",
                logProcessAliases: ["WeChat", "微信"],
                meetingWindowPatterns: []  // Relies on mic detection and process count
            )
        ]
    }

    var monitoredApps: [MonitoredApp] = defaultMonitoredApps

    /// Mock settings manager for filtering enabled apps
    var mockSettings: MockSettingsManager = MockSettingsManager()

    /// Filtered list of monitored apps based on user settings
    /// - Note: This is @MainActor isolated and accesses settings properly
    var enabledApps: [MonitoredApp] {
        return monitoredApps.filter { app in
            switch app.bundleIdentifier {
            // Western Apps
            case "us.zoom.xos":
                return mockSettings.detectZoom
            case "com.microsoft.teams":
                return mockSettings.detectTeamsClassic
            case "com.microsoft.teams2":
                return mockSettings.detectTeamsNew
            case "com.cisco.webex.webex":
                return mockSettings.detectWebex
            // Chinese Apps
            case "com.tencent.meeting":
                return mockSettings.detectTencentMeeting
            case "com.electron.lark.iron":
                return mockSettings.detectFeishu
            case "com.tencent.xinWeChat":
                return mockSettings.detectWeChat
            default:
                return true
            }
        }
    }

    /// Whether monitoring is active
    private(set) var isMonitoring: Bool = false

    /// Number of times startMonitoring was called
    private(set) var startMonitoringCallCount: Int = 0

    /// Number of times stopMonitoring was called
    private(set) var stopMonitoringCallCount: Int = 0

    // MARK: - Monitoring Control

    func startMonitoring() {
        startMonitoringCallCount += 1
        isMonitoring = true
    }

    func stopMonitoring() {
        stopMonitoringCallCount += 1
        isMonitoring = false
    }

    // MARK: - Test Helpers

    /// Configure for testing (clears all state)
    func configureForTesting() {
        reset()
    }

    /// Reset all tracking state
    func reset() {
        currentMeetingApp = nil
        meetingState = .notRunning
        isMonitoring = false
        startMonitoringCallCount = 0
        stopMonitoringCallCount = 0
        mockSettings.reset()
    }

    /// Simulate app detected
    func simulateAppDetected(app: MonitoredApp, pid: pid_t = 1234) {
        currentMeetingApp = app
        meetingState = .running(pid: pid)
    }

    /// Simulate meeting detected (window found)
    func simulateMeetingDetected(app: MonitoredApp, pid: pid_t = 1234) {
        currentMeetingApp = app
        meetingState = .inMeeting(pid: pid)
    }

    /// Simulate app terminated
    func simulateAppTerminated() {
        currentMeetingApp = nil
        meetingState = .notRunning
    }

    /// Find monitored app by bundle identifier
    func findApp(by bundleIdentifier: String) -> MonitoredApp? {
        return monitoredApps.first { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Find monitored app by process name
    func findAppByProcessName(_ processName: String) -> MonitoredApp? {
        return monitoredApps.first { $0.processName == processName }
    }
}
