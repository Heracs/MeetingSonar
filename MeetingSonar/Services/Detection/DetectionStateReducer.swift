import Foundation

struct DetectionReducerEnvironment: Equatable {
    let mode: SettingsManager.SmartDetectionMode
    let smartDetectionEnabled: Bool
    let isRecording: Bool
    let now: Date
    let cooldownDuration: TimeInterval

    init(
        mode: SettingsManager.SmartDetectionMode,
        smartDetectionEnabled: Bool,
        isRecording: Bool,
        now: Date,
        cooldownDuration: TimeInterval = 5
    ) {
        self.mode = mode
        self.smartDetectionEnabled = smartDetectionEnabled
        self.isRecording = isRecording
        self.now = now
        self.cooldownDuration = cooldownDuration
    }
}

enum RecordingStopReason: String, Codable, Equatable {
    case autoStop
    case manualStop
    case maxDuration
    case appCrashed
    case appDisabled
}

enum DetectionReducerAction: Equatable {
    case startRecording(RecordingContext)
    case stopRecording(RecordingStopReason)
    case showReminder(appName: String, mode: String)
    case scheduleCooldown(CooldownContext)
    case logCandidate(bundleID: String, reason: String)
    case none
}

struct DetectionReducerResult: Equatable {
    let state: DetectionState
    let actions: [DetectionReducerAction]
}

struct DetectionStateReducer {
    static func suppressedApps(
        for reason: CooldownReason,
        triggerAppBundleID: String?
    ) -> Set<String> {
        guard let triggerAppBundleID else { return [] }

        switch reason {
        case .manualStop, .appCrashed, .appDisabled:
            return [triggerAppBundleID]
        case .autoStop, .maxDuration:
            return []
        }
    }

