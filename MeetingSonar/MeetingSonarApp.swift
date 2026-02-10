//
//  MeetingSonarApp.swift
//  MeetingSonar
//
//  A macOS menu bar app for intelligent meeting audio recording.
//  v0.1-rebuild: Core recording functionality with SCK + AVCapture.
//

import SwiftUI
import AppKit
import Combine

@main
@available(macOS 13.0, *)
struct MeetingSonarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}

/// Application delegate for managing menu bar status item and app lifecycle
@available(macOS 13.0, *)
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Constants

    /// Timer constants
    enum TimerConstants {
        /// Duration update interval (seconds)
        static let durationUpdateInterval: TimeInterval = 1.0
    }

    /// Time formatting constants
    enum TimeConstants {
        /// Seconds per hour
        static let secondsPerHour: Int = 3600
        /// Seconds per minute
        static let secondsPerMinute: Int = 60
        /// Minutes per hour
        static let minutesPerHour: Int = 60
    }

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    
    /// Preferences window (manually managed for accessory mode)
    private var preferencesWindow: NSWindow?
    
    /// Dashboard window (F-6.1)
    private var dashboardWindow: NSWindow?

    
    /// Shared services
    private let recordingService = RecordingService.shared
    private let permissionManager = PermissionManager.shared
    private let settings = SettingsManager.shared
    private let logger = LoggerService.shared
    private let detectionService = DetectionService.shared // F-2.1 & F-2.2
    private let overlayController = OverlayWindowController.shared // F-2.4 (v0.3.1)
    private let iconGenerator = MenuIconGenerator() // F-2.5 (v0.3.2)
    
    /// AI Processing Coordinator (v0.5.0)
    private let aiCoordinator = AIProcessingCoordinator.shared
    
    /// Timer for updating recording duration display
    private var durationUpdateTimer: Timer?
    
    /// Last recorded file URL for AI processing
    private var lastRecordedURL: URL?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - v0.5.1: Early Initialization
    
    override init() {
        super.init()
        // Log at the earliest possible point during AppDelegate construction
        logger.log(category: .general, message: "[App] AppDelegate.init() ********* Logger initialized at earliest startup")
    }
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Log app version and build info
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        logger.log(category: .general, message: "App Launch - MeetingSonar v\(version) (Build \(BuildInfo.fullBuildString))")
        logger.log(category: .general, message: "Git Commit: \(BuildInfo.gitSHA) on branch: \(BuildInfo.gitBranch)")
        
        setupMenuBar()
        checkPermissions()
        setupSubscriptions()
        
        // Start services
        detectionService.start()
        NotificationManager.shared.requestAuthorization()
        
        // F-4.5: Initialize Data Infrastructure
        PathManager.shared.ensureDataDirectories()
        logger.log(category: .general, message: "Data Root: \(PathManager.shared.rootDataURL.path)")
        
        // F-6.0: Initialize Metadata Manager & Migrate Legacy Files
        Task {
            // Run in background to avoid blocking launch
            await MetadataManager.shared.load()
            await MetadataManager.shared.scanAndMigrate()
            
            // Refresh local model availability cache
            SettingsManager.shared.refreshReadyLocalModels()
        }

        
        // F-5.10: AI Capability Check (v0.5.0)
        AICapability.shared.configure()
        logger.log(category: .general, message: "System Info:\n\(SystemChecker.getSystemInfoString())")
        AICapability.shared.showIntelAlertIfNeeded()
        
        // Hide dock icon - menu bar only app
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.log(category: .general, message: "App terminating")
        
        if recordingService.isRecording {
            recordingService.stopRecording()
        }
        
        durationUpdateTimer?.invalidate()
    }
    
    /// Handle Dock icon click when app is already running
    /// This is called when user clicks the Dock icon (especially when pinned)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows, open the Dashboard
            openDashboardWindow()
        }
        return true
    }
    
    // MARK: - Setup
    
    private func setupSubscriptions() {
        // Observe recording state changes via NotificationCenter
        NotificationCenter.default.publisher(for: .recordingDidStart)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleRecordingStateChange(state: .recording)
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .recordingDidStop)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handleRecordingStateChange(state: .idle)
                // F-9.1: Removed automatic AI processing prompt
                // AI processing is now triggered manually from DetailView
                if let url = notification.userInfo?["url"] as? URL {
                    self?.lastRecordedURL = url
                    // F-9.1: No longer calling showAIProcessingPrompt(for: url)
                }
            }
            .store(in: &cancellables)
            
        // F-2.5: Handle pause/resume for icon updates
        NotificationCenter.default.publisher(for: .recordingDidPause)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleRecordingStateChange(state: .paused)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .recordingDidResume)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleRecordingStateChange(state: .recording)
            }
            .store(in: &cancellables)
            
        // F-10.4: Handle OpenPreferences from DetailView
        NotificationCenter.default.publisher(for: Notification.Name("OpenPreferences"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.openPreferences()
            }
            .store(in: &cancellables)

        // Handle showAISettings notification from UnifiedSettingsView
        NotificationCenter.default.publisher(for: .showAISettings)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.openAISettings()
            }
            .store(in: &cancellables)

        // Handle showAbout notification from UnifiedSettingsView
        NotificationCenter.default.publisher(for: .showAbout)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.openAbout()
            }
            .store(in: &cancellables)
    }
    
    // Updated to accept RecordingState instead of Bool
    private func handleRecordingStateChange(state: RecordingState) {
        updateMenuState(state: state)
        if state == .recording {
            startDurationUpdateTimer()
        } else if state == .idle {
            durationUpdateTimer?.invalidate()
            durationUpdateTimer = nil
        }
        // If paused, we can keep timer invalid or handle it differently. 
        // For menu icon, pausing updates might be fine, but the timer text update relies on this timer.
        // If paused, paused duration grows, but adjusted duration stays same.
        // We can keep timer running to update "Paused: 00:05" if we want, or just update title once.
        // For simplicity, let's keep timer running but check state in update.
    }
    
    /// Configure the menu bar status item
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Accessible ID for UI Test (F-Testability)
            button.setAccessibilityIdentifier("MenuBarIcon_Idle")
            
            // F-2.5: Use Generator
            button.image = iconGenerator.icon(for: .idle)
            button.action = #selector(statusItemClicked)
            button.target = self
        }
        
        setupMenu()
    }
    
    /// Build the dropdown menu
    private func setupMenu() {
        let menu = NSMenu()
        
        // Status display (Active/Idle)
        let statusItem = NSMenuItem(title: L10n.Menu.Status.ready, action: nil, keyEquivalent: "")
        statusItem.tag = 100
        menu.addItem(statusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // F-6.1: Dashboard Access
        let dashboardItem = NSMenuItem(title: L10n.Menu.Action.manageRecordings, action: #selector(openDashboard), keyEquivalent: "m")
        dashboardItem.setAccessibilityIdentifier("MenuItem_Dashboard")
        menu.addItem(dashboardItem)
        
        menu.addItem(NSMenuItem.separator())

        
        // Start/Stop Recording
        let recordItem = NSMenuItem(title: L10n.Menu.Action.startRecording, action: #selector(toggleRecording), keyEquivalent: "r")
        recordItem.tag = 101
        recordItem.setAccessibilityIdentifier("MenuItem_StartRecording")
        menu.addItem(recordItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open Folder
        let folderItem = NSMenuItem(title: L10n.Menu.Action.openFolder, action: #selector(openRecordingsFolder), keyEquivalent: "o")
        folderItem.setAccessibilityIdentifier("MenuItem_OpenFolder")
        menu.addItem(folderItem)
        
        // Open Logs
        let logsItem = NSMenuItem(title: L10n.Menu.Action.openLogs, action: #selector(openLogsFolder), keyEquivalent: "l")
        logsItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(logsItem)
        
        // Preferences
        let prefItem = NSMenuItem(title: L10n.Menu.Action.preferences, action: #selector(openPreferences), keyEquivalent: ",")
        prefItem.setAccessibilityIdentifier("MenuItem_Preferences")
        menu.addItem(prefItem)
        
        // About
        let aboutItem = NSMenuItem(title: L10n.Menu.Action.about, action: #selector(openAbout), keyEquivalent: "")
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: L10n.Menu.Action.quit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.setAccessibilityIdentifier("MenuItem_Quit")
        menu.addItem(quitItem)
        
        self.statusItem?.menu = menu
        
        // Apply current state
        // Apply current state
        updateMenuState(state: recordingService.recordingState)
    }
    
    /// Check permissions on launch
    private func checkPermissions() {
        // 1. Accessibility (Immediate check & prompt)
        if !permissionManager.checkAccessibilityPermission() {
            _ = permissionManager.requestAccessibilityPermission()
        }
        
        Task {
            // 2. Screen & Mic (Async check)
            let screenPermission = await permissionManager.checkScreenCapturePermission()
            let micPermission = await permissionManager.checkMicrophonePermission()
            let axPermission = permissionManager.checkAccessibilityPermission()
            
            await MainActor.run {
                logger.log(category: .permission, message: "Startup check - AX: \(axPermission), Screen: \(screenPermission), Mic: \(micPermission)")
                
                if !screenPermission || !micPermission || !axPermission {
                    showPermissionAlert(screen: screenPermission, mic: micPermission, ax: axPermission)
                }
            }
        }
    }
    
    private func showPermissionAlert(screen: Bool = true, mic: Bool = true, ax: Bool = true) {
        // If all are granted, don't show
        if screen && mic && ax { return }
        
        // Use generic error if PermissionManager error text is used, 
        // or customize here based on missing permissions
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.Alert.Button.openSettings)
        alert.addButton(withTitle: L10n.Alert.Button.later)
        
        if !ax {
            alert.messageText = "Permission Required" // L10n.Alert.PermissionsRequired.title
            alert.informativeText = "MeetingSonar needs Accessibility permission to detect meeting windows (e.g. Zoom Meeting). Please grant it in System Settings."
            // TODO: Use PermissionManager.PermissionError.accessibilityNotAuthorized.errorDescription ?
        } else if !screen {
             alert.messageText = L10n.Alert.PermissionsRequired.title
             alert.informativeText = "Screen Recording permission is required to capture audio."
        } else {
             alert.messageText = L10n.Alert.PermissionsRequired.title
             alert.informativeText = L10n.Alert.PermissionsRequired.message
        }
        
        if alert.runModal() == .alertFirstButtonReturn {
            if !ax {
                permissionManager.openAccessibilitySettings()
            } else if !screen {
                permissionManager.openScreenRecordingSettings()
            } else {
                permissionManager.openSystemSettings()
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func statusItemClicked() {
        // Menu shown automatically
    }
    
    @objc private func toggleRecording() {
        if recordingService.isRecording {
            Task { try? await recordingService.stopRecording() }
        } else {
            Task { @MainActor in
                startRecording()
            }
        }
    }
    
    @MainActor
    private func startRecording() {
        LoggerService.shared.log(category: .recording, level: .debug, message: "Attempting to start recording...")

        let savePath = SettingsManager.shared.savePath
        if !isWritable(path: savePath) {
            showPermissionErrorAlert(path: savePath)
            return
        }

        Task {
            do {
                try await recordingService.startRecording(trigger: .manual)
                LoggerService.shared.log(category: .recording, level: .info, message: "Recording started successfully")
                // UI update handled by subscription
            } catch {
                await MainActor.run {
                    showErrorAlert(error: error)
                }
            }
        }
    }

    private func isWritable(path: URL) -> Bool {
        let testUrl = path.appendingPathComponent(".permission_check_\(UUID().uuidString)")
        do {
            try "test".write(to: testUrl, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testUrl)
            return true
        } catch {
            LoggerService.shared.log(category: .permission, level: .error, message: "[Permissions] Write check failed for \(path.path): \(error)")
            return false
        }
    }
    
    private func showPermissionErrorAlert(path: URL) {
        let alert = NSAlert()
        alert.messageText = L10n.Alert.CannotSave.title
        alert.informativeText = L10n.Alert.CannotSave.message(path.path)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.Alert.Button.openPreferences)
        alert.addButton(withTitle: L10n.Alert.Button.cancel)
        
        if alert.runModal() == .alertFirstButtonReturn {
            openPreferencesWindow()
        }
    }
    
    private func stopRecording() {
         // Stop call only. UI update handled by subscription.
         recordingService.stopRecording()
    }
    
    @objc private func openRecordingsFolder() {
        Task { @MainActor in
            let savePath = SettingsManager.shared.savePath
            NSWorkspace.shared.open(savePath)
        }
    }
    
    @objc private func openLogsFolder() {
        logger.openLogDirectory()
    }
    
    @objc private func openPreferences() {
        openPreferencesWindow()
    }
    
    @objc private func openDashboard() {
        openDashboardWindow()
    }

    @objc private func openAISettings() {
        // Open preferences window (which now includes AI settings section)
        openPreferencesWindow()
    }

    @objc private func openAbout() {
        openPreferencesWindow()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Dock Icon Policy (F-10.4)
    
    private func updateDockIconPolicy() {
        // Debounce to prevent rapid flickering
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(performDockPolicyUpdate), object: nil)
        self.perform(#selector(performDockPolicyUpdate), with: nil, afterDelay: 0.1)
    }
    
    @objc private func performDockPolicyUpdate() {
        let shouldShowDockIcon = (preferencesWindow != nil || dashboardWindow != nil)
        let currentPolicy = NSApp.activationPolicy()
        
        if shouldShowDockIcon && currentPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
            // Re-activate to ensure menu bar appears
            NSApp.activate(ignoringOtherApps: true)
        } else if !shouldShowDockIcon && currentPolicy != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - UI Updates

    


    
    private func updateMenuState(state: RecordingState) {
        let isRecording = (state != .idle)
        
        if let button = statusItem?.button {
            // F-2.5: Dynamic Icon Logic
            var iconState: MenuIconGenerator.IconState = .idle
            if state == .recording { iconState = .recording }
            else if state == .paused { iconState = .paused }
            
            button.image = iconGenerator.icon(for: iconState)
            
            // Reset tint color as we are drawing colors in the image itself
            button.contentTintColor = nil 
            
            // Accessibility
            switch state {
            case .recording: button.setAccessibilityIdentifier("MenuBarIcon_Recording")
            case .paused: button.setAccessibilityIdentifier("MenuBarIcon_Paused")
            default: button.setAccessibilityIdentifier("MenuBarIcon_Idle")
            }
        }
        
        if let menu = statusItem?.menu {
            if let statusItem = menu.item(withTag: 100) {
                if isRecording {
                    let duration = recordingService.adjustedDuration
                    let timeString = formatDuration(duration)
                    if state == .paused {
                        statusItem.title = "Paused: \(timeString)"
                    } else {
                        statusItem.title = L10n.Menu.Status.recording(timeString)
                    }
                } else {
                    statusItem.title = L10n.Menu.Status.ready
                }
            }
            
            // Update Action Item (Stop/Start)
            // Note: Pause/Resume is not in the main menu yet, only in Overlay.
            // Main menu currently only controls Start/Stop.
            if let recordItem = menu.item(withTag: 101) {
                if isRecording {
                    recordItem.title = L10n.Menu.Action.stopRecording
                    recordItem.setAccessibilityIdentifier("MenuItem_StopRecording")
                    recordItem.action = #selector(stopRecordingWrapper) // New wrapper to handle stop
                } else {
                    recordItem.title = L10n.Menu.Action.startRecording
                    recordItem.setAccessibilityIdentifier("MenuItem_StartRecording")
                    recordItem.action = #selector(toggleRecording)
                }
            }
        }
    }
    
    @objc private func stopRecordingWrapper() {
        Task { try? await recordingService.stopRecording() }
    }
    
    private func startDurationUpdateTimer() {
        durationUpdateTimer?.invalidate()
        // Must add to .common mode to fire during menu event tracking
        let timer = Timer(timeInterval: TimerConstants.durationUpdateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // self.recordingService.recordingState might be recording OR paused.
            // We want to update the menu title (timer) regardless.
            self.updateMenuState(state: self.recordingService.recordingState)
        }
        RunLoop.current.add(timer, forMode: .common)
        durationUpdateTimer = timer
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / TimeConstants.secondsPerHour
        let minutes = (totalSeconds % TimeConstants.secondsPerHour) / TimeConstants.secondsPerMinute
        let secs = totalSeconds % TimeConstants.secondsPerMinute

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
    
    private func openPreferencesWindow() {
        LoggerService.shared.log(category: .general, level: .debug, message: "[App] openPreferencesWindow called")

        if let window = preferencesWindow {
            LoggerService.shared.log(category: .general, level: .debug, message: "[App] Existing Preferences window found. Activating.")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        LoggerService.shared.log(category: .general, level: .debug, message: "[App] Creating new Preferences window.")
        let preferencesView = PreferencesView()
        let hostingController = NSHostingController(rootView: preferencesView)
        
        // Ensure the hosting controller has a size before window creation (helper for some macOS versions)
        hostingController.view.frame = CGRect(x: 0, y: 0, width: 500, height: 400)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Preferences" // Fallback if L10n fails or is slow
        // window.title = L10n.Window.preferencesTitle
        
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 500, height: 400))
        window.minSize = NSSize(width: 480, height: 320)
        
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("MeetingSonarPreferences")
        
        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateDockIconPolicy()
        LoggerService.shared.log(category: .general, level: .debug, message: "[App] Preferences window created and activated.")
    }

    private func openDashboardWindow() {
        if let window = dashboardWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let dashboardView = DashboardView()
        let hostingController = NSHostingController(rootView: dashboardView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "MeetingSonar"
        // F-6.1: Resizable window
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 800, height: 600))
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Autosave frame
        window.setFrameAutosaveName("DashboardWindow")

        dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateDockIconPolicy()
        LoggerService.shared.log(category: .general, level: .info, message: "Dashboard window opened")
    }

    private func showErrorAlert(error: Error) {
        LoggerService.shared.log(category: .general, level: .error, message: "Error Alert: \(error)")
        let alert = NSAlert()
        alert.messageText = L10n.Alert.RecordingError.title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }
    
    // MARK: - AI Processing (v0.5.0)
    
    /// Show prompt to generate AI meeting summary after recording stops
    private func showAIProcessingPrompt(for audioURL: URL) {
        // Check if AI is available (Apple Silicon only)
        guard !AICapability.shared.isDisabled else {
            logger.log(category: .ai, message: "[AI] Skipping prompt - AI not available on this device")
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.recordingSaved.message", comment: "")
        alert.informativeText = String(format: NSLocalizedString("alert.recordingSaved.informative", comment: ""), audioURL.lastPathComponent)
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("alert.recordingSaved.button.generate", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("alert.recordingSaved.button.later", comment: ""))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            startAIProcessing(for: audioURL)
        }
    }
    
    /// Start AI processing pipeline for the recorded audio (Cloud-only version)
    private func startAIProcessing(for audioURL: URL) {
        Task { @MainActor in
            // Cloud-only: Check if API is configured
            let isConfigured = await ModelManager.shared.isModelReady(.online)

            if !isConfigured {
                // Show configuration prompt
                let shouldConfigure = showAPIConfigPrompt()
                if !shouldConfigure {
                    return
                }
            }

            // Show processing notification
            NotificationManager.shared.showAIProcessingNotification()

            // Start processing using the new coordinator
            do {
                // F-6.0: Mark as processing
                await MetadataManager.shared.updateStatus(filename: audioURL.lastPathComponent, status: .processing)

                await AIProcessingCoordinator.shared.process(audioURL: audioURL, meetingID: UUID())

                // F-6.0: Mark as completed
                await MetadataManager.shared.updateAIStatus(
                    filename: audioURL.lastPathComponent,
                    status: .completed,
                    hasTranscript: true,
                    hasSummary: false  // TODO: Enable when LLM is implemented
                )

                // Show completion notification
                // NotificationManager.shared.showAICompleteNotification(summaryURL: result.summaryURL)

            } catch {
                // F-6.0: Mark as failed
                await MetadataManager.shared.updateStatus(filename: audioURL.lastPathComponent, status: .failed)

                logger.log(category: .ai, level: .error, message: "[AI] Processing failed: \(error)")
                showAIErrorAlert(error: error)
            }
        }
    }

    /// Show API configuration prompt
    private func showAPIConfigPrompt() -> Bool {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.apiConfigRequired.title", comment: "")

        alert.informativeText = NSLocalizedString("alert.apiConfigRequired.message", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("alert.apiConfigRequired.button.openSettings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("alert.apiConfigRequired.button.cancel", comment: ""))

        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            openPreferences()
        }
        return false  // Return false to stop processing, user needs to configure first
    }

    /// Show alert when AI processing completes
    private func showAICompleteAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.transcriptionComplete.title", comment: "")
        alert.informativeText = NSLocalizedString("alert.transcriptionComplete.message", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: ""))
        alert.runModal()
    }

    /// Show alert when AI processing fails
    private func showAIErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.aiProcessingFailed.title", comment: "")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("alert.aiProcessingFailed.button.ok", comment: ""))
        alert.runModal()
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    /// Show AI Settings notification (from UnifiedSettingsView)
    static let showAISettings = Notification.Name("showAISettings")
    /// Show About notification (from UnifiedSettingsView)
    static let showAbout = Notification.Name("showAbout")
}

@available(macOS 13.0, *)
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window == preferencesWindow {
                preferencesWindow = nil
            } else if window == dashboardWindow {
                dashboardWindow = nil
            }
            updateDockIconPolicy()
        }
    }
}

// Extension to ease setting accessibility Identifier
extension NSAccessibilityElement {
    func setAccessibilityIdentifier(_ id: String) {
        self.setAccessibilityElement(true)
        self.setAccessibilityIdentifier(id)
    }
}

