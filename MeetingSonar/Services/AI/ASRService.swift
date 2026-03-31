import Foundation

/// ASR 服务 - 云端版本
/// 负责管理语音识别流程
@MainActor
class ASRService: ObservableObject {
    static let shared = ASRService()

    // MARK: - Published State

    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var lastError: Error?

    // MARK: - Private Properties

    private var currentEngine: ASREngine?

    // MARK: - Initialization

    private init() {
        LoggerService.shared.log(category: .ai, message: "ASRService initialized (cloud-only mode)")
    }

    // MARK: - Transcription

    /// 转录音频文件
    /// - Parameters:
    ///   - audioURL: 音频文件URL
    ///   - meetingID: 关联的会议ID
    ///   - onChunkProgress: 可选的 chunk 级别进度回调（在 MainActor 上调用）
    /// - Returns: 转录结果
    func transcribe(
        audioURL: URL,
        meetingID: UUID,
        onChunkProgress: ((ASRChunkStage) -> Void)? = nil
    ) async throws -> ASRTranscriptionResult {
        LoggerService.shared.log(category: .ai, message: "Starting transcription for meeting: \(meetingID)")

        isProcessing = true
        progress = 0
        defer { isProcessing = false }

        do {
            // 获取或创建引擎
            let engine = try await getOrCreateEngine()

            // 准备 chunk 进度回调（跨 actor 边界需要 @Sendable）
            let sendableChunkProgress: (@Sendable (ASRChunkStage) -> Void)? = onChunkProgress.map { handler in
                { @Sendable stage in
                    Task { @MainActor in
                        handler(stage)
                    }
                }
            }

            // 执行转录（优先使用带 chunk 进度的方法）
            let transcriptResult: TranscriptionResult
            if let onlineEngine = engine as? OnlineASREngine {
                transcriptResult = try await onlineEngine.transcribe(
                    audioURL: audioURL,
                    language: "zh",
                    progress: { [weak self] p in
                        Task { @MainActor in
                            self?.progress = p * 0.8
                        }
                    },
                    chunkProgress: sendableChunkProgress
                )
            } else {
                transcriptResult = try await engine.transcribe(
                    audioURL: audioURL,
                    language: "zh",
                    progress: { [weak self] p in
                        self?.progress = p * 0.8  // 预留 20% 给后续处理
                    }
                )
            }

            progress = 1.0

            // 转换为ASRTranscriptionResult
            let segments: [TranscriptSegment] = transcriptResult.segments.map { segment in
                TranscriptSegment(
                    start: segment.startTime,
                    end: segment.endTime,
                    text: segment.text
                )
            }
            let result = ASRTranscriptionResult(
                meetingID: meetingID,
                text: transcriptResult.text,
                segments: segments,
                language: transcriptResult.language ?? "zh",
                processingTime: transcriptResult.processingTime
            )

            LoggerService.shared.log(category: .ai, message: "Transcription completed for meeting: \(meetingID)")
            return result

        } catch {
            lastError = error
            LoggerService.shared.log(category: .ai, level: .error, message: "Transcription failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Engine Management

    /// 获取或创建ASR引擎
    private func getOrCreateEngine() async throws -> ASREngine {
        // 如果已有引擎且已加载，直接返回
        if let engine = currentEngine, await engine.isLoaded {
            return engine
        }

        // 创建新引擎
        let engine = try ASREngineFactory.createEngine(type: .online)

        // 从 SettingsManager 获取用户选择的模型 ID
        let selectedModelId = SettingsManager.shared.selectedUnifiedASRId
        LoggerService.shared.log(category: .ai, message: """
        [ASR Service] Resolving ASR model
        ├─ Selected ID: \(selectedModelId)
        └─ Available models: \(await CloudAIModelManager.shared.getModels(for: .asr).map { "\($0.displayName) (\($0.id.uuidString))" })
        """)

        // 从 CloudAIModelManager 获取对应 ID 的模型配置
        guard let config = await CloudAIModelManager.shared.getModel(byId: selectedModelId),
              config.supports(.asr) else {
            // 如果用户选择的模型无效，尝试获取第一个可用的 ASR 模型
            guard let fallbackConfig = await CloudAIModelManager.shared.getFirstModel(for: .asr) else {
                throw ASREngineFactoryError.initializationFailed(
                    String(localized: "error.no_asr_model", defaultValue: "请先添加云端 ASR 模型配置")
                )
            }
            LoggerService.shared.log(category: .ai, level: .warning, message: """
            [ASR Service] Selected model not found, using fallback
            ├─ Selected ID: \(selectedModelId)
            ├─ Fallback: \(fallbackConfig.displayName)
            └─ Fallback ID: \(fallbackConfig.id.uuidString)
            """)

            let apiKey = await CloudAIModelManager.shared.getAPIKey(for: fallbackConfig.id)
            LoggerService.shared.log(category: .ai, message: """
            [ASR Service] API Key lookup for fallback model
            ├─ Model ID: \(fallbackConfig.id.uuidString)
            ├─ Key found: \(apiKey != nil)
            └─ Key empty: \(apiKey?.isEmpty ?? true)
            """)

            guard let apiKey, !apiKey.isEmpty else {
                throw ASREngineFactoryError.initializationFailed(
                    String(localized: "error.api_key_missing", defaultValue: "请先配置云端 ASR 服务的 API Key")
                )
            }

            guard let asrSettings = fallbackConfig.asrConfig else {
                throw ASREngineFactoryError.initializationFailed(
                    String(localized: "error.invalid_asr_config", defaultValue: "ASR 配置无效")
                )
            }

            // 获取选中的提示词
            let promptContent = await PromptManager.shared.getSelectedPromptContent(for: .asr)

            // 获取全局热词 (F-0.10.14)
            let hotwords = SettingsManager.shared.asrHotwords

            // 创建在线配置
            let onlineConfig = OnlineASRConfig(
                provider: fallbackConfig.provider,
                endpoint: fallbackConfig.baseURL,
                apiKey: apiKey,
                model: asrSettings.modelName,
                language: "zh",
                prompt: promptContent.isEmpty ? nil : promptContent,
                hotwords: hotwords.isEmpty ? nil : hotwords
            )

            // 初始化引擎
            let tempURL = URL(fileURLWithPath: "/tmp/dummy.model")
            try await engine.loadModel(modelPath: tempURL, config: onlineConfig)

            currentEngine = engine
            return engine
        }

        LoggerService.shared.log(category: .ai, message: """
        [ASR Service] Using user-selected model
        ├─ Model ID: \(selectedModelId)
        └─ Display Name: \(config.displayName)
        """)

        let primaryApiKey = await CloudAIModelManager.shared.getAPIKey(for: config.id)
        LoggerService.shared.log(category: .ai, message: """
        [ASR Service] API Key lookup for selected model
        ├─ Model ID: \(config.id.uuidString)
        ├─ Key found: \(primaryApiKey != nil)
        └─ Key empty: \(primaryApiKey?.isEmpty ?? true)
        """)

        guard let apiKey = primaryApiKey, !apiKey.isEmpty else {
            throw ASREngineFactoryError.initializationFailed(
                String(localized: "error.api_key_missing", defaultValue: "请先配置云端 ASR 服务的 API Key")
            )
        }

        guard let asrSettings = config.asrConfig else {
            throw ASREngineFactoryError.initializationFailed(
                String(localized: "error.invalid_asr_config", defaultValue: "ASR 配置无效")
            )
        }

        // 获取选中的提示词
        let promptContent = await PromptManager.shared.getSelectedPromptContent(for: .asr)

        // 获取全局热词 (F-0.10.14)
        let hotwords = SettingsManager.shared.asrHotwords

        // 创建在线配置
        let onlineConfig = OnlineASRConfig(
            provider: config.provider,
            endpoint: config.baseURL,
            apiKey: apiKey,
            model: asrSettings.modelName,
            language: "zh",
            prompt: promptContent.isEmpty ? nil : promptContent,
            hotwords: hotwords.isEmpty ? nil : hotwords
        )

        // 初始化引擎
        let tempURL = URL(fileURLWithPath: "/tmp/dummy.model")
        try await engine.loadModel(modelPath: tempURL, config: onlineConfig)

        currentEngine = engine
        return engine
    }

    /// 关闭当前引擎
    func shutdownEngine() async {
        if let engine = currentEngine {
            await engine.unload()
            currentEngine = nil
            LoggerService.shared.log(category: .ai, message: "ASR engine shutdown")
        }
    }

    /// 重置服务状态
    func reset() {
        isProcessing = false
        progress = 0
        lastError = nil
        Task {
            await shutdownEngine()
        }
    }
}

// MARK: - ASR Transcription Result

/// ASR服务返回的转录结果
struct ASRTranscriptionResult {
    let meetingID: UUID
    let text: String
    let segments: [TranscriptSegment]
    let language: String
    let processingTime: TimeInterval
}

// TranscriptSegment is defined in Models/TranscriptModel.swift

// MARK: - ASR Chunk Progress

/// Represents the current stage of chunk-level ASR processing
enum ASRChunkStage {
    /// Audio is being split into chunks
    case splitting
    /// Processing chunk N of total
    case chunk(current: Int, total: Int)
    /// Chunk N failed with error message
    case chunkFailed(current: Int, total: Int, error: String)
}