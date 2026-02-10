//
//  CloudAIModelConfig.swift
//  MeetingSonar
//
//  Phase 2: 统一云端 AI 配置模型
//  支持单配置多能力（ASR + LLM）
//  Updated: v1.1.0 - Added LLMQualityPreset, conditional parameter strategy
//

import Foundation

// MARK: - Model Capability

/// 模型能力类型 / Model capability type
enum ModelCapability: String, Codable, CaseIterable, Identifiable, Sendable {
    case asr = "asr"
    case llm = "llm"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .asr:
            return String(localized: "capability.asr", defaultValue: "语音识别")
        case .llm:
            return String(localized: "capability.llm", defaultValue: "文本生成")
        }
    }

    var icon: String {
        switch self {
        case .asr:
            return "waveform"
        case .llm:
            return "text.bubble"
        }
    }
}

// MARK: - LLM Quality Preset

/// LLM 质量预设
/// LLM Quality Preset - User-friendly quality options for LLM output
/// v1.1.0: Simplified parameter configuration using presets
enum LLMQualityPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case fast = "fast"
    case balanced = "balanced"
    case quality = "quality"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast: return String(localized: "quality.fast", defaultValue: "快速")
        case .balanced: return String(localized: "quality.balanced", defaultValue: "平衡")
        case .quality: return String(localized: "quality.quality", defaultValue: "高质量")
        }
    }

    var description: String {
        switch self {
        case .fast: return String(localized: "quality.fast.description", defaultValue: "响应快，摘要简洁")
        case .balanced: return String(localized: "quality.balanced.description", defaultValue: "速度与质量兼顾")
        case .quality: return String(localized: "quality.quality.description", defaultValue: "详细摘要，响应较慢")
        }
    }

    /// SF Symbol 图标 / SF Symbol icon
    var icon: String {
        switch self {
        case .fast: return "bolt.fill"
        case .balanced: return "scale.3d"
        case .quality: return "wand.and.stars"
        }
    }

    /// 颜色 / Color
    var color: String {
        switch self {
        case .fast: return "blue"
        case .balanced: return "green"
        case .quality: return "purple"
        }
    }

    /// 推荐的参数值（仅供参考，实际使用取决于用户配置）
    /// Recommended parameter values (for reference only, actual use depends on user config)
    /// v1.1.0: Updated for 128K+ output support
    var recommendedParameters: (temperature: Double, maxTokens: Int) {
        switch self {
        case .fast: return (0.3, 16384)      // 16K
        case .balanced: return (0.7, 32768)  // 32K
        case .quality: return (0.9, 65536)   // 64K
        }
    }
}

// MARK: - ASR Model Settings

/// ASR 模型设置 / ASR Model Settings
/// v1.1.0: Only ZhipuAI supports ASR
struct ASRModelSettings: Codable, Hashable, Sendable {
    var modelName: String
    var temperature: Double?
    var maxTokens: Int?

    static let `default` = ASRModelSettings(
        modelName: "GLM-4-ASR-2512",
        temperature: nil,  // Use provider default
        maxTokens: nil     // Use provider default
    )
}

// MARK: - LLM Model Settings

/// LLM 模型设置（简化版 + 可选参数）
/// LLM Model Settings (Simplified + Optional Parameters)
/// v1.1.0: Added qualityPreset, conditional parameter strategy
struct LLMModelSettings: Codable, Hashable, Sendable {
    var modelName: String

    /// 质量预设（UI 概念）/ Quality preset (UI concept)
    var qualityPreset: LLMQualityPreset

    /// 可选参数：仅在用户明确配置时设置 / Optional parameters: Only set when explicitly configured
    ///
    /// 设计原则 / Design Principle:
    /// - 如果这些参数为 nil，API 请求中将不包含它们，使用各厂家的默认值
    /// - If these parameters are nil, they won't be included in API requests, using provider defaults
    /// - 只有用户主动配置时，这些值才会被设置
    /// - Only set when user actively configures them
    var temperature: Double?
    var maxTokens: Int?
    var topP: Double?

    /// 流式输出开关（可选，默认使用全局设置）
    /// Streaming output toggle (optional, defaults to global setting)
    var enableStreaming: Bool?

    /// 获取用于 API 请求的参数（仅返回已配置的参数）
    /// Get parameters for API request (only returns configured parameters)
    func apiRequestParameters() -> [String: Any] {
        var params: [String: Any] = [:]

        // 只添加已配置的参数 / Only add configured parameters
        if let temp = temperature {
            params["temperature"] = temp
        }
        if let tokens = maxTokens {
            params["max_tokens"] = tokens
        }
        if let p = topP {
            params["top_p"] = p
        }

        return params
    }

