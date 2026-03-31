import Foundation
import Combine

/// Coordinator for Smart Awareness features (F-2.2)
@MainActor
class DetectionService: ObservableObject, DetectionServiceProtocol {
    static let shared = DetectionService()

    // MARK: - Dependencies

    private let appMonitor: ApplicationMonitor
    private let logMonitor: LogMonitorService
    private let recordingService: RecordingServiceProtocol
    private let notificationManager: NotificationManager
    private let settings: SettingsManagerProtocol
    private let logger: LoggerService

    private var cancellables = Set<AnyCancellable>()

    /// Timer for checking mic status if needed (though LogMonitor is push-based)
    private var stopDebounceTimer: Timer?
    private let debounceInterval: TimeInterval = 2.0

    /// Manual stop suppression: prevents auto-start for a cooldown period after user manually stops recording.
    /// This avoids false re-triggers caused by Teams afterglow signals (~600ms post-meeting-end).
    private var manualStopSuppressed: Bool = false
    private var suppressionLiftTimer: Timer?
    private let suppressionCooldown: TimeInterval = 5.0

    /// Test mode flag
    private let testMode: Bool

    // MARK: - Initialization

    /// Standard initialization (production use)
    private init() {
        // Create default instances
        self.appMonitor = ApplicationMonitor()
        self.logMonitor = LogMonitorService.shared
        self.recordingService = RecordingService.shared
        self.notificationManager = NotificationManager.shared
        self.settings = SettingsManager.shared
        self.logger = LoggerService.shared
        self.testMode = false

        setupSubscriptions()
        setupNotificationHandling()

        // Configure LogMonitor with alias-to-canonical mapping
        logMonitor.configureMonitoredApps(appMonitor.enabledApps)

        // Ensure LogMonitor starts
        logMonitor.startMonitoring()
    }

    /// Test initialization with dependency injection
    ///
    /// - Parameters:
    ///   - appMonitor: Mock or real application monitor
    ///   - logMonitor: Mock or real log monitor service
    ///   - recordingService: Mock or real recording service
    ///   - notificationManager: Mock or real notification manager
    ///   - settings: Mock or real settings manager
    ///   - logger: Mock or real logger service
    /// - Important: Only use this in unit tests
    @MainActor
    static func createForTesting(
        appMonitor: ApplicationMonitor,
        logMonitor: LogMonitorService = LogMonitorService.shared,
        recordingService: RecordingServiceProtocol = RecordingService.shared,
        notificationManager: NotificationManager = NotificationManager.shared,
        settings: SettingsManagerProtocol = SettingsManager.shared,
        logger: LoggerService = LoggerService.shared
    ) -> DetectionService {
        let instance = DetectionService(
            appMonitor: appMonitor,
            logMonitor: logMonitor,
            recordingService: recordingService,
            notificationManager: notificationManager,
            settings: settings,
            logger: logger,
            testMode: true
        )
        return instance
    }

    /// Private initializer with dependency injection
    private init(
        appMonitor: ApplicationMonitor,
        logMonitor: LogMonitorService,
        recordingService: RecordingServiceProtocol,
        notificationManager: NotificationManager,
        settings: SettingsManagerProtocol,
        logger: LoggerService,
        testMode: Bool
    ) {
        self.appMonitor = appMonitor
        self.logMonitor = logMonitor
        self.recordingService = recordingService
        self.notificationManager = notificationManager
        self.settings = settings
        self.logger = logger
        self.testMode = testMode

        setupSubscriptions()
        setupNotificationHandling()

        // Configure LogMonitor with alias-to-canonical mapping
        logMonitor.configureMonitoredApps(appMonitor.enabledApps)

        // Ensure LogMonitor starts
        logMonitor.startMonitoring()
    }

    /// Start monitoring
    func start() {
        Task { @MainActor in
            // Only start monitoring if enabled in settings
            if settings.smartDetectionEnabled {
                appMonitor.startMonitoring()
                logger.log(category: .detection, message: "DetectionService started")
            } else {
                logger.log(category: .detection, message: "DetectionService disabled by settings")
            }
        }
    }
    
    private func setupSubscriptions() {
        // Listen to ApplicationMonitor state changes
        // Combine with LogMonitor changes.
        // We want to react if EITHER changes.
        
        Publishers.CombineLatest(appMonitor.$meetingState, logMonitor.$activeMicUsers)
            .receive(on: RunLoop.main)
            .sink { [weak self] (appState, activeMicUsers) in
                Task { @MainActor [weak self] in
                    self?.evaluateMeetingStatus(appState: appState, activeMicUsers: activeMicUsers)
                }
            }
            .store(in: &cancellables)
            
        // Listen for Recording Stopped event to send "Saved" notification
        NotificationCenter.default.publisher(for: .recordingDidStop)
            .sink { [weak self] notification in
                self?.handleRecordingStopped(notification)
            }
            .store(in: &cancellables)
    }

