import UserNotifications
import AppKit

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    private let center = UNUserNotificationCenter.current()
    
    // Notification Categories
    enum Category: String {
        case meetingDetected = "MEETING_DETECTED"
    }
    
    // Notification Actions
    enum Action: String {
        case startRecording = "START_RECORDING"
    }
    
    override init() {
        super.init()
        center.delegate = self
        setupCategories()
    }
    
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                LoggerService.shared.log(category: .general, level: .error, message: "Notification auth error: \(error)")
            } else {
                LoggerService.shared.log(category: .general, message: "Notification auth granted: \(granted)")
            }
        }
    }
    
    private func setupCategories() {
        let startAction = UNNotificationAction(
            identifier: Action.startRecording.rawValue,
            title: "Start Recording",
            options: [.foreground]
        )
        
        // Category for "Remind Me" mode
        let meetingCategory = UNNotificationCategory(
            identifier: Category.meetingDetected.rawValue,
            actions: [startAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        center.setNotificationCategories([meetingCategory])
    }
    
    // MARK: - Sending Notifications
    
    /// Send a notification asking user to start recording
    func sendRemindNotification(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Meeting Detected"
        content.body = "Detected \(appName) meeting. Start recording?"
        content.sound = .default
        content.categoryIdentifier = Category.meetingDetected.rawValue
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate delivery
        )
        
        center.add(request) { error in
            if let error = error {
                LoggerService.shared.log(category: .general, level: .error, message: "Failed to send notification: \(error)")
            }
        }
    }
    
    /// Send a passive notification that recording has auto-started
    func sendAutoStartNotification(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Recording Started"
        content.body = "Auto-recording started for \(appName)."
        content.body = "Auto-recording started for \(appName)."
        content.sound = .default
        
        if #available(macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        
        // Use fixed identifier to update existing notification instead of stacking
        let request = UNNotificationRequest(
            identifier: "meeting_sonar_recording_active",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        
        center.add(request)
    }
    
    /// Send notification that recording was saved
    func sendRecordingSavedNotification(path: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Recording Saved"
        content.body = "Meeting recording has been saved."
        content.sound = .default
        
        // Could add "Show in Finder" action in future
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        center.add(request)
    }
    
    // MARK: - AI Notifications (v0.5.0)
    
    /// Send notification that AI processing has started
    func showAIProcessingNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.ai.processing")
        content.body = String(localized: "notification.ai.generatingSummary")
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "meeting_sonar_ai_processing",
            content: content,
            trigger: nil
        )
        
        center.add(request)
    }
    
    /// Send notification that AI processing is complete
    func showAICompleteNotification(summaryURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.ai.summaryReady")
        content.body = String(format: String(localized: "notification.ai.clickToView.%@"), summaryURL.lastPathComponent)
        content.sound = .default
        
        if #available(macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        
        let request = UNNotificationRequest(
            identifier: "meeting_sonar_ai_complete",
            content: content,
            trigger: nil
        )
        
        center.add(request)
    }
    
    /// Send notification that AI processing failed
    func showAIErrorNotification(error: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.ai.failed")
        content.body = String(format: String(localized: "notification.ai.errorMessage.%@"), error)
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "meeting_sonar_ai_error",
            content: content,
            trigger: nil
        )
        
        center.add(request)
    }
    
    // MARK: - Delegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        if response.actionIdentifier == Action.startRecording.rawValue {
            LoggerService.shared.log(category: .general, message: "User clicked Start Recording notification action")
            
            // Notify DetectionService or Start Recording directly
            // Since NotificationManager is low-level, we might use a callback or direct call if logic is simple.
            // Better to post a specific notification that DetectionService listens to, 
            // OR expose a completion handler.
            // For simplicity in MVP, we can post a NotificationCenter event.
            NotificationCenter.default.post(name: .startRecordingRequested, object: nil)
        }
        
        completionHandler()
    }
    
    // Allow notifications to show even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

extension Notification.Name {
    static let startRecordingRequested = Notification.Name("StartRecordingRequested")
}
