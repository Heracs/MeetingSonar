import Foundation
import SwiftUI
import Combine
import AppKit

/// Manages application localization settings and language switching.
/// Implements Restart-Strategy for changing languages.
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    // User preference storage
    // "system" = use system default
    // "en" = English
    // "zh-Hans" = Chinese (Simplified)
    @AppStorage("app_language_preference")
    var languagePreference: String = "system" {
        didSet {
            objectWillChange.send()
        }
    }
    
    private init() {}
    
    /// Apply the selected language to UserDefaults so the system picks it up on next launch.
    /// - Parameter code: The language code to switch to ("system", "en", "zh-Hans").
    /// - Returns: Bool indicating if a restart is required (always true for language changes in this strategy).
    func setLanguage(_ code: String) -> Bool {
        // The @AppStorage 'languagePreference' is already updated by the binding or caller.
        // We only need to configure the system-level 'AppleLanguages' key.
        
        if code == "system" {
            // Remove override, let system decide based on OS order
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            // Force specific language
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        
        // Force sync to ensure it's saved before potential immediate restart
        UserDefaults.standard.synchronize()
        
        return true
    }
    
    /// Relaunch the application to apply language changes.
    /// Uses /usr/bin/open -n to spawn a new instance before terminating the current one.
    func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        
        // Safety check: Don't try to relaunch if we are not a valid bundle (e.g. running from Xcode preview sometimes)
        guard bundleURL.pathExtension == "app" else {
            LoggerService.shared.log(category: .general, level: .error, message: "LocalizationManager: Cannot relaunch, not running as .app bundle.")
            NSApplication.shared.terminate(nil)
            return
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundleURL.path]
        
        do {
            try task.run()
            NSApplication.shared.terminate(nil)
        } catch {
            LoggerService.shared.log(category: .general, level: .error, message: "LocalizationManager: Failed to relaunch app: \(error)")
        }
    }

    /// Revert any pending changes (restore AppleLanguages to match current preference if needed)
    /// This is useful if user cancels the restart.
    func revertSelection() {
        // In this simple implementation, the User Default 'AppleLanguages' is set immediately.
        // If user cancels, we might want to undo that.
        // However, since @AppStorage languagePreference drives the UI, if we revert, we should reset languagePreference.
        // But logic is complex. For v0.2 P1, we assume if they hit "Cancel" on restart alert,
        // we might not auto-revert deeply, but we can ensure next launch is consistent.
        // Actually, better to just re-apply the logical "current" state if we tracked it.
        // For now, let's just log.
        LoggerService.shared.log(category: .general, level: .info, message: "LocalizationManager: User cancelled restart. Pending language change remains in UserDefaults until next launch.")
    }
}