    // New evaluation logic combining AppMonitor state and Log-based Mic state
    @MainActor
    private func evaluateMeetingStatus(appState: ApplicationMonitor.MeetingState, activeMicUsers: Set<String>) {
        guard settings.smartDetectionEnabled else { return }

        let hasMicUser = findMonitoredAppUsingMic(activeMicUsers)

        // Manual stop suppression lifecycle:
        // - Activated when user manually stops recording
        // - Stays active as long as any mic signal exists (meeting still going)
        // - Starts cooldown timer only when ALL mic signals disappear
        // - Lifted after cooldown expires with no new mic signals
        if manualStopSuppressed {
            if hasMicUser != nil {
                // Meeting still active — cancel any pending lift, keep suppressing
                suppressionLiftTimer?.invalidate()
                suppressionLiftTimer = nil
            } else if suppressionLiftTimer == nil {
                // All mic signals gone — start cooldown to lift suppression
                scheduleSuppressionLift()
            }
            // While suppressed, don't trigger any auto-start
            // But still allow auto-stop if recording (shouldn't happen, but safe)
            if recordingService.isRecording && hasMicUser == nil {
                scheduleAutoStop()
            }
            return
        }

        // 1. Priority Check: Is ANY monitored app using the Microphone?
        if let micUser = hasMicUser {
            logger.log(category: .detection, message: "Mic usage detected globally: \(micUser.processName)")
            handleMeetingDetected(appName: micUser.processName)
            return
        }

        // 2. Secondary Check: Window Title matches (Legacy/Fallback)
        switch appState {
        case .inMeeting:
            if let appName = appMonitor.currentMeetingApp?.processName {
                handleMeetingDetected(appName: appName)
            }

        case .running, .notRunning:
            // No Mic AND No Window — safe to schedule stop
            if recordingService.isRecording {
                scheduleAutoStop()
            }
        }
    }
    
    private func findMonitoredAppUsingMic(_ activeMicUsers: Set<String>) -> ApplicationMonitor.MonitoredApp? {
        for app in appMonitor.enabledApps {
            // Check canonical processName
            if activeMicUsers.contains(app.processName) { return app }
            // Check aliases (activeMicUsers stores matched names which may be aliases)
            if app.logProcessAliases.contains(where: { activeMicUsers.contains($0) }) {
                return app
            }
        }
        return nil
    }
    
    private func setupNotificationHandling() {
        // Listen for "Start Recording" action from NotificationManager
        NotificationCenter.default.publisher(for: .startRecordingRequested)
            .sink { [weak self] _ in
                self?.handleStartRecordingRequest()
            }
            .store(in: &cancellables)
    }
    
    // Old handleStateChange removed. Logic moved to evaluateMeetingStatus.
    
    @MainActor
    private func handleMeetingDetected(appName: String) {
        // Cancel any pending stop (debounce)
        stopDebounceTimer?.invalidate()
        stopDebounceTimer = nil

        // If already recording, do nothing
        if recordingService.isRecording { return }

        // If user recently manually stopped, suppress auto-start to avoid afterglow false triggers
        if manualStopSuppressed {
            logger.log(category: .detection, level: .debug, message: "Auto-start suppressed (manual stop cooldown active) for \(appName)")
            return
        }

        logger.log(category: .detection, message: "Meeting started: \(appName)")
        
        switch settings.smartDetectionMode {
        case .auto:
            Task {
                do {
                    try await recordingService.startRecording(trigger: .auto, appName: appName)
                    notificationManager.sendAutoStartNotification(appName: appName)
                    logger.log(category: .detection, message: "Auto-recording started for \(appName)")
                } catch {
                    logger.log(category: .detection, level: .error, message: "Auto-recording failed: \(error)")
                }
            }
            
        case .remind:
            // Show in-app overlay instead of system notification
            NotificationCenter.default.post(name: .showRemindOverlay, object: nil, userInfo: ["appName": appName])
            logger.log(category: .detection, message: "Sent reminder overlay for \(appName)")
        }
    }
    
