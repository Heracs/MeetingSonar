//
//  MockSettingsManager.swift
//  MeetingSonar
//
//  Mock implementation of SettingsManager for testing.
//

import Foundation
import SwiftUI

/// Mock settings manager for unit testing
///
/// ## Usage
/// ```swift
/// let mockSettings = MockSettingsManager()
/// mockSettings.savePath = testURL
/// mockSettings.smartDetectionEnabled = true
/// XCTAssertEqual(mockSettings.savePath, testURL)
/// ```
@MainActor
final class MockSettingsManager: ObservableObject {

    // MARK: - Properties

    @Published var savePath: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    @Published var audioFormat: AudioFormat = .m4a
    @Published var audioQuality: AudioQuality = .high
    @Published var includeSystemAudio: Bool = true
    @Published var includeMicrophone: Bool = false
    @Published var smartDetectionEnabled: Bool = true
    @Published var smartDetectionMode: SmartDetectionMode = .remind
    @Published var selectedUnifiedASRId: String = ""
    @Published var selectedUnifiedLLMId: String = ""

    // MARK: - Recording Scenario Optimization

    @Published var autoRecordingDefaultConfig: AudioSourceConfig = .default
    @Published var manualRecordingDefaultConfig: AudioSourceConfig = .systemOnly

    // MARK: - Per-App Detection Settings

    // Western Apps
    @Published var detectZoom: Bool = true
    @Published var detectTeamsClassic: Bool = true
    @Published var detectTeamsNew: Bool = true
    @Published var detectWebex: Bool = true

    // Chinese Apps
    @Published var detectTencentMeeting: Bool = true
    @Published var detectFeishu: Bool = true
    @Published var detectWeChat: Bool = false

    // MARK: - Transcripts Settings

    @Published var autoGenerateSummary: Bool = true
    @Published var transcriptLanguage: String = "auto"

    // MARK: - Published Properties Helper

    /// Trigger objectWillChange manually for testing
    func publishChanges() {
        objectWillChange.send()
    }

    /// Track whether generateFilename was called
    private(set) var generateFilenameCalled = false

    /// Track whether generateFileURL was called
    private(set) var generateFileURLCalled = false

    /// Last app name passed to generate methods
    private(set) var lastAppName: String?

    /// Custom filename generator (optional override)
    var customFilenameGenerator: ((String?) -> String)?

    /// Custom file URL generator (optional override)
    var customFileURLGenerator: ((String?) -> URL)?

    // MARK: - Protocol Methods

    func generateFilename(appName: String?) -> String {
        generateFilenameCalled = true
        lastAppName = appName

        if let custom = customFilenameGenerator {
            return custom(appName)
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let prefix = appName?.replacingOccurrences(of: " ", with: "_") ?? "Meeting"
        return "\(prefix)_\(timestamp).m4a"
    }

    func generateFileURL(appName: String?) -> URL {
        generateFileURLCalled = true
        lastAppName = appName

        if let custom = customFileURLGenerator {
            return custom(appName)
        }

        let filename = generateFilename(appName: appName)
        return savePath.appendingPathComponent(filename)
    }

    // MARK: - Test Helpers

    /// Reset all tracking state
    func reset() {
        savePath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        audioFormat = .m4a
        audioQuality = .high
        includeSystemAudio = true
        includeMicrophone = false
        smartDetectionEnabled = true
        smartDetectionMode = .remind
        selectedUnifiedASRId = ""
        selectedUnifiedLLMId = ""
        autoRecordingDefaultConfig = .default
        manualRecordingDefaultConfig = .systemOnly
        detectZoom = true
        detectTeamsClassic = true
        detectTeamsNew = true
        detectWebex = true
        detectTencentMeeting = true
        detectFeishu = true
        detectWeChat = false
        autoGenerateSummary = true
        transcriptLanguage = "auto"
        generateFilenameCalled = false
        generateFileURLCalled = false
        lastAppName = nil
        customFilenameGenerator = nil
        customFileURLGenerator = nil
    }

    /// Configure with default test values
    func configureForTesting() {
        savePath = FileManager.default.temporaryDirectory
        smartDetectionEnabled = true
        smartDetectionMode = .remind
        includeSystemAudio = true
        includeMicrophone = false
        audioFormat = .m4a
        audioQuality = .high
        autoRecordingDefaultConfig = .default
        manualRecordingDefaultConfig = .systemOnly
        detectZoom = true
        detectTeamsClassic = true
        detectTeamsNew = true
        detectWebex = true
        detectTencentMeeting = true
        detectFeishu = true
        detectWeChat = false
        autoGenerateSummary = true
        transcriptLanguage = "auto"
    }

    /// Configure all app detection settings to enabled
    func enableAllAppDetection() {
        detectZoom = true
        detectTeamsClassic = true
        detectTeamsNew = true
        detectWebex = true
        detectTencentMeeting = true
        detectFeishu = true
        detectWeChat = true
    }

    /// Configure all app detection settings to disabled
    func disableAllAppDetection() {
        detectZoom = false
        detectTeamsClassic = false
        detectTeamsNew = false
        detectWebex = false
        detectTencentMeeting = false
        detectFeishu = false
        detectWeChat = false
    }
}
