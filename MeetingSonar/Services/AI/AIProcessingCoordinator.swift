import Foundation

/// AI 处理协调器 - 云端版本
/// 协调 ASR 和 LLM 的处理流程
@MainActor
class AIProcessingCoordinator: ObservableObject, AIProcessingCoordinatorProtocol {
    static let shared = AIProcessingCoordinator()

    // MARK: - Logging Constants

    /// 日志前缀常量
    private enum LoggingPrefix {
        static let llmService = "[LLM Service]"
        static let aiProcessing = "[AI Processing]"
    }

    // MARK: - Published State

    @Published var isProcessing = false
    @Published var currentStage: ProcessingStage = .idle
    @Published var progress: Double = 0
    @Published var lastError: Error?

    // MARK: - Processing Stage

    enum ProcessingStage: Equatable {
        case idle
        case asr
        case persistingTranscript
        case llm
        case persistingSummary
        case completed
        case failed(String)

        var displayName: String {
            switch self {
            case .idle:
                return String(localized: "processing.stage.idle", defaultValue: "空闲")
            case .asr:
                return String(localized: "processing.stage.asr", defaultValue: "语音识别中...")
            case .persistingTranscript:
                return String(localized: "processing.stage.persisting_transcript", defaultValue: "保存转录结果...")
            case .llm:
                return String(localized: "processing.stage.llm", defaultValue: "生成摘要中...")
            case .persistingSummary:
                return String(localized: "processing.stage.persisting_summary", defaultValue: "保存摘要...")
            case .completed:
                return String(localized: "processing.stage.completed", defaultValue: "处理完成")
            case .failed(let error):
                return String(localized: "processing.stage.failed", defaultValue: "处理失败: \(error)")
            }
        }
    }

    // MARK: - Initialization

    private init() {
        LoggerService.shared.log(category: .ai, message: "AIProcessingCoordinator initialized (cloud-only mode)")
    }

    // MARK: - Main Processing Pipeline

    /// 处理音频文件 - 完整流程：ASR → 持久化 → LLM → 持久化
    func process(audioURL: URL, meetingID: UUID) async {
        LoggerService.shared.log(category: .ai, message: "Starting AI processing pipeline for meeting: \(meetingID)")

        isProcessing = true
        progress = 0
        lastError = nil
        let startTime = Date()

        do {
            // Stage 1: ASR
            currentStage = .asr
            let result = try await performASRWithResult(audioURL: audioURL, meetingID: meetingID)
            let asrProcessingTime = Date().timeIntervalSince(startTime)
            progress = 0.4

            // Stage 2: Persist Transcript
            currentStage = .persistingTranscript
            let (_, transcriptVersion) = try await persistTranscriptWithVersion(
                result: result,
                audioURL: audioURL,
                meetingID: meetingID,
                processingTime: asrProcessingTime
            )
            progress = 0.5

            // Stage 3: LLM Summary
            currentStage = .llm
            let llmStartTime = Date()
            let summary = try await performLLM(transcript: result.text, meetingID: meetingID)
            let llmProcessingTime = Date().timeIntervalSince(llmStartTime)
            progress = 0.9

            // Stage 4: Persist Summary
            currentStage = .persistingSummary
            _ = try await persistSummaryWithVersion(
                summary,
                audioURL: audioURL,
                sourceTranscriptId: transcriptVersion.id,
                meetingID: meetingID
            )
            progress = 1.0

            // Completed
            currentStage = .completed
            LoggerService.shared.log(category: .ai, message: "AI processing pipeline completed for meeting: \(meetingID)")

        } catch {
            lastError = error
            currentStage = .failed(error.localizedDescription)
            LoggerService.shared.log(category: .ai, level: .error, message: "AI processing pipeline failed: \(error.localizedDescription)")
        }

        isProcessing = false
    }

    /// 仅执行 ASR（不生成摘要）
    func processASROnly(audioURL: URL, meetingID: UUID) async -> (text: String?, transcriptURL: URL?) {
        let result = await processASROnlyWithVersion(audioURL: audioURL, meetingID: meetingID)
        return (result.text, result.url)
    }

