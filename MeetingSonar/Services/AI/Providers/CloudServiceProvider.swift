//
//  CloudServiceProvider.swift
//  MeetingSonar
//
//  Phase 2: Cloud-only AI Service Architecture
//

import Foundation
import OSLog

// MARK: - Cloud Service Errors

enum CloudServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case authenticationFailed
    case rateLimited(retryAfter: TimeInterval?)
    case quotaExceeded
    case networkError(Error)
    case apiError(String)
    case invalidAPIKey
    case serviceUnavailable
    case timeout
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "error.cloud.invalidURL", defaultValue: "无效的 API URL")
        case .invalidResponse:
            return String(localized: "error.cloud.invalidResponse", defaultValue: "服务器返回无效响应")
        case .authenticationFailed:
            return String(localized: "error.cloud.authenticationFailed", defaultValue: "认证失败，请检查 API Key")
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return String(format: String(localized: "error.cloud.rateLimited.seconds"), Int(seconds))
            }
            return String(localized: "error.cloud.rateLimited", defaultValue: "请求过于频繁，请稍后再试")
        case .quotaExceeded:
            return String(localized: "error.cloud.quotaExceeded", defaultValue: "API 配额已用完")
        case .networkError(let error):
            return String(format: String(localized: "error.cloud.network"), error.localizedDescription)
        case .apiError(let message):
            return String(format: String(localized: "error.cloud.api"), message)
        case .invalidAPIKey:
            return String(localized: "error.cloud.invalidAPIKey", defaultValue: "无效的 API Key")
        case .serviceUnavailable:
            return String(localized: "error.cloud.serviceUnavailable", defaultValue: "服务暂时不可用")
        case .timeout:
            return String(localized: "error.cloud.timeout", defaultValue: "请求超时")
        case .unknown:
            return String(localized: "error.cloud.unknown", defaultValue: "未知错误")
        }
    }
}

// MARK: - Cloud Service Provider Protocol

/// 统一云端服务提供商协议
protocol CloudServiceProvider: Sendable {
    /// 提供商类型
    var provider: OnlineServiceProvider { get }

    /// API Key
    var apiKey: String { get }

    /// Base URL
    var baseURL: String { get }

    /// 是否已配置
    var isConfigured: Bool { get }

    // MARK: - ASR Methods

    /// 转录音频文件
    /// - Parameters:
    ///   - audioData: 音频数据
    ///   - model: 模型名称
    ///   - prompt: 提示词（可选）
    /// - Returns: 转录结果
    func transcribe(
        audioData: Data,
        model: String,
        prompt: String?
    ) async throws -> CloudTranscriptionResult

    /// 流式转录（用于长音频）
    func transcribeStream(
        audioData: Data,
        model: String,
        prompt: String?,
        onProgress: (Double) -> Void
    ) async throws -> CloudTranscriptionResult

    // MARK: - LLM Methods

    /// 生成文本（用于摘要）
    /// - Parameters:
    ///   - messages: 对话消息
    ///   - model: 模型名称
    ///   - temperature: 温度参数
    ///   - maxTokens: 最大 token 数
    /// - Returns: 生成结果
    func generateChatCompletion(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> CloudLLMResult

    /// 流式生成文本（用于实时摘要显示）
    /// - Parameters:
    ///   - messages: 对话消息
    ///   - model: 模型名称
    ///   - temperature: 温度参数（可选，nil 表示使用默认值）
    ///   - maxTokens: 最大 token 数（可选，nil 表示使用默认值）
    /// - Returns: 异步文本流
    func generateChatCompletionStream(
        messages: [ChatMessage],
        model: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> AsyncStream<String>

    /// 验证 API Key 是否有效
    func verifyAPIKey() async throws -> Bool
}

// MARK: - Default Implementations

extension CloudServiceProvider {
    var isConfigured: Bool {
        !apiKey.isEmpty && !baseURL.isEmpty
    }

    /// 构建请求头（子类可以覆盖）
    func buildHeaders() -> [String: String] {
        [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
    }

    /// 处理 HTTP 响应错误
    func handleHTTPError(_ response: HTTPURLResponse, data: Data?) -> CloudServiceError {
        switch response.statusCode {
        case 401:
            return .authenticationFailed
        case 403:
            return .invalidAPIKey
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            return .rateLimited(retryAfter: retryAfter)
        case 503:
            return .serviceUnavailable
        case 500...599:
            return .serviceUnavailable
        default:
            if let data = data,
               let errorMsg = parseErrorMessage(from: data) {
                return .apiError(errorMsg)
            }
            return .apiError("HTTP \(response.statusCode)")
        }
    }

    /// 解析错误消息（子类可以覆盖）
    func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // 尝试常见错误字段
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        if let message = json["message"] as? String {
            return message
        }

        if let errorMsg = json["error_msg"] as? String {
            return errorMsg
        }

        return nil
    }
}

// MARK: - Result Types

/// 云端 ASR 转录结果
struct CloudTranscriptionResult {
    /// 完整转录文本
    let text: String

    /// 分段结果（带时间戳）
    let segments: [TranscriptSegment]

    /// 检测到的语言
    let language: String?

    /// 处理时间
    let processingTime: TimeInterval

    /// 输入音频时长
    let audioDuration: TimeInterval?

    /// Token 使用量（如果有）
    let usage: TokenUsage?
}

/// 云端 LLM 生成结果
struct CloudLLMResult {
    /// 生成的文本
    let text: String

    /// 输入 token 数
    let inputTokens: Int

    /// 输出 token 数
    let outputTokens: Int

    /// 处理时间
    let processingTime: TimeInterval

    /// 模型名称
    let model: String

    /// Token 使用量
    var usage: TokenUsage {
        TokenUsage(promptTokens: inputTokens, completionTokens: outputTokens)
    }
}

/// Token 使用量
struct TokenUsage {
    let promptTokens: Int
    let completionTokens: Int

    var totalTokens: Int {
        promptTokens + completionTokens
    }
}

/// 对话消息
struct ChatMessage {
    let role: MessageRole
    let content: String

    enum MessageRole: String {
        case system
        case user
        case assistant
    }
}

/// 网络请求重试策略
struct RetryPolicy {
    /// 最大重试次数
    let maxRetries: Int

    /// 基础延迟（秒）
    let baseDelay: TimeInterval

    /// 最大延迟（秒）
    let maxDelay: TimeInterval

    /// 是否使用指数退避
    let useExponentialBackoff: Bool

    static let `default` = RetryPolicy(
        maxRetries: 3,
        baseDelay: 1.0,
        maxDelay: 60.0,
        useExponentialBackoff: true
    )

    /// 计算第 n 次重试的延迟
    func delayForRetry(_ attempt: Int) -> TimeInterval {
        guard useExponentialBackoff else { return baseDelay }

        let delay = baseDelay * pow(2.0, Double(attempt))
        return min(delay, maxDelay)
    }
}