    private func scheduleAutoStop() {
        // If timer already running, let it run
        if stopDebounceTimer != nil { return }

        logger.log(category: .detection, message: "Meeting ended. Scheduling auto-stop in \(debounceInterval)s...")

        stopDebounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performAutoStop()
            }
        }
    }
    
    /// Flag to distinguish auto-stop from manual stop in handleRecordingStopped
    private var isAutoStopping: Bool = false

    private func performAutoStop() {
        stopDebounceTimer = nil

        // Final check: is recording still active?
        guard recordingService.isRecording else { return }

        isAutoStopping = true
        recordingService.stopRecording()
        logger.log(category: .detection, message: "Auto-stopped recording.")
    }

    // MARK: - Manual Stop Suppression

    /// Activate suppression to prevent auto-start after manual stop.
    /// Suppression stays active until all mic signals disappear + cooldown expires.
    private func activateManualStopSuppression() {
        manualStopSuppressed = true
        suppressionLiftTimer?.invalidate()
        suppressionLiftTimer = nil
        logger.log(category: .detection, level: .debug, message: "Manual stop suppression activated (will lift \(suppressionCooldown)s after all mic signals stop)")
    }

    /// Schedule suppression lift — called when activeMicUsers becomes empty while suppressed
    private func scheduleSuppressionLift() {
        suppressionLiftTimer?.invalidate()
        logger.log(category: .detection, level: .debug, message: "All mic signals gone, scheduling suppression lift in \(suppressionCooldown)s")

        suppressionLiftTimer = Timer.scheduledTimer(withTimeInterval: suppressionCooldown, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.liftManualStopSuppression()
            }
        }
    }

    /// Lift suppression after cooldown expires
    private func liftManualStopSuppression() {
        manualStopSuppressed = false
        suppressionLiftTimer?.invalidate()
        suppressionLiftTimer = nil
        logger.log(category: .detection, level: .debug, message: "Manual stop suppression lifted")
    }
    
    private func handleRecordingStopped(_ notification: Notification) {
        Task { @MainActor in
            // Activate manual stop suppression if this was NOT an auto-stop
            // (isAutoStopping is set true only in performAutoStop)
            if !isAutoStopping {
                activateManualStopSuppression()
            }
            isAutoStopping = false

            if let url = notification.userInfo?["url"] as? URL {
                notificationManager.sendRecordingSavedNotification(path: url)
            } else {
                notificationManager.sendRecordingSavedNotification(path: settings.savePath)
            }
        }
    }
    
    private func handleStartRecordingRequest() {
        Task {
            do {
                try await recordingService.startRecording(trigger: .manual, appName: nil) // Manual trigger from reminder
                logger.log(category: .detection, message: "User accepted reminder, recording started.")
            } catch {
                logger.log(category: .detection, level: .error, message: "Failed to start recording from notification: \(error)")
            }
        }
    }

    // MARK: - Cleanup

    /// CRITICAL FIX: Cleanup method to prevent memory leaks
    /// Call this when the service needs to be reset (e.g., in tests or on app termination)
    func cleanup() {
        // Cancel all Combine subscriptions to prevent memory leaks
        cancellables.removeAll()

        // Invalidate timers
        stopDebounceTimer?.invalidate()
        stopDebounceTimer = nil
        suppressionLiftTimer?.invalidate()
        suppressionLiftTimer = nil
        manualStopSuppressed = false

        logger.log(category: .detection, message: "DetectionService cleaned up")
    }

    /// Deinit to ensure resources are released
    /// Note: Since DetectionService is a singleton, deinit is rarely called in production.
    /// However, this is important for testing and potential future refactoring.
    ///
    /// - Important: Cannot call cleanup() directly from deinit due to @MainActor isolation.
    /// Resources are cleaned up when cleanup() is called explicitly.
    deinit {
        // Timer cleanup is safe from deinit
        stopDebounceTimer?.invalidate()
        stopDebounceTimer = nil
        suppressionLiftTimer?.invalidate()
        suppressionLiftTimer = nil
    }
}

// MARK: - Log Monitor (Private Service)
// Ideally this should be a separate file, but for MVP/Build simplicity integrated here.
class LogMonitorService: ObservableObject {
    static let shared = LogMonitorService()
    
    @Published private(set) var activeMicUsers: Set<String> = [] // keyed by matched process name (not canonical)

    // Sorted by length descending for longest-match-first substring matching.
    // Ensures "Microsoft Teams WebView Helper" matches before "Microsoft Teams".
    private(set) var sortedProcessNames: [String] = []

    // Maps any alias/name → canonical processName (e.g. "Microsoft Teams WebView Helper" → "MSTeams")
    private(set) var aliasToCanonical: [String: String] = [:]
    
    private var process: Process?
    private var pipe: Pipe?
    private let queue = DispatchQueue(label: "com.meetingsonar.logmonitor")
    private var isMonitoring = false
    private var restartTimer: Timer?
    
    private init() {}

    deinit {
        stopMonitoring()
    }