    /// 仅执行 ASR 并返回版本信息
    func processASROnlyWithVersion(audioURL: URL, meetingID: UUID) async -> (
        text: String?,
        url: URL?,
        version: TranscriptVersion?
    ) {
        LoggerService.shared.log(category: .ai, message: "Starting ASR-only processing for meeting: \(meetingID)")

        isProcessing = true
        progress = 0
        lastError = nil
        let startTime = Date()

        do {
            currentStage = .asr
            let result = try await performASRWithResult(audioURL: audioURL, meetingID: meetingID)
            let processingTime = Date().timeIntervalSince(startTime)
            progress = 0.8

            currentStage = .persistingTranscript
            let (transcriptURL, version) = try await persistTranscriptWithVersion(
                result: result,
                audioURL: audioURL,
                meetingID: meetingID,
                processingTime: processingTime
            )
            progress = 1.0

            currentStage = .completed
            LoggerService.shared.log(category: .ai, message: "ASR processing completed for meeting: \(meetingID), version: \(version.versionNumber)")

            isProcessing = false
            return (result.text, transcriptURL, version)

        } catch {
            lastError = error
            currentStage = .failed(error.localizedDescription)
            LoggerService.shared.log(category: .ai, level: .error, message: "ASR processing failed: \(error.localizedDescription)")
            isProcessing = false
            return (nil, nil, nil)
        }
    }

    // MARK: - Legacy API (Compatibility)

    /// 仅执行转录（兼容旧接口）
    /// - Returns: (转录文本, 文件URL, 版本ID)
    func transcribeOnly(audioURL: URL, meetingID: UUID? = nil) async throws -> (String, URL, UUID) {
        let actualMeetingID = meetingID ?? UUID()
        let (text, url, version) = await processASROnlyWithVersion(audioURL: audioURL, meetingID: actualMeetingID)
        guard let transcriptText = text, let transcriptURL = url, let transcriptVersion = version else {
            throw AIProcessingError.notImplemented(String(localized: "error.asr.transcription_failed", defaultValue: "转录失败"))
        }
        return (transcriptText, transcriptURL, transcriptVersion.id)
    }

    /// 仅生成摘要（兼容旧接口）
    /// - Parameters:
    ///   - transcriptText: 转录文本
    ///   - audioURL: 音频文件URL
    ///   - sourceTranscriptId: 来源转录版本ID
    /// - Returns: (摘要文本, 文件URL, 版本ID)
    func generateSummaryOnly(
        transcriptText: String,
        audioURL: URL,
        sourceTranscriptId: UUID,
        meetingID: UUID? = nil
    ) async throws -> (String, URL, UUID) {
        let actualMeetingID = meetingID ?? UUID()
        let summary = try await performLLM(transcript: transcriptText, meetingID: actualMeetingID)
        // 保存摘要并返回 URL
        let (summaryURL, summaryVersion) = try await persistSummaryWithVersion(
            summary,
            audioURL: audioURL,
            sourceTranscriptId: sourceTranscriptId
        )
        return (summary, summaryURL, summaryVersion.id)
    }

    // MARK: - Private Methods

    /// 执行 ASR 转录
    private func performASR(audioURL: URL, meetingID: UUID) async throws -> String {
        let result = try await ASRService.shared.transcribe(audioURL: audioURL, meetingID: meetingID)
        return result.text
    }

    /// 执行 ASR 转录并返回完整结果
    private func performASRWithResult(audioURL: URL, meetingID: UUID) async throws -> ASRTranscriptionResult {
        let result = try await ASRService.shared.transcribe(audioURL: audioURL, meetingID: meetingID)
        return result
    }

    // MARK: - LLM Processing Helper Methods

