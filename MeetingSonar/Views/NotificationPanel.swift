//
//  NotificationPanel.swift
//  MeetingSonar
//
//  Unused in v0.1-rebuild. Reference kept for project file compatibility.
//

import SwiftUI

// Placeholder
struct NotificationPanelConfig {
    // Empty
}

class NotificationPanelManager {
    static let shared = NotificationPanelManager()
    private init() {}
    
    func showPanel(config: Any, onPrimary: (() -> Void)?, onSecondary: (() -> Void)?, onDismiss: (() -> Void)? = nil) {
        // No-op
    }
}
