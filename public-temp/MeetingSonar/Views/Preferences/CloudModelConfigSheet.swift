//
//  CloudModelConfigSheet.swift
//  MeetingSonar
//
//  Phase 3: 统一云端模型配置表单
//  支持同时配置 ASR 和 LLM 能力
//  Updated: v1.1.0 - Quality preset mode, conditional parameters, removed OpenAI, added Kimi
//

import SwiftUI

/// 云端模型配置添加/编辑表单
/// Cloud model configuration add/edit form
@available(macOS 13.0, *)
struct CloudModelConfigSheet: View {
    @Environment(\.dismiss) var dismiss

    // MARK: - Properties

    let existingConfig: CloudAIModelConfig?

    // MARK: - State

    // Basic
    @State private var displayName: String = ""
    @State private var provider: OnlineServiceProvider = .deepseek  // v1.1.0: Default to DeepSeek
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false

    // Capabilities
    @State private var enableASR: Bool = false  // v1.1.0: Disabled by default, only ZhipuAI supports
    @State private var enableLLM: Bool = true   // v1.1.0: LLM is default

    // ASR Config (simplified in v1.1.0)
    @State private var asrModelName: String = ""

    // LLM Config (v1.1.0: Quality preset + optional advanced parameters)
    @State private var llmModelName: String = ""
    @State private var qualityPreset: LLMQualityPreset = .balanced
    @State private var llmTemperature: Double? = nil      // Optional - nil means use provider default
    @State private var llmMaxTokens: Int? = nil           // Optional - nil means use provider default
    @State private var llmTopP: Double? = nil             // Optional - nil means use provider default

    // UI State
    @State private var showAdvancedSheet: Bool = false
    @State private var verificationStatus: VerificationStatus = .notVerified
    @State private var isVerifying: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    // MARK: - Initialization