    /// Configure monitored apps with alias-to-canonical mapping.
    /// Must be called before startMonitoring().
    func configureMonitoredApps(_ apps: [ApplicationMonitor.MonitoredApp]) {
        var mapping: [String: String] = [:]
        var allNames = Set<String>()
        for app in apps {
            // processName maps to itself
            mapping[app.processName] = app.processName
            allNames.insert(app.processName)
            // Each alias maps to canonical processName
            for alias in app.logProcessAliases {
                mapping[alias] = app.processName
                allNames.insert(alias)
            }
        }
        aliasToCanonical = mapping
        // Sort by length descending: "Microsoft Teams WebView Helper" before "Microsoft Teams"
        sortedProcessNames = allNames.sorted { $0.count > $1.count }
        LoggerService.shared.log(category: .detection, level: .debug,
            message: "[LogMonitor] Configured \(sortedProcessNames.count) process names with \(mapping.count) alias mappings")
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        queue.async { [weak self] in
            self?.runLogStream()
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        process?.terminate()
        process = nil
        pipe = nil
        restartTimer?.invalidate()
    }
    
    private func runLogStream() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        
        // Predicate: Search for CoreAudio client session state changes
        // We need broadly "setPlayState" to catch both "IOState" (Teams) and "Started Input" (Zoom)
        let predicate = "message CONTAINS 'setPlayState'"
        process.arguments = ["stream", "--predicate", predicate]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        self.pipe = pipe
        self.process = process
        
        process.terminationHandler = { [weak self] _ in
            guard let self = self, self.isMonitoring else { return }
            DispatchQueue.main.async {
                self.scheduleRestart()
            }
        }
        
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            if !data.isEmpty, let string = String(data: data, encoding: .utf8) {
                self?.processLogOutput(string)
            }
        }
        
        do {
            try process.run()
            LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] Started monitoring CoreAudio logs for mic usage")
        } catch {
            LoggerService.shared.log(category: .detection, level: .error, message: "[LogMonitor] Failed to start log stream: \(error)")
        }
    }
    
    private func scheduleRestart() {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.queue.async {
                self?.runLogStream()
            }
        }
    }
    
    private func processLogOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            // Filter for setPlayState first to reduce noise
            guard line.contains("setPlayState") else { continue }

            // Longest-match-first: sortedProcessNames is pre-sorted by length descending.
            // "Microsoft Teams WebView Helper" will match before "Microsoft Teams".
            guard let matchedName = sortedProcessNames.first(where: { line.contains($0) }) else {
                continue
            }

            // Resolve to canonical processName (e.g. "Microsoft Teams WebView Helper" → "MSTeams")
            let canonicalName = aliasToCanonical[matchedName] ?? matchedName

            // Debug print to see what we are catching
            LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] Processing line for \(canonicalName) (via \(matchedName)): \(line)")

            var isActive: Bool? = nil

            // Pattern 1: IOState: [Input, Output] (Teams mostly)
            if let range = line.range(of: "IOState: [") {
                let afterStart = line[range.upperBound...]
                let parts = afterStart.components(separatedBy: ",")
                if parts.count >= 1,
                   let inputStr = parts.first?.trimmingCharacters(in: .whitespaces),
                   let inputLevel = Int(inputStr) {
                    isActive = inputLevel > 0
                    LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] -> Matched IOState. Active: \(isActive!)")
                }
            }
            // Pattern 2: Explicit "Started Input" (Zoom) - Exclude WeChat's "Input/Output" combined format
            else if line.contains("setPlayState Started") && line.contains("Input") && !line.contains("Input/Output") {
                isActive = true
                LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] -> Matched Started Input. Active: true")
            }
            // Pattern 3: Explicit "Stopped Input" (Zoom)
            else if line.contains("setPlayState Stopped") && line.contains("Input") {
                isActive = false
                LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] -> Matched Stopped Input. Active: false")
            } else {
                 LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] -> No Pattern Matched.")
            }

            guard let newStatus = isActive else { continue }

            // Use the matched name (not canonical) as key in activeMicUsers.
            // MSTeams and Microsoft Teams WebView Helper are separate processes
            // with independent IOState — canonicalizing would cause one process's
            // inactive signal to remove the other's active state.
            let name = matchedName
            DispatchQueue.main.async {
                if newStatus {
                    if !self.activeMicUsers.contains(name) {
                        LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] Mic ACTIVE for: \(name)")
                        self.activeMicUsers.insert(name)
                    }
                } else {
                    if self.activeMicUsers.contains(name) {
                        LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] Mic INACTIVE for: \(name)")
                        self.activeMicUsers.remove(name)
                    }
                }
            }
        }
    }
}
