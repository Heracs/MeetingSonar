import Foundation

/// Defines the event protocol for the Smart Awareness module.
/// Decouples detection logic from recording logic.
enum DetectionEvent {
    case appStateChanged(app: RunningApp, state: AppState)
    case micStateChanged(isUsingMic: Bool)
    // Future: case meetingDetected
}

struct RunningApp {
    let bundleId: String
    let name: String
}

enum AppState {
    case launched
    case terminated
    case active
    case hidden
}

protocol DetectionEventDelegate: AnyObject {
    func didReceiveEvent(_ event: DetectionEvent)
}
