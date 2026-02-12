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
///
/// `CloudAIModelManager` 负责管理所有云端 AI 模型的配置，包括 ASR 和 LLM 模型。
/// 使用 `actor` 模式确保线程安全，所有访问必须通过 `await` 进行。
///
/// # 功能
/// - 管理多个 AI 服务提供商（阿里云、智谱、DeepSeek 等）的配置
/// - 使用 Keychain 安全存储 API Keys
/// - 持久化配置到 UserDefaults
/// - 支持从旧版本数据迁移
///
/// # 线程安全
/// 此类型是 `actor`，确保所有操作在序列化的执行上下文中运行。
/// 从 `@MainActor` 上下文访问时需要使用 `await`。
///
/// # 通知
/// 发布 `modelsDidChange` 通知以通知 UI 配置变更。
///
/// # 使用示例
/// ```swift
/// // 获取模型配置
/// let manager = CloudAIModelManager.shared
/// let asrModels = await manager.getModels(for: .asr)
///
/// // 添加新模型
/// let config = CloudAIModelConfig(...)
/// try await manager.addModel(config, apiKey: "your-api-key")
/// ```
actor CloudAIModelManager {
    /// 单例实例
    static let shared = CloudAIModelManager()

    private let logger = Logger(subsystem: "com.meetingsonar", category: "CloudAIModelManager")
    private let defaults = UserDefaults.standard

    // MARK: - Storage Keys

    private enum Keys {
        static let models = "cloudAIModels_v2"
        static let migrationCompleted = "cloudAIMigrationCompleted_v2"
        static let phase5MigrationCompleted = "cloudAIPhase5MigrationCompleted_v2"
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
            // Phase 5: 数据迁移（移除 OpenAI、ASR 配置调整、添加 qualityPreset）
            await migrateConfigurations()
            // Notify that initialization is complete and models are available
            await notifyChange()
        }
    }

    // MARK: - CRUD Operations

    /// 添加新模型配置
    ///
    /// 将新的 AI 模型配置添加到管理器中，API Key 会被安全存储到 Keychain。
    /// 添加成功后发送 `modelsDidChange` 通知。
    ///
    /// - Parameters:
    ///   - config: 模型配置对象，包含提供商、能力、模型名称等信息
    ///   - apiKey: 服务的 API Key，将被安全存储到 Keychain
    ///
    /// - Throws: `CloudAIError` 如果 API Key 保存失败或配置无效
    ///
    /// # 线程安全
    /// 此方法是 `actor` 隔离的，可以安全地从任何上下文调用。
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
    ///
    /// 更新现有模型配置。可以选择性地更新 API Key。
    /// 更新成功后发送 `modelsDidChange` 通知。
    ///
    /// - Parameters:
    ///   - config: 更新后的模型配置对象，`id` 必须与现有配置匹配
    ///   - apiKey: 新的 API Key，如果为 `nil` 则不修改现有 Key
    ///
    /// - Throws: `CloudAIError.modelNotFound` 如果指定 ID 的配置不存在
    ///
    /// # 注意事项
    /// - 配置的 `updatedAt` 时间戳会自动更新
    /// - 只有提供新 API Key 时才会更新 Keychain
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
    ///
    /// 从管理器中移除指定的模型配置，并从 Keychain 中删除关联的 API Key。
    /// 删除成功后发送 `modelsDidChange` 通知。
    ///
    /// - Parameter id: 要删除的模型配置 ID
    ///
    /// - Throws: `CloudAIError.modelNotFound` 如果指定 ID 的配置不存在
    ///
    /// # 注意事项
    /// - 此操作不可逆，API Key 将从 Keychain 中永久删除
    /// - 如果 Keychain 删除失败，操作仍会继续（记录警告日志）
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
    ///
    /// 返回模型列表中第一个支持指定能力的配置。
    /// 常用于快速获取默认模型。
    ///
    /// - Parameter capability: 模型能力类型（ASR 或 LLM）
    /// - Returns: 第一个匹配的模型配置，如果没有则返回 `nil`
    ///
    /// # 使用示例
    /// ```swift
    /// // 获取第一个可用的 ASR 模型
    /// if let asrModel = await manager.getFirstModel(for: .asr) {
    ///     // 使用 asrModel
    /// }
    /// ```
    func getFirstModel(for capability: ModelCapability) -> CloudAIModelConfig? {
        return models.first { $0.supports(capability) }
    }

    /// 获取所有支持指定能力的模型
    ///
    /// 返回模型列表中所有支持指定能力的配置。
    /// 常用于 UI 中显示模型选择列表。
    ///
    /// - Parameter capability: 模型能力类型（ASR 或 LLM）
    /// - Returns: 所有匹配的模型配置数组
    ///
    /// # 使用示例
    /// ```swift
    /// // 获取所有可用的 LLM 模型
    /// let llmModels = await manager.getModels(for: .llm)
    /// for model in llmModels {
    ///     print(model.displayName)
    /// }
    /// ```
    func getModels(for capability: ModelCapability) -> [CloudAIModelConfig] {
        return models.filter { $0.supports(capability) }
    }

    /// 通过 ID 获取模型配置
    ///
    /// 根据模型的 UUID 字符串查找并返回对应的配置。
    ///
    /// - Parameter id: 模型的 UUID 字符串表示
    /// - Returns: 匹配的模型配置，如果未找到返回 `nil`
    ///
    /// # 使用示例
    /// ```swift
    /// let modelIdString = "12345678-1234-1234-1234-123456789012"
    /// if let model = await manager.getModel(byId: modelIdString) {
    ///     print("Found model: \(model.displayName)")
    /// }
    /// ```
    func getModel(byId id: String) -> CloudAIModelConfig? {
        return models.first { $0.id.uuidString == id }
    }

    // MARK: - API Key Management

    /// 获取 API Key
    ///
    /// 从 Keychain 中获取指定模型的 API Key。
    /// 此方法会切换到主线程调用 `@MainActor` 的 `KeychainService`。
    ///
    /// - Parameter modelId: 模型配置的 UUID
    /// - Returns: API Key 字符串，如果不存在返回 `nil`
    ///
    /// # 线程安全
    /// 自动切换到主线程访问 KeychainService。
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
    ///
    /// 将 API Key 安全存储到 Keychain 中。
    ///
    /// - Parameters:
    ///   - key: API Key 字符串
    ///   - modelId: 关联的模型配置 UUID
    ///
    /// - Throws: Keychain 存储错误
    ///
    /// # 线程安全
    /// 自动切换到主线程访问 KeychainService。
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
    ///
    /// 从 Keychain 中移除指定模型的 API Key。
    /// 如果删除失败，只记录错误日志而不抛出异常。
    ///
    /// - Parameter modelId: 要删除的模型配置 UUID
    ///
    /// # 线程安全
    /// 自动切换到主线程访问 KeychainService。
    private func deleteAPIKey(for modelId: UUID) async throws {
        await MainActor.run {
            do {
                try KeychainService.shared.delete(
                    for: modelId.uuidString,
                    modelType: .asr
                )
                logger.debug("Deleted API key for model: \(modelId)")
            } catch {
                logger.error("Failed to delete API key for model \(modelId): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Persistence

    /// 加载所有模型配置
    ///
    /// 从 UserDefaults 中加载持久化的模型配置列表。
    /// 如果加载失败（解码错误），会将配置列表设为空数组。
    ///
    /// # 错误处理
    /// - 解码失败时记录错误日志
    /// - 没有数据时记录警告日志
    private func loadModels() async {
        guard let data = defaults.data(forKey: Keys.models) else {
            logger.warning("No model data found in UserDefaults, starting with empty list")
            models = []
            return
        }

        do {
            let loaded = try JSONDecoder().decode([CloudAIModelConfig].self, from: data)
            models = loaded
            logger.info("Loaded \(self.models.count) model configs successfully")
        } catch {
            logger.error("Failed to decode model configurations: \(error.localizedDescription)")
            models = []
        }
    }

    /// 保存所有模型配置
    ///
    /// 将当前的模型配置列表编码并持久化到 UserDefaults。
    ///
    /// # 错误处理
    /// 编码失败时记录错误日志，配置状态不会改变。
    private func saveModels() async {
        do {
            let data = try JSONEncoder().encode(self.models)
            defaults.set(data, forKey: Keys.models)
            logger.debug("Saved \(self.models.count) model configurations successfully")
        } catch {
            logger.error("Failed to encode model configurations: \(error.localizedDescription)")
        }
    }

    // MARK: - Phase 5 Migration (Task #19)

    /// Phase 5: 数据迁移 - 处理移除的配置和添加新字段
    ///
    /// 执行 Phase 5 数据迁移，主要包括：
    /// - 移除 OpenAI 配置（迁移到 DeepSeek）
    /// - 移除 Aliyun/DeepSeek/Kimi 的 ASR 配置（仅 Zhipu 支持 ASR）
    /// - 为旧配置添加默认 qualityPreset
    ///
    /// # 迁移策略
    /// 1. OpenAI 配置 → DeepSeek 配置
    /// 2. 非 ASR 提供商的 ASR 能力被移除
    /// 3. 为缺少 qualityPreset 的 LLM 配置添加默认值 `.balanced`
    /// 4. 为没有任何能力的配置添加默认 LLM 能力
    ///
    /// # 执行条件
    /// 只在 `phase5MigrationCompleted` 标记为 `false` 时执行一次。
    func migrateConfigurations() async {
        guard !defaults.bool(forKey: Keys.phase5MigrationCompleted) else {
            logger.info("Phase 5 migration already completed, skipping")
            return
        }

        logger.info("Starting Phase 5 migration...")

        var migratedConfigs: [CloudAIModelConfig] = []
        var migrationLog: [String] = []

        for var config in models {
            let originalProvider = config.provider
            var needsUpdate = false

            // 1. 处理 OpenAI 配置迁移
            if config.provider.rawValue == "openai" {
                logger.info("Migrating OpenAI config to DeepSeek: \(config.displayName)")

                // 创建 DeepSeek 配置替代 OpenAI
                var updatedConfig = config
                updatedConfig.provider = .deepseek
                updatedConfig.baseURL = OnlineServiceProvider.deepseek.defaultBaseURL
                updatedConfig.displayName = config.displayName.replacingOccurrences(of: "OpenAI", with: "DeepSeek")

                // 更新 LLM 配置为 DeepSeek 默认模型
                if var llmConfig = updatedConfig.llmConfig {
                    llmConfig.modelName = OnlineServiceProvider.deepseek.defaultLLMModel
                    if llmConfig.qualityPreset == nil {
                        llmConfig.qualityPreset = .balanced
                    }
                    updatedConfig.llmConfig = llmConfig
                }

                // 移除 ASR 能力（DeepSeek 不支持 ASR）
                updatedConfig.capabilities.remove(.asr)
                updatedConfig.asrConfig = nil

                config = updatedConfig
                needsUpdate = true
                migrationLog.append("Migrated OpenAI config '\(originalProvider.displayName)' to DeepSeek")
            }

            // 2. 处理 Aliyun/DeepSeek/Kimi 的 ASR 配置移除
            if !config.provider.supportsASR && config.supports(.asr) {
                logger.info("Removing ASR capability from \(config.provider.displayName) config: \(config.displayName)")

                config.capabilities.remove(.asr)
                config.asrConfig = nil
                needsUpdate = true
                migrationLog.append("Removed ASR capability from \(config.provider.displayName) config")
            }

            // 3. 为缺少 qualityPreset 的 LLM 配置添加默认值
            if config.supports(.llm) {
                if var llmConfig = config.llmConfig {
                    // 检查是否需要添加 qualityPreset
                    if llmConfig.qualityPreset == nil {
                        logger.info("Adding default qualityPreset (.balanced) to \(config.displayName)")
                        llmConfig.qualityPreset = .balanced
                        config.llmConfig = llmConfig
                        needsUpdate = true
                        migrationLog.append("Added default qualityPreset to \(config.displayName)")
                    }
                } else {
                    // 如果支持 LLM 但没有配置，创建默认配置
                    logger.info("Creating default LLM config for \(config.displayName)")
                    config.llmConfig = LLMModelSettings(
                        modelName: config.provider.defaultLLMModel,
                        qualityPreset: .balanced,
                        temperature: nil,
                        maxTokens: nil,
                        topP: nil,
                        enableStreaming: nil
                    )
                    needsUpdate = true
                    migrationLog.append("Created default LLM config for \(config.displayName)")
                }
            }

            // 4. 如果配置没有任何能力，添加默认 LLM 能力
            if config.capabilities.isEmpty {
                logger.info("Adding default LLM capability to \(config.displayName)")
                config.capabilities.insert(.llm)
                config.llmConfig = LLMModelSettings(
                    modelName: config.provider.defaultLLMModel,
                    qualityPreset: .balanced,
                    temperature: nil,
                    maxTokens: nil,
                    topP: nil,
                    enableStreaming: nil
                )
                needsUpdate = true
                migrationLog.append("Added default LLM capability to \(config.displayName)")
            }

            // 更新时间戳（如果配置被修改）
            if needsUpdate {
                config.updatedAt = Date()
            }

            migratedConfigs.append(config)
        }

        // 保存迁移后的配置
        models = migratedConfigs
        await saveModels()

        // 标记迁移完成
        defaults.set(true, forKey: Keys.phase5MigrationCompleted)

        // 记录迁移结果
        if migrationLog.isEmpty {
            logger.info("Phase 5 migration completed. No changes needed.")
        } else {
            logger.info("Phase 5 migration completed. Changes: \(migrationLog.joined(separator: "; "))")
        }

        // 通知 UI 更新
        await notifyChange()
    }

    /// 重置 Phase 5 迁移标记
    ///
    /// 清除 Phase 5 迁移完成标记，使得下次初始化时重新执行迁移。
    /// 主要用于测试或调试目的。
    ///
    /// # 注意事项
    /// 此方法不会立即执行迁移，只重置标记。迁移会在下次初始化时执行。
    func resetPhase5Migration() async {
        defaults.set(false, forKey: Keys.phase5MigrationCompleted)
        logger.info("Phase 5 migration flag reset")
    }

    // MARK: - Legacy Migration (Phase 1-4)

    // 旧的 UserDefaults keys
    private let legacyASRModelsKey = "onlineASRModels"
    private let legacyLLMModelsKey = "onlineLLMModels"

    /// 从旧系统迁移数据
    ///
    /// 从 `OnlineModelManager` 迁移到 `CloudAIModelManager`。
    /// 将旧的 ASR 和 LLM 配置合并为统一的 `CloudAIModelConfig` 格式。
    ///
    /// # 迁移逻辑
    /// 1. 从 UserDefaults 读取旧配置
    /// 2. 合并同一提供商的 ASR 和 LLM 配置
    /// 3. 转换为新的 `CloudAIModelConfig` 格式
    /// 4. 迁移 API Key 到新位置
    /// 5. 标记迁移完成
    ///
    /// # 执行条件
    /// 只在 `migrationCompleted` 标记为 `false` 时执行一次。
    private func migrateIfNeeded() async {
        guard !defaults.bool(forKey: Keys.migrationCompleted) else {
            return // 已迁移
        }

        logger.info("Starting migration from legacy OnlineModelManager...")

        // 直接从 UserDefaults 读取旧配置
        let oldASRModels: [OnlineModelConfig] = await MainActor.run {
            guard let data = defaults.data(forKey: legacyASRModelsKey) else {
                logger.warning("No legacy ASR models data found for migration")
                return []
            }

            do {
                let models = try JSONDecoder().decode([OnlineModelConfig].self, from: data)
                return models
            } catch {
                logger.error("Failed to decode legacy ASR models: \(error.localizedDescription)")
                return []
            }
        }

        let oldLLMModels: [OnlineModelConfig] = await MainActor.run {
            guard let data = defaults.data(forKey: legacyLLMModelsKey) else {
                logger.warning("No legacy LLM models data found for migration")
                return []
            }

            do {
                let models = try JSONDecoder().decode([OnlineModelConfig].self, from: data)
                return models
            } catch {
                logger.error("Failed to decode legacy LLM models: \(error.localizedDescription)")
                return []
            }
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

    /// 获取旧的 API Key
    ///
    /// 从 Keychain 中读取旧格式的 API Key。
    ///
    /// - Parameters:
    ///   - config: 旧的模型配置对象
    ///   - type: 模型类型（ASR 或 LLM）
    /// - Returns: API Key 字符串，如果不存在返回 `nil`
    private func getOldAPIKey(for config: OnlineModelConfig?, type: OnlineModelType) async -> String? {
        guard let config = config else { return nil }
        return await MainActor.run {
            KeychainService.shared.load(for: config.id.uuidString, modelType: type)
        }
    }

    // MARK: - Helpers

    /// 通知 UI 更新
    ///
    /// 在主线程发送 `modelsDidChange` 通知。
    /// 用于通知 UI 层配置已变更，需要刷新显示。
    private func notifyChange() async {
        await MainActor.run {
            NotificationCenter.default.post(name: Self.modelsDidChange, object: nil)
        }
    }

    /// 重置所有数据
    ///
    /// 删除所有模型配置、API Keys，并重置迁移标记。
    /// 主要用于调试和测试目的。
    ///
    /// # 注意事项
    /// - 此操作不可逆
    /// - 所有 API Keys 将从 Keychain 中删除
    /// - 配置列表将被清空
    /// - 迁移标记将被重置，下次初始化时会重新执行迁移
    func resetAllData() async {
        // 删除所有 API Keys
        for model in models {
            do {
                try await deleteAPIKey(for: model.id)
            } catch {
                logger.error("Failed to delete API key during reset for model \(model.id): \(error.localizedDescription)")
            }
        }

        // 清空配置
        models = []
        await saveModels()

        // 重置迁移标记
        defaults.set(false, forKey: Keys.migrationCompleted)
        defaults.set(false, forKey: Keys.phase5MigrationCompleted)

        await notifyChange()

        logger.info("All Cloud AI data reset")
    }
}
