//
//  UnifiedSettingsView.swift
//  MeetingSonar
//
//  Unified Settings View combining Audio and Smart Detection settings
//  Created for HIG-compliant, accessible preferences interface
//

import SwiftUI

// MARK: - Unified Settings View

/// Main unified settings view that combines audio and smart detection settings
@available(macOS 13.0, *)
struct UnifiedSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var showResetAlert = false
    @State private var showAISettings = false
    @State private var showAbout = false
    @State private var showRestartAlert = false
    @State private var pendingLanguageChange: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                headerView

                VStack(spacing: 24) {
                    // General Section
                    generalSection

                    // Recording Section
                    recordingSection

                    // Smart Detection Section
                    smartDetectionSection

                    // AI Services Section
                    aiServicesSection

                    // Transcripts Section
                    transcriptsSection
                }
                .padding(20)

                // Footer
                footerView
            }
        }
        .frame(minWidth: 650, idealWidth: 700, maxHeight: 700)
        .alert("settings.reset.title", isPresented: $showResetAlert) {
            Button("settings.reset.confirm", role: .destructive) {
                resetToDefaults()
            }
            Button("general.cancel", role: .cancel) { }
        } message: {
            Text("settings.reset.message")
        }
        .alert("settings.language.restart.title", isPresented: $showRestartAlert) {
            Button("general.cancel", role: .cancel) {
                cancelLanguageChange()
            }
            Button("settings.language.restart.confirm", role: .destructive) {
                confirmLanguageChange()
            }
        } message: {
            Text("settings.language.restart.message")
        }
        .sheet(isPresented: $showAISettings) {
            CloudAISettingsView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
                .frame(width: 450, height: 400)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("settings.unified.title")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("settings.unified.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("general.done")
                    .frame(minWidth: 60)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("Button_Done")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - General Section

    private var generalSection: some View {
        SectionContainer(
            icon: "gearshape",
            title: "settings.general.title"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                labeledRow(label: "settings.language.ui") {
                    Picker("", selection: Binding(
                        get: { localizationManager.languagePreference },
                        set: { newValue in
                            handleLanguageChange(newValue)
                        }
                    )) {
                        Text("settings.language.system").tag("system")
                        Text("settings.language.english").tag("en")
                        Text("settings.language.chinese").tag("zh-Hans")
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 140)
                }
                .accessibilityIdentifier("Picker_UI_Language")

                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.language.ui.explanation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
            }
        }
    }

    // MARK: - Recording Section

    private var recordingSection: some View {
        SectionContainer(
            icon: "waveform",
            title: "settings.recording.title"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Recording Quality
                labeledRow(label: "settings.recording.quality") {
                    Picker("", selection: $settings.audioQuality) {
                        ForEach(AudioQuality.allCases, id: \.self) { quality in
                            Text(quality.localizedDisplayName).tag(quality)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 180)
                }
                .accessibilityIdentifier("Picker_AudioQuality")

                Divider()

                // Audio Sources for Auto Recording
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.recording.autoConfig")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        Toggle(isOn: bindingForAuto(\.includeSystemAudio)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("settings.audio.systemAudio")
                                    .font(.body)
                                Text("settings.audio.systemAudio.hint")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("Toggle_AutoSystemAudio")

                        Toggle(isOn: bindingForAuto(\.includeMicrophone)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("settings.audio.microphone")
                                    .font(.body)
                                Text("settings.audio.microphone.hint")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("Toggle_AutoMicrophone")
                    }
                }

                Divider()

                // Audio Sources for Manual Recording
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.recording.manualConfig")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        Toggle(isOn: bindingForManual(\.includeSystemAudio)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("settings.audio.systemAudio")
                                    .font(.body)
                                Text("settings.audio.systemAudio.hint")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("Toggle_ManualSystemAudio")

                        Toggle(isOn: bindingForManual(\.includeMicrophone)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("settings.audio.microphone")
                                    .font(.body)
                                Text("settings.audio.microphone.hint")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("Toggle_ManualMicrophone")
                    }
                }

                Divider()

                // Auto Split
                Toggle("settings.recording.autoSplit", isOn: .constant(true))
                    .disabled(true)
                    .help("settings.recording.autoSplit.hint")
                    .accessibilityIdentifier("Toggle_AutoSplit")
            }
        }
    }

    // MARK: - Smart Detection Section

    private var smartDetectionSection: some View {
        SectionContainer(
            icon: "brain.head.profile",
            title: "settings.smartDetection.title"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Enable Smart Detection
                Toggle("settings.smartDetection.enable", isOn: $settings.smartDetectionEnabled)
                    .accessibilityIdentifier("Toggle_SmartDetection")

                if settings.smartDetectionEnabled {
                    Divider()

                    // Action Mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.smartDetection.whenDetected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("", selection: $settings.smartDetectionMode) {
                            ForEach(SettingsManager.SmartDetectionMode.allCases) { mode in
                                Text(mode.localizedDisplayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("Picker_SmartDetectionMode")

                        Text(modeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    // App Detection List
                    VStack(alignment: .leading, spacing: 12) {
                        Text("settings.smartDetection.monitorApps")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 0) {
                            AppDetectionToggleRow(
                                appName: "Zoom",
                                bundleIdentifier: "us.zoom.xos",
                                isEnabled: bindingForApp("us.zoom.xos"),
                                icon: "video.badge.ellipsis"
                            )

                            Divider()
                                .padding(.leading, 52)

                            AppDetectionToggleRow(
                                appName: "Microsoft Teams",
                                subtitle: "settings.smartDetection.teams.classic",
                                bundleIdentifier: "com.microsoft.teams",
                                isEnabled: bindingForApp("com.microsoft.teams"),
                                icon: "person.2.fill"
                            )

                            Divider()
                                .padding(.leading, 42)

                            AppDetectionToggleRow(
                                appName: "Microsoft Teams",
                                subtitle: "settings.smartDetection.teams.new",
                                bundleIdentifier: "com.microsoft.teams2",
                                isEnabled: bindingForApp("com.microsoft.teams2"),
                                icon: "person.2.fill"
                            )

                            Divider()
                                .padding(.leading, 42)

                            AppDetectionToggleRow(
                                appName: "Webex",
                                bundleIdentifier: "com.cisco.webex.webex",
                                isEnabled: bindingForApp("com.cisco.webex.webex"),
                                icon: "video.fill"
                            )

                            Divider()
                                .padding(.leading, 42)

                            AppDetectionToggleRow(
                                appName: "Tencent Meeting",
                                subtitle: "腾讯会议",
                                bundleIdentifier: "com.tencent.meeting",
                                isEnabled: $settings.detectTencentMeeting,
                                icon: "video.bubble.left.fill"
                            )

                            Divider()
                                .padding(.leading, 42)

                            AppDetectionToggleRow(
                                appName: "Feishu / Lark",
                                subtitle: "飞书",
                                bundleIdentifier: "com.electron.lark.iron",
                                isEnabled: $settings.detectFeishu,
                                icon: "text.bubble.fill"
                            )

                            Divider()
                                .padding(.leading, 42)

                            AppDetectionToggleRow(
                                appName: "WeChat Voice Call",
                                subtitle: "微信语音",
                                bundleIdentifier: "com.tencent.xinWeChat",
                                isEnabled: $settings.detectWeChat,
                                icon: "phone.fill",
                                showPrivacyWarning: true
                            )
                        }
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    // MARK: - AI Services Section

    private var aiServicesSection: some View {
        SectionContainer(
            icon: "cloud",
            title: "settings.aiServices.title"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                labeledRow(label: "settings.aiServices.asrModel") {
                    Text(settings.currentASRModel?.name ?? "settings.aiServices.noModel")
                        .foregroundStyle(.secondary)
                    Button("settings.aiServices.configure") {
                        showAISettings = true
                    }
                    .buttonStyle(.bordered)
                }
                .accessibilityIdentifier("Row_ASRModel")

                Divider()

                labeledRow(label: "settings.aiServices.llmModel") {
                    Text(settings.currentLLMModel?.name ?? "settings.aiServices.noModel")
                        .foregroundStyle(.secondary)
                    Button("settings.aiServices.configure") {
                        showAISettings = true
                    }
                    .buttonStyle(.bordered)
                }
                .accessibilityIdentifier("Row_LLMModel")
            }
        }
    }

    // MARK: - Transcripts Section

    private var transcriptsSection: some View {
        SectionContainer(
            icon: "text.alignleft",
            title: "settings.transcripts.title"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("settings.transcripts.autoSummary", isOn: $settings.autoGenerateSummary)
                    .accessibilityIdentifier("Toggle_AutoSummary")

                Divider()

                labeledRow(label: "settings.transcripts.language") {
                    Picker("", selection: $settings.transcriptLanguage) {
                        Text("settings.transcripts.language.auto").tag("auto")
                        Text("settings.transcripts.language.en").tag("en")
                        Text("settings.transcripts.language.zh").tag("zh")
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 140)
                }
                .accessibilityIdentifier("Picker_Language")

                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.transcripts.language.explanation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
            }
        }
    }

    // MARK: - Footer View

    private var footerView: some View {
        HStack {
            Button("settings.reset.button") {
                showResetAlert = true
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("Button_Reset")

            Spacer()

            Button("settings.about.button") {
                showAbout = true
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("Button_About")
        }
        .buttonStyle(.borderless)
        .padding(16)
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Helper Methods

    // MARK: - Language Change Handling

    private func handleLanguageChange(_ newLanguage: String) {
        // Store the pending change
        pendingLanguageChange = newLanguage
        // Show restart confirmation
        showRestartAlert = true
    }

    private func confirmLanguageChange() {
        guard let newLanguage = pendingLanguageChange else { return }

        // Update language preference BEFORE applying system changes
        localizationManager.languagePreference = newLanguage

        // Apply language change (sets AppleLanguages)
        _ = localizationManager.setLanguage(newLanguage)

        // Relaunch the app
        localizationManager.relaunchApp()
    }

    private func cancelLanguageChange() {
        // Revert to current preference
        pendingLanguageChange = nil
    }

    private var modeDescription: String {
        switch settings.smartDetectionMode {
        case .auto:
            return String(localized: "settings.smartDetection.mode.auto.description")
        case .remind:
            return String(localized: "settings.smartDetection.mode.remind.description")
        }
    }

    private func bindingForAuto(_ keyPath: WritableKeyPath<AudioSourceConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.autoRecordingDefaultConfig[keyPath: keyPath] },
            set: { settings.autoRecordingDefaultConfig[keyPath: keyPath] = $0 }
        )
    }

    private func bindingForManual(_ keyPath: WritableKeyPath<AudioSourceConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.manualRecordingDefaultConfig[keyPath: keyPath] },
            set: { settings.manualRecordingDefaultConfig[keyPath: keyPath] = $0 }
        )
    }

    private func bindingForApp(_ bundleIdentifier: String) -> Binding<Bool> {
        switch bundleIdentifier {
        case "us.zoom.xos":
            return $settings.detectZoom
        case "com.microsoft.teams":
            return $settings.detectTeamsClassic
        case "com.microsoft.teams2":
            return $settings.detectTeamsNew
        case "com.cisco.webex.webex":
            return $settings.detectWebex
        default:
            return .constant(true)
        }
    }

    private func resetToDefaults() {
        // Reset settings to defaults
        settings.smartDetectionEnabled = true
        settings.smartDetectionMode = .remind
        settings.audioQuality = .high
        settings.detectZoom = true
        settings.detectTeamsClassic = true
        settings.detectTeamsNew = true
        settings.detectWebex = true
        settings.detectTencentMeeting = true
        settings.detectFeishu = true
        settings.detectWeChat = false
    }

    // MARK: - Labeled Row

    @ViewBuilder
    private func labeledRow<Content: View>(
        label: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.body)
            Spacer()
            content()
        }
    }
}

