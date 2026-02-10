//
//  CloudServiceFactory.swift
//  MeetingSonar
//
//  Phase 2: Cloud Service Factory
//

import Foundation
import OSLog

/// 云服务工厂
/// 负责创建和管理云端服务提供商实例
actor CloudServiceFactory {
    static let shared = CloudServiceFactory()

    private let logger = Logger(subsystem: "com.meetingsonar", category: "CloudServiceFactory")
    private var providers: [String: any CloudServiceProvider] = [:]

    private init() {}

    // MARK: - Provider Creation

    /// 创建或获取服务提供商
    /// - Parameters:
    ///   - provider: 提供商类型
    ///   - apiKey: API Key
    ///   - baseURL: 可选的自定义 Base URL
    /// - Returns: 服务提供商实例
    func createProvider(
        _ provider: OnlineServiceProvider,
        apiKey: String,
        baseURL: String? = nil
    ) -> any CloudServiceProvider {
        let key = "\(provider.rawValue)_\(apiKey.prefix(8))"

        // 检查是否已有缓存的实例
        if let cached = providers[key] {
            logger.info("Using cached provider: \(provider.displayName)")
            return cached
        }

        // 创建新实例
        let newProvider: any CloudServiceProvider

        switch provider {
        case .aliyun:
            newProvider = AliyunServiceProvider(
                apiKey: apiKey,
                baseURL: baseURL ?? provider.defaultBaseURL
            )
        case .zhipu:
            newProvider = ZhipuServiceProvider(
                apiKey: apiKey,
                baseURL: baseURL ?? provider.defaultBaseURL
            )
        case .deepseek:
            // DeepSeek 使用 OpenAI 兼容格式
            newProvider = OpenAICompatibleProvider(
                apiKey: apiKey,
                baseURL: baseURL ?? provider.defaultBaseURL,
                providerType: .deepseek
            )
        case .kimi:
            // Kimi 使用 OpenAI 兼容格式
            newProvider = OpenAICompatibleProvider(
                apiKey: apiKey,
                baseURL: baseURL ?? provider.defaultBaseURL,
                providerType: .kimi
            )
        }

        // 缓存实例
        providers[key] = newProvider
        logger.info("Created new provider: \(provider.displayName)")

        return newProvider
    }

    /// 从配置创建提供商
    func createProvider(from config: OnlineModelConfig, apiKey: String) -> any CloudServiceProvider {
        createProvider(config.provider, apiKey: apiKey, baseURL: config.baseURL)
    }

    /// 获取当前配置的 ASR 提供商
    func getCurrentASRProvider() async throws -> any CloudServiceProvider {
        let config = await ModelManager.shared.getASROnlineConfig()
        guard let apiKey = await KeychainService.shared.load(
            for: config.id.uuidString,
            modelType: .asr
        ), !apiKey.isEmpty else {
            throw CloudServiceError.invalidAPIKey
        }
        return createProvider(from: config, apiKey: apiKey)
    }

    /// 获取当前配置的 LLM 提供商
    func getCurrentLLMProvider() async throws -> any CloudServiceProvider {
        let config = await ModelManager.shared.getLLMOnlineConfig()
        guard let apiKey = await KeychainService.shared.load(
            for: config.id.uuidString,
            modelType: .llm
        ), !apiKey.isEmpty else {
            throw CloudServiceError.invalidAPIKey
        }
        return createProvider(from: config, apiKey: apiKey)
    }

    // MARK: - Cache Management

    /// 清除缓存
    func clearCache() {
        providers.removeAll()
        logger.info("Provider cache cleared")
    }

    /// 移除特定提供商的缓存
    func removeFromCache(provider: OnlineServiceProvider, apiKey: String) {
        let key = "\(provider.rawValue)_\(apiKey.prefix(8))"
        providers.removeValue(forKey: key)
        logger.info("Removed provider from cache: \(provider.displayName)")
    }
}

// MARK: - OpenAI Compatible Provider

