//
//  OnlineModelsExtensions.swift
//  MeetingSonar
//
//  F-9.3: Online model related extensions and UI components
//
//  NOTE: OnlineModelType and OnlineServiceProvider enums have been moved to
//  separate files (Models/OnlineModelType.swift and Models/OnlineServiceProvider.swift)
//  to support proper localization.

import Foundation
import SwiftUI
import AVFoundation
import Accelerate

// MARK: - Data Models

/// Configuration for an online AI model
struct OnlineModelConfig: Codable, Identifiable, Hashable {

    // MARK: - LLM Parameter Defaults

    /// Default LLM parameters
    enum LLMDefaults {
        /// Default temperature (controls randomness/creativity)
        /// 0.7 provides balanced creativity and coherence
        static let temperature: Double = 0.7
        /// Default maximum tokens for response
        /// 4096 tokens allows for comprehensive summaries
        static let maxTokens: Int = 4096
        /// Default top_p (nucleus sampling parameter)
        /// 0.95 focuses on the most likely 95% of tokens
        static let topP: Double = 0.95
    }

    /// Default ASR parameters
    enum ASRDefaults {
        /// Default temperature for ASR (should be 0 for consistent transcription)
        static let temperature: Double = 0.0
        /// Default maximum tokens for transcription
        /// 1000 tokens is sufficient for typical meeting segments
        static let maxTokens: Int = 1000
    }

    let id: UUID
    var provider: OnlineServiceProvider
    var modelName: String
    var baseURL: String
    var isVerified: Bool
    var temperature: Double?
    var maxTokens: Int?
    var topP: Double?

    init(
        id: UUID = UUID(),
        provider: OnlineServiceProvider,
        modelName: String,
        baseURL: String,
        isVerified: Bool = false,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil
    ) {
        self.id = id
        self.provider = provider
        self.modelName = modelName
        self.baseURL = baseURL
        self.isVerified = isVerified
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
    }

    static func defaultConfig(provider: OnlineServiceProvider, type: OnlineModelType) -> OnlineModelConfig {
        return OnlineModelConfig(
            provider: provider,
            modelName: provider.defaultModel(for: type),
            baseURL: provider.defaultBaseURL,
            temperature: type == .llm ? OnlineModelConfig.LLMDefaults.temperature : OnlineModelConfig.ASRDefaults.temperature,
            maxTokens: type == .llm ? OnlineModelConfig.LLMDefaults.maxTokens : OnlineModelConfig.ASRDefaults.maxTokens,
            topP: type == .llm ? OnlineModelConfig.LLMDefaults.topP : nil
        )
    }
}

// MARK: - Verification

enum VerificationResult {
    case success
    case failure(String)
}

@MainActor
final class APIKeyVerifier: ObservableObject {
    static let shared = APIKeyVerifier()
    private init() {}
    
