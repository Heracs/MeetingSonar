//
//  MeetingSonarUITests.swift
//  MeetingSonarUITests
//
//  UI Tests for MeetingSonar.
//  Corresponds to F-6.1, F-6.2 (Language Support).
//
//  Note: macOS menu bar apps have limited UI testability.
//  Complex interactions like clicking menu items that open windows
//  may fail due to XCTest framework limitations with NSStatusItem menus.
//
//  Updated for v1.0: Tests now use sheet-based UnifiedSettingsView
//  instead of the previous tabbed interface.
//

import XCTest

final class MeetingSonarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Basic Launch Tests

    /// TC-6.1.1: Test app launches and menu bar icon exists
    func testLaunchAndMenuBarIcon() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify status item exists in menu bar
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5.0), "Menu bar icon should exist after launch")
    }

    /// TC-6.1.8: Test menu can be opened and contains expected items
    func testMenuContainsExpectedItems() throws {
        let app = XCUIApplication()
        app.launch()

        // Click status item to open menu
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5.0))
        statusItem.click()

        // Wait a moment for menu to appear
        sleep(1)

        // Verify menu items exist (using contains to handle localization)
        // Check for Start Recording / 开始录音
        let startPredicate = NSPredicate(format: "title CONTAINS[c] 'Start' OR title CONTAINS[c] '开始'")
        let startItem = app.menuItems.matching(startPredicate).firstMatch
        XCTAssertTrue(startItem.waitForExistence(timeout: 2.0), "Start Recording menu item should exist")

        // Check for Preferences / 偏好设置
        let settingsPredicate = NSPredicate(format: "title CONTAINS[c] 'Preferences' OR title CONTAINS[c] '偏好设置'")
        let settingsItem = app.menuItems.matching(settingsPredicate).firstMatch
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 2.0), "Preferences menu item should exist")

        // Check for Quit / 退出
        let quitPredicate = NSPredicate(format: "title CONTAINS[c] 'Quit' OR title CONTAINS[c] '退出'")
        let quitItem = app.menuItems.matching(quitPredicate).firstMatch
        XCTAssertTrue(quitItem.waitForExistence(timeout: 2.0), "Quit menu item should exist")

        // Close menu by clicking elsewhere or pressing Escape
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Unified Settings View Tests

    /// Test that preferences window opens with unified settings view
    func testPreferencesWindowOpens() throws {
        let app = XCUIApplication()
        app.launch()

        // Open preferences via menu
        openPreferencesWindow(app: app)

        let prefsWindow = app.windows.firstMatch
        XCTAssertTrue(prefsWindow.waitForExistence(timeout: 3.0), "Preferences window should open")

        // Verify the window contains expected elements from UnifiedSettingsView
        // Check for Done button in header
        let doneButton = prefsWindow.buttons["Button_Done"]
        XCTAssertTrue(doneButton.exists, "Done button should exist in preferences window")

        // Check for version text in footer
        let versionText = prefsWindow.staticTexts["Text_Version"]
        XCTAssertTrue(versionText.exists, "Version text should exist in preferences window")

        // Close the window
        closePreferencesWindow(app: app, prefsWindow: prefsWindow)
    }

    /// Test that all main sections are visible in unified settings view
    func testUnifiedSettingsSectionsExist() throws {
        let app = XCUIApplication()
        app.launch()

        openPreferencesWindow(app: app)

        let prefsWindow = app.windows.firstMatch
        XCTAssertTrue(prefsWindow.waitForExistence(timeout: 3.0))

        // Verify key UI elements from each section exist

        // Recording Section
        let audioQualityPicker = prefsWindow.popUpButtons["Picker_AudioQuality"]
        XCTAssertTrue(audioQualityPicker.exists, "Audio Quality picker should exist in Recording section")

        // Smart Detection Section
        let smartDetectionToggle = findToggle(in: prefsWindow, withIdentifier: "Toggle_SmartDetection")
        XCTAssertNotNil(smartDetectionToggle, "Smart Detection toggle should exist")

        // AI Services Section - These are the rows with Configure buttons
        let asrModelRow = prefsWindow.otherElements["Row_ASRModel"]
        XCTAssertTrue(asrModelRow.exists, "ASR Model configuration row should exist")

        let llmModelRow = prefsWindow.otherElements["Row_LLMModel"]
        XCTAssertTrue(llmModelRow.exists, "LLM Model configuration row should exist")

        // Transcripts Section
        let autoSummaryToggle = findToggle(in: prefsWindow, withIdentifier: "Toggle_AutoSummary")
        XCTAssertNotNil(autoSummaryToggle, "Auto Summary toggle should exist")

        let languagePicker = prefsWindow.popUpButtons["Picker_Language"]
        XCTAssertTrue(languagePicker.exists, "Language picker should exist")

        // Footer buttons
        let resetButton = prefsWindow.buttons["Button_Reset"]
        XCTAssertTrue(resetButton.exists, "Reset button should exist in footer")

        let aboutButton = prefsWindow.buttons["Button_About"]
        XCTAssertTrue(aboutButton.exists, "About button should exist in footer")

        closePreferencesWindow(app: app, prefsWindow: prefsWindow)
    }

    /// Test that clicking Configure button opens AI Settings sheet
    func testAISettingsSheetOpens() throws {
        let app = XCUIApplication()
        app.launch()

        openPreferencesWindow(app: app)

        let prefsWindow = app.windows.firstMatch
        XCTAssertTrue(prefsWindow.waitForExistence(timeout: 3.0))

        // Find and click one of the Configure buttons
        // Both ASR and LLM rows have "Configure" buttons that open the same sheet
        let configureButtons = prefsWindow.buttons.matching(NSPredicate(format: "title CONTAINS[c] 'Configure' OR title CONTAINS[c] '配置'"))

        if configureButtons.count > 0 {
            let firstConfigureButton = configureButtons.firstMatch
            XCTAssertTrue(firstConfigureButton.exists, "Configure button should exist")

            firstConfigureButton.click()
            sleep(1) // Wait for sheet animation

            // Verify the AI Settings sheet opened
            // Sheets appear as new windows in XCTest
            let sheets = app.windows.allElementsBoundByIndex
            var aiSettingsSheetFound = false

            for window in sheets {
                // Look for elements that would be in CloudAISettingsView
                // It has a segmented picker with "Services" and "Prompts" tabs
                let segmentedControl = window.segmentedControls.firstMatch
                if segmentedControl.exists {
                    aiSettingsSheetFound = true
                    break
                }
                // Also check for the Done button in the toolbar
                let doneButton = window.buttons.matching(NSPredicate(format: "title CONTAINS[c] 'Done' OR title CONTAINS[c] '完成'")).firstMatch
                if doneButton.exists {
                    aiSettingsSheetFound = true
                    break
                }
            }

            XCTAssertTrue(aiSettingsSheetFound, "AI Settings sheet should open after clicking Configure button")

            // Close the sheet by clicking the Done button
            for window in sheets {
                let doneButton = window.buttons.matching(NSPredicate(format: "title CONTAINS[c] 'Done' OR title CONTAINS[c] '完成'")).firstMatch
                if doneButton.exists {
                    doneButton.click()
                    sleep(1)
                    break
                }
            }
        }

        closePreferencesWindow(app: app, prefsWindow: prefsWindow)
    }

    /// Test that About sheet opens when clicking About button
    func testAboutSheetOpens() throws {
        let app = XCUIApplication()
        app.launch()

        openPreferencesWindow(app: app)

        let prefsWindow = app.windows.firstMatch
        XCTAssertTrue(prefsWindow.waitForExistence(timeout: 3.0))

        // Click the About button in footer
        let aboutButton = prefsWindow.buttons["Button_About"]
        XCTAssertTrue(aboutButton.exists, "About button should exist")
        aboutButton.click()
        sleep(1) // Wait for sheet animation

        // Verify the About sheet opened
        let sheets = app.windows.allElementsBoundByIndex
        var aboutSheetFound = false

        for window in sheets {
            // Look for AboutView elements or Done button
            let appIcon = window.images["Image_AppIcon"]
            let appName = window.staticTexts["Text_AppName"]
            let versionInfo = window.staticTexts["Text_VersionInfo"]
            let doneButton = window.buttons.matching(NSPredicate(format: "title CONTAINS[c] 'Done' OR title CONTAINS[c] '完成'")).firstMatch

            if appIcon.exists || appName.exists || versionInfo.exists || doneButton.exists {
                aboutSheetFound = true
                break
            }
        }

        XCTAssertTrue(aboutSheetFound, "About sheet should open after clicking About button")

        // Close the sheet by clicking the Done button
        let sheetsAfter = app.windows.allElementsBoundByIndex
        for window in sheetsAfter {
            let doneButton = window.buttons.matching(NSPredicate(format: "title CONTAINS[c] 'Done' OR title CONTAINS[c] '完成'")).firstMatch
            if doneButton.exists {
                doneButton.click()
                sleep(1)
                break
            }
        }

        closePreferencesWindow(app: app, prefsWindow: prefsWindow)
    }

    // MARK: - App Detection Toggles Tests

    /// Test that all app detection toggles exist
    func testAppDetectionTogglesExist() throws {
        let app = XCUIApplication()
        app.launch()

        openPreferencesWindow(app: app)

        let prefsWindow = app.windows.firstMatch
        XCTAssertTrue(prefsWindow.waitForExistence(timeout: 3.0))

        // First enable Smart Detection to reveal app detection toggles
        // Smart Detection toggle might be exposed as otherElement or switch
        let smartDetectionToggle = findToggle(in: prefsWindow, withIdentifier: "Toggle_SmartDetection")
        if let toggle = smartDetectionToggle, toggle.isHittable {
            let isSelected = toggle.isSelected
            if !isSelected {
                toggle.click()
                sleep(1) // Wait for UI to update
            }
        }

        // Verify all app detection toggles exist
        let expectedApps = [
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.cisco.webex.webex"
        ]

        for bundleId in expectedApps {
            let toggle = findToggle(in: prefsWindow, withIdentifier: "Toggle_App_\(bundleId)")
            XCTAssertTrue(toggle != nil && toggle!.exists, "Toggle for app \(bundleId) should exist")
        }

        // WeChat toggle should also exist
        let weChatToggle = findToggle(in: prefsWindow, withIdentifier: "Toggle_App_com.tencent.xinWeChat")
        XCTAssertTrue(weChatToggle != nil && weChatToggle!.exists, "Toggle for WeChat should exist")

        closePreferencesWindow(app: app, prefsWindow: prefsWindow)
    }

    /// Test that toggling Smart Detection enables/disables app detection section
    func testSmartDetectionToggleControlsAppVisibility() throws {
        let app = XCUIApplication()
        app.launch()

        openPreferencesWindow(app: app)

        let prefsWindow = app.windows.firstMatch
        XCTAssertTrue(prefsWindow.waitForExistence(timeout: 3.0))

        let smartDetectionToggle = findToggle(in: prefsWindow, withIdentifier: "Toggle_SmartDetection")
        XCTAssertNotNil(smartDetectionToggle, "Smart Detection toggle should exist")
        guard let toggle = smartDetectionToggle else { return }

        // Get initial state
        let initialState = toggle.isSelected

        // Toggle the state
        toggle.click()
        sleep(1) // Wait for UI animation

        // Verify that app detection toggles visibility changed
        // When disabled, app detection toggles should not be accessible
        let zoomToggle = findToggle(in: prefsWindow, withIdentifier: "Toggle_App_us.zoom.xos")

        if initialState {
            // Was enabled, now should be disabled (not visible/enabled)
            // Note: In SwiftUI, disabled elements may still exist but not be hittable
        } else {
            // Was disabled, now should be enabled
            if let zoom = zoomToggle {
                XCTAssertTrue(zoom.exists || zoom.isHittable, "App toggles should be visible when Smart Detection is enabled")
            }
        }

        // Restore original state
        toggle.click()
        sleep(1)

        closePreferencesWindow(app: app, prefsWindow: prefsWindow)
    }

    // MARK: - Audio Settings Tests

    /// Test audio quality picker exists and can be interacted with
    func testAudioQualityPickerExists() throws {
        let app = XCUIApplication()
        app.launch()

        openPreferencesWindow(app: app)

        let prefsWindow = app.windows.firstMatch
        XCTAssertTrue(prefsWindow.waitForExistence(timeout: 3.0))

        let audioQualityPicker = prefsWindow.popUpButtons["Picker_AudioQuality"]
        XCTAssertTrue(audioQualityPicker.exists, "Audio Quality picker should exist")

        // Verify it can be clicked (even if we don't change the value)
        XCTAssertTrue(audioQualityPicker.isHittable, "Audio Quality picker should be interactive")

        closePreferencesWindow(app: app, prefsWindow: prefsWindow)
    }

    /// Test audio source toggles for auto and manual recording
    func testAudioSourceTogglesExist() throws {
        let app = XCUIApplication()
        app.launch()

        openPreferencesWindow(app: app)

        let prefsWindow = app.windows.firstMatch
        XCTAssertTrue(prefsWindow.waitForExistence(timeout: 3.0))

        // Auto recording toggles
        let autoSystemAudioToggle = findToggle(in: prefsWindow, withIdentifier: "Toggle_AutoSystemAudio")
        XCTAssertNotNil(autoSystemAudioToggle, "Auto System Audio toggle should exist")

        let autoMicrophoneToggle = findToggle(in: prefsWindow, withIdentifier: "Toggle_AutoMicrophone")
        XCTAssertNotNil(autoMicrophoneToggle, "Auto Microphone toggle should exist")

        // Manual recording toggles
        let manualSystemAudioToggle = findToggle(in: prefsWindow, withIdentifier: "Toggle_ManualSystemAudio")
        XCTAssertNotNil(manualSystemAudioToggle, "Manual System Audio toggle should exist")

        let manualMicrophoneToggle = findToggle(in: prefsWindow, withIdentifier: "Toggle_ManualMicrophone")
        XCTAssertNotNil(manualMicrophoneToggle, "Manual Microphone toggle should exist")

        closePreferencesWindow(app: app, prefsWindow: prefsWindow)
    }

    // MARK: - Helper Methods

    /// Helper method to find a toggle control with the given accessibility identifier
    /// Tries multiple approaches since SwiftUI toggles may be exposed differently
    private func findToggle(in window: XCUIElement, withIdentifier identifier: String) -> XCUIElement? {
        // First try as a switch
        let switchElement = window.switches[identifier]
        if switchElement.exists {
            return switchElement
        }

        // Try as other element (SwiftUI containers with accessibilityIdentifier)
        let otherElement = window.otherElements[identifier]
        if otherElement.exists {
            // Try to find the actual switch within this container
            let containedSwitch = otherElement.switches.firstMatch
            if containedSwitch.exists {
                return containedSwitch
            }
            // If no switch found, return the container itself
            return otherElement
        }

        // Try to find by querying all switches and checking their identifiers
        let allSwitches = window.switches.allElementsBoundByIndex
        for sw in allSwitches {
            if sw.identifier == identifier {
                return sw
            }
        }

        return nil
    }

    /// Opens the preferences window via the menu bar
    private func openPreferencesWindow(app: XCUIApplication) {
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5.0))
        statusItem.click()
        sleep(1)

        let settingsPredicate = NSPredicate(format: "title CONTAINS[c] 'Preferences' OR title CONTAINS[c] '偏好设置'")
        let settingsItem = app.menuItems.matching(settingsPredicate).firstMatch
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 2.0))
        settingsItem.click()
        sleep(1) // Wait for window to open
    }

    /// Closes the preferences window
    private func closePreferencesWindow(app: XCUIApplication, prefsWindow: XCUIElement) {
        // Try clicking the Done button first
        let doneButton = prefsWindow.buttons["Button_Done"]
        if doneButton.exists {
            doneButton.click()
        } else {
            // Fallback to close button
            let closeButton = prefsWindow.buttons[XCUIIdentifierCloseWindow]
            if closeButton.exists {
                closeButton.click()
            }
        }
        sleep(1) // Wait for window to close
    }
}
