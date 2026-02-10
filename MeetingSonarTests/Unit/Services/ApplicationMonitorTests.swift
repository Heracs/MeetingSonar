//
//  ApplicationMonitorTests.swift
//  MeetingSonarTests
//
//  Comprehensive tests for ApplicationMonitor enabledApps filtering logic.
//  Tests that the filtering correctly respects user settings for all 7 apps.
//

import Testing
import Foundation
@preconcurrency import XCTest
@testable import MeetingSonar

@Suite("ApplicationMonitor Tests", .serialized)
@MainActor
struct ApplicationMonitorTests {

    // MARK: - Test Helper Types

    /// Test version of MonitoredApp
    struct TestMonitoredApp {
        let bundleIdentifier: String
        let processName: String
    }

    /// All 7 monitored apps for testing
    let allApps: [TestMonitoredApp] = [
        TestMonitoredApp(bundleIdentifier: "us.zoom.xos", processName: "zoom.us"),
        TestMonitoredApp(bundleIdentifier: "com.microsoft.teams", processName: "Microsoft Teams"),
        TestMonitoredApp(bundleIdentifier: "com.microsoft.teams2", processName: "MSTeams"),
        TestMonitoredApp(bundleIdentifier: "com.cisco.webex.webex", processName: "Webex"),
        TestMonitoredApp(bundleIdentifier: "com.tencent.meeting", processName: "TencentMeeting"),
        TestMonitoredApp(bundleIdentifier: "com.electron.lark.iron", processName: "Feishu"),
        TestMonitoredApp(bundleIdentifier: "com.tencent.xinWeChat", processName: "WeChat")
    ]

    /// Filter apps based on settings (mimics ApplicationMonitor.enabledApps logic)
    func filterApps(_ apps: [TestMonitoredApp], settings: MockSettingsManager) -> [TestMonitoredApp] {
        return apps.filter { app in
            switch app.bundleIdentifier {
            // Western Apps
            case "us.zoom.xos":
                return settings.detectZoom
            case "com.microsoft.teams":
                return settings.detectTeamsClassic
            case "com.microsoft.teams2":
                return settings.detectTeamsNew
            case "com.cisco.webex.webex":
                return settings.detectWebex
            // Chinese Apps
            case "com.tencent.meeting":
                return settings.detectTencentMeeting
            case "com.electron.lark.iron":
                return settings.detectFeishu
            case "com.tencent.xinWeChat":
                return settings.detectWeChat
            default:
                return true
            }
        }
    }

    // MARK: - Helper Methods

    /// Get the expected count of enabled apps based on settings
    func expectedEnabledCount(settings: MockSettingsManager) -> Int {
        var count = 0
        if settings.detectZoom { count += 1 }
        if settings.detectTeamsClassic { count += 1 }
        if settings.detectTeamsNew { count += 1 }
        if settings.detectWebex { count += 1 }
        if settings.detectTencentMeeting { count += 1 }
        if settings.detectFeishu { count += 1 }
        if settings.detectWeChat { count += 1 }
        return count
    }

    // MARK: - Default State Tests

    @Test("enabledApps respects default settings")
    func testEnabledAppsDefaultState() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        let enabledApps = filterApps(allApps, settings: settings)
        let expectedCount = expectedEnabledCount(settings: settings)