    func verify(config: OnlineModelConfig, apiKey: String, type: OnlineModelType) async -> VerificationResult {
        LoggerService.shared.log(
            category: .general,
            message: "[APIKeyVerifier] Verifying \(config.provider.displayName) \(type.rawValue) model: \(config.modelName)"
        )
        
        let baseURL = config.baseURL
        let path = config.provider.verificationPath(for: type)
        let fullURL = baseURL + path

        // Log sanitized URL
        let sanitizedURL = SensitiveDataSanitizer.sanitizeURL(fullURL)
        LoggerService.shared.log(category: .general, message: "[APIKeyVerifier] Request URL: \(sanitizedURL)")

        guard let url = URL(string: fullURL) else {
            LoggerService.shared.log(category: .general, level: .error, message: "[APIKeyVerifier] Invalid URL: \(sanitizedURL)")
            return .failure(String(format: String(localized: "error.invalidBaseURL.%@"), sanitizedURL))
        }
        
        if type == .asr {
            // Use Multipart/Form-Data for ASR
            guard let request = createMultipartRequest(config: config, apiKey: apiKey, type: type) else {
                return .failure(String(localized: "error.cannotCreateMultipartRequest"))
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    return .failure(String(localized: "error.invalidResponse"))
                }
                
                LoggerService.shared.log(category: .general, message: "[APIKeyVerifier] ASR Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    return .success
                } else {
                    // Log sanitized error response
                    let sanitizedResponse = SensitiveDataSanitizer.sanitizeResponseBody(data)
                    LoggerService.shared.log(category: .general, level: .error, message: "[APIKeyVerifier] ASR Error Response: \(sanitizedResponse)")
                    let errorMessage = parseErrorMessage(from: data, provider: config.provider)
                    return .failure(String(format: String(localized: "error.verificationFailed.%@.%@"), String(httpResponse.statusCode), errorMessage))
                }
            } catch {
                LoggerService.shared.log(category: .general, level: .error, message: "[APIKeyVerifier] ASR Network Error: \(error)")
                return .failure(String(format: String(localized: "error.networkError.%@"), error.localizedDescription))
            }
            
        } else {
            // Use JSON for LLM
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            // Log headers (mask API Key using sanitizer)
            let maskedKey = SensitiveDataSanitizer.maskBearerToken(apiKey)
            LoggerService.shared.log(category: .general, message: "[APIKeyVerifier] LLM Headers: Content-Type=application/json, Authorization=Bearer \(maskedKey)")

            guard let testPayload = createTestPayload(for: config, type: type) else {
                LoggerService.shared.log(category: .general, level: .error, message: "[APIKeyVerifier] Failed to create test payload for \(config.provider.displayName)")
                return .failure(String(localized: "error.cannotCreateTestData"))
            }
            request.httpBody = testPayload

            // Log sanitized payload
            let sanitizedPayload = SensitiveDataSanitizer.sanitizeRequestBody(testPayload)
            LoggerService.shared.log(category: .general, message: "[APIKeyVerifier] LLM Payload: \(sanitizedPayload)")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    return .failure(String(localized: "error.invalidResponse"))
                }
                
                LoggerService.shared.log(category: .general, message: "[APIKeyVerifier] LLM Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    LoggerService.shared.log(category: .general, message: "[APIKeyVerifier] Verification successful")
                    return .success
                } else {
                    // Log sanitized error response
                    let sanitizedResponse = SensitiveDataSanitizer.sanitizeResponseBody(data)
                    LoggerService.shared.log(category: .general, level: .error, message: "[APIKeyVerifier] LLM Error Response: \(sanitizedResponse)")
                    let errorMessage = parseErrorMessage(from: data, provider: config.provider)
                    return .failure(String(format: String(localized: "error.verificationFailed.%@.%@"), String(httpResponse.statusCode), errorMessage))
                }
            } catch {
                LoggerService.shared.log(category: .general, level: .error, message: "[APIKeyVerifier] LLM Network Error: \(error)")
                return .failure(String(format: String(localized: "error.networkError.%@"), error.localizedDescription))
            }
        }
    }
    
    private func createMultipartRequest(config: OnlineModelConfig, apiKey: String, type: OnlineModelType) -> URLRequest? {
        let baseURL = config.baseURL
        let path = config.provider.verificationPath(for: type)
        guard let url = URL(string: baseURL + path) else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        var body = Data()
        
        // 1. Add Model ID
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(config.modelName)\r\n".data(using: .utf8)!)
        
        // 2. Add File Data (Generated 1s Silent WAV)
        let wavData = generateSilentWav()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"test_audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End Boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body

        // Debug Logging - use sanitizer for consistent behavior
        let sanitizedBody = SensitiveDataSanitizer.sanitizeRequestBody(body, maxLength: 500)
        LoggerService.shared.log(category: .general, message: "[APIKeyVerifier] Request Body: \(sanitizedBody)")

        return request
    }
    
    private func generateSilentWav() -> Data {
        let sampleRate: Int32 = 16000
        let duration: Double = 1.0
        let numSamples = Int(Double(sampleRate) * duration)
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate) * Int32(numChannels) * Int32(bitsPerSample) / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = Int32(numSamples) * Int32(blockAlign)
        let chunkSize = 36 + dataSize
        
        var wavData = Data()
        
        // RIFF Header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: chunkSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt Subchunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: Int32(16).littleEndian) { Data($0) }) // Subchunk1Size
        wavData.append(withUnsafeBytes(of: Int16(1).littleEndian) { Data($0) })  // AudioFormat (PCM)
        wavData.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        
        // data Subchunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        
        // Silent PCM data (zeros)
        let silentBytes = [UInt8](repeating: 0, count: Int(dataSize))
        wavData.append(contentsOf: silentBytes)
        
        return wavData
    }
    
    private func createTestPayload(for config: OnlineModelConfig, type: OnlineModelType) -> Data? {
        // Only for LLM now
        var payload: [String: Any] = [:]
        
        switch (config.provider, type) {
        case (.zhipu, .llm), (.deepseek, .llm):
            payload = [
                "model": config.modelName,
                "messages": [["role": "user", "content": "Hi"]],
                "max_tokens": 1
            ]
        case (.aliyun, .llm):
            payload = [
                "model": config.modelName,
                "input": ["messages": [["role": "user", "content": "Hi"]]],
                "parameters": ["max_tokens": 1]
            ]
        default:
            return nil
        }
        
        return try? JSONSerialization.data(withJSONObject: payload)
    }
    
    private func parseErrorMessage(from data: Data, provider: OnlineServiceProvider) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(localized: "error.unknown")
        }
        
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = json["message"] as? String {
            return message
        }
        if let errorMsg = json["error_msg"] as? String {
            return errorMsg
        }

        return String(localized: "error.unknown")
    }
}

actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) { self.permits = value }

    func wait() async {
        if permits > 0 {
            permits -= 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func signal() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            permits += 1
        }
    }
}

class OnlineASRService {
    private let splitter = AudioSplitter()
    private let maxConcurrency = 3
    
    /// Transcribes the audio file using the specified online configuration.
    /// Handles splitting, concurrent uploading, and merging.
    /// Returns: TranscriptResult (structured with segments)
    func transcribe(audioURL: URL, config: OnlineModelConfig) async throws -> TranscriptResult {
        // 1. Validate API Key
        guard let apiKey = await KeychainService.shared.load(for: config.id.uuidString, modelType: .asr) else {
            throw NSError(domain: "OnlineASRService", code: 401, userInfo: [NSLocalizedDescriptionKey: String(localized: "error.apiKeyNotFound")])
        }
        
        // 2. Split Audio
        LoggerService.shared.log(category: .general, message: "[OnlineASR] Starting split for \(audioURL.lastPathComponent)")
        let chunks = try await splitter.split(audioURL: audioURL)
        LoggerService.shared.log(category: .general, message: "[OnlineASR] Generated \(chunks.count) chunks")
        
        if chunks.isEmpty {
            return TranscriptResult(
                segments: [],
                fullText: "",
                duration: 0,
                processingTime: 0
            )
        }
        
        let totalAudioDuration = chunks.last.map { $0.start + $0.duration } ?? 0
        let startTime = Date()
        
        // 3. Concurrent Upload
        let semaphore = AsyncSemaphore(value: maxConcurrency)
        
        // Store results indexed by chunk index to maintain order
        let results = await withTaskGroup(of: (Int, String).self) { group -> [(Int, String)] in
            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    await semaphore.wait()
                    defer {
                        Task { await semaphore.signal() }
                        // Cleanup temp file
                        try? FileManager.default.removeItem(at: chunk.url)
                    }
                    
                    let chunkStart = Date()
                    do {
                        let (text, latency, metadata) = try await self.uploadAndTranscribe(chunkURL: chunk.url, config: config, apiKey: apiKey)
                        
                        // F-10.1 Logging: Log chunk success
                        LoggerService.shared.logMetric(event: "online_asr_chunk_processed", attributes: [
                            "chunk_index": index,
                            "chunk_duration": String(format: "%.2f", chunk.duration),
                            "latency_ms": Int(latency * 1000),
                            "status": "success",
                            "provider": config.provider.rawValue,
                            "request_id": metadata["request_id"] as? String ?? "",
                            "task_id": metadata["task_id"] as? String ?? ""
                        ])
                        
                        return (index, text)
                    } catch {
                        LoggerService.shared.log(category: .general, message: "[OnlineASR] Chunk \(index) failed: \(error.localizedDescription)")
                        
                         // F-10.1 Logging: Log chunk failure
                        LoggerService.shared.logMetric(event: "online_asr_chunk_processed", attributes: [
                            "chunk_index": index,
                            "chunk_duration": String(format: "%.2f", chunk.duration),
                            "latency_ms": Int(Date().timeIntervalSince(chunkStart) * 1000),
                            "status": "failed",
                            "error": error.localizedDescription
                        ])
                        
                        return (index, "[Chunk Error]") // Graceful failure for single chunk
                    }
                }
            }
            
