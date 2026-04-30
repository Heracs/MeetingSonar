import Foundation
import AppKit
import Combine

/// 负责通过"进程存在"和"窗口特征"双重验证来监测会议应用的状态

// MARK: - Detection Settings Notification Name
// Defined here in addition to SettingsManager.swift for cross-file visibility during batch compilation.
extension Notification.Name {
    static let detectionSettingsDidChange = Notification.Name("DetectionSettingsDidChange")
}
@MainActor
class ApplicationMonitor: ObservableObject {
    
    // MARK: - Types
    
    // MARK: - Types
    
    enum MeetingState: Equatable {
        case notRunning
        case running(pid: pid_t) // 进程运行，但未检测到会议窗口
        case inMeeting(pid: pid_t) // 进程运行 + 检测到会议窗口
    }
    
    struct MonitoredApp {
        let bundleIdentifier: String
        let processName: String
        let logProcessAliases: [String] // Additional names to look for in logs (e.g. "aomhost")
        let meetingWindowPatterns: [String] // 特征窗口标题关键字（包含匹配）
        let excludeWindowPatterns: [String] // 排除窗口模式（优先级高于 meetingWindowPatterns）。具体值需实测确定。
    }
    
    // MARK: - Properties
    
    /// Per-app monitoring state keyed by bundleIdentifier
    struct PerAppState {
        let config: MonitoredApp
        var meetingState: MeetingState = .notRunning
        var windowPollCount: Int = 0
    }

    /// Per-app states keyed by bundleIdentifier
    @Published private(set) var appStates: [String: PerAppState] = [:]

    /// BundleIDs of apps currently in .inMeeting state (for DetectionService)
    @Published private(set) var activeMeetingApps: Set<String> = []
    
    let monitoredApps: [MonitoredApp] = [
        // MARK: - Existing Apps
        MonitoredApp(
            bundleIdentifier: "us.zoom.xos",
            processName: "zoom.us",
            logProcessAliases: ["zoom.us", "Zoom", "aomhost"],
            meetingWindowPatterns: ["Zoom Meeting", "Zoom Webinar", "Zoom会议"],
            excludeWindowPatterns: []
        ),
        MonitoredApp(
            bundleIdentifier: "com.microsoft.teams",
            processName: "Microsoft Teams",
            logProcessAliases: ["Microsoft Teams"],
            meetingWindowPatterns: ["| Microsoft Teams", "Meeting"],
            excludeWindowPatterns: []
        ),
        MonitoredApp(
            bundleIdentifier: "com.microsoft.teams2", // New Teams (Work/School)
            processName: "MSTeams",
            logProcessAliases: ["MSTeams", "Microsoft Teams WebView Helper"],
            meetingWindowPatterns: [], // Reliant on Mic Detection (LogMonitor) due to "No Title" issue
            excludeWindowPatterns: []
        ),
        MonitoredApp(
            bundleIdentifier: "com.cisco.webex.webex",
            processName: "Webex",
            logProcessAliases: ["Webex"],
            meetingWindowPatterns: ["Webex Meeting"],
            excludeWindowPatterns: []
        ),

        // MARK: - New Apps (Phase 1: Tencent Meeting)
        MonitoredApp(
            bundleIdentifier: "com.tencent.meeting",
            processName: "TencentMeeting",
            logProcessAliases: ["TencentMeeting", "wemeet", "com.tencent.meeting"],
            meetingWindowPatterns: ["腾讯会议", "Tencent Meeting"],
            excludeWindowPatterns: []
        ),

        // MARK: - New Apps (Phase 2: Feishu/Lark Meeting)
        MonitoredApp(
            bundleIdentifier: "com.electron.lark.iron",
            processName: "Feishu",
            logProcessAliases: ["Feishu", "Lark", "Lark Helper", "com.electron.lark.iron"],
            meetingWindowPatterns: ["视频会议", "语音通话", "会议中", "Video Meeting", "Voice Call", "Meeting"],
            excludeWindowPatterns: []
        ),

        // MARK: - New Apps (Phase 3: WeChat Voice Call)
        MonitoredApp(
            bundleIdentifier: "com.tencent.xinWeChat",
            processName: "WeChat",
            logProcessAliases: ["WeChat", "微信"],
            meetingWindowPatterns: [],  // Relies on mic detection and process count
            excludeWindowPatterns: []
        )
    ]

