//
//  MeetingSonarTests.swift
//  MeetingSonarTests
//
//  Unit tests for v0.1-rebuild components.
//

import XCTest
@testable import MeetingSonar

@MainActor
final class MeetingSonarTests: XCTestCase {

    var settings: SettingsManager!
    var logger: LoggerService!

    override func setUpWithError() throws {
        // Use a temporary user defaults domain
        let domain = "com.meetingsonar.tests"
        UserDefaults.standard.removePersistentDomain(forName: domain)
        
        settings = SettingsManager.shared
        // Note: resetToDefaults is not public in v0.1 SettingsManager, 
        // effectively we are testing the singleton state.
        
        logger = LoggerService.shared
    }

    override func tearDownWithError() throws {
        // Cleaning up defaults
    }

    // MARK: - SettingsManager Tests

    func testDefaultSavePath() {
        // Verify default save path logic
        let path = settings.savePath
        XCTAssertFalse(path.path.isEmpty, "Default save path should not be empty")
        // Default save path is the user's Documents directory (sandbox fallback)
        XCTAssertTrue(path.path.contains("Documents"), "Default save path should be under Documents directory: \(path.path)")
    }
    
    func testAudioQualityPersistence() {
        // Change quality to low
        settings.audioQuality = .low
        XCTAssertEqual(settings.audioQuality, .low)

        // Change to high
        settings.audioQuality = .high
        XCTAssertEqual(settings.audioQuality, .high)

        // Verify User Defaults
        let rawVal = UserDefaults.standard.string(forKey: "audioQuality")
        XCTAssertEqual(rawVal, AudioQuality.high.rawValue)
    }

    // MARK: - LoggerService Tests
    
    func testLoggerServiceInitialization() {
        XCTAssertNotNil(logger)
        // We cannot easily verify console output but we can verify it doesn't crash
        logger.log(category: .general, message: "Test Log from XCTest")
    }
    
    func testMetricLoggingFormat() {
        // This test ensures the logMetric function can be called
        logger.logMetric(event: "test_event", attributes: ["key": "value", "id": 123])
        // Verification would require reading the log file, which is complex in Unit Test due to paths
    }
}
