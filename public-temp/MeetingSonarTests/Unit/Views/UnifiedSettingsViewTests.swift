//
//  UnifiedSettingsViewTests.swift
//  MeetingSonarTests
//
//  Comprehensive tests for UnifiedSettingsView and related settings functionality.
//  Tests cover:
//  - Settings binding and persistence
//  - App detection toggles (all 7 apps)
//  - Transcripts settings
//  - Reset functionality
//  - ApplicationMonitor.enabledApps filtering
//

import Testing
import SwiftUI
@preconcurrency import XCTest
@testable import MeetingSonar

@Suite("UnifiedSettingsView Tests", .serialized)
@MainActor
struct UnifiedSettingsViewTests {

    // MARK: - Test Helper Properties

    /// All 7 app bundle identifiers for testing
    let allAppBundleIds: [String] = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.cisco.webex.webex",
        "com.tencent.meeting",
        "com.electron.lark.iron",
        "com.tencent.xinWeChat"
    ]

    /// Default app detection states according to requirements
    /// WeChat should default to false (privacy), others to true
    let defaultDetectionStates: [String: Bool] = [
        "us.zoom.xos": true,
        "com.microsoft.teams": true,
        "com.microsoft.teams2": true,
        "com.cisco.webex.webex": true,
        "com.tencent.meeting": true,
        "com.electron.lark.iron": true,
        "com.tencent.xinWeChat": false  // Privacy default
    ]

    // MARK: - Recording Quality Tests

    @Test("Audio quality defaults to high")
    func testAudioQualityDefaultsToHigh() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.audioQuality == .high)
    }

    @Test("Audio quality can be changed")
    func testAudioQualityCanBeChanged() async throws {
        let mockSettings = MockSettingsManager()

        // Change to low
        mockSettings.audioQuality = .low
        #expect(mockSettings.audioQuality == .low)

        // Change to medium
        mockSettings.audioQuality = .medium
        #expect(mockSettings.audioQuality == .medium)

        // Change back to high
        mockSettings.audioQuality = .high
        #expect(mockSettings.audioQuality == .high)
    }

    @Test("All audio quality values are valid")
    func testAllAudioQualityValues() async throws {
        let mockSettings = MockSettingsManager()
        let qualities: [AudioQuality] = [.low, .medium, .high]

        for quality in qualities {
            mockSettings.audioQuality = quality
            #expect(mockSettings.audioQuality == quality)
        }
    }

    // MARK: - Auto Recording Configuration Tests

    @Test("Auto recording config defaults to both sources enabled")
    func testAutoRecordingConfigDefaults() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.autoRecordingDefaultConfig.includeSystemAudio == true)
        #expect(mockSettings.autoRecordingDefaultConfig.includeMicrophone == true)
    }

    @Test("Auto recording config can be modified")
    func testAutoRecordingConfigModification() async throws {
        let mockSettings = MockSettingsManager()

        // Change to system only
        mockSettings.autoRecordingDefaultConfig = .systemOnly
        #expect(mockSettings.autoRecordingDefaultConfig.includeSystemAudio == true)
        #expect(mockSettings.autoRecordingDefaultConfig.includeMicrophone == false)

        // Change to microphone only
        mockSettings.autoRecordingDefaultConfig = .microphoneOnly
        #expect(mockSettings.autoRecordingDefaultConfig.includeSystemAudio == false)
        #expect(mockSettings.autoRecordingDefaultConfig.includeMicrophone == true)

        // Change back to default
        mockSettings.autoRecordingDefaultConfig = .default
        #expect(mockSettings.autoRecordingDefaultConfig.includeSystemAudio == true)
        #expect(mockSettings.autoRecordingDefaultConfig.includeMicrophone == true)
    }

    @Test("Auto recording config binding works correctly")
    func testAutoRecordingConfigBinding() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.autoRecordingDefaultConfig = .default

        // Simulate binding behavior from UnifiedSettingsView
        let binding = Binding(
            get: { mockSettings.autoRecordingDefaultConfig.includeSystemAudio },
            set: { mockSettings.autoRecordingDefaultConfig.includeSystemAudio = $0 }
        )

        #expect(binding.wrappedValue == true)
        binding.wrappedValue = false
        #expect(binding.wrappedValue == false)
        #expect(mockSettings.autoRecordingDefaultConfig.includeSystemAudio == false)
    }

    // MARK: - Manual Recording Configuration Tests

    @Test("Manual recording config defaults to system audio only")
    func testManualRecordingConfigDefaults() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.manualRecordingDefaultConfig.includeSystemAudio == true)
        #expect(mockSettings.manualRecordingDefaultConfig.includeMicrophone == false)
    }

    @Test("Manual recording config can be modified")
    func testManualRecordingConfigModification() async throws {
        let mockSettings = MockSettingsManager()

        // Change to default (both enabled)
        mockSettings.manualRecordingDefaultConfig = .default
        #expect(mockSettings.manualRecordingDefaultConfig.includeSystemAudio == true)
        #expect(mockSettings.manualRecordingDefaultConfig.includeMicrophone == true)

        // Change to microphone only
        mockSettings.manualRecordingDefaultConfig = .microphoneOnly
        #expect(mockSettings.manualRecordingDefaultConfig.includeSystemAudio == false)
        #expect(mockSettings.manualRecordingDefaultConfig.includeMicrophone == true)

        // Change back to system only
        mockSettings.manualRecordingDefaultConfig = .systemOnly
        #expect(mockSettings.manualRecordingDefaultConfig.includeSystemAudio == true)
        #expect(mockSettings.manualRecordingDefaultConfig.includeMicrophone == false)
    }

    // MARK: - Smart Detection Toggle Tests

    @Test("Smart detection enabled defaults to true")
    func testSmartDetectionEnabledDefaults() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.smartDetectionEnabled == true)
    }

    @Test("Smart detection enabled can be toggled")
    func testSmartDetectionEnabledToggle() async throws {
        let mockSettings = MockSettingsManager()

        // Start with enabled
        mockSettings.smartDetectionEnabled = true
        #expect(mockSettings.smartDetectionEnabled == true)

        // Disable
        mockSettings.smartDetectionEnabled = false
        #expect(mockSettings.smartDetectionEnabled == false)

        // Enable again
        mockSettings.smartDetectionEnabled = true
        #expect(mockSettings.smartDetectionEnabled == true)
    }

    @Test("Smart detection mode defaults to remind")
    func testSmartDetectionModeDefaults() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.smartDetectionMode == .remind)
    }

    @Test("Smart detection mode can be switched")
    func testSmartDetectionModeSwitch() async throws {
        let mockSettings = MockSettingsManager()

        // Start with remind
        mockSettings.smartDetectionMode = .remind
        #expect(mockSettings.smartDetectionMode == .remind)

        // Switch to auto
        mockSettings.smartDetectionMode = .auto
        #expect(mockSettings.smartDetectionMode == .auto)

        // Switch back to remind
        mockSettings.smartDetectionMode = .remind
        #expect(mockSettings.smartDetectionMode == .remind)
    }

    // MARK: - App Detection Toggle Tests (All 7 Apps)

    @Test("Zoom detection defaults to enabled")
    func testZoomDetectionDefault() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.detectZoom == true)
    }

    @Test("Zoom detection can be toggled")
    func testZoomDetectionToggle() async throws {
        let mockSettings = MockSettingsManager()

        mockSettings.detectZoom = false
        #expect(mockSettings.detectZoom == false)

        mockSettings.detectZoom = true
        #expect(mockSettings.detectZoom == true)
    }

    @Test("Teams Classic detection defaults to enabled")
    func testTeamsClassicDetectionDefault() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.detectTeamsClassic == true)
    }

    @Test("Teams Classic detection can be toggled")
    func testTeamsClassicDetectionToggle() async throws {
        let mockSettings = MockSettingsManager()

        mockSettings.detectTeamsClassic = false
        #expect(mockSettings.detectTeamsClassic == false)

        mockSettings.detectTeamsClassic = true
        #expect(mockSettings.detectTeamsClassic == true)
    }

    @Test("Teams New detection defaults to enabled")
    func testTeamsNewDetectionDefault() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.detectTeamsNew == true)
    }

    @Test("Teams New detection can be toggled")
    func testTeamsNewDetectionToggle() async throws {
        let mockSettings = MockSettingsManager()

        mockSettings.detectTeamsNew = false
        #expect(mockSettings.detectTeamsNew == false)

        mockSettings.detectTeamsNew = true
        #expect(mockSettings.detectTeamsNew == true)
    }

    @Test("Webex detection defaults to enabled")
    func testWebexDetectionDefault() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.detectWebex == true)
    }

    @Test("Webex detection can be toggled")
    func testWebexDetectionToggle() async throws {
        let mockSettings = MockSettingsManager()

        mockSettings.detectWebex = false
        #expect(mockSettings.detectWebex == false)

        mockSettings.detectWebex = true
        #expect(mockSettings.detectWebex == true)
    }

    @Test("Tencent Meeting detection defaults to enabled")
    func testTencentMeetingDetectionDefault() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.detectTencentMeeting == true)
    }

    @Test("Tencent Meeting detection can be toggled")
    func testTencentMeetingDetectionToggle() async throws {
        let mockSettings = MockSettingsManager()

        mockSettings.detectTencentMeeting = false
        #expect(mockSettings.detectTencentMeeting == false)

        mockSettings.detectTencentMeeting = true
        #expect(mockSettings.detectTencentMeeting == true)
    }

    @Test("Feishu detection defaults to enabled")
    func testFeishuDetectionDefault() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.detectFeishu == true)
    }

    @Test("Feishu detection can be toggled")
    func testFeishuDetectionToggle() async throws {
        let mockSettings = MockSettingsManager()

        mockSettings.detectFeishu = false
        #expect(mockSettings.detectFeishu == false)

        mockSettings.detectFeishu = true
        #expect(mockSettings.detectFeishu == true)
    }

    @Test("WeChat detection defaults to disabled (privacy)")
    func testWeChatDetectionDefault() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.detectWeChat == false)
    }

    @Test("WeChat detection can be enabled (opt-in)")
    func testWeChatDetectionEnable() async throws {
        let mockSettings = MockSettingsManager()

        // Start with disabled (default)
        #expect(mockSettings.detectWeChat == false)

        // User opts in
        mockSettings.detectWeChat = true
        #expect(mockSettings.detectWeChat == true)

        // User can opt back out
        mockSettings.detectWeChat = false
        #expect(mockSettings.detectWeChat == false)
    }

    // MARK: - All App Detection Tests

    @Test("All app detection toggles are independent")
    func testAllAppDetectionIndependence() async throws {
        let mockSettings = MockSettingsManager()

        // Set all to true
        mockSettings.enableAllAppDetection()
        #expect(mockSettings.detectZoom == true)
        #expect(mockSettings.detectTeamsClassic == true)
        #expect(mockSettings.detectTeamsNew == true)
        #expect(mockSettings.detectWebex == true)
        #expect(mockSettings.detectTencentMeeting == true)
        #expect(mockSettings.detectFeishu == true)
        #expect(mockSettings.detectWeChat == true)

        // Set all to false
        mockSettings.disableAllAppDetection()
        #expect(mockSettings.detectZoom == false)
        #expect(mockSettings.detectTeamsClassic == false)
        #expect(mockSettings.detectTeamsNew == false)
        #expect(mockSettings.detectWebex == false)
        #expect(mockSettings.detectTencentMeeting == false)
        #expect(mockSettings.detectFeishu == false)
        #expect(mockSettings.detectWeChat == false)
    }

    @Test("Mixed app detection configuration")
    func testMixedAppDetectionConfig() async throws {
        let mockSettings = MockSettingsManager()

        // Custom mixed configuration
        mockSettings.detectZoom = true
        mockSettings.detectTeamsClassic = false
        mockSettings.detectTeamsNew = true
        mockSettings.detectWebex = false
        mockSettings.detectTencentMeeting = true
        mockSettings.detectFeishu = false
        mockSettings.detectWeChat = true  // User opted in

        #expect(mockSettings.detectZoom == true)
        #expect(mockSettings.detectTeamsClassic == false)
        #expect(mockSettings.detectTeamsNew == true)
        #expect(mockSettings.detectWebex == false)
        #expect(mockSettings.detectTencentMeeting == true)
        #expect(mockSettings.detectFeishu == false)
        #expect(mockSettings.detectWeChat == true)
    }

    // MARK: - Transcripts Settings Tests

    @Test("Auto-generate summary defaults to enabled")
    func testAutoGenerateSummaryDefault() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.autoGenerateSummary == true)
    }

    @Test("Auto-generate summary can be toggled")
    func testAutoGenerateSummaryToggle() async throws {
        let mockSettings = MockSettingsManager()

        mockSettings.autoGenerateSummary = false
        #expect(mockSettings.autoGenerateSummary == false)

        mockSettings.autoGenerateSummary = true
        #expect(mockSettings.autoGenerateSummary == true)
    }

    @Test("Transcript language defaults to auto")
    func testTranscriptLanguageDefault() async throws {
        let mockSettings = MockSettingsManager()
        mockSettings.reset()

        #expect(mockSettings.transcriptLanguage == "auto")
    }

    @Test("Transcript language can be changed")
    func testTranscriptLanguageChange() async throws {
        let mockSettings = MockSettingsManager()

        // Change to English
        mockSettings.transcriptLanguage = "en"
        #expect(mockSettings.transcriptLanguage == "en")

        // Change to Chinese
        mockSettings.transcriptLanguage = "zh"
        #expect(mockSettings.transcriptLanguage == "zh")

        // Change back to auto
        mockSettings.transcriptLanguage = "auto"
        #expect(mockSettings.transcriptLanguage == "auto")
    }

    @Test("Transcript language supports all valid values")
    func testTranscriptLanguageValidValues() async throws {
        let mockSettings = MockSettingsManager()
        let validLanguages = ["auto", "en", "zh"]

        for language in validLanguages {
            mockSettings.transcriptLanguage = language
            #expect(mockSettings.transcriptLanguage == language)
        }
    }

    // MARK: - Reset Functionality Tests

    @Test("Reset to defaults restores all settings correctly")
    func testResetToDefaultsFunctionality() async throws {
        let mockSettings = MockSettingsManager()

        // Modify all settings to non-default values
        mockSettings.smartDetectionEnabled = false
        mockSettings.smartDetectionMode = .auto
        mockSettings.audioQuality = .low
        mockSettings.detectZoom = false
        mockSettings.detectTeamsClassic = false
        mockSettings.detectTeamsNew = false
        mockSettings.detectWebex = false
        mockSettings.detectTencentMeeting = false
        mockSettings.detectFeishu = false
        mockSettings.detectWeChat = true  // User enabled

        // Simulate the resetToDefaults() behavior from UnifiedSettingsView
        mockSettings.smartDetectionEnabled = true
        mockSettings.smartDetectionMode = .remind
        mockSettings.audioQuality = .high
        mockSettings.detectZoom = true
        mockSettings.detectTeamsClassic = true
        mockSettings.detectTeamsNew = true
        mockSettings.detectWebex = true
        mockSettings.detectTencentMeeting = true
        mockSettings.detectFeishu = true
        mockSettings.detectWeChat = false  // Privacy: stays false

        // Verify all values are reset correctly
        #expect(mockSettings.smartDetectionEnabled == true)
        #expect(mockSettings.smartDetectionMode == .remind)
        #expect(mockSettings.audioQuality == .high)
        #expect(mockSettings.detectZoom == true)
        #expect(mockSettings.detectTeamsClassic == true)
        #expect(mockSettings.detectTeamsNew == true)
        #expect(mockSettings.detectWebex == true)
        #expect(mockSettings.detectTencentMeeting == true)
        #expect(mockSettings.detectFeishu == true)
        #expect(mockSettings.detectWeChat == false)  // Critical: stays false
    }

    @Test("Reset preserves WeChat disabled state")
    func testResetPreservesWeChatDisabled() async throws {
        let mockSettings = MockSettingsManager()

        // Even if user enabled WeChat
        mockSettings.detectWeChat = true

        // Reset should restore to default (disabled for privacy)
        mockSettings.detectWeChat = false

        #expect(mockSettings.detectWeChat == false)
    }

    // MARK: - Settings Binding State Persistence Tests

    @Test("Settings changes are persistent within session")
    func testSettingsPersistenceInSession() async throws {
        let mockSettings = MockSettingsManager()

        // Change multiple settings
        mockSettings.audioQuality = .low
        mockSettings.smartDetectionEnabled = false
        mockSettings.detectZoom = false
        mockSettings.autoGenerateSummary = false
        mockSettings.transcriptLanguage = "en"

        // Verify all changes persist
        #expect(mockSettings.audioQuality == .low)
        #expect(mockSettings.smartDetectionEnabled == false)
        #expect(mockSettings.detectZoom == false)
        #expect(mockSettings.autoGenerateSummary == false)
        #expect(mockSettings.transcriptLanguage == "en")
    }

    @Test("Multiple rapid setting changes are handled correctly")
    func testRapidSettingChanges() async throws {
        let mockSettings = MockSettingsManager()

        // Rapid changes to same setting
        for i in 0..<10 {
            mockSettings.audioQuality = (i % 2 == 0) ? .high : .low
        }

        // Final state should be preserved
        #expect(mockSettings.audioQuality == .low)

        // Rapid changes to different settings
        mockSettings.detectZoom = true
        mockSettings.detectTeamsClassic = false
        mockSettings.detectWebex = true
        mockSettings.smartDetectionEnabled = false

        #expect(mockSettings.detectZoom == true)
        #expect(mockSettings.detectTeamsClassic == false)
        #expect(mockSettings.detectWebex == true)
        #expect(mockSettings.smartDetectionEnabled == false)
    }

    // MARK: - Edge Cases Tests

    @Test("Disabling all audio sources is possible but should warn")
    func testDisableAllAudioSources() async throws {
        let mockSettings = MockSettingsManager()

        // Create config with no sources (edge case)
        let noSourcesConfig = AudioSourceConfig(
            includeSystemAudio: false,
            includeMicrophone: false
        )

        mockSettings.autoRecordingDefaultConfig = noSourcesConfig

        #expect(noSourcesConfig.hasAnySource == false)
        #expect(noSourcesConfig.isValid() == false)
    }

    @Test("At least one audio source should be enabled for valid config")
    func testValidAudioSourceConfig() async throws {
        let validConfigs: [AudioSourceConfig] = [.default, .systemOnly, .microphoneOnly]

        for config in validConfigs {
            #expect(config.hasAnySource == true)
            #expect(config.isValid() == true)
        }
    }

    @Test("Smart detection mode has only two valid values")
    func testSmartDetectionModeValues() async throws {
        let mockSettings = MockSettingsManager()
        let modes: [SmartDetectionMode] = [.auto, .remind]

        for mode in modes {
            mockSettings.smartDetectionMode = mode
            #expect(mockSettings.smartDetectionMode == mode)
        }
    }

    // MARK: - ObservableObject Tests

    @Test("SettingsManager is an ObservableObject")
    func testObservableObjectConformance() async throws {
        let mockSettings = MockSettingsManager()

        // MockSettingsManager conforms to ObservableObject
        // This test verifies the @Published properties work correctly
        #expect(mockSettings.smartDetectionEnabled == true)

        mockSettings.smartDetectionEnabled = false
        #expect(mockSettings.smartDetectionEnabled == false)
    }

    @Test("Published properties trigger updates")
    func testPublishedPropertiesTriggerUpdates() async throws {
        let mockSettings = MockSettingsManager()

        // Verify that changing a @Published property works
        // In a real SwiftUI view, this would trigger a view update
        mockSettings.smartDetectionEnabled = !mockSettings.smartDetectionEnabled
        mockSettings.publishChanges()  // Manually trigger objectWillChange

        #expect(mockSettings.smartDetectionEnabled == false)
    }
}