    /// 获取LLM模型配置
    ///
    /// - Parameter selectedModelId: 用户选择的模型ID
    /// - Returns: (配置, API密钥, LLM设置)
    /// - Throws: AIProcessingError 如果配置无效
    private func getLLMModelConfiguration(selectedModelId: String) async throws -> (
        config: CloudAIModelConfig,
        apiKey: String,
        llmSettings: LLMModelSettings
    ) {
        // 从 CloudAIModelManager 获取对应 ID 的模型配置
        guard let config = await CloudAIModelManager.shared.getModel(byId: selectedModelId),
              config.supports(.llm) else {
            // 如果用户选择的模型无效，尝试获取第一个可用的 LLM 模型
            guard let fallbackConfig = await CloudAIModelManager.shared.getFirstModel(for: .llm) else {
                throw AIProcessingError.notImplemented(String(localized: "error.llm.no_model_configured", defaultValue: "请先添加云端 LLM 模型配置"))
            }
            LoggerService.shared.log(category: .ai, level: .warning, message: """
            \(LoggingPrefix.llmService) Selected model not found, using fallback
            ├─ Selected ID: \(selectedModelId)
            └─ Fallback: \(fallbackConfig.displayName)
            """)

            guard let apiKey = await CloudAIModelManager.shared.getAPIKey(for: fallbackConfig.id), !apiKey.isEmpty else {
                throw AIProcessingError.notImplemented(String(localized: "error.llm.no_api_key", defaultValue: "请先配置云端 LLM 服务的 API Key"))
            }

            guard let llmSettings = fallbackConfig.llmConfig else {
                throw AIProcessingError.notImplemented(String(localized: "error.llm.invalid_config", defaultValue: "LLM 配置无效"))
            }

            return (fallbackConfig, apiKey, llmSettings)
        }

        guard let apiKey = await CloudAIModelManager.shared.getAPIKey(for: config.id), !apiKey.isEmpty else {
            throw AIProcessingError.notImplemented(String(localized: "error.llm.no_api_key", defaultValue: "请先配置云端 LLM 服务的 API Key"))
        }

        guard let llmSettings = config.llmConfig else {
            throw AIProcessingError.notImplemented(String(localized: "error.llm.invalid_config", defaultValue: "LLM 配置无效"))
        }

        LoggerService.shared.log(category: .ai, message: """
        \(LoggingPrefix.llmService) Using user-selected model
        ├─ Model ID: \(selectedModelId)
        └─ Display Name: \(config.displayName)
        """)

        return (config, apiKey, llmSettings)
    }

    /// 构建系统提示词
    ///
    /// - Parameter promptContent: 用户选择的提示词内容
    /// - Returns: 系统提示词字符串
    private func buildSystemPrompt(promptContent: String) -> String {
        // 如果用户提供了自定义提示词，使用自定义内容；否则使用默认提示词
        if promptContent.isEmpty {
            return """
            你是一个专业的会议记录助手。请根据提供的会议转录文本，生成一份结构化的会议纪要。

            要求：
            1. 参会者：列出所有发言者（如果能识别）
            2. 核心议题：用1-3句话概括会议主题
            3. 关键决策：列出会议中做出的重要决定
            4. 待办事项：列出需要跟进的行动项（如有）
            5. 总结：用2-3句话总结会议内容

            请使用简洁清晰的语言，突出重点。
            """
        } else {
            return promptContent
        }
    }

