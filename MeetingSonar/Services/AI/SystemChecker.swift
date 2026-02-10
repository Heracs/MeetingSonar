//
//  SystemChecker.swift
//  MeetingSonar
//
//  F-5.10: Chip detection and AI capability management
//  Detects Apple Silicon vs Intel and manages AI feature availability
//

import Foundation
import AppKit

// MARK: - Chip Type

/// Detected processor architecture
enum ChipType: String {
    case appleSilicon = "arm64"
    case intel = "x86_64"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .appleSilicon: return "Apple Silicon"
        case .intel: return "Intel"
        case .unknown: return "Unknown"
        }
    }
    
    var supportsAI: Bool {
        return self == .appleSilicon
    }
}

// MARK: - AI Capability

/// Singleton managing AI feature availability
final class AICapability {
    static let shared = AICapability()
    
    /// Whether AI features are disabled (Intel Mac)
    private(set) var isDisabled: Bool = false
    
    /// Reason for disabling (if applicable)
    private(set) var disabledReason: String?
    
    /// Detected chip type
    private(set) var chipType: ChipType = .unknown
    
    /// UserDefaults key for tracking if alert has been shown
    private let kAlertShownKey = "AICapability_IntelAlertShown"
    
    private init() {}
    
    /// Check system capability and configure AI availability
    /// Call this once during app launch
    func configure() {
        chipType = SystemChecker.detectChipType()
        
        if !chipType.supportsAI {
            isDisabled = true
            disabledReason = String(localized: "system.ai.disabledReason")

            LoggerService.shared.log(
                category: .system,
                level: .warning,
                message: "[SystemChecker] Detected chip: \(chipType.rawValue) - AI features disabled"
            )
        } else {
            LoggerService.shared.log(
                category: .system,
                message: "[SystemChecker] Detected chip: \(chipType.rawValue) - AI features enabled"
            )
        }
    }
    
    /// Show one-time alert for Intel users
    /// Returns true if alert was shown
    @discardableResult
    func showIntelAlertIfNeeded() -> Bool {
        guard isDisabled else { return false }
        
        // Check if already shown
        if UserDefaults.standard.bool(forKey: kAlertShownKey) {
            return false
        }
        
        // Show alert on main thread
        DispatchQueue.main.async {
            self.showIntelAlert()
        }
        
        // Mark as shown
        UserDefaults.standard.set(true, forKey: kAlertShownKey)
        return true
    }
    
    private func showIntelAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "system.ai.alert.title")
        alert.informativeText = String(localized: "system.ai.alert.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "system.ai.alert.button"))
        alert.runModal()
    }
    
    /// Reset alert shown state (for testing)
    func resetAlertState() {
        UserDefaults.standard.removeObject(forKey: kAlertShownKey)
    }
}

// MARK: - System Checker

/// Utility for detecting system hardware information
struct SystemChecker {
    
    /// Detect the processor architecture
    static func detectChipType() -> ChipType {
        var sysinfo = utsname()
        uname(&sysinfo)
        
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        
        guard let machineStr = machine else {
            return .unknown
        }
        
        // arm64 = Apple Silicon, x86_64 = Intel
        if machineStr.contains("arm64") {
            return .appleSilicon
        } else if machineStr.contains("x86_64") {
            return .intel
        }
        
        return .unknown
    }
    
    /// Get system info string for logging
    static func getSystemInfoString() -> String {
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersionString
        let chipType = detectChipType()
        let memoryGB = Double(processInfo.physicalMemory) / 1_073_741_824.0
        
        return """
        OS: \(osVersion)
        Chip: \(chipType.displayName) (\(chipType.rawValue))
        Memory: \(String(format: "%.1f", memoryGB)) GB
        """
    }
    
    /// Check if running on Apple Silicon
    static var isAppleSilicon: Bool {
        return detectChipType() == .appleSilicon
    }
    
    /// Check minimum memory requirement for AI (8GB recommended)
    static var hasMinimumMemoryForAI: Bool {
        let memoryBytes = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Double(memoryBytes) / 1_073_741_824.0
        return memoryGB >= 8.0
    }
}
