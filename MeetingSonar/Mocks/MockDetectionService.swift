//
//  MockDetectionService.swift
//  MeetingSonar
//
//  Mock implementation of DetectionServiceProtocol for testing.
//

import Foundation

/// Mock detection service for unit testing
///
/// ## Usage
/// ```swift
/// let mockDetector = MockDetectionService()
/// mockDetector.start()
/// XCTAssertTrue(mockDetector.isRunning)
/// ```
@MainActor
final class MockDetectionService: DetectionServiceProtocol {

    // MARK: - Properties

    /// Whether the service is currently running
    private(set) var isRunning = false

    /// Whether start was called
    var startCalled = false

    /// Whether cleanup was called
    private(set) var cleanupCalled = false

    /// Number of times start was called
    private(set) var startCallCount = 0

    /// Number of times cleanup was called
    private(set) var cleanupCallCount = 0

    // MARK: - Control

    func start() {
        startCalled = true
        startCallCount += 1
        isRunning = true
    }

    func cleanup() {
        cleanupCalled = true
        cleanupCallCount += 1
        isRunning = false
    }

    // MARK: - Test Helpers

    /// Configure for testing (clears all state)
    func configureForTesting() {
        reset()
    }

    /// Reset all tracking state
    func reset() {
        isRunning = false
        startCalled = false
        cleanupCalled = false
        startCallCount = 0
        cleanupCallCount = 0
    }

    /// Simulate meeting detection
    func simulateMeetingDetected() {
        // Can be used to trigger delegate callbacks in tests
    }

    /// Simulate meeting ended
    func simulateMeetingEnded() {
        // Can be used to trigger delegate callbacks in tests
    }
}