    /// 构建聊天消息
    ///
    /// - Parameters:
    ///   - systemPrompt: 系统提示词
    ///   - transcript: 转录文本
    /// - Returns: 聊天消息数组
    private func buildChatMessages(systemPrompt: String, transcript: String) -> [ChatMessage] {
        return [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: transcript)
        ]
    }

    /// 调用云端LLM API生成摘要
    ///
    /// - Parameters:
    ///   - provider: 云服务提供商
    ///   - llmSettings: LLM设置
    ///   - messages: 聊天消息数组
    /// - Returns: 生成的摘要文本
    /// - Throws: AIProcessingError 如果API调用失败
    private func callCloudLLMAPI(
        provider: any CloudServiceProvider,
        llmSettings: LLMModelSettings,
        messages: [ChatMessage]
    ) async throws -> String {
        do {
            let result = try await provider.generateChatCompletion(
                messages: messages,
                model: llmSettings.modelName,
                temperature: llmSettings.temperature ?? 0.7,
                maxTokens: llmSettings.maxTokens ?? 4096
            )

            LoggerService.shared.log(category: .ai, message: "LLM summary generated: \(result.text.prefix(100))...")
            return result.text

        } catch let error as CloudServiceError {
            LoggerService.shared.log(category: .ai, level: .error, message: "Cloud service error: \(error.localizedDescription)")
            throw AIProcessingError.notImplemented(error.localizedDescription)
        } catch {
            LoggerService.shared.log(category: .ai, level: .error, message: "LLM generation failed: \(error.localizedDescription)")
            throw AIProcessingError.notImplemented(error.localizedDescription)
        }
    }

    /// 执行 LLM 摘要生成（重构后版本）
    ///
    /// - Parameters:
    ///   - transcript: 转录文本
    ///   - meetingID: 会议ID
    /// - Returns: 生成的摘要文本
    /// - Throws: AIProcessingError 如果处理失败
    private func performLLM(transcript: String, meetingID: UUID) async throws -> String {
        LoggerService.shared.log(category: .ai, message: "Starting LLM summary generation for meeting: \(meetingID)")

        // 获取模型配置
        let (config, apiKey, llmSettings) = try await getLLMModelConfiguration(
            selectedModelId: SettingsManager.shared.selectedUnifiedLLMId
        )

        // 创建提供商
        let provider = await CloudServiceFactory.shared.createProvider(
            config.provider,
            apiKey: apiKey,
            baseURL: config.baseURL
        )

        // 获取选中的提示词
        let promptContent = await PromptManager.shared.getSelectedPromptContent(for: .llm)

        // 构建提示词
        let systemPrompt = buildSystemPrompt(promptContent: promptContent)

        // 构建消息
        let messages = buildChatMessages(systemPrompt: systemPrompt, transcript: transcript)

        // 调用API生成摘要
        let summary = try await callCloudLLMAPI(
            provider: provider,
            llmSettings: llmSettings,
            messages: messages
        )

        LoggerService.shared.log(category: .ai, message: """
        \(LoggingPrefix.llmService) Successfully generated summary for meeting: \(meetingID)
        ├─ Model ID: \(config.id)
        └─ Display Name: \(config.displayName)
        """)

        return summary
    }

    /// 持久化转录结果 - 使用新版本系统
    private func persistTranscriptWithVersion(
        result: ASRTranscriptionResult,
        audioURL: URL,
        meetingID: UUID,
        processingTime: TimeInterval
    ) async throws -> (URL, TranscriptVersion) {
        // 转换为 VersionManager 的 VersionTranscriptResult 类型
        let transcriptResult = VersionTranscriptResult(
            segments: result.segments.map { segment in
                VersionTranscriptSegment(
                    startTime: segment.start,
                    endTime: segment.end,
                    text: segment.text,
                    speaker: nil  // TranscriptModel.TranscriptSegment 没有 speaker 字段
                )
            },
            text: result.text,
            language: result.language,
            duration: result.segments.last?.end ?? 0
        )

        // 使用 VersionManager 创建版本
        let version = try await VersionManager.shared.createTranscriptVersion(
            meetingId: meetingID,
            result: transcriptResult,
            audioURL: audioURL,
            processingTime: processingTime
        )

        // 返回文件 URL
        let fileURL = PathManager.shared.rootDataURL.appendingPathComponent(version.filePath)
        return (fileURL, version)
    }

    /// 持久化摘要结果 - 使用新版本系统
    private func persistSummaryWithVersion(
        _ text: String,
        audioURL: URL,
        sourceTranscriptId: UUID,
        meetingID: UUID? = nil
    ) async throws -> (URL, SummaryVersion) {
        let actualMeetingID = meetingID ?? UUID()
        let startTime = Date()

        // 获取音频文件 basename
        let basename = audioURL.deletingPathExtension().lastPathComponent

        // 查找或创建 meeting 记录
        var targetMeetingID = actualMeetingID
        if let index = MetadataManager.shared.recordings.firstIndex(where: {
            $0.filename.hasPrefix(basename)
        }) {
            targetMeetingID = MetadataManager.shared.recordings[index].id
        }

        // 计算处理时间
        let processingTime = Date().timeIntervalSince(startTime)

        // 使用 VersionManager 创建版本
        let version = try await VersionManager.shared.createSummaryVersion(
            meetingId: targetMeetingID,
            summaryText: text,
            audioURL: audioURL,
            sourceTranscriptId: sourceTranscriptId,
            processingTime: processingTime
        )

        // 返回文件 URL
        let fileURL = PathManager.shared.rootDataURL.appendingPathComponent(version.filePath)
        return (fileURL, version)
    }

    // MARK: - Reset

    /// 重置协调器状态
    func reset() {
        isProcessing = false
        currentStage = .idle
        progress = 0
        lastError = nil
    }
}

// MARK: - Errors

enum AIProcessingError: LocalizedError {
    case transcriptNotFound
    case noSourceTranscript
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .transcriptNotFound:
            return String(localized: "error.transcript_not_found", defaultValue: "未找到转录文件")
        case .noSourceTranscript:
            return String(localized: "error.no_source_transcript", defaultValue: "未找到来源转录文本")
        case .notImplemented(let message):
            return message
        }
    }
}
