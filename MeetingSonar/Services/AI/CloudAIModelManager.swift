//
//  CloudAIModelManager.swift
//  MeetingSonar
//
//  Phase 2: 统一云端 AI 配置管理器
//  替代 OnlineModelManager 和 ModelManager 的在线配置功能
//

import Foundation
import OSLog

/// 统一的云端 AI 配置管理器
/// 单例模式，使用 actor 保证线程安全
actor CloudAIModelManager {
    static let shared = CloudAIModelManager()

    private let logger = Logger(subsystem: "com.meetingsonar", category: "CloudAIModelManager")
    private let defaults = UserDefaults.standard

    // MARK: - Storage Keys

    private enum Keys {
        static let models = "cloudAIModels_v2"
        static let migrationCompleted = "cloudAIMigrationCompleted_v2"
    }

    // MARK: - Published State

    /// 所有模型配置
    private(set) var models: [CloudAIModelConfig] = []

    // MARK: - Notification Names

    static let modelsDidChange = Notification.Name("CloudAIModelsDidChange")

    // MARK: - Initialization

    private init() {
        Task {
            await loadModels()
            await migrateIfNeeded()
            // Notify that initialization is complete and models are available
            await notifyChange()
        }
    }

    // MARK: - CRUD Operations

    /// 添加新模型配置
    /// - Parameters:
    ///   - config: 模型配置
    ///   - apiKey: API Key（将保存到 Keychain）
    func addModel(_ config: CloudAIModelConfig, apiKey: String) async throws {
        // 1. 保存 API Key 到 Keychain
        try await saveAPIKey(apiKey, for: config.id)

        // 2. 添加到列表
        models.append(config)

        // 3. 持久化
        await saveModels()

        // 4. 通知 UI 更新
        await notifyChange()

        logger.info("Added model config: \(config.displayName) (\(config.id))")
    }

    /// 更新模型配置
    /// - Parameters:
    ///   - config: 更新的配置
    ///   - apiKey: 新 API Key（可选，nil 表示不修改）
    func updateModel(_ config: CloudAIModelConfig, apiKey: String? = nil) async throws {
        guard let index = models.firstIndex(where: { $0.id == config.id }) else {
            throw CloudAIError.modelNotFound
        }

        // 更新 API Key（如果提供）
        if let newKey = apiKey {
            try await saveAPIKey(newKey, for: config.id)
        }

        // 更新时间戳
        var updatedConfig = config
        updatedConfig.updatedAt = Date()

        models[index] = updatedConfig
        await saveModels()
        await notifyChange()

        logger.info("Updated model config: \(config.displayName)")
    }

    /// 删除模型配置
    /// - Parameter id: 配置 ID
    func deleteModel(id: UUID) async throws {
        guard let index = models.firstIndex(where: { $0.id == id }) else {
            throw CloudAIError.modelNotFound
        }

        let config = models[index]

        // 1. 从 Keychain 删除 API Key
        try? await deleteAPIKey(for: id)

        // 2. 从列表移除
        models.remove(at: index)

        // 3. 持久化
        await saveModels()
        await notifyChange()

        logger.info("Deleted model config: \(config.displayName)")
    }

    /// 获取第一个支持指定能力的模型
    /// - Parameter capability: 能力类型
    /// - Returns: 模型配置，如果没有则返回 nil
    func getFirstModel(for capability: ModelCapability) -> CloudAIModelConfig? {
        return models.first { $0.supports(capability) }
    }

    /// 获取所有支持指定能力的模型
    /// - Parameter capability: 能力类型
    /// - Returns: 模型配置列表
    func getModels(for capability: ModelCapability) -> [CloudAIModelConfig] {
        return models.filter { $0.supports(capability) }
    }

    /// 通过 ID 获取模型配置
    /// - Parameter id: 模型 ID (UUID string)
    /// - Returns: 模型配置，如果未找到返回 nil
    func getModel(byId id: String) -> CloudAIModelConfig? {
        return models.first { $0.id.uuidString == id }
    }

    // MARK: - API Key Management

    /// 获取 API Key
    /// - Parameter modelId: 模型 ID
    /// - Returns: API Key，如果不存在返回 nil
    func getAPIKey(for modelId: UUID) async -> String? {
        // KeychainService 是 @MainActor，需要切换到主线程
        return await MainActor.run {
            KeychainService.shared.load(
                for: modelId.uuidString,
                modelType: .asr // 使用统一的 keychain 存储
            )
        }
    }

    /// 保存 API Key
    private func saveAPIKey(_ key: String, for modelId: UUID) async throws {
        // KeychainService 是 @MainActor，需要切换到主线程
        try await MainActor.run {
            try KeychainService.shared.save(
                key: key,
                for: modelId.uuidString,
                modelType: .asr
            )
        }
    }

    /// 删除 API Key
    private func deleteAPIKey(for modelId: UUID) async throws {
        await MainActor.run {
            try? KeychainService.shared.delete(
                for: modelId.uuidString,
                modelType: .asr
            )
        }
    }

    // MARK: - Persistence

    /// 加载所有模型配置
    private func loadModels() async {
        guard let data = defaults.data(forKey: Keys.models),
              let loaded = try? JSONDecoder().decode([CloudAIModelConfig].self, from: data) else {
            models = []
            return
        }
        models = loaded
        logger.info("Loaded \(self.models.count) model configs")
    }

    /// 保存所有模型配置
    private func saveModels() async {
        if let data = try? JSONEncoder().encode(models) {
            defaults.set(data, forKey: Keys.models)
        }
    }

    // MARK: - Migration

    // 旧的 UserDefaults keys
    private let legacyASRModelsKey = "onlineASRModels"
    private let legacyLLMModelsKey = "onlineLLMModels"

    /// 从旧系统迁移数据
    /// 从 OnlineModelManager 迁移到 CloudAIModelManager
    private func migrateIfNeeded() async {
        guard !defaults.bool(forKey: Keys.migrationCompleted) else {
            return // 已迁移
        }

        logger.info("Starting migration from legacy OnlineModelManager...")

        // 直接从 UserDefaults 读取旧配置
        let oldASRModels: [OnlineModelConfig] = await MainActor.run {
            guard let data = defaults.data(forKey: legacyASRModelsKey),
                  let models = try? JSONDecoder().decode([OnlineModelConfig].self, from: data) else {
                return []
            }
            return models
        }

        let oldLLMModels: [OnlineModelConfig] = await MainActor.run {
            guard let data = defaults.data(forKey: legacyLLMModelsKey),
                  let models = try? JSONDecoder().decode([OnlineModelConfig].self, from: data) else {
                return []
            }
            return models
        }

        guard !oldASRModels.isEmpty || !oldLLMModels.isEmpty else {
            // 没有旧数据，标记迁移完成
            defaults.set(true, forKey: Keys.migrationCompleted)
            logger.info("No old data to migrate")
            return
        }

        // 合并同一提供商的配置
        var providerConfigs: [OnlineServiceProvider: (asr: OnlineModelConfig?, llm: OnlineModelConfig?)] = [:]

        // 收集 ASR 配置
        for asrConfig in oldASRModels {
            if providerConfigs[asrConfig.provider] == nil {
                providerConfigs[asrConfig.provider] = (asr: asrConfig, llm: nil)
            } else {
                providerConfigs[asrConfig.provider]?.asr = asrConfig
            }
        }

        // 收集 LLM 配置
        for llmConfig in oldLLMModels {
            if providerConfigs[llmConfig.provider] == nil {
                providerConfigs[llmConfig.provider] = (asr: nil, llm: llmConfig)
            } else {
                providerConfigs[llmConfig.provider]?.llm = llmConfig
            }
        }

        // 转换为新格式
        for (provider, configs) in providerConfigs {
            var capabilities: Set<ModelCapability> = []
            if configs.asr != nil { capabilities.insert(.asr) }
            if configs.llm != nil { capabilities.insert(.llm) }

            let asrSettings: ASRModelSettings? = configs.asr.map {
                ASRModelSettings(
                    modelName: $0.modelName,
                    temperature: $0.temperature,
                    maxTokens: $0.maxTokens
                )
            }

            let llmSettings: LLMModelSettings? = configs.llm.map {
                LLMModelSettings(
                    modelName: $0.modelName,
                    qualityPreset: .balanced, // v1.1.0: Default to balanced for migrated configs
                    temperature: $0.temperature,
                    maxTokens: $0.maxTokens,
                    topP: nil,
                    enableStreaming: nil
                )
            }

            let newConfig = CloudAIModelConfig(
                displayName: "\(provider.displayName) (已迁移)",
                provider: provider,
                baseURL: configs.asr?.baseURL ?? configs.llm?.baseURL ?? provider.defaultBaseURL,
                capabilities: capabilities,
                asrConfig: asrSettings,
                llmConfig: llmSettings,
                isVerified: true // 假设已验证
            )

            // 迁移 API Key
            let apiKey: String? = await getOldAPIKey(for: configs.asr ?? configs.llm, type: configs.asr != nil ? .asr : .llm)

            if let key = apiKey {
                do {
                    try await addModel(newConfig, apiKey: key)
                    logger.info("Migrated config for \(provider.displayName)")
                } catch {
                    logger.error("Failed to migrate config for \(provider.displayName): \(error.localizedDescription)")
                }
            }
        }

        // 标记迁移完成
        defaults.set(true, forKey: Keys.migrationCompleted)
        logger.info("Migration completed. Migrated \(self.models.count) configs.")
    }

    /// 获取旧的 API Key（直接从 Keychain 读取）
    private func getOldAPIKey(for config: OnlineModelConfig?, type: OnlineModelType) async -> String? {
        guard let config = config else { return nil }
        return await MainActor.run {
            KeychainService.shared.load(for: config.id.uuidString, modelType: type)
        }
    }

    // MARK: - Helpers

    /// 通知 UI 更新
    private func notifyChange() async {
        await MainActor.run {
            NotificationCenter.default.post(name: Self.modelsDidChange, object: nil)
        }
    }

    /// 重置所有数据（调试用）
    func resetAllData() async {
        // 删除所有 API Keys
        for model in models {
            try? await deleteAPIKey(for: model.id)
        }

        // 清空配置
        models = []
        await saveModels()

        // 重置迁移标记
        defaults.set(false, forKey: Keys.migrationCompleted)

        await notifyChange()

        logger.info("All Cloud AI data reset")
    }
}
