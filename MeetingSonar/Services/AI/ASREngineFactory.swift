import Foundation
import AVFoundation

/// ASR Engine Factory — Cloud-only (v0.10.0+)
enum ASREngineFactory {

    /// Create online ASR engine
    static func createEngine(type: ASREngineType = .online) throws -> ASREngine {
        LoggerService.shared.log(category: .ai, message: "Creating ASR engine of type: \(type.rawValue)")
        return OnlineASREngine()
    }

    /// Available engine types (cloud-only)
    static func availableEngineTypes() -> [ASREngineType] {
        return [.online]
    }

    /// Create engine for model type
    static func createEngineForModel(_ modelType: ModelType) throws -> ASREngine {
        return try createEngine()
    }
}

/// ASR 引擎错误
enum ASREngineFactoryError: LocalizedError {
    case unsupportedEngine(String)
    case initializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedEngine(let message):
            return message
        case .initializationFailed(let message):
            return message
        }
    }
}

// MARK: - Online ASR Engine

/// 云端 ASR 引擎
/// 使用在线API进行语音识别
actor OnlineASREngine: ASREngine {

    // MARK: - Properties

    private(set) var isLoaded = false
    private var configuration: OnlineASRConfig?
    private var cloudProvider: (any CloudServiceProvider)?

    // MARK: - Context Chaining (F-0.10.13)

    /// Combine user-configured static prompt with previous chunk's tail text.
    /// Static prompt takes priority — placed first so truncation only affects the tail.
    /// Returns nil if both inputs are nil/empty (preserves original behavior for first chunk with no prompt).
    private func buildChainedPrompt(
        staticPrompt: String?,
        previousTailText: String?,
        maxLength: Int
    ) -> String? {
        let staticPart = (staticPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tailPart = (previousTailText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if staticPart.isEmpty && tailPart.isEmpty { return nil }
        if tailPart.isEmpty { return String(staticPart.prefix(maxLength)) }
        if staticPart.isEmpty { return String(tailPart.prefix(maxLength)) }

        // Both present: static prompt first, then tail text with remaining budget
        let separator = "\n"
        let remainingBudget = maxLength - staticPart.count - separator.count
        if remainingBudget <= 0 {
            // Static prompt alone fills the budget — no room for tail
            return String(staticPart.prefix(maxLength))
        }
        return staticPart + separator + String(tailPart.suffix(remainingBudget))
    }

    /// Extract tail text from a transcription result for context chaining.
    /// Uses `.suffix` to grab the trailing portion — the part most relevant
    /// for continuity with the next chunk.
    private func extractTailText(from text: String, maxLength: Int) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return String(trimmed.suffix(maxLength))
    }

    // MARK: - ASREngine Protocol

    var engineType: ASREngineType { .online }

    func loadModel(modelPath: URL, config: some ASRModelConfiguration) async throws {
        guard let onlineConfig = config as? OnlineASRConfig else {
            throw ASREngineFactoryError.initializationFailed(
                String(localized: "error.invalid_config", defaultValue: "无效的配置类型")
            )
        }

        self.configuration = onlineConfig

        // 创建云服务提供商
        let provider = await CloudServiceFactory.shared.createProvider(
            onlineConfig.provider,
            apiKey: onlineConfig.apiKey,
            baseURL: onlineConfig.endpoint
        )

        // 验证 API Key
        do {
            let isValid = try await provider.verifyAPIKey()
            guard isValid else {
                throw ASREngineFactoryError.initializationFailed(
                    String(localized: "error.invalid_api_key", defaultValue: "API Key 验证失败")
                )
            }
        } catch {
            throw ASREngineFactoryError.initializationFailed(
                String(localized: "error.api_verification_failed", defaultValue: "无法验证 API: \(error.localizedDescription)")
            )
        }

        self.cloudProvider = provider
        self.isLoaded = true

        LoggerService.shared.log(category: .ai, message: "Online ASR engine initialized with provider: \(onlineConfig.provider.displayName)")
    }

    func transcribe(
        audioURL: URL,
        language: String,
        progress: ((Double) -> Void)?
    ) async throws -> TranscriptionResult {
        // Delegate to the enriched method without chunk progress
        return try await transcribe(
            audioURL: audioURL,
            language: language,
            progress: progress,
            chunkProgress: nil
        )
    }

    /// Transcribe with chunk-level progress reporting
    func transcribe(
        audioURL: URL,
        language: String,
        progress: ((Double) -> Void)?,
        chunkProgress: (@Sendable (ASRChunkStage) -> Void)?
    ) async throws -> TranscriptionResult {
        guard isLoaded else {
            throw ASREngineFactoryError.initializationFailed(
                String(localized: "error.engine_not_initialized", defaultValue: "引擎未初始化")
            )
        }

        guard let provider = cloudProvider,
              let config = configuration else {
            throw ASREngineFactoryError.initializationFailed(
                String(localized: "error.configuration_missing", defaultValue: "配置缺失")
            )
        }

        // 详细日志：模型配置信息
        LoggerService.shared.log(category: .ai, message: """
        [ASR Request] Starting transcription
        ├─ Provider: \(config.provider.displayName)
        ├─ Model: \(config.model)
        ├─ Language: \(language)
        ├─ Audio File: \(audioURL.lastPathComponent)
        └─ Endpoint: \(config.endpoint)
        """)

        // 报告分割阶段
        chunkProgress?(.splitting)

        // 使用 AudioSplitter 将音频分割并转换为 WAV 格式
        let splitter = AudioSplitter()
        let chunks: [(url: URL, start: TimeInterval, duration: TimeInterval)]

        do {
            chunks = try await splitter.split(audioURL: audioURL)
            LoggerService.shared.log(category: .ai, message: "[ASR Audio Split] Split into \(chunks.count) chunks")
            for (index, chunk) in chunks.enumerated() {
                LoggerService.shared.log(category: .ai, level: .debug, message: "[Chunk \(index + 1)] Start: \(chunk.start)s, Duration: \(chunk.duration)s")
            }
        } catch {
            LoggerService.shared.log(category: .ai, level: .error, message: "[ASR Audio Split] Failed: \(error.localizedDescription)")
            throw ASREngineFactoryError.initializationFailed(
                String(localized: "error.audio_split_failed", defaultValue: "音频分割失败: \(error.localizedDescription)")
            )
        }

        guard !chunks.isEmpty else {
            return TranscriptionResult(
                text: "",
                segments: [],
                language: language,
                processingTime: 0
            )
        }

        // 依次处理每个音频块
        var allSegments: [ASRTranscriptSegment] = []
        var fullText = ""
        let startTime = Date()
        var successfulChunks = 0
        var failedChunks = 0

        // Context chaining: carry previous chunk's tail text as prompt context for the next chunk.
        // Improves transcription coherence when sentences are split across chunk boundaries.
        var previousChunkTailText: String?

        for (index, chunk) in chunks.enumerated() {
            let chunkNumber = index + 1
            let chunkProgressValue = Double(index) / Double(chunks.count)
            progress?(0.1 + chunkProgressValue * 0.8)

            // 报告当前 chunk 进度
            chunkProgress?(.chunk(current: chunkNumber, total: chunks.count))

            do {
                // 读取 WAV 格式的音频数据
                let audioData = try Data(contentsOf: chunk.url)
                let audioSizeMB = Double(audioData.count) / 1024 / 1024

                // Build prompt: static user prompt + previous chunk's tail text
                let chainedPrompt = buildChainedPrompt(
                    staticPrompt: config.prompt,
                    previousTailText: previousChunkTailText,
                    maxLength: ZhipuASRLimits.maxPromptLength
                )

                LoggerService.shared.log(category: .ai, message: """
                [ASR Chunk Request] \(chunkNumber)/\(chunks.count)
                ├─ Model: \(config.model)
                ├─ Provider: \(config.provider.displayName)
                ├─ Audio Size: \(String(format: "%.2f", audioSizeMB)) MB
                ├─ Start Time: \(chunk.start)s
                ├─ Duration: \(chunk.duration)s
                └─ Context Chain: \(previousChunkTailText != nil ? "Yes (\(previousChunkTailText!.count) chars)" : "No (first chunk or previous failed)")
                """)

                // 调用云端 API
                let result = try await provider.transcribe(
                    audioData: audioData,
                    model: config.model,
                    prompt: chainedPrompt,
                    hotwords: config.hotwords
                )

                // 记录成功响应
                successfulChunks += 1
                LoggerService.shared.log(category: .ai, message: """
                [ASR Chunk Response] \(chunkNumber)/\(chunks.count) - SUCCESS
                ├─ Status: 200 OK
                ├─ Processing Time: \(String(format: "%.2f", result.processingTime))s
                ├─ Text Length: \(result.text.count) chars
                ├─ Segments: \(result.segments.count)
                \(result.usage.map { "└─ Tokens: \($0.promptTokens + $0.completionTokens) (prompt: \($0.promptTokens), completion: \($0.completionTokens))" } ?? "")
                """)

                // 调整时间戳
                let adjustedSegments = result.segments.map { segment in
                    ASRTranscriptSegment(
                        startTime: segment.start + chunk.start,
                        endTime: segment.end + chunk.start,
                        text: segment.text
                    )
                }

                allSegments.append(contentsOf: adjustedSegments)
                if !result.text.isEmpty {
                    fullText += result.text + " "
                }

                // Update context chain: extract tail for next chunk's prompt
                previousChunkTailText = extractTailText(
                    from: result.text,
                    maxLength: ZhipuASRLimits.maxPromptLength
                )

                // 清理临时文件
                try? FileManager.default.removeItem(at: chunk.url)

            } catch {
                failedChunks += 1
                LoggerService.shared.log(category: .ai, level: .error, message: """
                [ASR Chunk Response] \(chunkNumber)/\(chunks.count) - FAILED
                ├─ Error: \(error.localizedDescription)
                └─ Continuing with next chunk...
                """)

                // Reset context chain on failure — don't carry stale context forward
                previousChunkTailText = nil

                // 报告 chunk 失败
                chunkProgress?(.chunkFailed(current: chunkNumber, total: chunks.count, error: error.localizedDescription))

                // 继续处理下一个块，不中断整体流程
            }
        }

        let processingTime = Date().timeIntervalSince(startTime)
        progress?(1.0)

        // 计算原始文件大小
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0

        // 详细日志：转录完成摘要
        LoggerService.shared.log(category: .ai, message: """
        [ASR Complete] Transcription finished
        ├─ Provider: \(config.provider.displayName)
        ├─ Model: \(config.model)
        ├─ Total Chunks: \(chunks.count)
        ├─ Successful: \(successfulChunks)
        ├─ Failed: \(failedChunks)
        ├─ Total Duration: \(processingTime)s
        ├─ Text Length: \(fullText.count) chars
        ├─ Segments: \(allSegments.count)
        └─ Throughput: \(String(format: "%.2f", Double(fileSize) / 1024 / 1024 / processingTime)) MB/s
        """)

        return TranscriptionResult(
            text: fullText.trimmingCharacters(in: .whitespaces),
            segments: allSegments,
            language: language,
            processingTime: processingTime
        )
    }

    func unload() async {
        isLoaded = false
        configuration = nil
        cloudProvider = nil
        LoggerService.shared.log(category: .ai, message: "Online ASR engine unloaded")
    }
}
