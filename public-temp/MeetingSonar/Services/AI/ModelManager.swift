import Foundation
import OSLog

/// 模型类型枚举 - 云端版本
/// 仅支持在线API模型
enum ModelType: String, CaseIterable, Identifiable, Codable {
    case online = "online"

    var id: String { rawValue }

    /// 本地化显示名称
    var displayName: String {
        switch self {
        case .online:
            return String(localized: "model.type.online", defaultValue: "云端API")
        }
    }

    /// 模型描述
    var description: String {
        switch self {
        case .online:
            return String(localized: "model.type.online.description", defaultValue: "使用云端AI服务进行转录和摘要")
        }
    }

    /// 是否为在线模型
    var isOnline: Bool {
        return true
    }
}

/// 模型管理错误
enum ModelManagerError: LocalizedError {
    case invalidModelType
    case configurationMissing

    var errorDescription: String? {
        switch self {
        case .invalidModelType:
            return String(localized: "error.invalid_model_type", defaultValue: "无效的模型类型")
        case .configurationMissing:
            return String(localized: "error.configuration_missing", defaultValue: "模型配置缺失")
        }
    }
}

/// 模型管理器 - 云端版本
/// 负责管理云端AI服务的配置
actor ModelManager {
    static let shared = ModelManager()

    private let logger = Logger(subsystem: "com.meetingsonar", category: "ModelManager")
    private let userDefaults = UserDefaults.standard

    // MARK: - Keys
    private enum Keys {
        static let selectedASRModel = "selectedASRModel"
        static let selectedLLMModel = "selectedLLMModel"
        static let asrConfig = "asrOnlineConfig"
        static let llmConfig = "llmOnlineConfig"
    }

    // MARK: - Initialization

    private init() {
        logger.info("ModelManager initialized (cloud-only mode)")
    }

    // MARK: - Model Selection

    /// 获取当前选择的ASR模型类型
    func getSelectedASRModel() -> ModelType {
        // 云端版本只返回 online
        return .online
    }

    /// 获取当前选择的LLM模型类型
    func getSelectedLLMModel() -> ModelType {
        // 云端版本只返回 online
        return .online
    }

    /// 设置ASR模型
    func setASRModel(_ model: ModelType) async {
        // 云端版本只支持 online
        logger.info("ASR model set to cloud API")
    }

    /// 设置LLM模型
    func setLLMModel(_ model: ModelType) async {
        // 云端版本只支持 online
        logger.info("LLM model set to cloud API")
    }

    // MARK: - Online Model Configuration

    /// 获取ASR在线模型配置
    func getASROnlineConfig() async -> OnlineModelConfig {
        guard let data = userDefaults.data(forKey: Keys.asrConfig),
              let config = try? JSONDecoder().decode(OnlineModelConfig.self, from: data) else {
            // 返回默认配置
            return OnlineModelConfig.defaultConfig(provider: .aliyun, type: .asr)
        }
        return config
    }

    /// 保存ASR在线模型配置
    func saveASROnlineConfig(_ config: OnlineModelConfig) async {
        if let data = try? JSONEncoder().encode(config) {
            userDefaults.set(data, forKey: Keys.asrConfig)
            logger.info("ASR online config saved")
        }
    }

    /// 获取LLM在线模型配置
    func getLLMOnlineConfig() async -> OnlineModelConfig {
        guard let data = userDefaults.data(forKey: Keys.llmConfig),
              let config = try? JSONDecoder().decode(OnlineModelConfig.self, from: data) else {
            // 返回默认配置
            return OnlineModelConfig.defaultConfig(provider: .aliyun, type: .llm)
        }
        return config
    }

    /// 保存LLM在线模型配置
    func saveLLMOnlineConfig(_ config: OnlineModelConfig) async {
        if let data = try? JSONEncoder().encode(config) {
            userDefaults.set(data, forKey: Keys.llmConfig)
            logger.info("LLM online config saved")
        }
    }

    /// 获取在线模型配置（兼容旧接口）
    func getOnlineModelConfig() async -> (provider: OnlineServiceProvider, apiKey: String, endpoint: String, asrModel: String, llmModel: String) {
        let asrConfig = await getASROnlineConfig()
        let llmConfig = await getLLMOnlineConfig()

        // 从 Keychain 获取 API Key
        let apiKey = await KeychainService.shared.load(for: asrConfig.id.uuidString, modelType: .asr) ?? ""

        return (
            provider: asrConfig.provider,
            apiKey: apiKey,
            endpoint: asrConfig.baseURL,
            asrModel: asrConfig.modelName,
            llmModel: llmConfig.modelName
        )
    }

    // MARK: - Model Status

    /// 检查模型是否就绪
    /// 云端版本：检查配置是否有效
    func isModelReady(_ model: ModelType) async -> Bool {
        let config = await getASROnlineConfig()
        let apiKey = await KeychainService.shared.load(for: config.id.uuidString, modelType: .asr)
        return apiKey != nil && !apiKey!.isEmpty && !config.baseURL.isEmpty
    }

    /// 获取模型状态描述
    func getModelStatusDescription(_ model: ModelType) async -> String {
        let isReady = await isModelReady(model)
        if isReady {
            return String(localized: "model.status.configured", defaultValue: "已配置")
        } else {
            return String(localized: "model.status.not_configured", defaultValue: "未配置")
        }
    }

    // MARK: - Migration

    /// 迁移旧版本设置
    /// 将本地模型设置迁移到云端设置
    func migrateFromLegacySettings() async {
        logger.info("Migrating from legacy settings to cloud-only mode")

        // 清除旧的本地模型选择
        userDefaults.removeObject(forKey: Keys.selectedASRModel)
        userDefaults.removeObject(forKey: Keys.selectedLLMModel)

        // 确保有默认配置
        let asrConfig = await getASROnlineConfig()
        let llmConfig = await getLLMOnlineConfig()

        await saveASROnlineConfig(asrConfig)
        await saveLLMOnlineConfig(llmConfig)

        logger.info("Migration completed")
    }
}
