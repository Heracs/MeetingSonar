//
//  OnlineServiceProvider.swift
//  MeetingSonar
//
//  F-9.3: Online service provider enumeration with default configurations
//  Updated: v1.1.0 - Removed OpenAI, added Kimi, updated default models
//

import Foundation

/// 支持的云端 AI 服务提供商
/// Supported cloud AI service providers
enum OnlineServiceProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case aliyun = "aliyun"      // 阿里云 DashScope (LLM only)
    case zhipu = "zhipu"        // 智谱 AI (ASR + LLM)
    case deepseek = "deepseek"  // DeepSeek (LLM only)
    case kimi = "kimi"          // 月之暗面 Kimi (LLM only) - NEW
    // REMOVED: case openai = "openai"

    var id: String { rawValue }

    /// 本地化显示名称 / Localized display name
    var displayName: String {
        switch self {
        case .aliyun:
            return String(localized: "provider.aliyun", defaultValue: "阿里云")
        case .zhipu:
            return String(localized: "provider.zhipu", defaultValue: "智谱 AI")
        case .deepseek:
            return String(localized: "provider.deepseek", defaultValue: "DeepSeek")
        case .kimi:
            return String(localized: "provider.kimi", defaultValue: "Kimi")
        }
    }

    /// 提供商描述 / Provider description
    var description: String {
        switch self {
        case .aliyun:
            return String(localized: "provider.aliyun.description", defaultValue: "阿里云 DashScope 平台，支持 Qwen 系列模型")
        case .zhipu:
            return String(localized: "provider.zhipu.description", defaultValue: "智谱 AI GLM 大模型平台")
        case .deepseek:
            return String(localized: "provider.deepseek.description", defaultValue: "DeepSeek 大模型服务")
        case .kimi:
            return String(localized: "provider.kimi.description", defaultValue: "Kimi 大模型服务，长上下文支持")
        }
    }

    /// SF Symbol 图标 / SF Symbol icon
    var icon: String {
        switch self {
        case .aliyun:
            return "cloud"
        case .zhipu:
            return "brain.head.profile"
        case .deepseek:
            return "sparkle"
        case .kimi:
            return "moon.stars"
        }
    }

    /// 默认基础 URL / Default base URL
    var defaultBaseURL: String {
        switch self {
        case .aliyun:
            return "https://dashscope.aliyuncs.com/api/v1"
        case .zhipu:
            return "https://open.bigmodel.cn/api/paas/v4"
        case .deepseek:
            return "https://api.deepseek.com/v1"
        case .kimi:
            return "https://api.moonshot.cn/v1"
        }
    }

    /// 是否支持 ASR / Supports ASR
    /// v1.1.0: 仅 ZhipuAI 支持 ASR
    var supportsASR: Bool {
        switch self {
        case .zhipu:
            return true
        default:
            return false
        }
    }

    /// 是否支持 LLM / Supports LLM
    var supportsLLM: Bool {
        true  // 所有提供商都支持 LLM
    }

    /// 默认 ASR 模型（仅 ZhipuAI 支持）/ Default ASR model (ZhipuAI only)
    var defaultASRModel: String {
        switch self {
        case .aliyun:
            return ""  // 不支持 ASR
        case .zhipu:
            return "GLM-4-ASR-2512"      // 智谱语音识别模型
        case .deepseek:
            return ""  // 不支持 ASR
        case .kimi:
            return ""  // 不支持 ASR
        }
    }

    /// 默认 LLM 模型（旗舰模型）/ Default LLM model (flagship)
    /// v1.1.0: 更新为各服务商最新旗舰模型
    var defaultLLMModel: String {
        switch self {
        case .aliyun:
            return "qwen-max"              // Qwen3 系列旗舰
        case .zhipu:
            return "glm-4.7"               // GLM-4.7 最新旗舰
        case .deepseek:
            return "deepseek-reasoner"     // DeepSeek 思考模式
        case .kimi:
            return "kimi-2.5"              // Kimi 2.5 最新模型
        }
    }

    /// 支持的 ASR 模型列表 / Supported ASR models
    /// v1.1.0: 仅 ZhipuAI 支持 ASR
    var supportedASRModels: [String] {
        switch self {
        case .aliyun, .deepseek, .kimi:
            return []  // 不支持 ASR
        case .zhipu:
            return [
                "GLM-4-ASR-2512"
            ]
        }
    }

    /// 支持的 LLM 模型列表 / Supported LLM models
    /// v1.1.0: 更新为最新可用模型
    var supportedLLMModels: [String] {
        switch self {
        case .aliyun:
            return [
                "qwen-max",
                "qwen-plus",
                "qwen-turbo",
                "qwen-long"
            ]
        case .zhipu:
            return [
                "glm-4.7",
                "glm-4-plus",
                "glm-4-flash",
                "glm-4"
            ]
        case .deepseek:
            return [
                "deepseek-reasoner",
                "deepseek-chat"
            ]
        case .kimi:
            return [
                "kimi-2.5",
                "moonshot-v1-8k",
                "moonshot-v1-32k",
                "moonshot-v1-128k"
            ]
        }
    }

    /// API 密钥格式提示 / API key format hint
    var apiKeyHint: String {
        switch self {
        case .aliyun:
            return String(localized: "provider.aliyun.apikey_hint", defaultValue: "请输入 DashScope API Key (sk-开头)")
        case .zhipu:
            return String(localized: "provider.zhipu.apikey_hint", defaultValue: "请输入智谱 API Key")
        case .deepseek:
            return String(localized: "provider.deepseek.apikey_hint", defaultValue: "请输入 DeepSeek API Key")
        case .kimi:
            return String(localized: "provider.kimi.apikey_hint", defaultValue: "请输入 Kimi API Key")
        }
    }

    /// 是否需要自定义 Endpoint / Supports custom endpoint
    var supportsCustomEndpoint: Bool {
        false  // v1.1.0: 所有提供商都不需要自定义 endpoint
    }

    /// 文档链接 / Documentation URL
    var documentationURL: String {
        switch self {
        case .aliyun:
            return "https://help.aliyun.com/zh/dashscope/"
        case .zhipu:
            return "https://open.bigmodel.cn/dev/api"
        case .deepseek:
            return "https://platform.deepseek.com/api-docs/"
        case .kimi:
            return "https://platform.moonshot.cn/docs"
        }
    }

    /// 获取验证 API 路径 / Get verification API path
    /// v1.1.0: Aliyun/DeepSeek/Kimi 不支持 ASR，使用 LLM 路径验证
    func verificationPath(for type: OnlineModelType) -> String {
        switch (self, type) {
        case (.aliyun, .llm):
            return "/chat/completions"
        case (.zhipu, .asr):
            return "/audio/transcriptions"
        case (.zhipu, .llm):
            return "/chat/completions"
        case (.deepseek, .llm):
            return "/chat/completions"
        case (.kimi, .llm):
            return "/chat/completions"
        default:
            // 对于不支持 ASR 的提供商，使用 LLM 路径验证
            return "/chat/completions"
        }
    }

    /// 获取默认模型
    func defaultModel(for type: OnlineModelType) -> String {
        switch type {
        case .asr:
            return defaultASRModel
        case .llm:
            return defaultLLMModel
        }
    }
}

// MARK: - Migration Support

extension OnlineServiceProvider {
    /// 从旧版本字符串迁移
    /// Migration from legacy provider identifiers
    static func migrateFromLegacy(_ value: String) -> OnlineServiceProvider {
        // v1.1.0: Map legacy identifiers to current providers
        switch value {
        case "qwen":
            return .aliyun
        case "openai":
            // OpenAI removed in v1.1.0, default to DeepSeek
            return .deepseek
        default:
            return OnlineServiceProvider(rawValue: value) ?? .deepseek
        }
    }

    /// 获取默认提供商（用于新配置）
    /// Default provider for new configurations (v1.1.0: DeepSeek)
    static var `default`: OnlineServiceProvider {
        .deepseek
    }
}
