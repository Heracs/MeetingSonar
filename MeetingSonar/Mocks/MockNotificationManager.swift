//
//  MockNotificationManager.swift
//  MeetingSonar
//
//  Mock implementation of NotificationManager for testing.
//

import Foundation

/// Mock implementation for testing notification functionality
@MainActor
final class MockNotificationManager {
    private(set) var notificationSent = false
    private(set) var lastNotificationTitle: String = ""
    private(set) var lastNotificationBody: String = ""
    private(set) var authorizationRequested = false

    func reset() {
        notificationSent = false
        lastNotificationTitle = ""
        lastNotificationBody = ""
        authorizationRequested = false
    }

    func configureForTesting() {
        reset()
    }

    /// Simulate requesting notification authorization
    func requestAuthorization() {
        authorizationRequested = true
    }

    /// Send a notification (mock)
    func sendNotification(title: String, body: String) {
        notificationSent = true
        lastNotificationTitle = title
        lastNotificationBody = body
    }

    /// Send remind notification (matching real API)
    func sendRemindNotification(appName: String) {
        sendNotification(title: "Meeting Detected", body: "Detected \(appName) meeting. Start recording?")
    }

    /// Send auto-start notification (matching real API)
    func sendAutoStartNotification(appName: String) {
        sendNotification(title: "Recording Started", body: "Auto-recording started for \(appName).")
    }

    /// Send recording saved notification (matching real API)
    func sendRecordingSavedNotification(path: URL) {
        sendNotification(title: "Recording Saved", body: "Meeting recording has been saved.")
    }

    /// Send AI processing notification (matching real API)
    func showAIProcessingNotification() {
        sendNotification(title: String(localized: "notification.ai.processing"), body: String(localized: "notification.ai.generatingSummary"))
    }

    /// Send AI complete notification (matching real API)
    func showAICompleteNotification(summaryURL: URL) {
        sendNotification(title: String(localized: "notification.ai.summaryReady"), body: String(format: String(localized: "notification.ai.clickToView.%@"), summaryURL.lastPathComponent))
    }

    /// Send AI error notification (matching real API)
    func showAIErrorNotification(error: String) {
        sendNotification(title: String(localized: "notification.ai.failed"), body: String(format: String(localized: "notification.ai.errorMessage.%@"), error))
    }
}