    func reduce(
        state: DetectionState,
        event: DetectionBusinessEvent,
        environment: DetectionReducerEnvironment
    ) -> DetectionReducerResult {
        guard environment.smartDetectionEnabled else {
            return reduceDisabled(state: state, environment: environment)
        }

        switch (state, event) {
        case (.monitoringAll(let suppressedApps), .meetingStartConfirmed(let app, let source, let count, let confidence)):
            guard !suppressedApps.contains(app.bundleIdentifier), !environment.isRecording else {
                return DetectionReducerResult(state: state, actions: [.none])
            }
            if environment.mode == .remind {
                return DetectionReducerResult(
                    state: state,
                    actions: [.showReminder(appName: app.processName, mode: "remind")]
                )
            }
            let context = RecordingContext(
                triggerAppBundleID: app.bundleIdentifier,
                triggerAppName: app.processName,
                triggerSource: source,
                triggerTimestamp: environment.now,
                participantCount: count,
                participantCountConfidence: confidence
            )
            return DetectionReducerResult(
                state: .recordingLocked(context),
                actions: [.startRecording(context)]
            )

        case (.monitoringAll, .meetingStartCandidate(let app, let reason)):
            return DetectionReducerResult(
                state: state,
                actions: [.logCandidate(bundleID: app.bundleIdentifier, reason: reason)]
            )

        case (.monitoringAll(let suppressedApps), .suppressionCleared(let bundleID)):
            var next = suppressedApps
            next.remove(bundleID)
            return DetectionReducerResult(state: .monitoringAll(suppressedApps: next), actions: [.none])

        case (.recordingLocked(let context), .meetingStillActive(let app)):
            guard app.bundleIdentifier == context.triggerAppBundleID else {
                return DetectionReducerResult(state: state, actions: [.none])
            }
            return DetectionReducerResult(state: state, actions: [.none])

        case (.recordingLocked(let context), .meetingEndConfirmed(let app)):
            guard app.bundleIdentifier == context.triggerAppBundleID else {
                return DetectionReducerResult(state: state, actions: [.none])
            }
            let cooldown = cooldownContext(
                from: context,
                reason: .autoStop,
                environment: environment,
                suppressedApps: []
            )
            return DetectionReducerResult(
                state: .cooldown(cooldown),
                actions: [.stopRecording(.autoStop), .scheduleCooldown(cooldown)]
            )

        case (.recordingLocked(let context), .manualStopRequested):
            let cooldown = cooldownContext(
                from: context,
                reason: .manualStop,
                environment: environment,
                suppressedApps: Self.suppressedApps(
                    for: .manualStop,
                    triggerAppBundleID: context.triggerAppBundleID
                )
            )
            return DetectionReducerResult(
                state: .cooldown(cooldown),
                actions: [.stopRecording(.manualStop), .scheduleCooldown(cooldown)]
            )

        case (.recordingLocked(let context), .maxDurationReached):
            let cooldown = cooldownContext(
                from: context,
                reason: .maxDuration,
                environment: environment,
                suppressedApps: []
            )
            return DetectionReducerResult(
                state: .cooldown(cooldown),
                actions: [.stopRecording(.maxDuration), .scheduleCooldown(cooldown)]
            )

        case (.recordingLocked(let context), .triggerAppTerminated(let bundleID)):
            guard bundleID == context.triggerAppBundleID else {
                return DetectionReducerResult(state: state, actions: [.none])
            }
            let cooldown = cooldownContext(
                from: context,
                reason: .appCrashed,
                environment: environment,
                suppressedApps: Self.suppressedApps(
                    for: .appCrashed,
                    triggerAppBundleID: bundleID
                )
            )
            return DetectionReducerResult(
                state: .cooldown(cooldown),
                actions: [.stopRecording(.appCrashed), .scheduleCooldown(cooldown)]
            )

        case (.recordingLocked(let context), .triggerAppDisabled(let bundleID)):
            guard bundleID == context.triggerAppBundleID else {
                return DetectionReducerResult(state: state, actions: [.none])
            }
            let cooldown = cooldownContext(
                from: context,
                reason: .appDisabled,
                environment: environment,
                suppressedApps: Self.suppressedApps(
                    for: .appDisabled,
                    triggerAppBundleID: bundleID
                )
            )
            return DetectionReducerResult(
                state: .cooldown(cooldown),
                actions: [.stopRecording(.appDisabled), .scheduleCooldown(cooldown)]
            )

        case (.cooldown(let cooldown), .residualSignalsCleared):
            return DetectionReducerResult(
                state: .monitoringAll(suppressedApps: cooldown.suppressedApps),
                actions: [.none]
            )

        case (.cooldown(let cooldown), .residualSignalsStillPresent(let bundleID)):
            let elapsed = environment.now.timeIntervalSince(cooldown.cooldownStartTime)
            if elapsed >= max(cooldown.cooldownDuration, 20) {
                var suppressed = cooldown.suppressedApps
                suppressed.insert(bundleID)
                return DetectionReducerResult(
                    state: .monitoringAll(suppressedApps: suppressed),
                    actions: [.none]
                )
            }
            return DetectionReducerResult(state: state, actions: [.scheduleCooldown(cooldown)])

        default:
            return DetectionReducerResult(state: state, actions: [.none])
        }
    }

    private func reduceDisabled(
        state: DetectionState,
        environment: DetectionReducerEnvironment
    ) -> DetectionReducerResult {
        if case .recordingLocked(let context) = state {
            let cooldown = cooldownContext(
                from: context,
                reason: .appDisabled,
                environment: environment,
                suppressedApps: Self.suppressedApps(
                    for: .appDisabled,
                    triggerAppBundleID: context.triggerAppBundleID
                )
            )
            return DetectionReducerResult(
                state: .cooldown(cooldown),
                actions: [.stopRecording(.appDisabled), .scheduleCooldown(cooldown)]
            )
        }
        return DetectionReducerResult(state: state, actions: [.none])
    }

    private func cooldownContext(
        from context: RecordingContext,
        reason: CooldownReason,
        environment: DetectionReducerEnvironment,
        suppressedApps: Set<String>
    ) -> CooldownContext {
        CooldownContext(
            reason: reason,
            triggerAppBundleID: context.triggerAppBundleID,
            triggerAppName: context.triggerAppName,
            triggerType: context.triggerSource,
            recordingDuration: environment.now.timeIntervalSince(context.triggerTimestamp),
            suppressedApps: suppressedApps,
            cooldownStartTime: environment.now,
            cooldownDuration: environment.cooldownDuration
        )
    }
}
