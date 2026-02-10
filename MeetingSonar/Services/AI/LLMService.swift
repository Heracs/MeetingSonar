import Foundation
import OSLog

// MARK: - Summary Result

/// LLM 生成结果
struct SummaryResult {
    /// 生成的摘要文本
    let summary: String

    /// 输入 token 数
    let inputTokens: Int

    /// 输出 token 数
    let outputTokens: Int

    /// 生成时间（秒）
    let generationTime: TimeInterval

    /// 每秒 token 数
    var tokensPerSecond: Double {
        guard generationTime > 0 else { return 0 }
        return Double(outputTokens) / generationTime
    }
}

// MARK: - LLM Error

enum LLMError: LocalizedError, Equatable {
    case notConfigured
    case generationFailed(String)
    case networkError(String)
    case rateLimited
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "error.llm_not_configured", defaultValue: "LLM 未配置")
        case .generationFailed(let msg):
            return String(localized: "error.llm_generation_failed", defaultValue: "生成失败: \(msg)")
        case .networkError(let msg):
            return String(localized: "error.llm_network", defaultValue: "网络错误: \(msg)")
        case .rateLimited:
            return String(localized: "error.llm_rate_limited", defaultValue: "请求过于频繁，请稍后再试")
        case .quotaExceeded:
            return String(localized: "error.llm_quota_exceeded", defaultValue: "API 配额已用完")
        }
    }
}

// MARK: - LLM Service

/// LLM 服务 - 云端版本
/// 使用云端 API 进行文本生成
actor LLMService {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.meetingsonar", category: "LLMService")

    /// 是否已配置
    private(set) var isConfigured = false

    /// 当前配置
    private var configuration: OnlineLLMConfig?

    /// 共享实例
    static let shared = LLMService()

    private init() {
        logger.info("LLMService initialized (cloud-only mode)")
    }

    // MARK: - Configuration

    /// 配置 LLM 服务
    func configure(with config: OnlineLLMConfig) async {
        self.configuration = config
        self.isConfigured = !config.apiKey.isEmpty && !config.endpoint.isEmpty

        if isConfigured {
            logger.info("LLM service configured with provider: \(config.provider.displayName)")
        } else {
            logger.warning("LLM service configured but API key or endpoint is empty")
        }
    }

    /// 从 ModelManager 加载配置
    func loadConfiguration() async {
        let config = await ModelManager.shared.getOnlineModelConfig()
        let llmConfig = OnlineLLMConfig(
            provider: config.provider,
            apiKey: config.apiKey,
            endpoint: config.endpoint,
            model: config.llmModel
        )
        await configure(with: llmConfig)
    }

    // MARK: - Generation

    /// 生成会议纪要
    /// - Parameters:
    ///   - transcript: 会议转录文本
    ///   - promptTemplate: 可选的自定义提示词模板
    /// - Returns: 生成结果
    func generateSummary(
        transcript: String,
        promptTemplate: String? = nil
    ) async throws -> SummaryResult {
        guard isConfigured else {
            throw LLMError.notConfigured
        }

        guard let config = configuration else {
            throw LLMError.notConfigured
        }

        let startTime = Date()

        logger.info("Generating summary with provider: \(config.provider.displayName)")

        // TODO: Phase 4 实现实际的 API 调用
        // 目前返回占位实现
        throw LLMError.generationFailed(
            String(localized: "error.llm_not_implemented", defaultValue: "云端 LLM 功能尚未实现")
        )
    }

    /// 使用智能分块策略生成摘要
    /// 用于处理超长文本
    func generateSummaryWithSmartChunking(
        transcript: String,
        promptTemplate: String? = nil,
        onProgress: ((Double, String) -> Void)? = nil
    ) async throws -> SummaryResult {
        guard isConfigured else {
            throw LLMError.notConfigured
        }

        logger.info("Generating summary with smart chunking...")

        // TODO: Phase 4 实现 Map-Reduce 策略
        // 如果文本过长，分段处理然后合并

        onProgress?(0.5, String(localized: "processing.stage.llm", defaultValue: "生成摘要中..."))

        return try await generateSummary(transcript: transcript, promptTemplate: promptTemplate)
    }

    // MARK: - Prompt Building

    /// 构建摘要生成提示词
    private func buildSummaryPrompt(transcript: String, customTemplate: String? = nil) -> String {
        if let template = customTemplate {
            return template.replacingOccurrences(of: "{{transcript}}", with: transcript)
        }

        return """
        你是一个专业的会议记录助手。请根据提供的会议转录文本，生成一份结构化的会议纪要。

        要求：
        1. 参会者：列出所有发言者（如果能识别）
        2. 核心议题：用1-3句话概括会议主题
        3. 关键决策：列出会议中做出的重要决定
        4. 待办事项：列出需要跟进的行动项（如有）
        5. 总结：用2-3句话总结会议内容

        请使用简洁清晰的语言，突出重点。

        会议转录文本：
        \(transcript)
        """
    }

    // MARK: - Utility

    /// 保存摘要到文件
    func saveSummary(_ result: SummaryResult, to url: URL) throws {
        let content = """
        # 会议纪要

        生成时间: \(Date())
        处理时间: \(String(format: "%.1f", result.generationTime))秒
        输入 Token: \(result.inputTokens)
        输出 Token: \(result.outputTokens)

        ---

        \(result.summary)
        """

        try content.write(to: url, atomically: true, encoding: .utf8)

        logger.info("Summary saved to: \(url.path)")
    }

    /// 重置服务状态
    func reset() {
        isConfigured = false
        configuration = nil
        logger.info("LLM service reset")
    }
}

// MARK: - Online LLM Configuration

/// 在线 LLM 配置
struct OnlineLLMConfig {
    let provider: OnlineServiceProvider
    let apiKey: String
    let endpoint: String
    let model: String

    init(
        provider: OnlineServiceProvider = .aliyun,
        apiKey: String = "",
        endpoint: String = "",
        model: String = "qwen-turbo"
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
    }
}
