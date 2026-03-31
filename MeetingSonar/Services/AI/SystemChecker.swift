//
//  SystemChecker.swift
//  MeetingSonar
//
//  System information utility.
//  Cloud-only architecture (v0.10.0+) — no Intel restriction needed.
//

import Foundation

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
}

// MARK: - AI Capability

/// Singleton managing AI feature availability.
/// In cloud-only architecture, AI is always available regardless of chip type.
final class AICapability {
    static let shared = AICapability()

    /// AI is always enabled in cloud-only architecture
    var isDisabled: Bool { false }

    /// Detected chip type
    private(set) var chipType: ChipType = .unknown

    private init() {}

    /// Detect system info and log it. No longer disables AI on Intel.
    func configure() {
        chipType = SystemChecker.detectChipType()
        LoggerService.shared.log(
            category: .system,
            message: "[SystemChecker] Detected chip: \(chipType.displayName) — cloud AI enabled"
        )
    }

    /// No-op in cloud-only architecture. Retained for call-site compatibility.
    @discardableResult
    func showIntelAlertIfNeeded() -> Bool { false }
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

        guard let machineStr = machine else { return .unknown }

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
}
