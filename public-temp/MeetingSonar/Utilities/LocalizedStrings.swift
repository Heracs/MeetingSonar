//
//  LocalizedStrings.swift
//  MeetingSonar
//
//  Provides localized string access for AppKit components (NSMenu, NSAlert).
//  v0.2: F-6.2 UI Text Replacement
//

import Foundation

/// Helper enum for accessing localized strings programmatically.
/// Used primarily for AppKit components that don't support SwiftUI's Text() localization.
enum L10n {
    
    // MARK: - Menu Bar
    
    enum Menu {
        enum Status {
            static var ready: String {
                NSLocalizedString("menu.status.ready", comment: "Menu bar status when idle")
            }
            
            static func recording(_ duration: String) -> String {
                String(format: NSLocalizedString("menu.status.recording", comment: "Menu bar status when recording"), duration)
            }
        }
        
        enum Action {
            static var manageRecordings: String {
                NSLocalizedString("menu.action.manageRecordings", comment: "Manage recordings menu item")
            }

            static var startRecording: String {
                NSLocalizedString("menu.action.startRecording", comment: "Start recording menu item")
            }
            
            static var stopRecording: String {
                NSLocalizedString("menu.action.stopRecording", comment: "Stop recording menu item")
            }
            
            static var openFolder: String {
                NSLocalizedString("menu.action.openFolder", comment: "Open output folder menu item")
            }
            
            static var openLogs: String {
                NSLocalizedString("menu.action.openLogs", comment: "Open logs menu item")
            }
            
            static var preferences: String {
                NSLocalizedString("menu.action.preferences", comment: "Preferences menu item")
            }
            
            static var about: String {
                NSLocalizedString("menu.action.about", comment: "About menu item")
            }
            
            static var quit: String {
                NSLocalizedString("menu.action.quit", comment: "Quit menu item")
            }
        }
    }
    
    // MARK: - Settings Tabs
    
    enum Settings {
        enum Tab {
            static var general: String {
                NSLocalizedString("settings.tab.general", comment: "General settings tab")
            }
            
            static var audio: String {
                NSLocalizedString("settings.tab.audio", comment: "Audio settings tab")
            }
            
            static var permissions: String {
                NSLocalizedString("settings.tab.permissions", comment: "Permissions settings tab")
            }
            
            static var about: String {
                NSLocalizedString("settings.tab.about", comment: "About settings tab")
            }
        }
        
        enum General {
            static var saveLocation: String {
                NSLocalizedString("settings.general.saveLocation", comment: "Save location label")
            }
            
            static var choose: String {
                NSLocalizedString("settings.general.choose", comment: "Choose button")
            }
            
            static var launchAtLogin: String {
                NSLocalizedString("settings.general.launchAtLogin", comment: "Launch at login toggle")
            }
            
            static var launchAtLoginDesc: String {
                NSLocalizedString("settings.general.launchAtLoginDesc", comment: "Launch at login description")
            }
        }
        
        enum Audio {
            static var format: String {
                NSLocalizedString("settings.audio.format", comment: "Format section header")
            }
            
            static var formatLabel: String {
                NSLocalizedString("settings.audio.formatLabel", comment: "Format picker label")
            }
            
            static var qualityLabel: String {
                NSLocalizedString("settings.audio.qualityLabel", comment: "Quality picker label")
            }
            
            static var sources: String {
                NSLocalizedString("settings.audio.sources", comment: "Sources section header")
            }
            
            static var systemAudio: String {
                NSLocalizedString("settings.audio.systemAudio", comment: "System audio toggle")
            }
            
            static var microphone: String {
                NSLocalizedString("settings.audio.microphone", comment: "Microphone toggle")
            }
            
            static var volumes: String {
                NSLocalizedString("settings.audio.volumes", comment: "Volumes section header")
            }
            
            static var systemLabel: String {
                NSLocalizedString("settings.audio.systemLabel", comment: "System volume label")
            }
            
            static var micLabel: String {
                NSLocalizedString("settings.audio.micLabel", comment: "Mic volume label")
            }
        }
        
        enum Permissions {
            static var screenRecording: String {
                NSLocalizedString("settings.permissions.screenRecording", comment: "Screen recording permission")
            }
            
            static var microphone: String {
                NSLocalizedString("settings.permissions.microphone", comment: "Microphone permission")
            }
            
            static var grantAccess: String {
                NSLocalizedString("settings.permissions.grantAccess", comment: "Grant access button")
            }
            
            static var description: String {
                NSLocalizedString("settings.permissions.description", comment: "Permissions description")
            }
            
            static var refreshStatus: String {
                NSLocalizedString("settings.permissions.refreshStatus", comment: "Refresh status button")
            }
        }
    }
    
    // MARK: - About
    
    enum About {
        static var appName: String {
            NSLocalizedString("about.appName", comment: "App name")
        }
        
        static func version(_ version: String, build: String) -> String {
            String(format: NSLocalizedString("about.version", comment: "Version string"), version, build)
        }
        
        static var tagline: String {
            NSLocalizedString("about.tagline", comment: "App tagline")
        }
        
        static var github: String {
            NSLocalizedString("about.github", comment: "GitHub button")
        }
    }
    
    // MARK: - Alerts
    
    enum Alert {
        enum PermissionsRequired {
            static var title: String {
                NSLocalizedString("alert.permissionsRequired.title", comment: "Permissions required alert title")
            }
            
            static var message: String {
                NSLocalizedString("alert.permissionsRequired.message", comment: "Permissions required alert message")
            }
        }
        
        enum CannotSave {
            static var title: String {
                NSLocalizedString("alert.cannotSave.title", comment: "Cannot save alert title")
            }
            
            static func message(_ path: String) -> String {
                String(format: NSLocalizedString("alert.cannotSave.message", comment: "Cannot save alert message"), path)
            }
        }
        
        enum RecordingError {
            static var title: String {
                NSLocalizedString("alert.recordingError.title", comment: "Recording error alert title")
            }
        }
        
        enum Button {
            static var openSettings: String {
                NSLocalizedString("alert.button.openSettings", comment: "Open settings button")
            }
            
            static var later: String {
                NSLocalizedString("alert.button.later", comment: "Later button")
            }
            
            static var openPreferences: String {
                NSLocalizedString("alert.button.openPreferences", comment: "Open preferences button")
            }
            
            static var cancel: String {
                NSLocalizedString("alert.button.cancel", comment: "Cancel button")
            }
        }
    }
    
    // MARK: - Windows & Panels
    
    enum Window {
        static var preferencesTitle: String {
            NSLocalizedString("window.preferences.title", comment: "Preferences window title")
        }
    }
    
    enum Panel {
        static var selectPathMessage: String {
            NSLocalizedString("panel.selectPath.message", comment: "Select path panel message")
        }
    }
}
