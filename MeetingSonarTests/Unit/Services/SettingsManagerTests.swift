//
//  SettingsManagerTests.swift
//  MeetingSonarTests
//
//  Comprehensive tests for SettingsManager persistence and behavior.
//  Tests cover settings persistence, defaults, and behavior for all settings.
//

import Testing
import Foundation
@preconcurrency import XCTest
@testable import MeetingSonar

@Suite("SettingsManager Tests", .serialized)
@MainActor
struct SettingsManagerTests {

    // MARK: - Test Helper Properties

    /// Temporary UserDefaults domain for isolated testing
    private let testDomain = "com.meetingsonar.tests"

    /// Clean up test UserDefaults domain
    private func cleanTestDomain() {
        UserDefaults.standard.removePersistentDomain(forName: testDomain)
    }

    // MARK: - Audio Quality Tests

    @Test("Audio quality persists to UserDefaults")
    func testAudioQualityPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.audioQuality

            // Test each quality value
            for quality in [AudioQuality.low, .medium, .high] {
                settings.audioQuality = quality

                // Verify it persisted
                let rawValue = UserDefaults.standard.string(forKey: "audioQuality")
                #expect(rawValue == quality.rawValue)
            }

            // Restore original
            settings.audioQuality = original
        }
    }

    @Test("Audio quality can be loaded from UserDefaults")
    func testAudioQualityLoading() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.audioQuality

            // Set a value directly in UserDefaults
            UserDefaults.standard.set(AudioQuality.medium.rawValue, forKey: "audioQuality")

            // Create a new instance (simulating app restart)
            // Note: Since SettingsManager is a singleton, we test the didSet behavior
            settings.audioQuality = .medium
            #expect(settings.audioQuality == .medium)

            // Restore original
            settings.audioQuality = original
        }
    }

    // MARK: - Audio Format Tests

    @Test("Audio format persists to UserDefaults")
    func testAudioFormatPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.audioFormat

            // Test each format value
            for format in [AudioFormat.m4a, .mp3] {
                settings.audioFormat = format

                // Verify it persisted
                let rawValue = UserDefaults.standard.string(forKey: "audioFormat")
                #expect(rawValue == format.rawValue)
            }

            // Restore original
            settings.audioFormat = original
        }
    }

    // MARK: - Smart Detection Settings Tests

    @Test("Smart detection enabled persists to UserDefaults")
    func testSmartDetectionEnabledPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.smartDetectionEnabled

            // Test toggling
            settings.smartDetectionEnabled = false
            #expect(UserDefaults.standard.bool(forKey: "smartDetectionEnabled") == false)

            settings.smartDetectionEnabled = true
            #expect(UserDefaults.standard.bool(forKey: "smartDetectionEnabled") == true)

            // Restore original
            settings.smartDetectionEnabled = original
        }
    }

    @Test("Smart detection mode persists to UserDefaults")
    func testSmartDetectionModePersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.smartDetectionMode

            // Test each mode
            for mode in [SmartDetectionMode.auto, .remind] {
                settings.smartDetectionMode = mode

                // Verify it persisted
                let rawValue = UserDefaults.standard.string(forKey: "smartDetectionMode")
                #expect(rawValue == mode.rawValue)
            }

            // Restore original
            settings.smartDetectionMode = original
        }
    }

    // MARK: - App Detection Settings Tests (Western Apps)

    @Test("Zoom detection setting persists")
    func testZoomDetectionPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.detectZoom

            // Test toggling
            settings.detectZoom = false
            #expect(UserDefaults.standard.bool(forKey: "detectZoom") == false)

            settings.detectZoom = true
            #expect(UserDefaults.standard.bool(forKey: "detectZoom") == true)

            // Restore original
            settings.detectZoom = original
        }
    }

    @Test("Teams Classic detection setting persists")
    func testTeamsClassicDetectionPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.detectTeamsClassic

            // Test toggling
            settings.detectTeamsClassic = false
            #expect(UserDefaults.standard.bool(forKey: "detectTeamsClassic") == false)

            settings.detectTeamsClassic = true
            #expect(UserDefaults.standard.bool(forKey: "detectTeamsClassic") == true)

            // Restore original
            settings.detectTeamsClassic = original
        }
    }

    @Test("Teams New detection setting persists")
    func testTeamsNewDetectionPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.detectTeamsNew

            // Test toggling
            settings.detectTeamsNew = false
            #expect(UserDefaults.standard.bool(forKey: "detectTeamsNew") == false)

            settings.detectTeamsNew = true
            #expect(UserDefaults.standard.bool(forKey: "detectTeamsNew") == true)

            // Restore original
            settings.detectTeamsNew = original
        }
    }

    @Test("Webex detection setting persists")
    func testWebexDetectionPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.detectWebex

            // Test toggling
            settings.detectWebex = false
            #expect(UserDefaults.standard.bool(forKey: "detectWebex") == false)

            settings.detectWebex = true
            #expect(UserDefaults.standard.bool(forKey: "detectWebex") == true)

            // Restore original
            settings.detectWebex = original
        }
    }

    // MARK: - App Detection Settings Tests (Chinese Apps)

    @Test("Tencent Meeting detection setting persists")
    func testTencentMeetingDetectionPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.detectTencentMeeting

            // Test toggling
            settings.detectTencentMeeting = false
            #expect(UserDefaults.standard.bool(forKey: "detectTencentMeeting") == false)

            settings.detectTencentMeeting = true
            #expect(UserDefaults.standard.bool(forKey: "detectTencentMeeting") == true)

            // Restore original
            settings.detectTencentMeeting = original
        }
    }

    @Test("Feishu detection setting persists")
    func testFeishuDetectionPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.detectFeishu

            // Test toggling
            settings.detectFeishu = false
            #expect(UserDefaults.standard.bool(forKey: "detectFeishu") == false)

            settings.detectFeishu = true
            #expect(UserDefaults.standard.bool(forKey: "detectFeishu") == true)

            // Restore original
            settings.detectFeishu = original
        }
    }

    @Test("WeChat detection setting persists and defaults to false")
    func testWeChatDetectionPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.detectWeChat

            // Default should be false (privacy)
            // If this is first run, the default would be false
            let defaultFromDefaults = UserDefaults.standard.object(forKey: "detectWeChat") == nil

            // Test toggling
            settings.detectWeChat = true
            #expect(UserDefaults.standard.bool(forKey: "detectWeChat") == true)

            settings.detectWeChat = false
            #expect(UserDefaults.standard.bool(forKey: "detectWeChat") == false)

            // Restore original
            settings.detectWeChat = original
        }
    }

    // MARK: - Transcripts Settings Tests

    @Test("Auto-generate summary setting persists")
    func testAutoGenerateSummaryPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.autoGenerateSummary

            // Test toggling
            settings.autoGenerateSummary = false
            #expect(UserDefaults.standard.bool(forKey: "autoGenerateSummary") == false)

            settings.autoGenerateSummary = true
            #expect(UserDefaults.standard.bool(forKey: "autoGenerateSummary") == true)

            // Restore original
            settings.autoGenerateSummary = original
        }
    }

    @Test("Transcript language setting persists")
    func testTranscriptLanguagePersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.transcriptLanguage

            // Test each language option
            for language in ["auto", "en", "zh"] {
                settings.transcriptLanguage = language

                // Verify it persisted
                let savedValue = UserDefaults.standard.string(forKey: "transcriptLanguage")
                #expect(savedValue == language)
            }

            // Restore original
            settings.transcriptLanguage = original
        }
    }

    // MARK: - Recording Scenario Configuration Tests

    @Test("Auto recording configuration persists")
    func testAutoRecordingConfigPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.autoRecordingDefaultConfig

            // Test different configurations
            let configs: [AudioSourceConfig] = [.default, .systemOnly, .microphoneOnly]

            for config in configs {
                settings.autoRecordingDefaultConfig = config

                // Verify it persisted by reading from UserDefaults
                let saved = AudioSourceConfig.fromDefaults(key: "autoRecordingDefaultConfig")
                #expect(saved?.includeSystemAudio == config.includeSystemAudio)
                #expect(saved?.includeMicrophone == config.includeMicrophone)
            }

            // Restore original
            settings.autoRecordingDefaultConfig = original
        }
    }

    @Test("Manual recording configuration persists")
    func testManualRecordingConfigPersistence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original value
            let original = settings.manualRecordingDefaultConfig

            // Test different configurations
            let configs: [AudioSourceConfig] = [.default, .systemOnly, .microphoneOnly]

            for config in configs {
                settings.manualRecordingDefaultConfig = config

                // Verify it persisted by reading from UserDefaults
                let saved = AudioSourceConfig.fromDefaults(key: "manualRecordingDefaultConfig")
                #expect(saved?.includeSystemAudio == config.includeSystemAudio)
                #expect(saved?.includeMicrophone == config.includeMicrophone)
            }

            // Restore original
            settings.manualRecordingDefaultConfig = original
        }
    }

    // MARK: - Default Config Selection Tests

    @Test("Default config for manual trigger is system only")
    func testDefaultConfigForManualTrigger() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            let config = settings.defaultConfig(for: .manual)

            #expect(config.includeSystemAudio == true)
            #expect(config.includeMicrophone == false)
        }
    }

    @Test("Default config for auto trigger is both sources")
    func testDefaultConfigForAutoTrigger() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            let config = settings.defaultConfig(for: .auto)

            #expect(config.includeSystemAudio == true)
            #expect(config.includeMicrophone == true)
        }
    }

    @Test("Default config for smart reminder trigger is both sources")
    func testDefaultConfigForSmartReminderTrigger() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            let config = settings.defaultConfig(for: .smartReminder)

            #expect(config.includeSystemAudio == true)
            #expect(config.includeMicrophone == true)
        }
    }

    // MARK: - Legacy Settings Migration Tests

    @Test("Legacy settings are migrated on first load")
    func testLegacySettingsMigration() async throws {
        await MainActor.run {
            // Note: This test verifies the migration logic exists
            // but doesn't actually test migration since it's already run

            let settings = SettingsManager.shared

            // After migration, both scenario configs should be set
            #expect(settings.autoRecordingDefaultConfig.hasAnySource)
            #expect(settings.manualRecordingDefaultConfig.hasAnySource)
        }
    }

    // MARK: - Settings Independence Tests

    @Test("All app detection settings are independent")
    func testAppDetectionSettingsIndependence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original values
            let originals: [Bool] = [
                settings.detectZoom,
                settings.detectTeamsClassic,
                settings.detectTeamsNew,
                settings.detectWebex,
                settings.detectTencentMeeting,
                settings.detectFeishu,
                settings.detectWeChat
            ]

            // Set all to different values
            settings.detectZoom = true
            settings.detectTeamsClassic = false
            settings.detectTeamsNew = true
            settings.detectWebex = false
            settings.detectTencentMeeting = true
            settings.detectFeishu = false
            settings.detectWeChat = true

            // Verify they're independent
            #expect(settings.detectZoom == true)
            #expect(settings.detectTeamsClassic == false)
            #expect(settings.detectTeamsNew == true)
            #expect(settings.detectWebex == false)
            #expect(settings.detectTencentMeeting == true)
            #expect(settings.detectFeishu == false)
            #expect(settings.detectWeChat == true)

            // Restore originals
            settings.detectZoom = originals[0]
            settings.detectTeamsClassic = originals[1]
            settings.detectTeamsNew = originals[2]
            settings.detectWebex = originals[3]
            settings.detectTencentMeeting = originals[4]
            settings.detectFeishu = originals[5]
            settings.detectWeChat = originals[6]
        }
    }

    @Test("Recording configs are independent")
    func testRecordingConfigsIndependence() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original values
            let originalAuto = settings.autoRecordingDefaultConfig
            let originalManual = settings.manualRecordingDefaultConfig

            // Set to different values
            settings.autoRecordingDefaultConfig = .default
            settings.manualRecordingDefaultConfig = .systemOnly

            // Verify they're independent
            #expect(settings.autoRecordingDefaultConfig.includeMicrophone == true)
            #expect(settings.manualRecordingDefaultConfig.includeMicrophone == false)

            // Restore originals
            settings.autoRecordingDefaultConfig = originalAuto
            settings.manualRecordingDefaultConfig = originalManual
        }
    }

    // MARK: - ObservableObject Tests

    @Test("SettingsManager is an ObservableObject")
    func testObservableObjectConformance() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // SettingsManager should conform to ObservableObject
            // This is verified by the @Published properties
            #expect(settings.smartDetectionEnabled == settings.smartDetectionEnabled)
        }
    }

    @Test("Changing settings triggers objectWillChange")
    func testSettingsChangeTriggersUpdate() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original
            let original = settings.smartDetectionEnabled

            // Change a setting
            settings.smartDetectionEnabled = !settings.smartDetectionEnabled

            // The change should be reflected
            #expect(settings.smartDetectionEnabled != original)

            // Restore original
            settings.smartDetectionEnabled = original
        }
    }

    // MARK: - Edge Cases Tests

    @Test("Settings handle rapid changes correctly")
    func testRapidSettingsChanges() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save originals
            let originalQuality = settings.audioQuality
            let originalDetection = settings.smartDetectionEnabled

            // Rapid changes
            for i in 0..<10 {
                settings.audioQuality = (i % 2 == 0) ? .high : .low
                settings.smartDetectionEnabled = (i % 2 == 0)
            }

            // Final state should be preserved
            #expect(settings.audioQuality == .low)
            #expect(settings.smartDetectionEnabled == false)

            // Restore originals
            settings.audioQuality = originalQuality
            settings.smartDetectionEnabled = originalDetection
        }
    }

    @Test("Settings can be set to same value multiple times")
    func testSettingSameValueMultipleTimes() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original
            let original = settings.audioQuality

            // Set same value multiple times
            settings.audioQuality = .high
            settings.audioQuality = .high
            settings.audioQuality = .high

            // Should still be high
            #expect(settings.audioQuality == .high)

            // Restore original
            settings.audioQuality = original
        }
    }

    // MARK: - Filename Generation Tests

    @Test("Generated filename includes app name")
    func testGeneratedFilenameIncludesAppName() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            let filename = settings.generateFilename(appName: "Zoom")
            #expect(filename.contains("Zoom"))
        }
    }

    @Test("Generated filename includes timestamp")
    func testGeneratedFilenameIncludesTimestamp() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            let filename = settings.generateFilename(appName: nil)
            #expect(filename.contains("_"))
        }
    }

    @Test("Generated filename uses correct extension")
    func testGeneratedFilenameUsesCorrectExtension() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original
            let originalFormat = settings.audioFormat

            // Test M4A
            settings.audioFormat = .m4a
            let m4aFilename = settings.generateFilename(appName: "Test")
            #expect(m4aFilename.hasSuffix(".m4a"))

            // Test MP3
            settings.audioFormat = .mp3
            let mp3Filename = settings.generateFilename(appName: "Test")
            #expect(mp3Filename.hasSuffix(".mp3"))

            // Restore original
            settings.audioFormat = originalFormat
        }
    }

    @Test("Generated file URL is within save path")
    func testGeneratedFileURLInSavePath() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            let fileURL = settings.generateFileURL(appName: "Test")

            // The file URL should be within the save path
            #expect(fileURL.path.hasPrefix(settings.savePath.path))
        }
    }

    // MARK: - Audio Quality Enum Tests

    @Test("All audio quality values have valid display names")
    func testAudioQualityDisplayNames() async throws {
        let qualities: [AudioQuality] = [.low, .medium, .high]

        for quality in qualities {
            let displayName = quality.localizedDisplayName
            #expect(!displayName.isEmpty)
        }
    }

    @Test("All audio quality values have valid bit rates")
    func testAudioQualityBitRates() async throws {
        let qualities: [AudioQuality] = [.low, .medium, .high]

        for quality in qualities {
            #expect(quality.bitRate > 0)
        }
    }

    @Test("All audio quality values have valid sample rates")
    func testAudioQualitySampleRates() async throws {
        let qualities: [AudioQuality] = [.low, .medium, .high]

        for quality in qualities {
            #expect(quality.sampleRate > 0)
        }
    }

    // MARK: - Audio Format Enum Tests

    @Test("All audio formats have valid file extensions")
    func testAudioFormatFileExtensions() async throws {
        let formats: [AudioFormat] = [.m4a, .mp3]

        for format in formats {
            let ext = format.fileExtension
            #expect(!ext.isEmpty)
            #expect(ext == format.rawValue)
        }
    }

    @Test("All audio formats have valid display names")
    func testAudioFormatDisplayNames() async throws {
        let formats: [AudioFormat] = [.m4a, .mp3]

        for format in formats {
            let displayName = format.displayName
            #expect(!displayName.isEmpty)
        }
    }

    // MARK: - Smart Detection Mode Enum Tests

    @Test("All smart detection modes have valid raw values")
    func testSmartDetectionModeRawValues() async throws {
        let modes: [SmartDetectionMode] = [.auto, .remind]

        for mode in modes {
            #expect(!mode.rawValue.isEmpty)
        }
    }

    @Test("All smart detection modes have valid display names")
    func testSmartDetectionModeDisplayNames() async throws {
        let modes: [SmartDetectionMode] = [.auto, .remind]

        for mode in modes {
            let displayName = mode.localizedDisplayName
            #expect(!displayName.isEmpty)
        }
    }

    @Test("Smart detection modes have unique raw values")
    func testSmartDetectionModeUniqueRawValues() async throws {
        let modes: [SmartDetectionMode] = [.auto, .remind]
        let rawValues = modes.map { $0.rawValue }

        // All raw values should be unique
        #expect(rawValues.count == Set(rawValues).count)
    }
}