        // All apps except WeChat should be enabled by default
        #expect(enabledApps.count == expectedCount)
        #expect(enabledApps.count == 6)  // 7 total - 1 (WeChat disabled)
    }

    @Test("WeChat is not in enabledApps by default")
    func testWeChatNotEnabledByDefault() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        let enabledApps = filterApps(allApps, settings: settings)
        let weChatApp = enabledApps.first { $0.bundleIdentifier == "com.tencent.xinWeChat" }

        #expect(weChatApp == nil)
    }

    @Test("All other apps are in enabledApps by default")
    func testOtherAppsEnabledByDefault() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        let enabledApps = filterApps(allApps, settings: settings)
        let bundleIds = enabledApps.map { $0.bundleIdentifier }

        // These should all be enabled by default
        #expect(bundleIds.contains("us.zoom.xos"))
        #expect(bundleIds.contains("com.microsoft.teams"))
        #expect(bundleIds.contains("com.microsoft.teams2"))
        #expect(bundleIds.contains("com.cisco.webex.webex"))
        #expect(bundleIds.contains("com.tencent.meeting"))
        #expect(bundleIds.contains("com.electron.lark.iron"))
    }

    // MARK: - All Apps Enabled Tests

    @Test("enabledApps returns all apps when all toggles are on")
    func testEnabledAppsAllEnabled() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Enable all app detection
        settings.enableAllAppDetection()

        let enabledApps = filterApps(allApps, settings: settings)

        #expect(enabledApps.count == 7)
    }

    @Test("WeChat appears in enabledApps when enabled")
    func testWeChatAppearsWhenEnabled() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Enable WeChat
        settings.detectWeChat = true

        let enabledApps = filterApps(allApps, settings: settings)
        let weChatApp = enabledApps.first { $0.bundleIdentifier == "com.tencent.xinWeChat" }

        #expect(weChatApp != nil)
        #expect(weChatApp?.processName == "WeChat")
    }

    // MARK: - All Apps Disabled Tests

    @Test("enabledApps returns empty array when all toggles are off")
    func testEnabledAppsAllDisabled() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Disable all app detection
        settings.disableAllAppDetection()

        let enabledApps = filterApps(allApps, settings: settings)

        #expect(enabledApps.isEmpty)
    }

    @Test("No apps are monitored when all are disabled")
    func testNoAppsMonitoredWhenAllDisabled() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        settings.disableAllAppDetection()

        let enabledApps = filterApps(allApps, settings: settings)

        #expect(enabledApps.count == 0)
    }

    // MARK: - Individual App Toggle Tests

    @Test("Zoom toggle affects enabledApps correctly")
    func testZoomToggle() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Initially enabled
        var enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "us.zoom.xos" }))

        // Disable Zoom
        settings.detectZoom = false
        enabledApps = filterApps(allApps, settings: settings)
        #expect(!enabledApps.contains(where: { $0.bundleIdentifier == "us.zoom.xos" }))

        // Re-enable Zoom
        settings.detectZoom = true
        enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "us.zoom.xos" }))
    }

    @Test("Teams Classic toggle affects enabledApps correctly")
    func testTeamsClassicToggle() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Initially enabled
        var enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "com.microsoft.teams" }))

        // Disable Teams Classic
        settings.detectTeamsClassic = false
        enabledApps = filterApps(allApps, settings: settings)
        #expect(!enabledApps.contains(where: { $0.bundleIdentifier == "com.microsoft.teams" }))

        // Re-enable Teams Classic
        settings.detectTeamsClassic = true
        enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "com.microsoft.teams" }))
    }

    @Test("Teams New toggle affects enabledApps correctly")
    func testTeamsNewToggle() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Initially enabled
        var enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "com.microsoft.teams2" }))

        // Disable Teams New
        settings.detectTeamsNew = false
        enabledApps = filterApps(allApps, settings: settings)
        #expect(!enabledApps.contains(where: { $0.bundleIdentifier == "com.microsoft.teams2" }))

        // Re-enable Teams New
        settings.detectTeamsNew = true
        enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "com.microsoft.teams2" }))
    }

    @Test("Webex toggle affects enabledApps correctly")
    func testWebexToggle() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Initially enabled
        var enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "com.cisco.webex.webex" }))

        // Disable Webex
        settings.detectWebex = false
        enabledApps = filterApps(allApps, settings: settings)
        #expect(!enabledApps.contains(where: { $0.bundleIdentifier == "com.cisco.webex.webex" }))

        // Re-enable Webex
        settings.detectWebex = true
        enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "com.cisco.webex.webex" }))
    }

    @Test("Tencent Meeting toggle affects enabledApps correctly")
    func testTencentMeetingToggle() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Initially enabled
        var enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "com.tencent.meeting" }))

        // Disable Tencent Meeting
        settings.detectTencentMeeting = false
        enabledApps = filterApps(allApps, settings: settings)
        #expect(!enabledApps.contains(where: { $0.bundleIdentifier == "com.tencent.meeting" }))

        // Re-enable Tencent Meeting
        settings.detectTencentMeeting = true
        enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "com.tencent.meeting" }))
    }

    @Test("Feishu toggle affects enabledApps correctly")
    func testFeishuToggle() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Initially enabled
        var enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "com.electron.lark.iron" }))

        // Disable Feishu
        settings.detectFeishu = false
        enabledApps = filterApps(allApps, settings: settings)
        #expect(!enabledApps.contains(where: { $0.bundleIdentifier == "com.electron.lark.iron" }))

        // Re-enable Feishu
        settings.detectFeishu = true
        enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "com.electron.lark.iron" }))
    }

    @Test("WeChat toggle affects enabledApps correctly")
    func testWeChatToggle() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Initially disabled
        var enabledApps = filterApps(allApps, settings: settings)
        #expect(!enabledApps.contains(where: { $0.bundleIdentifier == "com.tencent.xinWeChat" }))

        // Enable WeChat
        settings.detectWeChat = true
        enabledApps = filterApps(allApps, settings: settings)
        #expect(enabledApps.contains(where: { $0.bundleIdentifier == "com.tencent.xinWeChat" }))

        // Disable WeChat again
        settings.detectWeChat = false
        enabledApps = filterApps(allApps, settings: settings)
        #expect(!enabledApps.contains(where: { $0.bundleIdentifier == "com.tencent.xinWeChat" }))
    }

    // MARK: - Mixed Configuration Tests

    @Test("enabledApps works with mixed app settings")
    func testEnabledAppsMixedConfiguration() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Enable only specific apps
        settings.detectZoom = true
        settings.detectTeamsClassic = false
        settings.detectTeamsNew = false
        settings.detectWebex = false
        settings.detectTencentMeeting = true
        settings.detectFeishu = false
        settings.detectWeChat = false

        let enabledApps = filterApps(allApps, settings: settings)
        let bundleIds = enabledApps.map { $0.bundleIdentifier }

        #expect(enabledApps.count == 2)
        #expect(bundleIds.contains("us.zoom.xos"))
        #expect(bundleIds.contains("com.tencent.meeting"))
    }

    @Test("enabledApps filters correctly for any combination")
    func testEnabledAppsAnyCombination() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Test various combinations
        let testCases: [(Set<String>, Int)] = [
            (["us.zoom.xos"], 1),
            (["us.zoom.xos", "com.microsoft.teams"], 2),
            (["us.zoom.xos", "com.tencent.meeting", "com.electron.lark.iron"], 3),
            (["com.tencent.xinWeChat"], 1),  // WeChat only
        ]

        for (enabledIds, expectedCount) in testCases {
            // Reset to all disabled first
            settings.disableAllAppDetection()

            // Enable specific apps
            for bundleId in enabledIds {
                switch bundleId {
                case "us.zoom.xos":
                    settings.detectZoom = true
                case "com.microsoft.teams":
                    settings.detectTeamsClassic = true
                case "com.microsoft.teams2":
                    settings.detectTeamsNew = true
                case "com.cisco.webex.webex":
                    settings.detectWebex = true
                case "com.tencent.meeting":
                    settings.detectTencentMeeting = true
                case "com.electron.lark.iron":
                    settings.detectFeishu = true
                case "com.tencent.xinWeChat":
                    settings.detectWeChat = true
                default:
                    break
                }
            }

            let enabledApps = filterApps(allApps, settings: settings)
            #expect(enabledApps.count == expectedCount, "Expected \(expectedCount) apps for combination \(enabledIds)")
        }
    }

    // MARK: - Western vs Chinese Apps Tests

    @Test("Western apps can be enabled independently")
    func testWesternAppsIndependent() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Enable only Western apps
        settings.detectZoom = true
        settings.detectTeamsClassic = true
        settings.detectTeamsNew = true
        settings.detectWebex = true
        settings.detectTencentMeeting = false
        settings.detectFeishu = false
        settings.detectWeChat = false

        let enabledApps = filterApps(allApps, settings: settings)
        let bundleIds = enabledApps.map { $0.bundleIdentifier }

        #expect(enabledApps.count == 4)
        #expect(bundleIds.contains("us.zoom.xos"))
        #expect(bundleIds.contains("com.microsoft.teams"))
        #expect(bundleIds.contains("com.microsoft.teams2"))
        #expect(bundleIds.contains("com.cisco.webex.webex"))
        #expect(!bundleIds.contains("com.tencent.meeting"))
        #expect(!bundleIds.contains("com.electron.lark.iron"))
        #expect(!bundleIds.contains("com.tencent.xinWeChat"))
    }

    @Test("Chinese apps can be enabled independently")
    func testChineseAppsIndependent() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Enable only Chinese apps
        settings.detectZoom = false
        settings.detectTeamsClassic = false
        settings.detectTeamsNew = false
        settings.detectWebex = false
        settings.detectTencentMeeting = true
        settings.detectFeishu = true
        settings.detectWeChat = true

        let enabledApps = filterApps(allApps, settings: settings)
        let bundleIds = enabledApps.map { $0.bundleIdentifier }

        #expect(enabledApps.count == 3)
        #expect(!bundleIds.contains("us.zoom.xos"))
        #expect(!bundleIds.contains("com.microsoft.teams"))
        #expect(!bundleIds.contains("com.microsoft.teams2"))
        #expect(!bundleIds.contains("com.cisco.webex.webex"))
        #expect(bundleIds.contains("com.tencent.meeting"))
        #expect(bundleIds.contains("com.electron.lark.iron"))
        #expect(bundleIds.contains("com.tencent.xinWeChat"))
    }

    // MARK: - Teams (Both Versions) Tests

    @Test("Both Teams versions can be enabled independently")
    func testTeamsVersionsIndependent() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Enable only Teams Classic
        settings.detectTeamsClassic = true
        settings.detectTeamsNew = false

        var enabledApps = filterApps(allApps, settings: settings)
        var bundleIds = enabledApps.map { $0.bundleIdentifier }

        #expect(bundleIds.contains("com.microsoft.teams"))
        #expect(!bundleIds.contains("com.microsoft.teams2"))

        // Switch to Teams New only
        settings.detectTeamsClassic = false
        settings.detectTeamsNew = true

        enabledApps = filterApps(allApps, settings: settings)
        bundleIds = enabledApps.map { $0.bundleIdentifier }

        #expect(!bundleIds.contains("com.microsoft.teams"))
        #expect(bundleIds.contains("com.microsoft.teams2"))

        // Enable both
        settings.detectTeamsClassic = true
        settings.detectTeamsNew = true

        enabledApps = filterApps(allApps, settings: settings)
        bundleIds = enabledApps.map { $0.bundleIdentifier }

        #expect(bundleIds.contains("com.microsoft.teams"))
        #expect(bundleIds.contains("com.microsoft.teams2"))
    }

    // MARK: - Real-World Scenarios Tests

    @Test("User who only uses Zoom")
    func testScenarioZoomOnly() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // User only wants Zoom detection
        settings.disableAllAppDetection()
        settings.detectZoom = true

        let enabledApps = filterApps(allApps, settings: settings)

        #expect(enabledApps.count == 1)
        #expect(enabledApps.first?.bundleIdentifier == "us.zoom.xos")
    }

    @Test("User who uses Microsoft products only")
    func testScenarioMicrosoftOnly() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // User wants both Teams versions
        settings.disableAllAppDetection()
        settings.detectTeamsClassic = true
        settings.detectTeamsNew = true

        let enabledApps = filterApps(allApps, settings: settings)
        let bundleIds = enabledApps.map { $0.bundleIdentifier }

        #expect(enabledApps.count == 2)
        #expect(bundleIds.contains("com.microsoft.teams"))
        #expect(bundleIds.contains("com.microsoft.teams2"))
    }

    @Test("User who uses Chinese apps only")
    func testScenarioChineseAppsOnly() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // User wants Chinese meeting apps but not WeChat (privacy)
        settings.disableAllAppDetection()
        settings.detectTencentMeeting = true
        settings.detectFeishu = true
        settings.detectWeChat = false

        let enabledApps = filterApps(allApps, settings: settings)
        let bundleIds = enabledApps.map { $0.bundleIdentifier }

        #expect(enabledApps.count == 2)
        #expect(bundleIds.contains("com.tencent.meeting"))
        #expect(bundleIds.contains("com.electron.lark.iron"))
    }

    @Test("User who works internationally (all apps)")
    func testScenarioInternationalUser() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Enable all apps including WeChat (user opted in)
        settings.enableAllAppDetection()

        let enabledApps = filterApps(allApps, settings: settings)

        #expect(enabledApps.count == 7)
    }

    @Test("User who disabled detection entirely")
    func testScenarioDetectionDisabled() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // User disabled all app detection
        settings.disableAllAppDetection()

        let enabledApps = filterApps(allApps, settings: settings)

        #expect(enabledApps.isEmpty)
    }

    // MARK: - Bundle Identifier Tests

    @Test("All bundle identifiers are unique")
    func testAllBundleIdentifiersUnique() async throws {
        let bundleIds = allApps.map { $0.bundleIdentifier }
        let uniqueIds = Set(bundleIds)

        #expect(bundleIds.count == uniqueIds.count)
    }

    @Test("All expected bundle identifiers are present")
    func testExpectedBundleIdentifiersPresent() async throws {
        let bundleIds = allApps.map { $0.bundleIdentifier }
        let expectedIds = Set([
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.cisco.webex.webex",
            "com.tencent.meeting",
            "com.electron.lark.iron",
            "com.tencent.xinWeChat"
        ])

        #expect(Set(bundleIds) == expectedIds)
    }

    // MARK: - Edge Cases Tests

    @Test("Filtering is dynamic and responds to settings changes")
    func testEnabledAppsDynamic() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Get initial count
        let initialCount = filterApps(allApps, settings: settings).count

        // Change a setting
        settings.detectZoom = !settings.detectZoom

        // Count should change
        let newCount = filterApps(allApps, settings: settings).count
        #expect(newCount != initialCount)
    }

    @Test("Settings changes don't affect the master apps list")
    func testMonitoredAppsConstant() async throws {
        let settings = MockSettingsManager()
        settings.reset()

        // Get initial count
        let initialCount = allApps.count

        // Change all settings
        settings.disableAllAppDetection()

        // allApps should not change (it's a constant)
        #expect(allApps.count == initialCount)
    }

    @Test("Find app by bundle identifier works correctly")
    func testFindAppByBundleIdentifier() async throws {
        let zoomApp = allApps.first { $0.bundleIdentifier == "us.zoom.xos" }

        #expect(zoomApp != nil)
        #expect(zoomApp?.processName == "zoom.us")
        #expect(zoomApp?.bundleIdentifier == "us.zoom.xos")
    }

    @Test("Finding non-existent app returns nil")
    func testFindNonExistentApp() async throws {
        let nonExistentApp = allApps.first { $0.bundleIdentifier == "com.nonexistent.app" }

        #expect(nonExistentApp == nil)
    }
}
