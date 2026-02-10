//
//  ZhipuServiceProvider.swift
//  MeetingSonar
//
//  Phase 2: Zhipu AI Implementation
//

import Foundation

/// 智谱 AI 服务提供商
actor ZhipuServiceProvider: CloudServiceProvider {

    // MARK: - Properties

    let provider: OnlineServiceProvider = .zhipu
    let apiKey: String
    let baseURL: String

    private let urlSession: URLSession
    private let retryPolicy: RetryPolicy

    // MARK: - Initialization

    init(apiKey: String, baseURL: String = "https://open.bigmodel.cn/api/paas/v4") {
        self.apiKey = apiKey
        self.baseURL = baseURL
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
        LoggerService.shared.log(category: .ai, message: "[Zhipu ASR Request] Starting transcription with model: \(model)")

        // 智谱的 ASR API 端点
        let endpoint = "\(baseURL)/audio/transcriptions"
        guard let url = URL(string: endpoint) else {
            throw CloudServiceError.invalidURL
        }

        // 构建 multipart/form-data 请求
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // 构建请求体
        var body = Data()

        // 添加模型参数
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // 添加提示词（如果有）
        if let prompt = prompt {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(prompt)\r\n".data(using: .utf8)!)
        }

        // 添加音频文件
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

        let processingTime = Date().timeIntervalSince(startTime)

        guard httpResponse.statusCode == 200 else {
            LoggerService.shared.log(category: .ai, level: .error, message: """
            [Zhipu ASR Response] HTTP ERROR
            ├─ Status Code: \(httpResponse.statusCode)
            ├─ Model: \(model)
            ├─ Processing Time: \(String(format: "%.2f", processingTime))s
            ├─ Response Size: \(data.count) bytes
            └─ Error: \(String(data: data, encoding: .utf8) ?? "N/A")
            """)
            throw handleHTTPError(httpResponse, data: data)
        }

        let result = try parseASRResponse(data: data)

        // 详细日志：成功响应
        LoggerService.shared.log(category: .ai, message: """
        [Zhipu ASR Response] SUCCESS
        ├─ Status Code: \(httpResponse.statusCode)
        ├─ Model: \(model)
        ├─ Processing Time: \(String(format: "%.2f", processingTime))s
        ├─ Text Length: \(result.text.count) chars
        ├─ Segments: \(result.segments.count)
        ├─ Language: \(result.language ?? "N/A")
        ├─ Audio Duration: \(result.audioDuration.map { String(format: "%.2f", $0) + "s" } ?? "N/A")
        \(result.usage.map { "└─ Tokens: \($0.promptTokens + $0.completionTokens) (prompt: \($0.promptTokens), completion: \($0.completionTokens))" } ?? "└─ Token Usage: N/A")
        """)

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
        // 详细日志：LLM 请求信息
        LoggerService.shared.log(category: .ai, message: """
        [LLM Request] Starting chat completion
        ├─ Provider: Zhipu AI
        ├─ Model: \(model)
        ├─ Temperature: \(temperature)
        ├─ Max Tokens: \(maxTokens)
        └─ Messages: \(messages.count)
        """)

        let endpoint = "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw CloudServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // 构建请求体（OpenAI 兼容格式）
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

        let processingTime = Date().timeIntervalSince(startTime)

        guard httpResponse.statusCode == 200 else {
            LoggerService.shared.log(category: .ai, level: .error, message: """
            [LLM Response] HTTP ERROR
            ├─ Status Code: \(httpResponse.statusCode)
            ├─ Model: \(model)
            ├─ Processing Time: \(String(format: "%.2f", processingTime))s
            └─ Error: \(String(data: data, encoding: .utf8) ?? "N/A")
            """)
            throw handleHTTPError(httpResponse, data: data)
        }

        let result = try parseLLMResponse(data: data)

        // 详细日志：LLM 响应信息
        LoggerService.shared.log(category: .ai, message: """
        [LLM Response] SUCCESS
        ├─ Status Code: \(httpResponse.statusCode)
        ├─ Model: \(model)
        ├─ Processing Time: \(String(format: "%.2f", processingTime))s
        ├─ Output Length: \(result.text.count) chars
        ├─ Input Tokens: \(result.inputTokens)
        ├─ Output Tokens: \(result.outputTokens)
        └─ Total Tokens: \(result.inputTokens + result.outputTokens)
        """)

        return CloudLLMResult(
            text: result.text,
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens,
            processingTime: processingTime,
            model: model
        )
    }

    // MARK: - API Key Verification

    func verifyAPIKey() async throws -> Bool {
        LoggerService.shared.log(category: .ai, message: "Verifying Zhipu API key")

        // 使用模型列表 API 验证
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
                    LoggerService.shared.log(category: .ai, level: .warning, message: "Request failed with status \(httpResponse.statusCode), retrying in \(delay)s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                return (data, response)
            } catch {
                lastError = error
                if attempt < retryPolicy.maxRetries - 1 {
                    let delay = retryPolicy.delayForRetry(attempt)
                    LoggerService.shared.log(category: .ai, level: .warning, message: "Request failed: \(error.localizedDescription), retrying in \(delay)s...")
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

        // 检查错误
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw CloudServiceError.apiError(message)
        }

        // 解析结果
        guard let text = json["text"] as? String else {
            throw CloudServiceError.invalidResponse
        }

        // 智谱 ASR 返回格式与 OpenAI 兼容
        var segments: [TranscriptSegment] = []

        // 1. 尝试直接获取 segments 字段
        if let segmentsArray = json["segments"] as? [[String: Any]] {
            for segment in segmentsArray {
                if let segText = segment["text"] as? String,
                   let segStart = segment["start"] as? TimeInterval,
                   let segEnd = segment["end"] as? TimeInterval {
                    segments.append(TranscriptSegment(
                        start: segStart,
                        end: segEnd,
                        text: segText
                    ))
                }
            }
        }
        // 2. 如果没有 segments，尝试从 words 构建
        else if let words = json["words"] as? [[String: Any]] {
            // 将单词组合成句子
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

                    // 句子结束标志
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
        // 3. 如果都没有，将整个 text 作为一个 segment
        else if !text.isEmpty {
            let duration = json["duration"] as? TimeInterval ?? 0
            segments.append(TranscriptSegment(
                start: 0,
                end: duration,
                text: text
            ))
        }

        let language = json["language"] as? String
        let duration = json["duration"] as? TimeInterval

        // 解析使用量
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

        // 检查错误
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw CloudServiceError.apiError(message)
        }

        // 解析结果
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CloudServiceError.invalidResponse
        }

        // 解析 token 使用量
        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0

        return (content, inputTokens, outputTokens)
    }

    // MARK: - Streaming LLM Implementation (v1.1.0)

    /// Stream summary generation using SSE
    /// Zhipu AI supports streaming via "stream": true parameter
    func generateChatCompletionStream(
        messages: [ChatMessage],
        model: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> AsyncStream<String> {
        LoggerService.shared.log(category: .ai, message: "[Zhipu] Starting streaming LLM with model: \(model)")

        let endpoint = "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw CloudServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let messagesDict: [[String: String]] = messages.map {
            ["role": $0.role.rawValue, "content": $0.content]
        }

        var body: [String: Any] = [
            "model": model,
            "messages": messagesDict,
            "stream": true  // Enable streaming
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
                    LoggerService.shared.log(category: .ai, level: .error, message: "[Zhipu] Streaming error: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }
}
