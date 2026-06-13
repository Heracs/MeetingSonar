import SwiftUI

struct AIProviderConfigFormValidator {
    func validateWhisperCpp(
        displayName: String,
        executablePath: String,
        modelPath: String
    ) -> AIProviderValidationResult {
        guard !displayName.trimmedForProviderForm.isEmpty else {
            return AIProviderValidationResult(
                isValid: false,
                message: String(localized: "aiProvider.validation.displayNameRequired")
            )
        }
        guard !executablePath.trimmedForProviderForm.isEmpty else {
            return AIProviderValidationResult(
                isValid: false,
                message: String(localized: "aiProvider.validation.whisperExecutableRequired")
            )
        }
        guard !modelPath.trimmedForProviderForm.isEmpty else {
            return AIProviderValidationResult(
                isValid: false,
                message: String(localized: "aiProvider.validation.whisperModelRequired")
            )
        }

        return AIProviderValidationResult(
            isValid: true,
            message: String(localized: "aiProvider.validation.ready")
        )
    }

    func validateCloud(
        displayName: String,
        apiKey: String,
        enableASR: Bool,
        enableLLM: Bool,
        provider: OnlineServiceProvider
    ) -> AIProviderValidationResult {
        guard !displayName.trimmedForProviderForm.isEmpty else {
            return AIProviderValidationResult(
                isValid: false,
                message: String(localized: "aiProvider.validation.displayNameRequired")
            )
        }
        guard !apiKey.trimmedForProviderForm.isEmpty else {
            return AIProviderValidationResult(
                isValid: false,
                message: String(localized: "aiProvider.validation.apiKeyRequired")
            )
        }
        guard enableASR || enableLLM else {
            return AIProviderValidationResult(
                isValid: false,
                message: String(localized: "aiProvider.validation.capabilityRequired")
            )
        }
        guard !enableASR || provider.supportsASR else {
            return AIProviderValidationResult(
                isValid: false,
                message: String(localized: "aiProvider.validation.providerDoesNotSupportASR")
            )
        }

        return AIProviderValidationResult(
            isValid: true,
            message: String(localized: "aiProvider.validation.ready")
        )
    }
}

