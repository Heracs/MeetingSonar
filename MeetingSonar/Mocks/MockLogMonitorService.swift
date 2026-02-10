//
//  MockLogMonitorService.swift
//  MeetingSonar
//
//  Mock implementation of LogMonitorService for testing.
//

import Foundation
import Combine

/// Mock log monitor service for unit testing
///
/// ## Usage
/// ```swift
/// let mockLogMonitor = MockLogMonitorService()
/// mockLogMonitor.simulateMicActivation(processName: "TencentMeeting")
/// XCTAssertTrue(mockLogMonitor.activeMicUsers.contains("TencentMeeting"))
/// ```
@MainActor
final class MockLogMonitorService: ObservableObject {

    // MARK: - Properties

    @Published private(set) var activeMicUsers: Set<String> = []

    /// Processes we care about (set by DetectionService)
    var monitoredProcessNames: Set<String> = []

    /// Whether monitoring is active
    private(set) var isMonitoring: Bool = false

    /// Number of times startMonitoring was called
    private(set) var startMonitoringCallCount: Int = 0

    /// Number of times stopMonitoring was called
    private(set) var stopMonitoringCallCount: Int = 0

    // MARK: - Monitoring Control

    func startMonitoring() {
        startMonitoringCallCount += 1
        isMonitoring = true
    }

    func stopMonitoring() {
        stopMonitoringCallCount += 1
        isMonitoring = false
    }

    // MARK: - Test Helpers

    /// Configure for testing (clears all state)
    func configureForTesting() {
        reset()
    }

    /// Reset all tracking state
    func reset() {
        activeMicUsers = []
        monitoredProcessNames = []
        isMonitoring = false
        startMonitoringCallCount = 0
        stopMonitoringCallCount = 0
    }

    /// Simulate microphone activation for a process
    func simulateMicActivation(processName: String) {
        activeMicUsers.insert(processName)
    }

    /// Simulate microphone deactivation for a process
    func simulateMicDeactivation(processName: String) {
        activeMicUsers.remove(processName)
    }

    /// Simulate a specific log line for testing pattern matching
    ///
    /// - Parameters:
    ///   - line: The log line to process
    ///   - processName: The process name to associate with the log
    func simulateLogLine(_ line: String, for processName: String) {
        // Process the line based on known patterns

        // Pattern 1: IOState: [Input, Output]
        if line.contains("IOState: [") {
            if let range = line.range(of: "IOState: [") {
                let afterStart = line[range.upperBound...]
                let parts = afterStart.components(separatedBy: ",")
                if parts.count >= 1,
                   let inputStr = parts.first?.trimmingCharacters(in: .whitespaces),
                   let inputLevel = Int(inputStr) {
                    let isActive = inputLevel > 0
                    if isActive {
                        activeMicUsers.insert(processName)
                    } else {
                        activeMicUsers.remove(processName)
                    }
                }
            }
        }
        // Pattern 2: Explicit "Started Input" - Exclude WeChat's "Input/Output" combined format
        else if line.contains("setPlayState Started") && line.contains("Input") && !line.contains("Input/Output") {
            activeMicUsers.insert(processName)
        }
        // Pattern 3: Explicit "Stopped Input"
        else if line.contains("setPlayState Stopped") && line.contains("Input") {
            activeMicUsers.remove(processName)
        }
    }

    /// Check if a specific process is using the microphone
    func isMicActive(for processName: String) -> Bool {
        return activeMicUsers.contains(processName)
    }

    /// Check if any monitored app alias is using the microphone
    func isMicActiveForAnyAlias(of app: MockApplicationMonitor.MonitoredApp) -> Bool {
        // Check process name
        if activeMicUsers.contains(app.processName) {
            return true
        }

        // Check aliases
        for alias in app.logProcessAliases {
            if activeMicUsers.contains(alias) {
                return true
            }
        }

        return false
    }
}