    init(existingConfig: CloudAIModelConfig? = nil) {
        self.existingConfig = existingConfig
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    basicSection
                    capabilitiesSection

                    if enableASR && provider.supportsASR {
                        asrConfigSection
                    }

                    if enableLLM {
                        llmConfigSection
                    }

                    verificationSection
                }
                .padding()
            }

            Divider()
            footerView
        }
        .frame(width: 550, height: 700)
        .onAppear { loadExistingConfig() }
        .sheet(isPresented: $showAdvancedSheet) {
            AdvancedParametersSheet(
                temperature: $llmTemperature,
                maxTokens: $llmMaxTokens,
                topP: $llmTopP
            )
        }
        .alert("保存失败", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(existingConfig == nil ? "添加云端服务" : "编辑云端服务")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("配置语言模型服务用于会议纪要生成")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Basic Section

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "基本信息", icon: "info.circle")

            // Display Name
            LabeledField(label: "显示名称") {
                TextField("例如: DeepSeek生产环境", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }

            // Provider
            VStack(alignment: .leading, spacing: 8) {
                Text("服务提供商")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("", selection: $provider) {
                    ForEach(OnlineServiceProvider.allCases, id: \.self) { p in
                        HStack(spacing: 4) {
                            Image(systemName: p.icon)
                            Text(p.displayName)
                        }
                        .tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(existingConfig != nil)
                .onChange(of: provider) { newProvider in
                    // v1.1.0: Update defaults when provider changes
                    baseURL = newProvider.defaultBaseURL
                    if !enableLLM {
                        enableLLM = true
                    }
                    // Disable ASR if provider doesn't support it
                    if !newProvider.supportsASR {
                        enableASR = false
                    }
                }
            }

            // Base URL
            LabeledField(label: "API 地址") {
                TextField(provider.defaultBaseURL, text: $baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            // API Key
            LabeledField(label: "API Key") {
                HStack(spacing: 8) {
                    Group {
                        if showAPIKey {
                            TextField("输入 API Key", text: $apiKey)
                        } else {
                            SecureField("输入 API Key", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button { showAPIKey.toggle() } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Capabilities Section

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "能力配置", icon: "gearshape.2")

            // Provider capability badges
            HStack(spacing: 12) {
                ForEach(OnlineServiceProvider.allCases, id: \.self) { p in
                    ProviderCapabilityBadge(
                        provider: p,
                        isSelected: provider == p
                    )
                }
            }

            Divider()

            // Capability toggles
            HStack(spacing: 20) {
                // ASR Toggle (only enabled for ZhipuAI)
                CapabilityToggle(
                    title: "语音识别 (ASR)",
                    subtitle: "将录音转换为文字",
                    icon: "waveform",
                    isOn: $enableASR,
                    isDisabled: !provider.supportsASR
                )
                .opacity(provider.supportsASR ? 1.0 : 0.5)

                CapabilityToggle(
                    title: "语言模型 (LLM)",
                    subtitle: "生成会议纪要",
                    icon: "text.bubble",
                    isOn: $enableLLM
                )
            }
        }
    }

    // MARK: - ASR Config Section

    private var asrConfigSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "语音识别配置", icon: "waveform")

            LabeledField(label: "模型名称") {
                TextField(provider.defaultASRModel, text: $asrModelName)
                    .textFieldStyle(.roundedBorder)
            }

            Text("使用厂家默认参数")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - LLM Config Section

    private var llmConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "语言模型配置", icon: "text.bubble")

            // Model Name
            LabeledField(label: "模型名称") {
                TextField(provider.defaultLLMModel, text: $llmModelName)
                    .textFieldStyle(.roundedBorder)
            }

            // Quality Preset Picker
            QualityPresetPicker(
                selection: $qualityPreset,
                showAdvancedSettings: $showAdvancedSheet
            )

            // Show current settings summary
            HStack {
                Text("当前设置: \(qualityPreset.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if llmTemperature != nil || llmMaxTokens != nil || llmTopP != nil {
                    Text("(已自定义参数)")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Text("(使用厂家默认)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
    }

    // MARK: - Verification Section

    private var verificationSection: some View {
        HStack {
            HStack(spacing: 8) {
                if case .verifying = verificationStatus {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: verificationStatus.icon)
                        .foregroundColor(verificationStatus.color)
                }

                Text(verificationStatus.text)
                    .font(.subheadline)
                    .foregroundColor(verificationStatus.color)
            }

            Spacer()

            Button {
                Task { await verifyOnly() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield")
                    Text("验证")
                }
            }
            .controlSize(.small)
            .disabled(apiKey.isEmpty || isVerifying)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button("取消") {
                dismiss()
            }

            Spacer()

            let buttonText = verificationStatus.isVerified ? "保存" : "保存(未验证)"
            let buttonIcon = verificationStatus.isVerified ? "checkmark.circle.fill" : "square.and.arrow.down"

            Button(action: {
                if !isValid {
                    errorMessage = "请填写所有必填字段并至少启用一项能力 (名称、API Key、至少一个能力)"
                    showError = true
                    return
                }

                Task {
                    await saveConfig(verified: verificationStatus.isVerified)
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: buttonIcon)
                    Text(buttonText)
                }
            }
            .disabled(!isValid)
        }
        .padding()
    }

    // MARK: - Validation

    private var isValid: Bool {
        !displayName.isEmpty && !apiKey.isEmpty && (enableASR || enableLLM)
    }

    // MARK: - Actions

    private func loadExistingConfig() {
        guard let config = existingConfig else {
            // 设置默认值 / Set defaults
            baseURL = provider.defaultBaseURL
            return
        }

        displayName = config.displayName
        provider = config.provider
        baseURL = config.baseURL
        enableASR = config.supports(.asr) && provider.supportsASR  // v1.1.0: Check if provider supports ASR
        enableLLM = config.supports(.llm)

        if let asr = config.asrConfig {
            asrModelName = asr.modelName
        }

        if let llm = config.llmConfig {
            llmModelName = llm.modelName
            qualityPreset = llm.qualityPreset
            llmTemperature = llm.temperature
            llmMaxTokens = llm.maxTokens
            llmTopP = llm.topP
        }

        verificationStatus = config.isVerified ? .verified : .notVerified

        // 加载 API Key / Load API Key
        Task {
            if let key = await CloudAIModelManager.shared.getAPIKey(for: config.id) {
                await MainActor.run {
                    apiKey = key
                }
            }
        }
    }

    private func verifyOnly() async {
        verificationStatus = .verifying
        isVerifying = true
        errorMessage = ""

        defer { isVerifying = false }

        do {
            // 创建云服务提供商进行验证
            let cloudProvider = await CloudServiceFactory.shared.createProvider(
                provider,
                apiKey: apiKey,
                baseURL: baseURL
            )

            let isValid = try await cloudProvider.verifyAPIKey()

            guard isValid else {
                throw VerificationError.apiKeyInvalid
            }

            // 验证通过
            await MainActor.run {
                verificationStatus = .verified
                LoggerService.shared.log(
                    category: .general,
                    message: "[CloudModelConfigSheet] API Key verified successfully"
                )
            }
        } catch let error as VerificationError {
            await MainActor.run {
                verificationStatus = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        } catch {
            await MainActor.run {
                verificationStatus = .failed(error.localizedDescription)
                errorMessage = "验证失败: \(error.localizedDescription)"
            }
        }
    }

    enum VerificationError: LocalizedError {
        case apiKeyInvalid

        var errorDescription: String? {
            switch self {
            case .apiKeyInvalid:
                return String(localized: "error.api_key_invalid", defaultValue: "API Key 验证失败，请检查密钥是否正确")
            }
        }
    }

    private func saveConfig(verified: Bool) async {
        let config = buildConfig(verified: verified)

        LoggerService.shared.log(category: .general, message: "[CloudModelConfigSheet] Saving config: \(config.displayName), id: \(config.id)")

        do {
            if existingConfig == nil {
                try await CloudAIModelManager.shared.addModel(config, apiKey: apiKey)
            } else {
                try await CloudAIModelManager.shared.updateModel(config, apiKey: apiKey)
            }

            await MainActor.run {
                dismiss()
            }
        } catch let error as CloudAIError {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        } catch {
            await MainActor.run {
                errorMessage = "保存失败: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func buildConfig(verified: Bool) -> CloudAIModelConfig {
        var capabilities: Set<ModelCapability> = []
        if enableASR && provider.supportsASR { capabilities.insert(.asr) }  // v1.1.0: Check provider support
        if enableLLM { capabilities.insert(.llm) }

        // ASR Config (v1.1.0: Use provider defaults)
        let asrConfig: ASRModelSettings? = (enableASR && provider.supportsASR) ? ASRModelSettings(
            modelName: asrModelName.isEmpty ? provider.defaultASRModel : asrModelName,
            temperature: nil,  // Use provider default
            maxTokens: nil     // Use provider default
        ) : nil

        // LLM Config (v1.1.0: Quality preset + optional parameters)
        let llmConfig: LLMModelSettings? = enableLLM ? LLMModelSettings(
            modelName: llmModelName.isEmpty ? provider.defaultLLMModel : llmModelName,
            qualityPreset: qualityPreset,
            temperature: llmTemperature,  // nil means use provider default
            maxTokens: llmMaxTokens,      // nil means use provider default
            topP: llmTopP,                // nil means use provider default
            enableStreaming: nil          // Use global setting
        ) : nil

        return CloudAIModelConfig(
            id: existingConfig?.id ?? UUID(),
            displayName: displayName,
            provider: provider,
            baseURL: baseURL.isEmpty ? provider.defaultBaseURL : baseURL,
            capabilities: capabilities,
            asrConfig: asrConfig,
            llmConfig: llmConfig,
            isVerified: verified
        )
    }
}

// MARK: - Provider Capability Badge

private struct ProviderCapabilityBadge: View {
    let provider: OnlineServiceProvider
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: provider.icon)
                .font(.caption)
            Text(provider.displayName)
                .font(.caption)

            // Capability indicators
            HStack(spacing: 2) {
                if provider.supportsASR {
                    Text("ASR")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(2)
                }
                Text("LLM")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Helper Views

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
            Text(title)
                .font(.headline)
        }
    }
}

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            content()
        }
    }
}

struct CapabilityToggle: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isOn ? .accentColor : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .disabled(isDisabled)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

// MARK: - Verification Status

enum VerificationStatus {
    case notVerified
    case verifying
    case verified
    case failed(String)

    var isVerified: Bool {
        if case .verified = self { return true }
        return false
    }

    var color: Color {
        switch self {
        case .notVerified: return .secondary
        case .verifying: return .blue
        case .verified: return .green
        case .failed: return .red
        }
    }

    var icon: String {
        switch self {
        case .notVerified: return "questionmark.circle"
        case .verifying: return "arrow.clockwise"
        case .verified: return "checkmark.seal.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var text: String {
        switch self {
        case .notVerified: return "未验证"
        case .verifying: return "验证中..."
        case .verified: return "验证通过"
        case .failed(let msg): return "验证失败: \(String(msg.prefix(20)))"
        }
    }
}

// MARK: - Preview

@available(macOS 13.0, *)
struct CloudModelConfigSheet_Previews: PreviewProvider {
    static var previews: some View {
        CloudModelConfigSheet()
    }
}
