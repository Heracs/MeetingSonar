//
//  AliyunServiceProvider.swift
//  MeetingSonar
//
//  Phase 2: Alibaba Cloud DashScope Implementation
//

import Foundation

/// 阿里云 DashScope 服务提供商
actor AliyunServiceProvider: CloudServiceProvider {

    // MARK: - Properties

    let provider: OnlineServiceProvider = .aliyun
    let apiKey: String
    let baseURL: String

    private let urlSession: URLSession
    private let retryPolicy: RetryPolicy

    // MARK: - Initialization

    init(apiKey: String, baseURL: String = "https://dashscope.aliyuncs.com/api/v1") {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.retryPolicy = .default

        // 配置 URLSession
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5分钟（音频转录可能较慢）
        config.timeoutIntervalForResource = 600 // 10分钟
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Logging Helpers

    private func truncateContent(_ content: String, maxLength: Int = 20) -> String {
        if content.count <= maxLength {
            return content
        }
        return String(content.prefix(maxLength)) + "..."
    }

    private func maskAPIKey(_ key: String) -> String {
        if key.count <= 12 {
            return "***"
        }
        return key.prefix(8) + "..." + key.suffix(4)
    }

    // MARK: - ASR Implementation

    func transcribe(
        audioData: Data,
        model: String,
        prompt: String?
    ) async throws -> CloudTranscriptionResult {
        let endpoint = "\(baseURL)/services/audio/asr/transcription"
        guard let url = URL(string: endpoint) else {
            throw CloudServiceError.invalidURL
        }

        // Log request
        LoggerService.shared.log(category: .ai, level: .debug, message: """
        [Aliyun] API Request:
        ├─ Endpoint: \(endpoint)
        ├─ Method: POST
        ├─ Headers:
        │  ├─ Content-Type: multipart/form-data
        │  ├─ Authorization: Bearer \(maskAPIKey(apiKey))
        │  └─ Content-Length: \(audioData.count) bytes
        └─ Body:
           ├─ Model: \(model)
           ├─ Audio Size: \(String(format: "%.2f", Double(audioData.count) / 1024 / 1024)) MB
           └─ Prompt: \(prompt.map { truncateContent($0) } ?? "N/A")
        """)

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

        // 发送请求（带重试）
        let (data, response) = try await performRequestWithRetry(request: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudServiceError.invalidResponse
        }

        let processingTime = Date().timeIntervalSince(startTime)

        // 检查响应状态
        guard httpResponse.statusCode == 200 else {
            LoggerService.shared.log(category: .ai, level: .error, message: """
            [Aliyun] API Response:
            ├─ Status Code: \(httpResponse.statusCode)
            ├─ Processing Time: \(String(format: "%.2f", processingTime))s
            ├─ Body:
            │  └─ Error: \(String(data: data, encoding: .utf8) ?? "N/A")
            └─ Result: ERROR
            """)
            throw handleHTTPError(httpResponse, data: data)
        }

        // 解析响应
        let result = try parseASRResponse(data: data)

        // Log response
        LoggerService.shared.log(category: .ai, level: .debug, message: """
        [Aliyun] API Response:
        ├─ Status Code: \(httpResponse.statusCode)
        ├─ Processing Time: \(String(format: "%.2f", processingTime))s
        ├─ Body:
        │  ├─ Text: \(truncateContent(result.text, maxLength: 50))
        │  ├─ Segments: \(result.segments.count)
        │  ├─ Language: \(result.language ?? "N/A")
        │  └─ Audio Duration: \(result.audioDuration.map { String(format: "%.2f", $0) + "s" } ?? "N/A")
        └─ Result: SUCCESS
        """)

        return CloudTranscriptionResult(
            text: result.text,
            segments: result.segments,
            language: result.language,
            processingTime: processingTime,
            audioDuration: result.audioDuration,
            usage: nil
        )
    }

    func transcribeStream(
        audioData: Data,
        model: String,
        prompt: String?,
        onProgress: (Double) -> Void
    ) async throws -> CloudTranscriptionResult {
        // 阿里云目前不支持流式 ASR，使用普通转录
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
        let endpoint = "\(baseURL)/services/aigc/text-generation/generation"
        guard let url = URL(string: endpoint) else {
            throw CloudServiceError.invalidURL
        }

        // Build messages for logging
        let messagesDict = messages.map { [
            "role": $0.role.rawValue,
            "content": $0.content
        ] }

        // Log request
        var messagesLog = ""
        for (index, msg) in messages.enumerated() {
            let prefix = index == messages.count - 1 ? "   └─" : "   ├─"
            messagesLog += "\n\(prefix) [\(msg.role.rawValue)]: \(truncateContent(msg.content))"
        }

        LoggerService.shared.log(category: .ai, level: .debug, message: """
        [Aliyun] API Request:
        ├─ Endpoint: \(endpoint)
        ├─ Method: POST
        ├─ Headers:
        │  ├─ Content-Type: application/json
        │  └─ Authorization: Bearer \(maskAPIKey(apiKey))
        └─ Body:
           ├─ Model: \(model)
           ├─ Messages (count: \(messages.count)):\(messagesLog)
           ├─ Temperature: \(temperature)
           └─ Max Tokens: \(maxTokens)
        """)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // 构建请求体（阿里云格式）
        let body: [String: Any] = [
            "model": model,
            "input": [
                "messages": messagesDict
            ],
            "parameters": [
                "temperature": temperature,
                "max_tokens": maxTokens,
                "result_format": "message"
            ]
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
            [Aliyun] API Response:
            ├─ Status Code: \(httpResponse.statusCode)
            ├─ Processing Time: \(String(format: "%.2f", processingTime))s
            ├─ Body:
            │  └─ Error: \(String(data: data, encoding: .utf8) ?? "N/A")
            └─ Result: ERROR
            """)
            throw handleHTTPError(httpResponse, data: data)
        }

        let result = try parseLLMResponse(data: data)

        // Log response
        LoggerService.shared.log(category: .ai, level: .debug, message: """
        [Aliyun] API Response:
        ├─ Status Code: \(httpResponse.statusCode)
        ├─ Processing Time: \(String(format: "%.2f", processingTime))s
        ├─ Body:
        │  ├─ Content: \(truncateContent(result.text, maxLength: 50))
        │  ├─ Input Tokens: \(result.inputTokens)
        │  ├─ Output Tokens: \(result.outputTokens)
        │  └─ Total Tokens: \(result.inputTokens + result.outputTokens)
        └─ Result: SUCCESS
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
        LoggerService.shared.log(category: .ai, message: "Verifying Aliyun API key")

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

    /// 执行带重试的请求
    private func performRequestWithRetry(request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?

        for attempt in 0..<retryPolicy.maxRetries {
            do {
                let (data, response) = try await urlSession.data(for: request)

                // 检查是否需要重试
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

    /// 判断是否应该重试
    private func shouldRetry(statusCode: Int) -> Bool {
        // 5xx 错误和服务不可用应该重试
        statusCode >= 500 || statusCode == 429
    }

    /// 解析 ASR 响应
    private func parseASRResponse(data: Data) throws -> (
        text: String,
        segments: [TranscriptSegment],
        language: String?,
        audioDuration: TimeInterval?
    ) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudServiceError.invalidResponse
        }

        // 检查错误
        if let code = json["code"] as? String, code != "200" {
            let message = json["message"] as? String ?? "Unknown error"
            throw CloudServiceError.apiError(message)
        }

        // 解析结果
        guard let output = json["output"] as? [String: Any],
              let transcription = output["transcription"] as? [String: Any],
              let text = transcription["text"] as? String else {
            throw CloudServiceError.invalidResponse
        }

        // 解析分段（如果有）
        var segments: [TranscriptSegment] = []
        if let sentences = transcription["sentences"] as? [[String: Any]] {
            segments = sentences.compactMap { sentence in
                guard let text = sentence["text"] as? String,
                      let beginTime = sentence["begin_time"] as? TimeInterval,
                      let endTime = sentence["end_time"] as? TimeInterval else {
                    return nil
                }
                return TranscriptSegment(
                    start: beginTime / 1000, // 转换为秒
                    end: endTime / 1000,
                    text: text
                )
            }
        }

        let language = transcription["language"] as? String
        let duration = transcription["duration"] as? TimeInterval

        return (text, segments, language, duration)
    }

    /// 解析 LLM 响应
    private func parseLLMResponse(data: Data) throws -> (
        text: String,
        inputTokens: Int,
        outputTokens: Int
    ) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudServiceError.invalidResponse
        }

        // 检查错误
        if let code = json["code"] as? String, code != "200" {
            let message = json["message"] as? String ?? "Unknown error"
            throw CloudServiceError.apiError(message)
        }

        // 解析结果
        guard let output = json["output"] as? [String: Any],
              let choices = output["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CloudServiceError.invalidResponse
        }

        // 解析 token 使用量
        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["input_tokens"] as? Int ?? 0
        let outputTokens = usage?["output_tokens"] as? Int ?? 0

        return (content, inputTokens, outputTokens)
    }

    // MARK: - Streaming LLM Implementation (v1.1.0)

    /// Stream summary generation using SSE
    /// Aliyun DashScope supports streaming via "stream": true parameter
    func generateChatCompletionStream(
        messages: [ChatMessage],
        model: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> AsyncStream<String> {
        let endpoint = "\(baseURL)/services/aigc/text-generation/generation"
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

        var parameters: [String: Any] = [
            "result_format": "message"
        ]
        if let temp = temperature {
            parameters["temperature"] = temp
        }
        if let tokens = maxTokens {
            parameters["max_tokens"] = tokens
        }

        let body: [String: Any] = [
            "model": model,
            "input": ["messages": messagesDict],
            "parameters": parameters,
            "stream": true  // Enable streaming
        ]

        // Log request
        var messagesLog = ""
        for (index, msg) in messages.enumerated() {
            let prefix = index == messages.count - 1 ? "   └─" : "   ├─"
            messagesLog += "\n\(prefix) [\(msg.role.rawValue)]: \(truncateContent(msg.content))"
        }

        LoggerService.shared.log(category: .ai, level: .debug, message: """
        [Aliyun] API Request (Stream):
        ├─ Endpoint: \(endpoint)
        ├─ Method: POST
        ├─ Headers:
        │  ├─ Content-Type: application/json
        │  └─ Authorization: Bearer \(maskAPIKey(apiKey))
        └─ Body:
           ├─ Model: \(model)
           ├─ Messages (count: \(messages.count)):\(messagesLog)
           ├─ Temperature: \(temperature.map { String($0) } ?? "default")
           ├─ Max Tokens: \(maxTokens.map { String($0) } ?? "default")
           └─ Stream: true
        """)

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return AsyncStream { continuation in
            Task {
                do {
                    let startTime = Date()
                    let (bytes, response) = try await urlSession.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw CloudServiceError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                        }
                        LoggerService.shared.log(category: .ai, level: .error, message: """
                        [Aliyun] API Response (Stream):
                        ├─ Status Code: \(httpResponse.statusCode)
                        ├─ Body:
                        │  └─ Error: \(String(data: data, encoding: .utf8) ?? "N/A")
                        └─ Result: ERROR
                        """)
                        throw self.handleHTTPError(httpResponse, data: data)
                    }

                    var totalContent = ""
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
                            let processingTime = Date().timeIntervalSince(startTime)
                            LoggerService.shared.log(category: .ai, level: .debug, message: """
                            [Aliyun] API Response (Stream):
                            ├─ Status Code: \(httpResponse.statusCode)
                            ├─ Processing Time: \(String(format: "%.2f", processingTime))s
                            ├─ Body:
                            │  ├─ Content: \(self.truncateContent(totalContent, maxLength: 50))
                            │  └─ Total Length: \(totalContent.count) chars
                            └─ Result: SUCCESS
                            """)
                            continuation.finish()
                            return
                        }

                        // Parse JSON
                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let output = json["output"] as? [String: Any],
                              let choices = output["choices"] as? [[String: Any]],
                              let firstChoice = choices.first,
                              let message = firstChoice["message"] as? [String: Any],
                              let content = message["content"] as? String else {
                            continue
                        }

                        totalContent += content
                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    LoggerService.shared.log(category: .ai, level: .error, message: "[Aliyun] Streaming error: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }
}
