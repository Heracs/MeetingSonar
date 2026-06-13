import Foundation

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
    let participantCount: Int?
    let participantCountConfidence: SignalConfidence?

    init(
        triggerAppBundleID: String,
        triggerAppName: String,
        triggerSource: TriggerSource,
        triggerTimestamp: Date,
        participantCount: Int? = nil,
        participantCountConfidence: SignalConfidence? = nil
    ) {
        self.triggerAppBundleID = triggerAppBundleID
        self.triggerAppName = triggerAppName
        self.triggerSource = triggerSource
        self.triggerTimestamp = triggerTimestamp
        self.participantCount = participantCount
        self.participantCountConfidence = participantCountConfidence
    }
}

enum TriggerSource: String, Equatable {
    case windowTitle
    case micUsage
    case combined
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