    /// 获取完整的 API 参数（包含推荐值）
    /// Get complete API parameters (including recommended values from preset)
    /// 当用户未配置具体参数时使用质量预设的推荐值
    func resolvedParameters() -> (temperature: Double, maxTokens: Int, topP: Double) {
        let recommended = qualityPreset.recommendedParameters
        return (
            temperature ?? recommended.temperature,
            maxTokens ?? recommended.maxTokens,
            topP ?? 1.0
        )
    }

    /// 默认配置（使用 DeepSeek Reasoner）
    /// Default configuration (using DeepSeek Reasoner)
    static let `default` = LLMModelSettings(
        modelName: "deepseek-reasoner",
        qualityPreset: .balanced,
        temperature: nil,  // Use provider default
        maxTokens: nil,    // Use provider default
        topP: nil,         // Use provider default
        enableStreaming: nil
    )
}

/// 统一的云端 AI 模型配置
/// 一个配置可以同时支持 ASR 和/或 LLM
struct CloudAIModelConfig: Codable, Identifiable, Hashable, Sendable {
    let id: UUID

    /// 用户自定义名称（便于识别）
    var displayName: String

    /// 服务提供商
    var provider: OnlineServiceProvider

    /// 基础配置
    var baseURL: String

    /// 支持的功能类型（一个模型可以支持多种类型）
    var capabilities: Set<ModelCapability>

    /// ASR 专用配置（如果支持 ASR）
    var asrConfig: ASRModelSettings?

    /// LLM 专用配置（如果支持 LLM）
    var llmConfig: LLMModelSettings?

    /// 验证状态
    var isVerified: Bool

    /// 创建时间
    let createdAt: Date

    /// 最后更新时间
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        provider: OnlineServiceProvider,
        baseURL: String,
        capabilities: Set<ModelCapability>,
        asrConfig: ASRModelSettings? = nil,
        llmConfig: LLMModelSettings? = nil,
        isVerified: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.baseURL = baseURL
        self.capabilities = capabilities
        self.asrConfig = asrConfig
        self.llmConfig = llmConfig
        self.isVerified = isVerified
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// 检查是否支持指定能力
    func supports(_ capability: ModelCapability) -> Bool {
        return capabilities.contains(capability)
    }

    /// 获取默认配置 / Get default configuration
    /// v1.1.0: Uses qualityPreset instead of hardcoded parameters
    static func `default`(for provider: OnlineServiceProvider, capabilities: Set<ModelCapability>) -> CloudAIModelConfig {
        // v1.1.0: Only ZhipuAI supports ASR
        let asrConfig: ASRModelSettings? = (capabilities.contains(.asr) && provider.supportsASR) ?
            ASRModelSettings(modelName: provider.defaultASRModel, temperature: nil, maxTokens: nil) : nil

        // v1.1.0: Use qualityPreset with nil parameters (provider defaults)
        let llmConfig: LLMModelSettings? = capabilities.contains(.llm) ?
            LLMModelSettings(
                modelName: provider.defaultLLMModel,
                qualityPreset: .balanced,
                temperature: nil,
                maxTokens: nil,
                topP: nil,
                enableStreaming: nil
            ) : nil

        var capabilityNames: [String] = []
        if capabilities.contains(.asr) && provider.supportsASR { capabilityNames.append("ASR") }
        if capabilities.contains(.llm) { capabilityNames.append("LLM") }

        // Fallback if no capabilities matched (e.g., ASR selected but provider doesn't support)
        let finalCapabilities: Set<ModelCapability>
        if capabilityNames.isEmpty && capabilities.contains(.llm) {
            finalCapabilities = [.llm]
        } else {
            finalCapabilities = capabilities.filter { cap in
                cap != .asr || provider.supportsASR
            }
        }

        return CloudAIModelConfig(
            displayName: "\(provider.displayName) - \(capabilityNames.joined(separator: "+"))",
            provider: provider,
            baseURL: provider.defaultBaseURL,
            capabilities: finalCapabilities,
            asrConfig: asrConfig,
            llmConfig: llmConfig
        )
    }

    /// 获取默认 LLM 配置（快捷方法）/ Get default LLM configuration (convenience method)
    /// v1.1.0: Default provider is DeepSeek, default capability is LLM
    static func defaultLLMConfig(provider: OnlineServiceProvider = .deepseek) -> CloudAIModelConfig {
        return .default(for: provider, capabilities: [.llm])
    }
}

// MARK: - Errors

enum CloudAIError: LocalizedError {
    case modelNotFound
    case apiKeyNotFound
    case invalidConfiguration
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return String(localized: "error.model_not_found", defaultValue: "找不到模型配置")
        case .apiKeyNotFound:
            return String(localized: "error.api_key_not_found", defaultValue: "找不到 API Key")
        case .invalidConfiguration:
            return String(localized: "error.invalid_configuration", defaultValue: "配置无效")
        case .migrationFailed(let message):
            return String(localized: "error.migration_failed", defaultValue: "迁移失败: \(message)")
        }
    }
}