// MARK: - Section Container

@available(macOS 13.0, *)
struct SectionContainer<Content: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let content: Content

    init(
        icon: String,
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)

            // Section Content
            content
                .padding(16)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - App Detection Toggle Row

@available(macOS 13.0, *)
struct AppDetectionToggleRow: View {
    let appName: String
    let subtitle: LocalizedStringKey?
    let bundleIdentifier: String
    @Binding var isEnabled: Bool
    let icon: String
    var showPrivacyWarning: Bool = false

    init(
        appName: String,
        subtitle: LocalizedStringKey? = nil,
        bundleIdentifier: String,
        isEnabled: Binding<Bool>,
        icon: String,
        showPrivacyWarning: Bool = false
    ) {
        self.appName = appName
        self.subtitle = subtitle
        self.bundleIdentifier = bundleIdentifier
        self._isEnabled = isEnabled
        self.icon = icon
        self.showPrivacyWarning = showPrivacyWarning
    }

    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            // App Info
            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(.body)
                    .fontWeight(.medium)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showPrivacyWarning {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("settings.smartDetection.privacyWarning")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }
            }

            Spacer()

            // Toggle
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appName) \(subtitle ?? "")")
        .accessibilityHint(showPrivacyWarning
            ? String(localized: "settings.smartDetection.privacyWarning")
            : "")
        .accessibilityIdentifier("Toggle_App_\(bundleIdentifier)")
    }
}

// MARK: - Preview

@available(macOS 13.0, *)
struct UnifiedSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedSettingsView()
    }
}