/// OpenAI 兼容格式的提供商（适用于 DeepSeek、OpenAI 等）
actor OpenAICompatibleProvider: CloudServiceProvider {

    let provider: OnlineServiceProvider
    let apiKey: String
    let baseURL: String

    private let logger = Logger(subsystem: "com.meetingsonar", category: "OpenAICompatibleProvider")
    private let urlSession: URLSession
    private let retryPolicy: RetryPolicy

    init(apiKey: String, baseURL: String, providerType: OnlineServiceProvider) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.provider = providerType
        self.retryPolicy = .default

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - ASR Implementation

    func transcribe(
        audioData: Data,
        model: String,
        prompt: String?
    ) async throws -> CloudTranscriptionResult {
        logger.info("Starting OpenAI-compatible ASR with model: \(model)")

        let endpoint = "\(baseURL)/audio/transcriptions"
        guard let url = URL(string: endpoint) else {
            throw CloudServiceError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        if let prompt = prompt {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(prompt)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let startTime = Date()

        let (data, response) = try await performRequestWithRetry(request: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw handleHTTPError(httpResponse, data: data)
        }

        let result = try parseASRResponse(data: data)
        let processingTime = Date().timeIntervalSince(startTime)

        logger.info("ASR completed in \(processingTime)s")

        return CloudTranscriptionResult(
            text: result.text,
            segments: result.segments,
            language: result.language,
            processingTime: processingTime,
            audioDuration: result.audioDuration,
            usage: result.usage
        )
    }

    func transcribeStream(
        audioData: Data,
        model: String,
        prompt: String?,
        onProgress: (Double) -> Void
    ) async throws -> CloudTranscriptionResult {
        onProgress(0.5)
        let result = try await transcribe(audioData: audioData, model: model, prompt: prompt)
        onProgress(1.0)
        return result
    }

    // MARK: - LLM Implementation

    func generateChatCompletion(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> CloudLLMResult {
        logger.info("Starting OpenAI-compatible LLM with model: \(model)")

        let endpoint = "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw CloudServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let messagesDict = messages.map { [
            "role": $0.role.rawValue,
            "content": $0.content
        ] }

        let body: [String: Any] = [
            "model": model,
            "messages": messagesDict,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startTime = Date()

        let (data, response) = try await performRequestWithRetry(request: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw handleHTTPError(httpResponse, data: data)
        }

        let result = try parseLLMResponse(data: data)
        let processingTime = Date().timeIntervalSince(startTime)

        logger.info("LLM completed in \(processingTime)s")

        return CloudLLMResult(
            text: result.text,
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens,
            processingTime: processingTime,
            model: model
        )
    }

    // MARK: - Streaming LLM Implementation

    func generateChatCompletionStream(
        messages: [ChatMessage],
        model: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> AsyncStream<String> {
        logger.info("Starting OpenAI-compatible streaming LLM with model: \(model)")

        let endpoint = "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw CloudServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let messagesDict = messages.map { [
            "role": $0.role.rawValue,
            "content": $0.content
        ] }

        var body: [String: Any] = [
            "model": model,
            "messages": messagesDict,
            "stream": true
        ]

        // Only add parameters if explicitly set
        if let temp = temperature {
            body["temperature"] = temp
        }
        if let tokens = maxTokens {
            body["max_tokens"] = tokens
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return AsyncStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await urlSession.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw CloudServiceError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                        }
                        throw self.handleHTTPError(httpResponse, data: data)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        // Parse SSE format: "data: {...}"
                        guard line.hasPrefix("data: ") else { continue }

                        let jsonString = String(line.dropFirst(6))

                        // Check for stream end
                        if jsonString == "[DONE]" {
                            continuation.finish()
                            return
                        }

                        // Parse JSON
                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let firstChoice = choices.first,
                              let delta = firstChoice["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    logger.error("Streaming error: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - API Key Verification

    func verifyAPIKey() async throws -> Bool {
        logger.info("Verifying OpenAI-compatible API key")

        let endpoint = "\(baseURL)/models"
        guard let url = URL(string: endpoint) else {
            throw CloudServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    // MARK: - Private Methods

    private func performRequestWithRetry(request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?

        for attempt in 0..<retryPolicy.maxRetries {
            do {
                let (data, response) = try await urlSession.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   shouldRetry(statusCode: httpResponse.statusCode) {
                    lastError = CloudServiceError.serviceUnavailable
                    let delay = retryPolicy.delayForRetry(attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                return (data, response)
            } catch {
                lastError = error
                if attempt < retryPolicy.maxRetries - 1 {
                    let delay = retryPolicy.delayForRetry(attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? CloudServiceError.unknown
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        statusCode >= 500 || statusCode == 429
    }

    private func parseASRResponse(data: Data) throws -> (
        text: String,
        segments: [TranscriptSegment],
        language: String?,
        audioDuration: TimeInterval?,
        usage: TokenUsage?
    ) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudServiceError.invalidResponse
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw CloudServiceError.apiError(message)
        }

        guard let text = json["text"] as? String else {
            throw CloudServiceError.invalidResponse
        }

        // Parse segments if available
        var segments: [TranscriptSegment] = []
        if let words = json["words"] as? [[String: Any]] {
            // Similar logic to Zhipu provider
            var currentText = ""
            var startTime: TimeInterval = 0
            var endTime: TimeInterval = 0

            for (index, word) in words.enumerated() {
                if let wordText = word["word"] as? String,
                   let wordStart = word["start"] as? TimeInterval,
                   let wordEnd = word["end"] as? TimeInterval {

                    if currentText.isEmpty {
                        startTime = wordStart
                    }
                    currentText += wordText
                    endTime = wordEnd

                    if wordText.hasSuffix("。") || wordText.hasSuffix("？") || wordText.hasSuffix("！") ||
                       (index == words.count - 1) {
                        segments.append(TranscriptSegment(
                            start: startTime,
                            end: endTime,
                            text: currentText
                        ))
                        currentText = ""
                    }
                }
            }
        }

        let language = json["language"] as? String
        let duration = json["duration"] as? TimeInterval

        var usage: TokenUsage?
        if let usageDict = json["usage"] as? [String: Any],
           let promptTokens = usageDict["prompt_tokens"] as? Int,
           let completionTokens = usageDict["completion_tokens"] as? Int {
            usage = TokenUsage(promptTokens: promptTokens, completionTokens: completionTokens)
        }

        return (text, segments, language, duration, usage)
    }

    private func parseLLMResponse(data: Data) throws -> (
        text: String,
        inputTokens: Int,
        outputTokens: Int
    ) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudServiceError.invalidResponse
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw CloudServiceError.apiError(message)
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CloudServiceError.invalidResponse
        }

        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0

        return (content, inputTokens, outputTokens)
    }
}
