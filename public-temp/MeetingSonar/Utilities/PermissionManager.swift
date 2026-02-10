//
//  PermissionManager.swift
//  MeetingSonar
//
//  Handles system permission checks and requests for Screen Recording and Microphone access.
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import AppKit

/// Manages system permissions required by MeetingSonar
/// 
/// Required permissions:
/// - Screen Recording: For capturing system/application audio via ScreenCaptureKit
/// - Microphone: For capturing user's voice input
final class PermissionManager {
    
    // MARK: - Singleton
    
    static let shared = PermissionManager()
    
    private init() {}
    
    // MARK: - Permission Status
    
    enum PermissionStatus {
        case authorized
        case denied
        case notDetermined
    }
    
    // MARK: - Screen Capture Permission
    
    /// Check if screen capture permission is granted
    /// - Returns: `true` if permission is granted, `false` otherwise
    func checkScreenCapturePermission() async -> Bool {
        do {
            // Attempting to get shareable content will trigger permission check
            // If permission is not granted, this will throw an error
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return !content.applications.isEmpty
        } catch {
            LoggerService.shared.log(category: .permission, level: .error, message: "Screen capture permission check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Request screen capture permission by triggering the system dialog
    /// Note: ScreenCaptureKit automatically triggers the permission dialog when first used
    func requestScreenCapturePermission() async {
        _ = await checkScreenCapturePermission()
    }
    
    // MARK: - Microphone Permission
    
    /// Get current microphone permission status
    var microphonePermissionStatus: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
    
    /// Check if microphone permission is granted
    /// - Returns: `true` if permission is granted, `false` otherwise
    func checkMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await requestMicrophonePermission()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    /// Request microphone permission
    /// - Returns: `true` if permission was granted, `false` otherwise
    func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    // MARK: - Combined Permission Check
    
    /// Check all required permissions
    /// - Returns: Tuple containing status of each permission
    func checkAllPermissions() async -> (screenCapture: Bool, microphone: Bool) {
        async let screenPermission = checkScreenCapturePermission()
        async let micPermission = checkMicrophonePermission()
        
        return await (screenPermission, micPermission)
    }
    
    // MARK: - System Settings
    
    /// Open System Settings to the appropriate privacy pane
    func openSystemSettings() {
        // Open Privacy & Security settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Open Screen Recording permission settings
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Open Microphone permission settings
    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    // MARK: - Accessibility Permission
    
    /// Check if Accessibility permission is granted (Required for window title detection in v0.3)
    /// - Returns: `true` if permission is granted, `false` otherwise
    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Request Accessibility permission by prompting system dialog
    /// - Returns: `true` if already trusted, `false` if prompt shown (async)
    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Open Accessibility permission settings
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Permission Error

/// Errors related to permission issues
enum PermissionError: LocalizedError {
    case screenCaptureNotAuthorized
    case microphoneNotAuthorized
    case accessibilityNotAuthorized
    case allPermissionsRequired
    
    var errorDescription: String? {
        switch self {
        case .screenCaptureNotAuthorized:
            return "Screen Recording permission is required to capture meeting audio. Please enable it in System Settings > Privacy & Security > Screen Recording."
        case .microphoneNotAuthorized:
            return "Microphone permission is required to record your voice. Please enable it in System Settings > Privacy & Security > Microphone."
        case .accessibilityNotAuthorized:
            return "Accessibility permission is required to detect meeting windows. Please enable it in System Settings > Privacy & Security > Accessibility."
        case .allPermissionsRequired:
            return "Multiple permissions are required. Please enable them in System Settings > Privacy & Security."
        }
    }
}


