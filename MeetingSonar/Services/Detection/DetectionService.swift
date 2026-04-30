import Foundation
import Combine

// MARK: - Detection State Machine Types

enum DetectionState: Equatable {
    case monitoringAll(suppressedApps: Set<String>)
    case recordingLocked(RecordingContext)
    case cooldown(CooldownContext)
}

struct RecordingContext: Equatable {
    let triggerAppBundleID: String
    let triggerAppName: String
    let triggerSource: TriggerSource
    let triggerTimestamp: Date
}

enum TriggerSource: String, Equatable {
    case windowTitle
    case micUsage
    case manual
    case reminderAccepted
}

struct CooldownContext: Equatable {
    let reason: CooldownReason
    let triggerAppBundleID: String?
    let triggerAppName: String?
    let triggerType: TriggerSource?
    let recordingDuration: TimeInterval?
    var suppressedApps: Set<String>
    let cooldownStartTime: Date
    let cooldownDuration: TimeInterval
}

enum CooldownReason: String, Equatable {
    case autoStop
    case manualStop
    case maxDuration
    case appCrashed
    case appDisabled
}

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

    /// Current state of the detection state machine
    @Published private(set) var detectionState: DetectionState = .monitoringAll(suppressedApps: [])

    /// Consecutive no-signal polling cycles for auto-stop debounce
    private var consecutiveNoSignalCount: Int = 0
    /// Consecutive active-signal cycles before resetting the stop debounce (reverse hysteresis)
    private var reverseDebounceCount: Int = 0
    private let debounceThreshold: Int = 2

    /// Cooldown configuration
    private let cooldownDuration: TimeInterval = 5.0

    /// Timer for cooldown exit
    private var cooldownTimer: Timer?

    /// Timer for periodic signal re-evaluation during recording (Issue 2 fix).
    /// Ensures auto-stop detection even when LogMonitor misses CoreAudio mic-off events.
    private var recordingEvalTimer: Timer?

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
        Publishers.CombineLatest(appMonitor.$activeMeetingApps, logMonitor.$activeMicUsers)
            .receive(on: RunLoop.main)
            .sink { [weak self] (activeMeetingApps, activeMicUsers) in
                Task { @MainActor [weak self] in
                    self?.evaluateMeetingSignals(activeMeetingApps: activeMeetingApps, activeMicUsers: activeMicUsers)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .recordingDidStop)
            .sink { [weak self] notification in
                self?.handleRecordingStopped(notification)
            }
            .store(in: &cancellables)

        // LogMonitor dynamic reconfiguration on settings change
        NotificationCenter.default.publisher(for: .detectionSettingsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.logMonitor.reconfigure(apps: self?.appMonitor.enabledApps ?? [])
                LoggerService.shared.log(category: .detection, level: .info, message: "[DetectionService] LogMonitor reconfigured due to settings change")
            }
            .store(in: &cancellables)
    }

    // MARK: - Signal Evaluation

    /// Evaluates meeting signals from both ApplicationMonitor (window titles) and
    /// LogMonitorService (mic usage) and transitions the detection state machine.
    @MainActor
    private func evaluateMeetingSignals(activeMeetingApps: Set<String>, activeMicUsers: Set<String>) {
        guard settings.smartDetectionEnabled else { return }

        logger.log(category: .detection, level: .debug, message: """
            [DetectionService] evaluateMeetingSignals
            ├─ state: \(detectionState)
            ├─ activeMeetingApps: \(activeMeetingApps)
            ├─ activeMicUsers: \(activeMicUsers)
            └─ isRecording: \(recordingService.isRecording)
            """)

        switch detectionState {
        case .monitoringAll(let suppressedApps):
            for bundleID in activeMeetingApps {
                if let state = appMonitor.appStates[bundleID],
                   case .inMeeting = state.meetingState {
                    let app = state.config
                    guard !suppressedApps.contains(bundleID) else {
                        logger.log(category: .detection, level: .debug, message: "[Decision] triggerApp \(app.processName) is in suppressedApps, ignoring")
                        return
                    }
                    // FIXME(Task 9): settings.isAppDetectionEnabled(bundleID:) not yet implemented
                    if settings.isAppDetectionEnabled(bundleID: bundleID) {
                        handleMeetingDetected(appName: app.processName, bundleID: bundleID, source: .windowTitle)
                        return
                    }
                }
            }

            if let micApp = findMonitoredAppUsingMic(activeMicUsers) {
                guard !suppressedApps.contains(micApp.bundleIdentifier) else {
                    logger.log(category: .detection, level: .debug, message: "[Decision] micApp \(micApp.processName) is in suppressedApps, ignoring")
                    return
                }
                handleMeetingDetected(appName: micApp.processName, bundleID: micApp.bundleIdentifier, source: .micUsage)
                return
            }

        case .recordingLocked(let ctx):
            evaluateDuringRecording(context: ctx)

        case .cooldown:
            break
        }
    }

    /// Evaluates window and mic signals during an active recording to determine
    /// whether auto-stop should be triggered.
    /// - Parameter context: The current recording context
    /// Minimum recording duration (seconds) before auto-stop evaluation begins.
    /// Prevents premature stop due to signal gaps during recording initialization.
    private let minRecordingDurationBeforeAutoStop: TimeInterval = 10.0

    @MainActor
    private func evaluateDuringRecording(context: RecordingContext) {
        // Skip auto-stop until recording has been running long enough to stabilize signals.
        let elapsed = Date().timeIntervalSince(context.triggerTimestamp)
        guard elapsed >= minRecordingDurationBeforeAutoStop else {
            consecutiveNoSignalCount = 0
            reverseDebounceCount = 0
            return
        }

        let hasWindowSignal: Bool = {
            if let state = appMonitor.appStates[context.triggerAppBundleID],
               case .inMeeting = state.meetingState {
                return true
            }
            return false
        }()

        let hasWindowPatterns: Bool = {
            appMonitor.appStates[context.triggerAppBundleID]?.config.meetingWindowPatterns.isEmpty == false
        }()

        let hasMicSignal: Bool = {
            if let state = appMonitor.appStates[context.triggerAppBundleID] {
                let config = state.config
                return logMonitor.activeMicUsers.contains { name in
                    name == config.processName || config.logProcessAliases.contains(name)
                }
            }
            return false
        }()

        // Window-based debounce only applies when the meeting was detected via window title.
        // For mic-triggered recordings (window never matched), rely solely on mic signal.
        let useWindowSignal = context.triggerSource == .windowTitle && hasWindowPatterns
        let windowGone = useWindowSignal && !hasWindowSignal
        let micGone = !hasMicSignal
        let signalsActive = (!windowGone) && (!micGone)

        logger.log(category: .detection, level: .debug, message: """
            [Decision] evaluateDuringRecording for \(context.triggerAppName)
            ├─ hasWindowSignal: \(hasWindowSignal) (patterns: \(hasWindowPatterns))
            ├─ hasMicSignal: \(hasMicSignal) (activeMicUsers: \(logMonitor.activeMicUsers))
            ├─ windowGone: \(windowGone), micGone: \(micGone)
            ├─ signalsActive: \(signalsActive)
            └─ consecutiveNoSignalCount: \(consecutiveNoSignalCount)/\(debounceThreshold)
            """)

        if !signalsActive {
            consecutiveNoSignalCount += 1
            reverseDebounceCount = 0
            logger.log(category: .detection, level: .debug, message: "[Decision] autoStopDebounce: \(consecutiveNoSignalCount)/\(debounceThreshold) no-signal cycles for \(context.triggerAppName)")

            if consecutiveNoSignalCount >= debounceThreshold {
                let duration = Date().timeIntervalSince(context.triggerTimestamp)
                let cooldownCtx = CooldownContext(
                    reason: .autoStop,
                    triggerAppBundleID: context.triggerAppBundleID,
                    triggerAppName: context.triggerAppName,
                    triggerType: context.triggerSource,
                    recordingDuration: duration,
                    suppressedApps: [],
                    cooldownStartTime: Date(),
                    cooldownDuration: cooldownDuration
                )
                transition(to: .cooldown(cooldownCtx))
                scheduleCooldownExit(context: cooldownCtx)
                consecutiveNoSignalCount = 0
            }
        } else {
            // Reverse debounce: require sustained active signals before resetting the stop countdown.
            // Prevents single-cycle flickers (e.g. post-meeting Zoom/Feishu windows) from
            // resetting the auto-stop debounce.
            reverseDebounceCount += 1
            if reverseDebounceCount >= debounceThreshold {
                consecutiveNoSignalCount = 0
                reverseDebounceCount = 0
            }
        }
    }

    // MARK: - State Transitions

    /// Executes a state machine transition with guard enforcement and side effects.
    @MainActor
    private func transition(to newState: DetectionState) {
        let oldState = detectionState

        guard canTransition(from: oldState, to: newState) else {
            logger.log(category: .detection, level: .debug, message: "[Decision] transitionRejected: \(oldState) → \(newState)")
            return
        }

        executeTransitionSideEffects(from: oldState, to: newState)
        detectionState = newState
        logStateTransition(from: oldState, to: newState)
    }

    /// Guards transitions to ensure only valid state changes are allowed.
    @MainActor
    private func canTransition(from oldState: DetectionState, to newState: DetectionState) -> Bool {
        switch (oldState, newState) {
        case (.monitoringAll, .recordingLocked):
            guard settings.smartDetectionEnabled else { return false }
            guard settings.smartDetectionMode == .auto else { return false }
            guard !recordingService.isRecording else { return false }
            return true
        case (.recordingLocked, .cooldown):
            return true  // stopRecording is handled by executeTransitionSideEffects
        case (.recordingLocked, .monitoringAll):
            return !settings.smartDetectionEnabled
        case (.cooldown, .monitoringAll):
            return true
        case (.cooldown, .recordingLocked):
            return !recordingService.isRecording
        default:
            return false
        }
    }

    /// Executes side effects required when transitioning between detection states.
    @MainActor
    private func executeTransitionSideEffects(from oldState: DetectionState, to newState: DetectionState) {
        switch (oldState, newState) {
        case (_, .cooldown):
            consecutiveNoSignalCount = 0
            reverseDebounceCount = 0
            recordingEvalTimer?.invalidate()
            recordingEvalTimer = nil
            if recordingService.isRecording {
                recordingService.stopRecording()
            }
        case (_, .recordingLocked):
            // Start periodic signal re-evaluation (Issue 2 fix)
            recordingEvalTimer?.invalidate()
            recordingEvalTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard case .recordingLocked(let ctx) = self?.detectionState else { return }
                    self?.evaluateDuringRecording(context: ctx)
                }
            }
        case (.recordingLocked, .monitoringAll):
            recordingEvalTimer?.invalidate()
            recordingEvalTimer = nil
            if recordingService.isRecording {
                recordingService.stopRecording()
            }
        case (.cooldown, .recordingLocked):
            cooldownTimer?.invalidate()
            cooldownTimer = nil
        default:
            break
        }
    }

    /// Schedules automatic exit from cooldown state after the configured duration.
    private func scheduleCooldownExit(context: CooldownContext) {
        cooldownTimer?.invalidate()
        logger.log(category: .detection, level: .debug, message: "[DetectionService] cooldown started: reason=\(context.reason.rawValue), duration=\(context.cooldownDuration)s")
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: context.cooldownDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.exitCooldown()
            }
        }
    }

    /// Exits the cooldown state and transitions back to monitoringAll.
    /// The suppressed apps set depends on the cooldown reason.
    @MainActor
    private func exitCooldown() {
        guard case .cooldown(let ctx) = detectionState else { return }

        switch ctx.reason {
        case .autoStop, .appCrashed:
            transition(to: .monitoringAll(suppressedApps: []))
        case .manualStop:
            var suppressed = ctx.suppressedApps
            suppressed.formUnion(appMonitor.activeMeetingApps)
            transition(to: .monitoringAll(suppressedApps: suppressed))
        case .maxDuration:
            if hasActiveMeetingSignals() {
                showMaxDurationReminder(context: ctx)
                // Wait for user response: accept → recordingLocked (handled by handleStartRecordingRequest)
                // or decline/timeout → monitoringAll with suppressedApps
                cooldownTimer?.invalidate()
                cooldownTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard case .cooldown(var cooldownCtx) = self?.detectionState else {
                            self?.transition(to: .monitoringAll(suppressedApps: []))
                            return
                        }
                        if let bundleID = cooldownCtx.triggerAppBundleID {
                            cooldownCtx.suppressedApps.insert(bundleID)
                        }
                        self?.transition(to: .monitoringAll(suppressedApps: cooldownCtx.suppressedApps))
                    }
                }
                return  // Don't transition now — wait for user
            } else {
                transition(to: .monitoringAll(suppressedApps: []))
            }
        case .appDisabled:
            transition(to: .monitoringAll(suppressedApps: []))
        }

        cooldownTimer?.invalidate()
        cooldownTimer = nil
    }

    /// Checks whether any monitored app still has active meeting signals (window or mic).
    @MainActor
    private func hasActiveMeetingSignals() -> Bool {
        if !appMonitor.activeMeetingApps.isEmpty { return true }
        return findMonitoredAppUsingMic(logMonitor.activeMicUsers) != nil
    }

    /// Shows the max duration reminder overlay and logs the event.
    @MainActor
    private func showMaxDurationReminder(context: CooldownContext) {
        let minutes = SettingsManager.shared.maxRecordingDurationMinutes
        let appName = context.triggerAppName ?? "Unknown"
        NotificationCenter.default.post(
            name: .showRemindOverlay,
            object: nil,
            userInfo: [
                "appName": appName,
                "mode": "maxDuration",
                "durationMinutes": minutes
            ]
        )
        logger.log(category: .detection, level: .info, message: "[Decision] cooldownExit: showing maxDuration reminder for \(appName)")
    }

    /// Logs state machine transitions with detailed structured logging for debugging and traceability.
    /// Each transition case includes contextual information: trigger app, mic users, recording duration,
    /// cooldown reason, and suppressed apps — providing full observability into the detection state machine.
    private func logStateTransition(from oldState: DetectionState, to newState: DetectionState) {
        let df: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()
        let timestamp = df.string(from: Date())

        switch (oldState, newState) {
        case (_, .recordingLocked(let ctx)):
            logger.log(category: .detection, level: .info, message: """
                [DetectionStateMachine] → recordingLocked
                ├─ triggerApp: "\(ctx.triggerAppName)"
                ├─ triggerSource: \(ctx.triggerSource.rawValue)
                ├─ activeMicUsers: \(logMonitor.activeMicUsers)
                └─ timestamp: \(timestamp)
                """)

        case (.recordingLocked(let ctx), .cooldown(let cooldownCtx)):
            let durStr = cooldownCtx.recordingDuration.map { "\(Int($0))s (\(Int($0)/60)m\(Int($0)%60)s)" } ?? "0s"
            logger.log(category: .detection, level: .info, message: """
                [DetectionStateMachine] → cooldown
                ├─ reason: \(cooldownCtx.reason.rawValue)
                ├─ triggerApp: "\(ctx.triggerAppName)"
                ├─ recordingDuration: \(durStr)
                ├─ suppressedApps: \(cooldownCtx.suppressedApps)
                └─ timestamp: \(timestamp)
                """)

        case (.cooldown(let ctx), .monitoringAll(let suppressed)):
            logger.log(category: .detection, level: .info, message: """
                [DetectionStateMachine] → monitoringAll
                ├─ suppressedApps: \(suppressed)
                ├─ activeMicUsers: \(logMonitor.activeMicUsers)
                └─ timestamp: \(timestamp)
                """)

        case (_, .monitoringAll):
            logger.log(category: .detection, level: .info, message: """
                [DetectionStateMachine] → monitoringAll
                └─ timestamp: \(timestamp)
                """)

        default:
            logger.log(category: .detection, level: .debug, message: "[DetectionStateMachine] \(oldState) → \(newState) at \(timestamp)")
        }
    }
    
    private func findMonitoredAppUsingMic(_ activeMicUsers: Set<String>) -> ApplicationMonitor.MonitoredApp? {
        for app in appMonitor.enabledApps {
            // Check canonical processName
            logger.log(category: .detection, level: .debug, message: "[DetectionService] findMonitoredAppUsingMic: checking '\(app.processName)' → canonical: \(app.processName)")
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
    private func handleMeetingDetected(appName: String, bundleID: String, source: TriggerSource) {
        logger.log(category: .detection, level: .debug, message: "[DetectionService] handleMeetingDetected: appName=\(appName), bundleID=\(bundleID), source=\(source)")

        guard !recordingService.isRecording else { return }
        guard settings.smartDetectionEnabled else { return }

        switch settings.smartDetectionMode {
        case .auto:
            let ctx = RecordingContext(
                triggerAppBundleID: bundleID,
                triggerAppName: appName,
                triggerSource: source,
                triggerTimestamp: Date()
            )
            transition(to: .recordingLocked(ctx))

            Task {
                do {
                    try await recordingService.startRecording(trigger: .auto, appName: appName)
                    notificationManager.sendAutoStartNotification(appName: appName)
                    logger.log(category: .detection, message: "Auto-recording started for \(appName)")
                } catch {
                    logger.log(category: .detection, level: .error, message: "Auto-recording failed: \(error)")
                    detectionState = .monitoringAll(suppressedApps: [])
                }
            }

        case .remind:
            NotificationCenter.default.post(name: .showRemindOverlay, object: nil, userInfo: ["appName": appName])
            logger.log(category: .detection, message: "Reminder overlay shown for \(appName)")
        }
    }
    
    
    private func handleRecordingStopped(_ notification: Notification) {
        logger.log(category: .detection, level: .debug, message: "[DetectionService] handleRecordingStopped")

        Task { @MainActor in
            if case .recordingLocked(let ctx) = detectionState {
                let duration = Date().timeIntervalSince(ctx.triggerTimestamp)

                let reason: CooldownReason
                if let userInfo = notification.userInfo,
                   let stopReason = userInfo["reason"] as? String,
                   stopReason == "maxDuration" {
                    reason = .maxDuration
                } else if let userInfo = notification.userInfo,
                          let isManual = userInfo["isManual"] as? Bool,
                          isManual {
                    reason = .manualStop
                } else {
                    reason = .autoStop
                }

                let cooldownCtx = CooldownContext(
                    reason: reason,
                    triggerAppBundleID: ctx.triggerAppBundleID,
                    triggerAppName: ctx.triggerAppName,
                    triggerType: ctx.triggerSource,
                    recordingDuration: duration,
                    suppressedApps: [],
                    cooldownStartTime: Date(),
                    cooldownDuration: cooldownDuration
                )
                transition(to: .cooldown(cooldownCtx))
                scheduleCooldownExit(context: cooldownCtx)
            }

            if let url = notification.userInfo?["url"] as? URL {
                notificationManager.sendRecordingSavedNotification(path: url)
            } else {
                notificationManager.sendRecordingSavedNotification(path: settings.savePath)
            }
        }
    }
    
    private func handleStartRecordingRequest() {
        logger.log(category: .detection, level: .debug, message: "[DetectionService] handleStartRecordingRequest")

        let triggerSource: TriggerSource
        let triggerAppBundleID: String
        let triggerAppName: String

        if case .cooldown(let ctx) = detectionState, ctx.reason == .maxDuration {
            // Resuming after max duration reminder accepted
            triggerAppBundleID = ctx.triggerAppBundleID ?? ""
            triggerAppName = ctx.triggerAppName ?? "Unknown"
            triggerSource = ctx.triggerType ?? .manual
        } else {
            // Remind overlay accepted, or manual start via notification
            triggerAppBundleID = appMonitor.activeMeetingApps.first
                ?? findMonitoredAppUsingMic(logMonitor.activeMicUsers)?.bundleIdentifier
                ?? "unknown"
            triggerAppName = appMonitor.activeMeetingApps.first
                .flatMap { appMonitor.appStates[$0]?.config.processName }
                ?? findMonitoredAppUsingMic(logMonitor.activeMicUsers)?.processName
                ?? "Unknown"
            triggerSource = .reminderAccepted
        }

        let ctx = RecordingContext(
            triggerAppBundleID: triggerAppBundleID,
            triggerAppName: triggerAppName,
            triggerSource: triggerSource,
            triggerTimestamp: Date()
        )
        transition(to: .recordingLocked(ctx))

        Task {
            do {
                try await recordingService.startRecording(trigger: .manual, appName: nil)
                logger.log(category: .detection, message: "Recording started from notification/reminder")
            } catch {
                logger.log(category: .detection, level: .error, message: "Failed to start recording: \(error)")
                detectionState = .monitoringAll(suppressedApps: [])
            }
        }
    }

    // MARK: - Cleanup

    /// CRITICAL FIX: Cleanup method to prevent memory leaks
    /// Call this when the service needs to be reset (e.g., in tests or on app termination)
    func cleanup() {
        // Cancel all Combine subscriptions to prevent memory leaks
        cancellables.removeAll()

        // Invalidate timers and reset state machine
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        recordingEvalTimer?.invalidate()
        recordingEvalTimer = nil
        detectionState = .monitoringAll(suppressedApps: [])

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
        cooldownTimer?.invalidate()
        cooldownTimer = nil
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

    /// Process names to exclude from mic detection (self-exclusion)
    private var excludedProcessNames: Set<String> = []
    private var hasConfiguredSelfExclusion = false

    private init() {}

    deinit {
        stopMonitoring()
    }

    /// Configure monitored apps with alias-to-canonical mapping.
    /// Must be called before startMonitoring().
    func configureMonitoredApps(_ apps: [ApplicationMonitor.MonitoredApp]) {
        reconfigure(apps: apps)
    }

    /// Reconfigure monitored apps dynamically (safe to call multiple times).
    /// Updates alias mapping and prunes activeMicUsers to only include matching names.
    func reconfigure(apps: [ApplicationMonitor.MonitoredApp]) {
        var mapping: [String: String] = [:]
        var allNames = Set<String>()
        for app in apps {
            mapping[app.processName] = app.processName
            allNames.insert(app.processName)
            for alias in app.logProcessAliases {
                mapping[alias] = app.processName
                allNames.insert(alias)
            }
        }
        aliasToCanonical = mapping
        sortedProcessNames = allNames.sorted { $0.count > $1.count }

        DispatchQueue.main.async {
            let validCanonicalNames = Set(apps.map(\.processName))
            self.activeMicUsers = self.activeMicUsers.filter { name in
                let canonical = self.aliasToCanonical[name] ?? name
                return validCanonicalNames.contains(canonical)
            }
        }

        LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] Reconfigured: \(sortedProcessNames.count) names, \(mapping.count) aliases")
    }

    /// Build exclusion set so MeetingSonar's own CoreAudio events
    /// are never mistaken for a meeting app using the microphone.
    private func setupSelfExclusion() {
        guard !hasConfiguredSelfExclusion else { return }
        hasConfiguredSelfExclusion = true
        let myProcessName = ProcessInfo.processInfo.processName
        let myBundleID = Bundle.main.bundleIdentifier ?? ""
        excludedProcessNames = [myProcessName, myBundleID, "MeetingSonar"]
        LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] Self-exclusion: \(excludedProcessNames)")
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        setupSelfExclusion()
        isMonitoring = true
        
        queue.async { [weak self] in
            self?.runLogStream()
        }
    }
    
    func stopMonitoring() {
        LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] log stream stopping (pid: \(process?.processIdentifier ?? 0))")
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
            LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] log stream started (pid: \(process.processIdentifier))")
            LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] Started monitoring CoreAudio logs for mic usage")
        } catch {
            LoggerService.shared.log(category: .detection, level: .error, message: "[LogMonitor] Failed to start log stream: \(error)")
        }
    }
    
    private func scheduleRestart() {
        LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] scheduling restart in 5.0s")
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
            LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] raw log line: \(line)")
            // Filter for setPlayState first to reduce noise
            guard line.contains("setPlayState") else { continue }

            // Self-exclusion: skip log lines matching our own process
            guard !excludedProcessNames.contains(where: { line.contains($0) }) else {
                continue
            }

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
                        LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] activeMicUsers changed: \(self.activeMicUsers)")
                    }
                } else {
                    if self.activeMicUsers.contains(name) {
                        LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] Mic INACTIVE for: \(name)")
                        self.activeMicUsers.remove(name)
                        LoggerService.shared.log(category: .detection, level: .debug, message: "[LogMonitor] activeMicUsers changed: \(self.activeMicUsers)")
                    }
                }
            }
        }
    }
}
