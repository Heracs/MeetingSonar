import Foundation

enum WindowReliability: Equatable {
    case reliableMeetingUI
    case meetingUIRequiresActiveMicSession
    case weakTitleOnly
    case unavailable
}

enum MicReliability: Equatable {
    case sessionOnly
    case meetingLikely
    case weakTransient
}

enum ParticipantCountUsage: Equatable {
    case unavailable
    case logOnly
    case futureSingleParticipantSetting
}

struct DetectionPolicy: Equatable {
    let bundleIdentifier: String
    let windowReliability: WindowReliability
    let micReliability: MicReliability
    let supportsParticipantCount: Bool
    let participantCountUsage: ParticipantCountUsage
    let startDebounce: TimeInterval
    let stopDebounce: TimeInterval
    let residualCooldownMaxWait: TimeInterval

    static func defaultPolicy(for app: ApplicationMonitor.MonitoredApp) -> DetectionPolicy {
        switch app.bundleIdentifier {
        case "us.zoom.xos":
            return DetectionPolicy(
                bundleIdentifier: app.bundleIdentifier,
                windowReliability: .reliableMeetingUI,
                micReliability: .weakTransient,
                supportsParticipantCount: true,
                participantCountUsage: .logOnly,
                startDebounce: 2,
                stopDebounce: 4,
                residualCooldownMaxWait: 20
            )
        case "com.tencent.meeting":
            return DetectionPolicy(
                bundleIdentifier: app.bundleIdentifier,
                windowReliability: .reliableMeetingUI,
                micReliability: .sessionOnly,
                supportsParticipantCount: false,
                participantCountUsage: .unavailable,
                startDebounce: 2,
                stopDebounce: 4,
                residualCooldownMaxWait: 20
            )
        case "com.electron.lark.iron":
            return DetectionPolicy(
                bundleIdentifier: app.bundleIdentifier,
                windowReliability: .meetingUIRequiresActiveMicSession,
                micReliability: .sessionOnly,
                supportsParticipantCount: false,
                participantCountUsage: .unavailable,
                startDebounce: 2,
                stopDebounce: 4,
                residualCooldownMaxWait: 20
            )
        case "com.microsoft.teams2":
            return DetectionPolicy(
                bundleIdentifier: app.bundleIdentifier,
                windowReliability: .weakTitleOnly,
                micReliability: .sessionOnly,
                supportsParticipantCount: false,
                participantCountUsage: .unavailable,
                startDebounce: 5,
                stopDebounce: 8,
                residualCooldownMaxWait: 20
            )
        default:
            return DetectionPolicy(
                bundleIdentifier: app.bundleIdentifier,
                windowReliability: .unavailable,
                micReliability: .sessionOnly,
                supportsParticipantCount: false,
                participantCountUsage: .unavailable,
                startDebounce: 5,
                stopDebounce: 10,
                residualCooldownMaxWait: 20
            )
        }
    }

    func evidence(for snapshot: AppSignalSnapshot) -> MeetingEvidence {
        guard snapshot.isRunning else {
            return .notMeeting
        }

        switch windowReliability {
        case .reliableMeetingUI:
            switch snapshot.windowState {
            case .meetingUI:
                return .meetingConfirmed(
                    participantCount: snapshot.participantCount?.count,
                    confidence: snapshot.participantCount?.confidence
                )
            case .leavingConfirmation:
                return .ending
            case .mainWindow, .preJoin, .none:
                return .notMeeting
            case .unknownMatched(let value):
                return .candidate(reason: "unknown_window_match:\(value)")
            }

        case .meetingUIRequiresActiveMicSession:
            switch snapshot.windowState {
            case .meetingUI:
                if snapshot.micState == .active {
                    return .meetingConfirmed(
                        participantCount: snapshot.participantCount?.count,
                        confidence: snapshot.participantCount?.confidence
                    )
                }
                return .candidate(reason: "meeting_window_requires_active_audio_session")
            case .leavingConfirmation:
                return .ending
            case .mainWindow, .preJoin, .none:
                return .notMeeting
            case .unknownMatched(let value):
                return .candidate(reason: "unknown_window_match:\(value)")
            }

        case .weakTitleOnly:
            if snapshot.windowState == .meetingUI && snapshot.micState == .active {
                return .meetingConfirmed(
                    participantCount: snapshot.participantCount?.count,
                    confidence: snapshot.participantCount?.confidence
                )
            }
            if snapshot.windowState == .meetingUI || snapshot.micState == .active {
                return .candidate(reason: "weak_window_or_mic_requires_debounce")
            }
            return .notMeeting

        case .unavailable:
            if snapshot.micState == .active {
                return .candidate(reason: "mic_active_requires_debounce")
            }
            return .notMeeting
        }
    }
}