            var collected: [(Int, String)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        
        // 4. Merge & Convert to TranscriptResult
        let sortedResults = results.sorted { $0.0 < $1.0 }
        
        var segments: [TranscriptResult.Segment] = []
        var fullText = ""
        
        for (index, text) in sortedResults {
            let chunk = chunks[index] // Safe since indices match
            let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !cleanText.isEmpty {
                let segment = TranscriptResult.Segment(
                    start: chunk.start,
                    end: chunk.start + chunk.duration,
                    text: cleanText
                )
                segments.append(segment)
                fullText += cleanText + " "
            }
        }
        
        fullText = fullText.trimmingCharacters(in: .whitespaces)
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Log total stats
        LoggerService.shared.logMetric(event: "online_asr_job_finished", attributes: [
            "total_chunks": chunks.count,
            "audio_duration": String(format: "%.2f", totalAudioDuration),
            "processing_time": String(format: "%.2f", processingTime),
            "model": config.modelName
        ])
        
        return TranscriptResult(
            segments: segments,
            fullText: fullText,
            duration: totalAudioDuration,
            processingTime: processingTime
        )
    }
    
    private func uploadAndTranscribe(chunkURL: URL, config: OnlineModelConfig, apiKey: String) async throws -> (String, TimeInterval, [String: Any]) {
        let baseURL = config.baseURL
        let path = config.provider.verificationPath(for: .asr)
        guard let url = URL(string: baseURL + path) else {
             throw NSError(domain: "OnlineASRService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Multipart Body construction
        var body = Data()
        let fileData = try Data(contentsOf: chunkURL)
        
        // Helper to append string
        func append(_ str: String) {
            body.append(str.data(using: .utf8)!)
        }
        
        // Model
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(config.modelName)\r\n")
        
        // File
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"chunk.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        
        append("--\(boundary)--\r\n")
        
        request.httpBody = body
        
        let startTime = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime)
        
        guard let httpResponse = response as? HTTPURLResponse else {
             throw NSError(domain: "OnlineASRService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
             let (text, meta) = parseResult(data: data)
             return (text, latency, meta)
        } else {
             let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
             throw NSError(domain: "OnlineASRService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMsg)"])
        }
    }
    
    private func parseResult(data: Data) -> (String, [String: Any]) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("", [:])
        }
        
        // Standard OpenAI
        if let text = json["text"] as? String { 
            return (text, json)
        }
        
        // Zhipu / Others
        if let result = json["result"] as? String {
             return (result, json)
        }
        
        // Fallback: check nested choices (OpenAI Audio standard sometimes uses choices?)
        // Usually ASR is {"text": "..."}
        
        return ("", json)
    }
}
// MARK: - Online LLM Service

class OnlineLLMService {
    
