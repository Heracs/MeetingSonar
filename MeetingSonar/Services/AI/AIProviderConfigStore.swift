import Foundation

actor AIProviderConfigStore {
    static let shared = AIProviderConfigStore()
    static let configsDidChange = Notification.Name("AIProviderConfigStore.configsDidChange")

    private let configsKey = "aiProviderConfigs_v1"
    private var configs: [AIProviderConfig] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadConfigsMigratingIfNeeded() async -> [AIProviderConfig] {
        if !configs.isEmpty {
            return configs
        }

        if let data = defaults.data(forKey: configsKey) {
            do {
                let decoded = try JSONDecoder().decode([AIProviderConfig].self, from: data)
                configs = decoded
                return decoded
            } catch {
                LoggerService.shared.log(
                    category: .ai,
                    level: .error,
                    message: "[AIProviderConfigStore] Failed to decode provider configs: \(error.localizedDescription)"
                )
            }
        }

        let migrated = await migrateCloudConfigs()
        configs = migrated
        save(migrated)
        return migrated
    }

    func allConfigs() async -> [AIProviderConfig] {
        await loadConfigsMigratingIfNeeded()
    }

    func configs(for capability: AIProviderCapability) async -> [AIProviderConfig] {
        let loaded = await loadConfigsMigratingIfNeeded()
        return loaded.filter { $0.enabledCapabilities.contains(capability) }
    }

    func config(byId id: String) async -> AIProviderConfig? {
        let loaded = await loadConfigsMigratingIfNeeded()
        return loaded.first { $0.id.uuidString == id }
    }

    func upsert(_ config: AIProviderConfig) async {
        var loaded = await loadConfigsMigratingIfNeeded()
        if let index = loaded.firstIndex(where: { $0.id == config.id }) {
            loaded[index] = config
        } else {
            loaded.append(config)
        }
        configs = loaded
        save(loaded)
        notifyChange()
    }

    func delete(id: UUID) async {
        var loaded = await loadConfigsMigratingIfNeeded()
        loaded.removeAll { $0.id == id }
        configs = loaded
        save(loaded)
        notifyChange()
    }

    func resetAllDataForTests() async {
        configs = []
        defaults.removeObject(forKey: configsKey)
    }

    private func save(_ configs: [AIProviderConfig]) {
        do {
            let data = try JSONEncoder().encode(configs)
            defaults.set(data, forKey: configsKey)
        } catch {
            LoggerService.shared.log(
                category: .ai,
                level: .error,
                message: "[AIProviderConfigStore] Failed to encode provider configs: \(error.localizedDescription)"
            )
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.configsDidChange, object: nil)
    }

    private func migrateCloudConfigs() async -> [AIProviderConfig] {
        let cloudModels = await CloudAIModelManager.shared.models
        return cloudModels.compactMap { cloudConfig in
            Self.convert(cloudConfig)
        }
    }

    static func convert(_ cloudConfig: CloudAIModelConfig) -> AIProviderConfig? {
        let providerKey: String
        switch cloudConfig.provider {
        case .aliyun:
            providerKey = "cloud.aliyun"
        case .zhipu:
            providerKey = "cloud.zhipu"
        case .deepseek:
            providerKey = "cloud.deepseek"
        case .kimi:
            providerKey = "cloud.kimi"
        }

        var capabilities = Set<AIProviderCapability>()
        var asr: ASRProviderConfig?
        var llm: LLMProviderConfig?

        if cloudConfig.capabilities.contains(.asr), let asrConfig = cloudConfig.asrConfig {
            capabilities.insert(.asr)
            asr = ASRProviderConfig(
                modelName: asrConfig.modelName,
                transport: asrTransport(for: cloudConfig.provider),
                language: nil,
                prompt: nil,
                hotwords: [],
                endpoint: URL(string: cloudConfig.baseURL),
                localCommand: nil,
                audioInputPolicy: audioInputPolicy(for: cloudConfig.provider)
            )
        }

        if cloudConfig.capabilities.contains(.llm), let llmConfig = cloudConfig.llmConfig {
            capabilities.insert(.llm)
            llm = LLMProviderConfig(
                modelName: llmConfig.modelName,
                transport: llmTransport(for: cloudConfig.provider),
                endpoint: URL(string: cloudConfig.baseURL),
                temperature: llmConfig.temperature,
                maxTokens: llmConfig.maxTokens,
                supportsStreaming: true
            )
        }

        guard !capabilities.isEmpty else { return nil }

        return AIProviderConfig(
            id: cloudConfig.id,
            displayName: cloudConfig.displayName,
            providerKey: providerKey,
            kind: .cloudAPI,
            enabledCapabilities: capabilities,
            asr: asr,
            llm: llm,
            createdAt: cloudConfig.createdAt,
            updatedAt: cloudConfig.updatedAt,
            revision: 1,
            isVerified: cloudConfig.isVerified
        )
    }

    private static func asrTransport(for provider: OnlineServiceProvider) -> ASRTransportKind {
        switch provider {
        case .aliyun:
            return .dashScopeAsync
        case .zhipu, .deepseek, .kimi:
            return .syncMultipart
        }
    }

    private static func llmTransport(for provider: OnlineServiceProvider) -> LLMTransportKind {
        switch provider {
        case .aliyun:
            return .dashScopeNative
        case .zhipu:
            return .zhipuNative
        case .deepseek, .kimi:
            return .openAICompatible
        }
    }

    private static func audioInputPolicy(for provider: OnlineServiceProvider) -> ASRAudioInputPolicy {
        switch provider {
        case .zhipu, .aliyun, .deepseek, .kimi:
            return .zhipuMultipart
        }
    }
}
