import Foundation
import AppKit
import Combine

/// 负责通过"进程存在"和"窗口特征"双重验证来监测会议应用的状态
@MainActor
class ApplicationMonitor: ObservableObject {
    
    // MARK: - Types
    
    // MARK: - Types
    
    enum MeetingState {
        case notRunning
        case running(pid: pid_t) // 进程运行，但未检测到会议窗口
        case inMeeting(pid: pid_t) // 进程运行 + 检测到会议窗口
    }
    
    struct MonitoredApp {
        let bundleIdentifier: String
        let processName: String
        let logProcessAliases: [String] // Additional names to look for in logs (e.g. "aomhost")
        let meetingWindowPatterns: [String] // 特征窗口标题关键字（包含匹配）
    }
    
    // MARK: - Properties
    
    @Published private(set) var currentMeetingApp: MonitoredApp?
    @Published private(set) var meetingState: MeetingState = .notRunning // Renamed from appState to meetingState to match usage
    
    let monitoredApps: [MonitoredApp] = [
        // MARK: - Existing Apps
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
            bundleIdentifier: "com.microsoft.teams2", // New Teams (Work/School)
            processName: "MSTeams",
            logProcessAliases: ["MSTeams"],
            meetingWindowPatterns: [] // Reliant on Mic Detection (LogMonitor) due to "No Title" issue
        ),
        MonitoredApp(
            bundleIdentifier: "com.cisco.webex.webex",
            processName: "Webex",
            logProcessAliases: ["Webex"],
            meetingWindowPatterns: ["Webex Meeting"]
        ),

        // MARK: - New Apps (Phase 1: Tencent Meeting)
        MonitoredApp(
            bundleIdentifier: "com.tencent.meeting",
            processName: "TencentMeeting",
            logProcessAliases: ["TencentMeeting", "wemeet", "com.tencent.meeting"],
            meetingWindowPatterns: ["腾讯会议", "Tencent Meeting"]
        ),

        // MARK: - New Apps (Phase 2: Feishu/Lark Meeting)
        MonitoredApp(
            bundleIdentifier: "com.electron.lark.iron",
            processName: "Feishu",
            logProcessAliases: ["Feishu", "Lark", "Lark Helper", "com.electron.lark.iron"],
            meetingWindowPatterns: ["视频会议", "语音通话", "会议中", "Video Meeting", "Voice Call", "Meeting"]
        ),

        // MARK: - New Apps (Phase 3: WeChat Voice Call)
        MonitoredApp(
            bundleIdentifier: "com.tencent.xinWeChat",
            processName: "WeChat",
            logProcessAliases: ["WeChat", "微信"],
            meetingWindowPatterns: []  // Relies on mic detection and process count
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
    
    // MARK: - Initialization
    
    init() {
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
            .sink { [weak self] _ in
                self?.checkForRunningApps()
            }
    }
    
    private func stopMonitoring() {
        workspaceObservation?.cancel()
        stopWindowPolling()
    }
    
    private func checkForRunningApps() {
        let runningApps = NSWorkspace.shared.runningApplications
        
        // Find if any supported meeting app is running
        if let foundApp = runningApps.first(where: { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return monitoredApps.contains { $0.bundleIdentifier == bundleId }
        }) {
            handleAppDetected(foundApp)
        } else {
            handleAppTerminated()
        }
    }
    
    private func handleAppDetected(_ nsApp: NSRunningApplication) {
        guard let config = monitoredApps.first(where: { $0.bundleIdentifier == nsApp.bundleIdentifier }) else { return }
        
        // 如果是从非运行状态切换过来，或者切换了App
        if case .notRunning = meetingState {
            logger.log(category: .detection, level: .info, message: "ApplicationMonitor: Detected \(config.processName) (PID: \(nsApp.processIdentifier))")
            currentMeetingApp = config
            meetingState = .running(pid: nsApp.processIdentifier)
            
            // Start Level 2: Window Polling
            startWindowPolling(for: config, pid: nsApp.processIdentifier)
        }
    }
    
    private func handleAppTerminated() {
        if case .notRunning = meetingState { return }
        
        logger.log(category: .detection, level: .info, message: "ApplicationMonitor: Target app terminated")
        currentMeetingApp = nil
        meetingState = .notRunning
        stopWindowPolling()
    }
    
    // MARK: - Window Monitoring (Level 2)
    
    private func startWindowPolling(for app: MonitoredApp, pid: pid_t) {
        stopWindowPolling() // Stop existing if any

        logger.log(category: .detection, level: .debug, message: "ApplicationMonitor: Starting window polling for \(app.processName)")

        // 每 2 秒检查一次窗口，避免过高 CPU
        windowCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkWindows(for: app, pid: pid)
            }
        }
    }
    
    private func stopWindowPolling() {
        windowCheckTimer?.invalidate()
        windowCheckTimer = nil
    }
    
    private func checkWindows(for config: MonitoredApp, pid: pid_t) {
        // 使用 Accessibility API (AXUIElement) 获取窗口标题
        // 这需要 "辅助功能" 权限
        
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            // 如果获取失败，可能是没有权限或没有窗口
            // 可以在这里加一个 debouncer 或者是权限检查日志
            if !AXIsProcessTrusted() {
                logger.log(category: .detection, level: .error, message: "ApplicationMonitor: No Accessibility permission.")
            }
            return
        }
        
        // 遍历窗口
        let detected = windows.contains { window in
            var titleRef: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            
            guard titleResult == .success, let title = titleRef as? String else {
                return false
            }
            
            // 匹配标题特征
            for pattern in config.meetingWindowPatterns {
                if title.localizedCaseInsensitiveContains(pattern) {
                    logger.log(category: .detection, level: .debug, message: "ApplicationMonitor: Matched window title '\(title)' for \(config.processName)")
                    return true
                }
            }
            
            return false
        }
        
        updateMeetingState(detected: detected, pid: pid)
    }
    
    private func updateMeetingState(detected: Bool, pid: pid_t) {
        switch (meetingState, detected) {
        case (.running, true):
            logger.log(category: .detection, level: .info, message: "ApplicationMonitor: Meeting window detected!")
            meetingState = .inMeeting(pid: pid)
            
        case (.inMeeting, false):
            logger.log(category: .detection, level: .info, message: "ApplicationMonitor: Meeting window disappeared.")
            meetingState = .running(pid: pid)
            
        default:
            break
        }
    }
}
