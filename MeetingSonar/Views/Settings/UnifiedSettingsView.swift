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
    @State private var hotwordsText: String = ""
    @State private var hotwordsSaveTask: Task<Void, Never>?
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

                Divider()

                Toggle(isOn: $settings.enableDebugLogging) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.general.debugLogging")
                            .font(.body)
                        Text("settings.general.debugLogging.hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("Toggle_DebugLogging")
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

                // Max Recording Duration
                labeledRow(label: "settings.recording.maxDuration") {
                    HStack(spacing: 8) {
                        Stepper(
                            value: $settings.maxRecordingDurationMinutes,
                            in: 5...180,
                            step: 5
                        ) {
                            EmptyView()
                        }
                        .labelsHidden()
                        Text("\(settings.maxRecordingDurationMinutes) min")
                            .monospacedDigit()
                            .frame(minWidth: 60, alignment: .trailing)
                    }
                }

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

                            // F-0.10.2: Unified Teams toggle (controls both Classic and New)
                            AppDetectionToggleRow(
                                appName: "Microsoft Teams",
                                subtitle: "settings.smartDetection.teams.unified",
                                bundleIdentifier: "com.microsoft.teams",
                                isEnabled: $settings.detectTeams,
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

    @State private var aiModels: [CloudAIModelConfig] = []

    private var aiServicesSection: some View {
        SectionContainer(
            icon: "cloud",
            title: "settings.aiServices.title"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if aiModels.isEmpty {
                    // Empty state
                    HStack {
                        Text("settings.aiServices.noModelsConfigured")
                            .foregroundStyle(.secondary)
                            .font(.body)
                        Spacer()
                        Button("settings.aiServices.configure") {
                            showAISettings = true
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    // Model list
                    ForEach(aiModels) { model in
                        aiModelRow(model)
                        if model.id != aiModels.last?.id {
                            Divider()
                        }
                    }

                    Divider()

                    // Footer: model count + configure button
                    HStack {
                        Text("\(aiModels.count) \(String(localized: "settings.aiServices.modelCount", defaultValue: "个模型已配置"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("settings.aiServices.configure") {
                            showAISettings = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .task {
            await loadAIModels()
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudAIModelManager.modelsDidChange)) { _ in
            Task { await loadAIModels() }
        }
    }

    @ViewBuilder
    private func aiModelRow(_ model: CloudAIModelConfig) -> some View {
        let isActiveASR = model.id.uuidString == settings.selectedUnifiedASRId
        let isActiveLLM = model.id.uuidString == settings.selectedUnifiedLLMId

        HStack(alignment: .center, spacing: 8) {
            // Verification status icon
            Image(systemName: model.isVerified ? "checkmark.circle.fill" : "circle")
                .foregroundColor(model.isVerified ? .green : .secondary.opacity(0.5))
                .font(.body)
                .help(model.isVerified
                    ? String(localized: "settings.aiServices.verified", defaultValue: "已验证")
                    : String(localized: "settings.aiServices.notVerified", defaultValue: "未验证"))

            // Model name + provider
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.body)
                    .lineLimit(1)
                Text(model.provider.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Active indicator
            if isActiveASR || isActiveLLM {
                let activeLabels = [
                    isActiveASR ? "ASR" : nil,
                    isActiveLLM ? "LLM" : nil
                ].compactMap { $0 }.joined(separator: "+")

                Text(String(localized: "settings.aiServices.active", defaultValue: "当前 \(activeLabels)"))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(4)
            }

            // Capability badges
            HStack(spacing: 4) {
                ForEach(Array(model.capabilities).sorted(by: { $0.rawValue < $1.rawValue })) { capability in
                    Text(capability.rawValue.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .cornerRadius(3)
                }
            }
        }
        .accessibilityIdentifier("Row_AIModel_\(model.id.uuidString)")
    }

    private func loadAIModels() async {
        let models = await CloudAIModelManager.shared.models
        await MainActor.run {
            self.aiModels = models
        }
    }

    // MARK: - Transcripts Section

    private var transcriptsSection: some View {
        SectionContainer(
            icon: "text.alignleft",
            title: "settings.transcripts.title"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // F-0.10.4: Auto Processing Mode Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.autoProcess.label")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $settings.autoProcessingMode) {
                        ForEach(AutoProcessingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(settings.autoProcessingMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("Picker_AutoProcess")

                Divider()

                // F-0.10.14: ASR Hotwords Editor
                hotwordsEditor
            }
        }
    }

    // MARK: - Hotwords Editor (F-0.10.14)

    /// Hotwords count parsed from current text
    private var hotwordsCount: Int {
        hotwordsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private var hotwordsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("settings.asr.hotwords.title")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(hotwordsCount)/\(ZhipuASRLimits.maxHotwords)")
                    .font(.caption)
                    .foregroundStyle(hotwordsCount > ZhipuASRLimits.maxHotwords ? .red : .secondary)
                    .accessibilityLabel("\(hotwordsCount) of \(ZhipuASRLimits.maxHotwords) hotwords configured")
            }

            TextEditor(text: $hotwordsText)
                .font(.body.monospaced())
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.separatorColor), lineWidth: 1)
                )
                .accessibilityIdentifier("TextEditor_ASRHotwords")
                .accessibilityLabel(String(localized: "settings.asr.hotwords.title", defaultValue: "ASR Hotwords"))
                .onChange(of: hotwordsText) { _ in
                    // Debounced save: cancel previous task, wait 0.5s, then save
                    hotwordsSaveTask?.cancel()
                    hotwordsSaveTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled else { return }
                        saveHotwordsFromText()
                    }
                }
                .onAppear {
                    hotwordsText = settings.asrHotwords.joined(separator: "\n")
                }

            Text("settings.asr.hotwords.description")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Parse text lines into hotwords array and save to SettingsManager
    private func saveHotwordsFromText() {
        var seen = Set<String>()
        let words = hotwordsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.replacingOccurrences(of: ",", with: "") } // Strip commas to avoid API parsing issues
            .filter { seen.insert($0).inserted } // Deduplicate preserving order
        let truncated = Array(words.prefix(ZhipuASRLimits.maxHotwords))
        settings.asrHotwords = truncated
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
        case "com.microsoft.teams", "com.microsoft.teams2":
            // F-0.10.2: Both Teams IDs use unified toggle
            return $settings.detectTeams
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
        settings.detectTeams = true  // F-0.10.2: Use unified property
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
