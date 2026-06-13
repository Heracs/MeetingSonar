import Foundation

struct SignalInterpreter {
    private var firstCandidateSeenAt: [String: Date] = [:]
    private var firstEndCandidateSeenAt: [String: Date] = [:]
    private let recentProcessGuard: TimeInterval = 3

    mutating func startEvent(
        for snapshot: AppSignalSnapshot,
        policy: DetectionPolicy
    ) -> DetectionBusinessEvent {
        if hasRecentProcessEvent(snapshot) {
            firstCandidateSeenAt[snapshot.app.bundleIdentifier] = nil
            return .meetingStartCandidate(app: snapshot.app, reason: "recent_process_event_guard")
        }

        switch policy.evidence(for: snapshot) {
        case .meetingConfirmed(let participantCount, let confidence):
            firstCandidateSeenAt[snapshot.app.bundleIdentifier] = nil
            return .meetingStartConfirmed(
                app: snapshot.app,
                source: source(for: snapshot, policy: policy),
                participantCount: participantCount,
                confidence: confidence
            )

        case .candidate(let reason):
            if snapshot.micState == .active {
                let firstSeen = firstCandidateSeenAt[snapshot.app.bundleIdentifier] ?? snapshot.timestamp
                firstCandidateSeenAt[snapshot.app.bundleIdentifier] = firstSeen
                if snapshot.timestamp.timeIntervalSince(firstSeen) >= policy.startDebounce {
                    firstCandidateSeenAt[snapshot.app.bundleIdentifier] = nil
                    return .meetingStartConfirmed(
                        app: snapshot.app,
                        source: .micUsage,
                        participantCount: snapshot.participantCount?.count,
                        confidence: snapshot.participantCount?.confidence
                    )
                }
            }
            return .meetingStartCandidate(app: snapshot.app, reason: reason)

        case .notMeeting, .ended:
            firstCandidateSeenAt[snapshot.app.bundleIdentifier] = nil
            return .meetingStartCandidate(app: snapshot.app, reason: "not_confirmed")

        case .ending:
            firstCandidateSeenAt[snapshot.app.bundleIdentifier] = nil
            return .meetingStartCandidate(app: snapshot.app, reason: "ending")

        case .stillActive:
            return .meetingStillActive(app: snapshot.app)

        case .unknown(let reason):
            return .meetingStartCandidate(app: snapshot.app, reason: reason)
        }
    }

    mutating func recordingEvent(
        for snapshot: AppSignalSnapshot,
        policy: DetectionPolicy,
        context: RecordingContext
    ) -> DetectionBusinessEvent {
        guard snapshot.app.bundleIdentifier == context.triggerAppBundleID else {
            return .meetingStillActive(app: snapshot.app)
        }

        if policy.windowReliability == .reliableMeetingUI {
            if snapshot.windowState == .meetingUI {
                firstEndCandidateSeenAt[snapshot.app.bundleIdentifier] = nil
                return .meetingStillActive(app: snapshot.app)
            }
            if snapshot.windowState == .none || snapshot.windowState == .mainWindow || snapshot.windowState == .preJoin {
                return endEventIfDebounced(for: snapshot, policy: policy)
            }
            return .meetingStillActive(app: snapshot.app)
        }

        if (policy.windowReliability == .weakTitleOnly ||
            policy.windowReliability == .meetingUIRequiresActiveMicSession) &&
            snapshot.windowState == .meetingUI {
            firstEndCandidateSeenAt[snapshot.app.bundleIdentifier] = nil
            return .meetingStillActive(app: snapshot.app)
        }

        if snapshot.micState == .inactive {
            return endEventIfDebounced(for: snapshot, policy: policy)
        }
        firstEndCandidateSeenAt[snapshot.app.bundleIdentifier] = nil
        return .meetingStillActive(app: snapshot.app)
    }

    func residualEvent(
        for snapshot: AppSignalSnapshot,
        cooldownStartedAt: Date,
        policy: DetectionPolicy
    ) -> DetectionBusinessEvent {
        let elapsed = snapshot.timestamp.timeIntervalSince(cooldownStartedAt)
        let hasResidual = snapshot.windowState == .meetingUI ||
            snapshot.micState == .active ||
            snapshot.micState != .inactive
        if hasResidual && elapsed < policy.residualCooldownMaxWait {
            return .residualSignalsStillPresent(bundleID: snapshot.app.bundleIdentifier)
        }
        if hasResidual {
            return .residualSignalsStillPresent(bundleID: snapshot.app.bundleIdentifier)
        }
        return .residualSignalsCleared(bundleID: snapshot.app.bundleIdentifier)
    }

    private func source(for snapshot: AppSignalSnapshot, policy: DetectionPolicy) -> TriggerSource {
        if policy.windowReliability == .meetingUIRequiresActiveMicSession &&
            snapshot.windowState == .meetingUI &&
            snapshot.micState == .active {
            return .combined
        }
        if policy.windowReliability == .reliableMeetingUI && snapshot.windowState == .meetingUI {
            return .windowTitle
        }
        if snapshot.windowState == .meetingUI && snapshot.micState == .active {
            return .combined
        }
        return .micUsage
    }

    private mutating func endEventIfDebounced(
        for snapshot: AppSignalSnapshot,
        policy: DetectionPolicy
    ) -> DetectionBusinessEvent {
        let bundleID = snapshot.app.bundleIdentifier
        let firstSeen = firstEndCandidateSeenAt[bundleID] ?? snapshot.timestamp
        firstEndCandidateSeenAt[bundleID] = firstSeen

        if snapshot.timestamp.timeIntervalSince(firstSeen) >= policy.stopDebounce {
            firstEndCandidateSeenAt[bundleID] = nil
            return .meetingEndConfirmed(app: snapshot.app)
        }

        return .meetingStillActive(app: snapshot.app)
    }

    private func hasRecentProcessEvent(_ snapshot: AppSignalSnapshot) -> Bool {
        guard let event = snapshot.lastProcessEvent else {
            return false
        }

        let eventDate: Date
        switch event {
        case .launched(let date), .terminated(let date):
            eventDate = date
        }

        let elapsed = snapshot.timestamp.timeIntervalSince(eventDate)
        return elapsed >= 0 && elapsed < recentProcessGuard
    }
}