    /// Filtered list of monitored apps based on user settings
    /// This allows users to enable/disable detection for specific apps
    var enabledApps: [MonitoredApp] {
        let settings = SettingsManager.shared
        return monitoredApps.filter { app in
            switch app.bundleIdentifier {
            // Western Apps
            case "us.zoom.xos":
                return settings.detectZoom
            case "com.microsoft.teams":
                return settings.detectTeamsClassic
            case "com.microsoft.teams2":
                return settings.detectTeamsNew
            case "com.cisco.webex.webex":
                return settings.detectWebex
            // Chinese Apps
            case "com.tencent.meeting":
                return settings.detectTencentMeeting
            case "com.electron.lark.iron":
                return settings.detectFeishu
            case "com.tencent.xinWeChat":
                return settings.detectWeChat
            default:
                return true
            }
        }
    }

    private var workspaceObservation: AnyCancellable?
    private var windowCheckTimer: Timer?
    private let logger = LoggerService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        NotificationCenter.default.publisher(for: .detectionSettingsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadEnabledApps()
            }
            .store(in: &cancellables)
        startMonitoring()
    }

    deinit {
        // Timer will be invalidated automatically when the object is deallocated
        // Note: Cannot call stopMonitoring() here due to @MainActor isolation
        windowCheckTimer?.invalidate()
    }
    
    // MARK: - Process Monitoring (Level 1)
    
    func startMonitoring() {
        logger.log(category: .detection, level: .debug, message: "ApplicationMonitor: Starting process monitoring")
        
        // 1. Check initial state
        checkForRunningApps()
        
        // 2. Observe Launch/Terminate
        let center = NSWorkspace.shared.notificationCenter
        
        workspaceObservation = center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: center.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .sink { [weak self] notification in
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   let bundleID = app.bundleIdentifier {
                    LoggerService.shared.log(category: .detection, level: .debug, message: "[ApplicationMonitor] NSWorkspace notification: \(bundleID) \(notification.name == NSWorkspace.didLaunchApplicationNotification ? "launched" : "terminated")")
                }
                self?.checkForRunningApps()
            }
    }
    
    private func stopMonitoring() {
        workspaceObservation?.cancel()
        stopWindowPolling()
    }
    
    private func checkForRunningApps() {
        let enabled = enabledApps
        let runningApps = NSWorkspace.shared.runningApplications

        var newAppStates: [String: PerAppState] = [:]
        var hasRunning = false

        for app in enabled {
            if let running = runningApps.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                let existingState = appStates[app.bundleIdentifier]
                let meetingState: MeetingState
                if let existing = existingState {
                    switch existing.meetingState {
                    case .notRunning:
                        meetingState = .running(pid: running.processIdentifier)
                    case .running, .inMeeting:
                        meetingState = .running(pid: running.processIdentifier)
                    }
                } else {
                    meetingState = .running(pid: running.processIdentifier)
                }
                newAppStates[app.bundleIdentifier] = PerAppState(
                    config: app,
                    meetingState: meetingState,
                    windowPollCount: existingState?.windowPollCount ?? 0
                )
                hasRunning = true
            } else {
                if let existing = appStates[app.bundleIdentifier] {
                    var state = existing
                    state.meetingState = .notRunning
                    state.windowPollCount = 0
                    newAppStates[app.bundleIdentifier] = state
                } else {
                    newAppStates[app.bundleIdentifier] = PerAppState(config: app)
                }
            }
        }

        appStates = newAppStates
        updateActiveMeetingApps()

        if hasRunning {
            startWindowPolling()
        } else {
            stopWindowPolling()
        }

        logger.log(category: .detection, level: .debug, message: """
            [ApplicationMonitor] checkForRunningApps: \(enabled.count) enabled, \
            \(appStates.filter { if case .running = $0.value.meetingState { true } else { false } }.count) running, \
            \(activeMeetingApps.count) in-meeting
            """)
    }

    func reloadEnabledApps() {
        let newEnabled = enabledApps
        let newBundleIDs = Set(newEnabled.map(\.bundleIdentifier))

        for bundleID in appStates.keys where !newBundleIDs.contains(bundleID) {
            appStates.removeValue(forKey: bundleID)
            logger.log(category: .detection, level: .info, message: "[ApplicationMonitor] Removed disabled app: \(bundleID)")
        }

        checkForRunningApps()
    }

    private func updateActiveMeetingApps() {
        activeMeetingApps = Set(
            appStates.compactMap { bundleID, state in
                if case .inMeeting = state.meetingState { return bundleID }
                return nil
            }
        )
    }

    // MARK: - Window Monitoring (Level 2)
    
    private func startWindowPolling() {
        guard windowCheckTimer == nil else { return }
        logger.log(category: .detection, level: .debug, message: "[ApplicationMonitor] Starting window polling")
        windowCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkWindows()
            }
        }
    }
    
    private func stopWindowPolling() {
        windowCheckTimer?.invalidate()
        windowCheckTimer = nil
        logger.log(category: .detection, level: .debug, message: "[ApplicationMonitor] Window polling stopped")
    }
    
    private func checkWindows() {
        for (bundleID, state) in appStates {
            let pid: pid_t
            switch state.meetingState {
            case .running(let p), .inMeeting(let p):
                pid = p
            default:
                continue
            }
            let config = state.config

            guard !config.meetingWindowPatterns.isEmpty else { continue }

            logger.log(category: .detection, level: .debug, message: "[ApplicationMonitor] AX poll: checking windows for \(config.processName) (pid: \(pid))")

            let appElement = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

            guard result == .success, let windows = windowsRef as? [AXUIElement] else {
                if !AXIsProcessTrusted() {
                    logger.log(category: .detection, level: .error, message: "[ApplicationMonitor] No Accessibility permission")
                }
                continue
            }

            let detected = windows.contains { window in
                var titleRef: CFTypeRef?
                let titleResult = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                guard titleResult == .success, let title = titleRef as? String else { return false }

                let matchedPattern = config.meetingWindowPatterns.first { title.localizedCaseInsensitiveContains($0) }
                guard let matched = matchedPattern else {
                    logger.log(category: .detection, level: .debug, message: "[Signal.AX] '\(title)' did not match any pattern for \(config.processName)")
                    return false
                }

                if let excludedBy = config.excludeWindowPatterns.first(where: { title.localizedCaseInsensitiveContains($0) }) {
                    logger.log(category: .detection, level: .debug, message: "[Signal.AX] '\(title)' matched '\(matched)' BUT excluded by '\(excludedBy)'")
                    return false
                }

                logger.log(category: .detection, level: .debug, message: "[Signal.AX] '\(title)' matched pattern '\(matched)'")
                return true
            }

            if !detected {
                logger.log(category: .detection, level: .debug, message: "[Signal.AX] no matching window for \(config.processName)")
            }

            updateAppMeetingState(bundleID: bundleID, detected: detected, pid: pid)
        }
    }
    
    private func updateAppMeetingState(bundleID: String, detected: Bool, pid: pid_t) {
        guard var state = appStates[bundleID] else { return }
        let oldState = state.meetingState

        switch (oldState, detected) {
        case (.running, true):
            state.meetingState = .inMeeting(pid: pid)
            logger.log(category: .detection, level: .info, message: "[ApplicationMonitor] \(state.config.processName): meeting window detected")

        case (.inMeeting, false):
            state.meetingState = .running(pid: pid)
            logger.log(category: .detection, level: .info, message: "[ApplicationMonitor] \(state.config.processName): meeting window disappeared")

        default:
            break
        }

        appStates[bundleID] = state

        if oldState != state.meetingState {
            logger.log(category: .detection, level: .debug, message: "[ApplicationMonitor] \(state.config.processName): \(oldState) → \(state.meetingState)")
            updateActiveMeetingApps()
        }
    }
}