    /// Generate meeting summary from transcript using online LLM
    /// - Parameters:
    ///   - transcript: Full transcript text
    ///   - config: Online model configuration
    /// - Returns: SummaryResult with generated summary
    func generateSummary(transcript: String, config: OnlineModelConfig) async throws -> SummaryResult {
        // 1. Validate API Key
        guard let apiKey = await KeychainService.shared.load(for: config.id.uuidString, modelType: .llm) else {
            throw NSError(domain: "OnlineLLMService", code: 401, userInfo: [NSLocalizedDescriptionKey: String(localized: "error.apiKeyNotFound")])
        }
        
        LoggerService.shared.log(category: .ai, message: "[OnlineLLM] Generating summary using \(config.provider.displayName) (\(config.modelName))...")
        let startTime = Date()
        
        // 2. Build Request
        let baseURL = config.baseURL
        let path = config.provider.verificationPath(for: .llm)
        guard let url = URL(string: baseURL + path) else {
            throw NSError(domain: "OnlineLLMService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // 3. Construct Body
        // OpenAI Chat Completion Format
        let systemPrompt = """
        你是一个专业的会议记录助手。请根据提供的会议转录文本，生成一份结构化的会议纪要。
        
        要求：
        1. 参会者：列出所有发言者（如果能识别）
        2. 核心议题：用1-3句话概括会议主题
        3. 关键决策：列出会议中做出的重要决定
        4. 待办事项：列出需要跟进的行动项（如有）
        5. 总结：用2-3句话总结会议内容
        
        请使用简洁清晰的语言，突出重点。
        """
        
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": transcript]
        ]
        
        // Build payload based on provider
        var payload: [String: Any]
        
        switch config.provider {
        case .aliyun:
            // Aliyun DashScope API format
            payload = [
                "model": config.modelName,
                "input": ["messages": messages],
                "parameters": [
                    "result_format": "message",
                    "max_tokens": config.maxTokens ?? OnlineModelConfig.LLMDefaults.maxTokens,
                    "temperature": config.temperature ?? OnlineModelConfig.LLMDefaults.temperature,
                    "top_p": config.topP ?? OnlineModelConfig.LLMDefaults.topP
                ]
            ]
        default:
            // OpenAI compatible format (Zhipu, DeepSeek, etc.)
            payload = [
                "model": config.modelName,
                "messages": messages,
                "max_tokens": config.maxTokens ?? OnlineModelConfig.LLMDefaults.maxTokens,
                "temperature": config.temperature ?? OnlineModelConfig.LLMDefaults.temperature,
                "top_p": config.topP ?? OnlineModelConfig.LLMDefaults.topP
            ]
        }

        // Log request details with sanitization
        let sanitizedURL = SensitiveDataSanitizer.sanitizeURL(baseURL + path)
        LoggerService.shared.log(category: .ai, message: "[OnlineLLM] Request URL: \(sanitizedURL)")

        if let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: []) {
            let sanitizedPayload = SensitiveDataSanitizer.sanitizeRequestBody(payloadData, maxLength: 500)
            LoggerService.shared.log(category: .ai, message: "[OnlineLLM] Payload: \(sanitizedPayload)")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // 4. Send Request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
             throw NSError(domain: "OnlineLLMService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode != 200 && httpResponse.statusCode != 201 {
            let sanitizedError = SensitiveDataSanitizer.sanitizeResponseBody(data)
            LoggerService.shared.log(
                category: .ai,
                level: .error,
                message: "[OnlineLLM] API Error (\(httpResponse.statusCode)): \(sanitizedError)"
            )
            throw NSError(domain: "OnlineLLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: See logs for details"])
        }
        
        // 5. Parse Response - handle both OpenAI and DashScope formats
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            LoggerService.shared.log(category: .ai, level: .error, message: "[OnlineLLM] Failed to parse JSON response")
            throw NSError(domain: "OnlineLLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse API response"])
        }
        
        var content: String?
        
        // Try OpenAI format first (Zhipu, DeepSeek)
        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let text = message["content"] as? String {
            content = text
        }
        
        // Try DashScope format (Qwen)
        if content == nil,
           let output = json["output"] as? [String: Any],
           let choices = output["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let text = message["content"] as? String {
            content = text
        }
        
        // Fallback: DashScope text format
        if content == nil,
           let output = json["output"] as? [String: Any],
           let text = output["text"] as? String {
            content = text
        }
        
        guard let finalContent = content else {
            let sanitizedResponse = SensitiveDataSanitizer.sanitizeResponseBody(data)
            LoggerService.shared.log(category: .ai, level: .error, message: "[OnlineLLM] Unexpected response format: \(sanitizedResponse)")
            throw NSError(domain: "OnlineLLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse API response"])
        }
        
        // Usage Stats
        var inputTokens = 0
        var outputTokens = 0
        if let usage = json["usage"] as? [String: Any] {
            inputTokens = usage["prompt_tokens"] as? Int ?? 0
            outputTokens = usage["completion_tokens"] as? Int ?? 0
        }
        
        let generationTime = Date().timeIntervalSince(startTime)
        
        LoggerService.shared.log(
            category: .ai,
            message: "[OnlineLLM] Summary generated in \(String(format: "%.1f", generationTime))s. Tokens: \(inputTokens) in / \(outputTokens) out."
        )
        
        return SummaryResult(
            summary: finalContent,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            generationTime: generationTime
        )
    }
}