@available(macOS 13.0, *)
struct AIProviderConfigSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingConfig: AIProviderConfig?
    var onSaved: () -> Void = {}

    @State private var mode: ProviderFormMode = .localWhisperCpp
    @State private var displayName = ""

    @State private var executablePath = ""
    @State private var modelPath = ""
    @State private var language = "zh"

    @State private var provider: OnlineServiceProvider = .deepseek
    @State private var baseURL = OnlineServiceProvider.deepseek.defaultBaseURL
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var enableASR = false
    @State private var enableLLM = true
    @State private var asrModelName = ""
    @State private var llmModelName = OnlineServiceProvider.deepseek.defaultLLMModel

    @State private var verificationState: ProviderVerificationState = .notVerified
    @State private var isVerifying = false
    @State private var showError = false
    @State private var errorMessage = ""

    private let validator = AIProviderConfigFormValidator()

    private var validation: AIProviderValidationResult {
        switch mode {
        case .localWhisperCpp:
            return validator.validateWhisperCpp(
                displayName: displayName,
                executablePath: executablePath,
                modelPath: modelPath
            )
        case .cloudAPI:
            return validator.validateCloud(
                displayName: displayName,
                apiKey: apiKey,
                enableASR: enableASR,
                enableLLM: enableLLM,
                provider: provider
            )
        }
    }

    private var canSave: Bool {
        validation.isValid && !isVerifying
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    basicSection

                    switch mode {
                    case .localWhisperCpp:
                        whisperSection
                    case .cloudAPI:
                        cloudSection
                    }

                    validationSection
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 580, height: 680)
        .onAppear(perform: loadExistingConfig)
        .alert("aiProvider.form.saveFailed", isPresented: $showError) {
            Button("general.ok", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: mode.icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(existingConfig == nil ? "aiProvider.form.addTitle" : "aiProvider.form.editTitle"))
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("aiProvider.form.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(Text("general.close"))
        }
        .padding(20)
    }

    private var basicSection: some View {
        ProviderFormSection(titleKey: "aiProvider.form.section.basic", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 12) {
                ProviderTextField(
                    labelKey: "aiProvider.form.displayName",
                    placeholderKey: "aiProvider.form.displayName.placeholder",
                    text: $displayName
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("aiProvider.form.providerType")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $mode) {
                        ForEach(ProviderFormMode.allCases) { item in
                            Label(item.titleKey, systemImage: item.icon)
                                .tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(existingConfig != nil)
                }
            }
        }
    }

    private var whisperSection: some View {
        ProviderFormSection(titleKey: "aiProvider.form.section.whisper", icon: "waveform") {
            VStack(alignment: .leading, spacing: 12) {
                ProviderTextField(
                    labelKey: "aiProvider.form.whisper.executable",
                    placeholderKey: "aiProvider.form.whisper.executable.placeholder",
                    text: $executablePath
                )

                HStack {
                    Button {
                        detectWhisperExecutable()
                    } label: {
                        Label("aiProvider.form.whisper.detect", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                ProviderTextField(
                    labelKey: "aiProvider.form.whisper.model",
                    placeholderKey: "aiProvider.form.whisper.model.placeholder",
                    text: $modelPath
                )

                ProviderTextField(
                    labelKey: "aiProvider.form.whisper.language",
                    placeholderKey: "aiProvider.form.whisper.language.placeholder",
                    text: $language
                )
            }
        }
    }

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProviderFormSection(titleKey: "aiProvider.form.section.cloud", icon: "cloud") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("aiProvider.form.cloud.provider")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("", selection: $provider) {
                            ForEach(OnlineServiceProvider.allCases) { item in
                                Label {
                                    Text(item.displayName)
                                } icon: {
                                    Image(systemName: item.icon)
                                }
                                .tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(existingConfig != nil)
                        .onChange(of: provider) { newProvider in
                            applyProviderDefaults(newProvider)
                        }
                    }

                    ProviderTextField(
                        labelKey: "aiProvider.form.cloud.baseURL",
                        placeholderKey: "aiProvider.form.cloud.baseURL.placeholder",
                        text: $baseURL
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("aiProvider.form.cloud.apiKey")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Group {
                                if showAPIKey {
                                    TextField("aiProvider.form.cloud.apiKey.placeholder", text: $apiKey)
                                } else {
                                    SecureField("aiProvider.form.cloud.apiKey.placeholder", text: $apiKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)

                            Button {
                                showAPIKey.toggle()
                            } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .frame(width: 18)
                            }
                            .buttonStyle(.borderless)
                            .help(Text(LocalizedStringKey(showAPIKey ? "aiProvider.form.cloud.hideAPIKey" : "aiProvider.form.cloud.showAPIKey")))
                        }
                    }
                }
            }

            ProviderFormSection(titleKey: "aiProvider.form.section.capabilities", icon: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $enableASR) {
                        Label("aiProvider.form.capability.asr", systemImage: "waveform")
                    }
                    .disabled(!provider.supportsASR)
                    .onChange(of: enableASR) { enabled in
                        if enabled && asrModelName.isEmpty {
                            asrModelName = provider.defaultASRModel
                        }
                    }

                    if enableASR && provider.supportsASR {
                        ProviderTextField(
                            labelKey: "aiProvider.form.cloud.asrModel",
                            placeholderKey: "aiProvider.form.cloud.asrModel.placeholder",
                            text: $asrModelName
                        )
                    }

                    Divider()

                    Toggle(isOn: $enableLLM) {
                        Label("aiProvider.form.capability.llm", systemImage: "text.bubble")
                    }
                    .onChange(of: enableLLM) { enabled in
                        if enabled && llmModelName.isEmpty {
                            llmModelName = provider.defaultLLMModel
                        }
                    }

                    if enableLLM {
                        ProviderTextField(
                            labelKey: "aiProvider.form.cloud.llmModel",
                            placeholderKey: "aiProvider.form.cloud.llmModel.placeholder",
                            text: $llmModelName
                        )
                    }
                }
            }
        }
    }

    private var validationSection: some View {
        HStack(spacing: 10) {
            if isVerifying {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: verificationState.icon)
                    .foregroundStyle(verificationState.color)
            }

            Text(verificationState.message)
                .font(.subheadline)
                .foregroundStyle(verificationState.color)
                .lineLimit(2)

            Spacer()

            Button {
                Task { await verifyConfiguration() }
            } label: {
                Label("aiProvider.form.verify", systemImage: "checkmark.shield")
            }
            .buttonStyle(.bordered)
            .disabled(!validation.isValid || isVerifying)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Button("general.cancel") {
                dismiss()
            }

            Spacer()

            Text(validation.message)
                .font(.caption)
                .foregroundStyle(validation.isValid ? Color.secondary : Color.red)
                .lineLimit(2)

            Button {
                Task { await saveConfiguration() }
            } label: {
                Label {
                    Text(LocalizedStringKey(verificationState.isVerified ? "aiProvider.form.save" : "aiProvider.form.saveUnverified"))
                } icon: {
                    Image(systemName: verificationState.isVerified ? "checkmark.circle.fill" : "square.and.arrow.down")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
        .padding(20)
    }

    private func loadExistingConfig() {
        guard let existingConfig else {
            baseURL = provider.defaultBaseURL
            llmModelName = provider.defaultLLMModel
            return
        }

        displayName = existingConfig.displayName
        verificationState = existingConfig.isVerified ? .verified : .notVerified

        if existingConfig.kind == .localCommand {
            mode = .localWhisperCpp
            executablePath = existingConfig.asr?.localCommand?.executablePath ?? ""
            modelPath = existingConfig.asr?.localCommand?.modelPath ?? ""
            language = existingConfig.asr?.language ?? "zh"
            return
        }

        mode = .cloudAPI
        provider = existingConfig.onlineServiceProvider ?? .deepseek
        baseURL = existingConfig.asr?.endpoint?.absoluteString
            ?? existingConfig.llm?.endpoint?.absoluteString
            ?? provider.defaultBaseURL
        enableASR = existingConfig.enabledCapabilities.contains(.asr) && provider.supportsASR
        enableLLM = existingConfig.enabledCapabilities.contains(.llm)
        asrModelName = existingConfig.asr?.modelName ?? provider.defaultASRModel
        llmModelName = existingConfig.llm?.modelName ?? provider.defaultLLMModel

        Task {
            let key = await CloudAIModelManager.shared.getAPIKey(for: existingConfig.id) ?? ""
            await MainActor.run {
                apiKey = key
            }
        }
    }

    private func detectWhisperExecutable() {
        if let detected = WhisperCppDetector().detectExecutable() {
            executablePath = detected.path
            verificationState = .notVerified
        } else {
            verificationState = .failed(String(localized: "aiProvider.validation.whisperExecutableNotFound"))
        }
    }

    private func applyProviderDefaults(_ newProvider: OnlineServiceProvider) {
        baseURL = newProvider.defaultBaseURL
        if !newProvider.supportsASR {
            enableASR = false
            asrModelName = ""
        } else if enableASR {
            asrModelName = newProvider.defaultASRModel
        }
        if enableLLM {
            llmModelName = newProvider.defaultLLMModel
        }
        verificationState = .notVerified
    }

    private func verifyConfiguration() async {
        isVerifying = true
        verificationState = .verifying
        defer { isVerifying = false }

        do {
            switch mode {
            case .localWhisperCpp:
                let result = WhisperCppDetector().validate(config: buildLocalConfig(verified: false))
                verificationState = result.isValid ? .verified : .failed(result.message)
            case .cloudAPI:
                let service = await CloudServiceFactory.shared.createProvider(
                    provider,
                    apiKey: apiKey,
                    baseURL: baseURL.trimmedForProviderForm.isEmpty ? provider.defaultBaseURL : baseURL
                )
                let isValid = try await service.verifyAPIKey()
                verificationState = isValid
                    ? .verified
                    : .failed(String(localized: "aiProvider.validation.apiKeyInvalid"))
            }
        } catch {
            verificationState = .failed(error.localizedDescription)
        }
    }

    private func saveConfiguration() async {
        do {
            switch mode {
            case .localWhisperCpp:
                await AIProviderConfigStore.shared.upsert(buildLocalConfig(verified: verificationState.isVerified))
            case .cloudAPI:
                let cloudConfig = buildCloudConfig(verified: verificationState.isVerified)
                if await CloudAIModelManager.shared.getModel(byId: cloudConfig.id.uuidString) == nil {
                    try await CloudAIModelManager.shared.addModel(cloudConfig, apiKey: apiKey)
                } else {
                    try await CloudAIModelManager.shared.updateModel(cloudConfig, apiKey: apiKey)
                }

                if let providerConfig = AIProviderConfigStore.convert(cloudConfig) {
                    await AIProviderConfigStore.shared.upsert(providerConfig)
                }
            }

            await SettingsManager.shared.refreshAIProviderConfigs()
            await MainActor.run {
                onSaved()
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func buildLocalConfig(verified: Bool) -> AIProviderConfig {
        var config = AIProviderConfig.localWhisperCpp(
            id: existingConfig?.id ?? UUID(),
            displayName: displayName.trimmedForProviderForm,
            executablePath: executablePath.trimmedForProviderForm,
            modelPath: modelPath.trimmedForProviderForm
        )
        config.asr?.language = language.trimmedForProviderForm.isEmpty ? nil : language.trimmedForProviderForm
        config.isVerified = verified
        if let existingConfig {
            config.createdAt = existingConfig.createdAt
            config.revision = existingConfig.revision
            config.touch()
        }
        return config
    }

    private func buildCloudConfig(verified: Bool) -> CloudAIModelConfig {
        let finalASR = enableASR && provider.supportsASR
        let finalLLM = enableLLM

        var capabilities: Set<ModelCapability> = []
        if finalASR {
            capabilities.insert(.asr)
        }
        if finalLLM {
            capabilities.insert(.llm)
        }

        return CloudAIModelConfig(
            id: existingConfig?.id ?? UUID(),
            displayName: displayName.trimmedForProviderForm,
            provider: provider,
            baseURL: baseURL.trimmedForProviderForm.isEmpty ? provider.defaultBaseURL : baseURL.trimmedForProviderForm,
            capabilities: capabilities,
            asrConfig: finalASR
                ? ASRModelSettings(
                    modelName: asrModelName.trimmedForProviderForm.isEmpty ? provider.defaultASRModel : asrModelName.trimmedForProviderForm,
                    temperature: nil,
                    maxTokens: nil
                )
                : nil,
            llmConfig: finalLLM
                ? LLMModelSettings(
                    modelName: llmModelName.trimmedForProviderForm.isEmpty ? provider.defaultLLMModel : llmModelName.trimmedForProviderForm,
                    qualityPreset: SettingsManager.shared.defaultLLMQualityPreset
                )
                : nil,
            isVerified: verified
        )
    }
}

private enum ProviderFormMode: String, CaseIterable, Identifiable {
    case localWhisperCpp
    case cloudAPI

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .localWhisperCpp:
            return "aiProvider.form.type.localWhisper"
        case .cloudAPI:
            return "aiProvider.form.type.cloud"
        }
    }

    var icon: String {
        switch self {
        case .localWhisperCpp:
            return "terminal"
        case .cloudAPI:
            return "cloud"
        }
    }
}

private enum ProviderVerificationState {
    case notVerified
    case verifying
    case verified
    case failed(String)

    var isVerified: Bool {
        if case .verified = self {
            return true
        }
        return false
    }

    var icon: String {
        switch self {
        case .notVerified:
            return "questionmark.circle"
        case .verifying:
            return "arrow.clockwise"
        case .verified:
            return "checkmark.seal.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notVerified:
            return .secondary
        case .verifying:
            return .blue
        case .verified:
            return .green
        case .failed:
            return .red
        }
    }

    var message: String {
        switch self {
        case .notVerified:
            return String(localized: "aiProvider.verification.notVerified")
        case .verifying:
            return String(localized: "aiProvider.verification.verifying")
        case .verified:
            return String(localized: "aiProvider.verification.verified")
        case .failed(let message):
            return String(
                format: String(localized: "aiProvider.verification.failedFormat"),
                message
            )
        }
    }
}

@available(macOS 13.0, *)
private struct ProviderFormSection<Content: View>: View {
    let titleKey: LocalizedStringKey
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(titleKey)
                    .font(.headline)
            }

            content()
        }
    }
}

@available(macOS 13.0, *)
private struct ProviderTextField: View {
    let labelKey: LocalizedStringKey
    let placeholderKey: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(labelKey)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(placeholderKey, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private extension String {
    var trimmedForProviderForm: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
