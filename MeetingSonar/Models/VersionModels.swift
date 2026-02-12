//
//  VersionModels.swift
//  MeetingSonar
//
//  F-11.1: Version Management Enhancement
//  Data models for transcript and summary versioning
//

import Foundation

// MARK: - Transcript Version

/// 转录版本信息
struct TranscriptVersion: Codable, Identifiable, Hashable, Sendable {
    let id: UUID

    /// 版本序号（从1开始，用于显示）
    let versionNumber: Int

    /// 生成时间戳
    let timestamp: Date

    /// 使用的ASR模型信息
    let modelInfo: ModelVersionInfo

    /// 使用的提示词信息
    let promptInfo: PromptVersionInfo

    /// 文件路径（相对于rootDataURL）
    let filePath: String

    /// 处理结果统计
    let statistics: TranscriptStatistics?

    init(
        id: UUID = UUID(),
        versionNumber: Int,
        timestamp: Date = Date(),
        modelInfo: ModelVersionInfo,
        promptInfo: PromptVersionInfo,
        filePath: String,
        statistics: TranscriptStatistics? = nil
    ) {
        self.id = id
        self.versionNumber = versionNumber
        self.timestamp = timestamp
        self.modelInfo = modelInfo
        self.promptInfo = promptInfo
        self.filePath = filePath
        self.statistics = statistics
    }
}

// MARK: - Summary Version

/// 摘要版本信息
struct SummaryVersion: Codable, Identifiable, Hashable, Sendable {
    let id: UUID

    /// 版本序号（从1开始）
    let versionNumber: Int

    /// 生成时间戳
    let timestamp: Date

    /// 使用的LLM模型信息
    let modelInfo: ModelVersionInfo

    /// 使用的提示词信息
    let promptInfo: PromptVersionInfo

    /// 文件路径（相对于rootDataURL）
    let filePath: String

    /// 来源转录版本ID
    let sourceTranscriptId: UUID

    /// 来源转录版本号（冗余存储，便于显示）
    let sourceTranscriptVersionNumber: Int

    /// 摘要统计
    let statistics: SummaryStatistics?

    init(
        id: UUID = UUID(),
        versionNumber: Int,
        timestamp: Date = Date(),
        modelInfo: ModelVersionInfo,
        promptInfo: PromptVersionInfo,
        filePath: String,
        sourceTranscriptId: UUID,
        sourceTranscriptVersionNumber: Int,
        statistics: SummaryStatistics? = nil
    ) {
        self.id = id
        self.versionNumber = versionNumber
        self.timestamp = timestamp
        self.modelInfo = modelInfo
        self.promptInfo = promptInfo
        self.filePath = filePath
        self.sourceTranscriptId = sourceTranscriptId
        self.sourceTranscriptVersionNumber = sourceTranscriptVersionNumber
        self.statistics = statistics
    }
}

// MARK: - Model Version Info

/// 模型版本信息
struct ModelVersionInfo: Codable, Hashable, Sendable {
    /// 模型ID（CloudAIModelConfig.id的字符串表示或本地模型标识）
    let modelId: String

    /// 模型显示名称（如 "Qwen3-ASR", "Whisper-1"）
    let displayName: String

    /// 服务提供商（如 "Aliyun", "OpenAI", "Local"）
    let provider: String

    /// 模型具体配置（如模型名称、温度等）
    let configuration: [String: String]?

    init(
        modelId: String,
        displayName: String,
        provider: String,
        configuration: [String: String]? = nil
    ) {
        self.modelId = modelId
        self.displayName = displayName
        self.provider = provider
        self.configuration = configuration
    }
}

// MARK: - Prompt Version Info

/// 提示词版本信息
struct PromptVersionInfo: Codable, Hashable, Sendable {
    /// 提示词模板ID
    let promptId: String

    /// 提示词模板名称
    let promptName: String

    /// 提示词内容摘要（前100字符，用于识别）
    let contentPreview: String

    /// 提示词分类
    let category: PromptCategory

    init(
        promptId: String,
        promptName: String,
        contentPreview: String,
        category: PromptCategory
    ) {
        self.promptId = promptId
        self.promptName = promptName
        self.contentPreview = contentPreview
        self.category = category
    }
}

// MARK: - Statistics

/// 转录统计信息
struct TranscriptStatistics: Codable, Hashable, Sendable {
    /// 音频时长（秒）
    let audioDuration: TimeInterval

    /// 处理耗时（秒）
    let processingTime: TimeInterval

    /// 实时因子（RTF = processingTime / audioDuration）
    var rtf: Double {
        guard audioDuration > 0 else { return 0 }
        return processingTime / audioDuration
    }

    /// 转录文本字数
    let wordCount: Int

    /// 分段数量
    let segmentCount: Int

    init(
        audioDuration: TimeInterval,
        processingTime: TimeInterval,
        wordCount: Int,
        segmentCount: Int
    ) {
        self.audioDuration = audioDuration
        self.processingTime = processingTime
        self.wordCount = wordCount
        self.segmentCount = segmentCount
    }
}

/// 摘要统计信息
struct SummaryStatistics: Codable, Hashable, Sendable {
    /// 生成耗时（秒）
    let processingTime: TimeInterval

    /// 输入token数（如果API返回）
    let inputTokens: Int?

    /// 输出token数（如果API返回）
    let outputTokens: Int?

    /// 摘要字数
    let wordCount: Int

    init(
        processingTime: TimeInterval,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        wordCount: Int
    ) {
        self.processingTime = processingTime
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.wordCount = wordCount
    }
}

// MARK: - Error Handling

/// 版本管理错误
enum VersionManagementError: LocalizedError {
    case meetingNotFound
    case sourceTranscriptNotFound
    case noSourceTranscript
    case fileSaveFailed(Error)
    case invalidVersionNumber

    var errorDescription: String? {
        switch self {
        case .meetingNotFound:
            return String(localized: "error.version.meeting_not_found", defaultValue: "找不到会议记录")
        case .sourceTranscriptNotFound:
            return String(localized: "error.version.source_transcript_not_found", defaultValue: "找不到来源转录版本")
        case .noSourceTranscript:
            return String(localized: "error.version.no_source_transcript", defaultValue: "请先生成转录")
        case .fileSaveFailed(let error):
            return String(localized: "error.version.file_save_failed", defaultValue: "保存文件失败: \(error.localizedDescription)")
        case .invalidVersionNumber:
            return String(localized: "error.version.invalid_version", defaultValue: "无效的版本号")
        }
    }
}

// MARK: - Display Extensions

extension TranscriptVersion {
    /// 显示名称：V1 - 02-05 18:25
    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "V\(versionNumber) - \(formatter.string(from: timestamp))"
    }
}

extension SummaryVersion {
    /// 显示名称：V1 - 02-05 18:28
    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "V\(versionNumber) - \(formatter.string(from: timestamp))"
    }
}

// MARK: - Migration Support (Backward Compatibility)

extension TranscriptVersion {
    enum CodingKeys: String, CodingKey {
        case id, versionNumber, timestamp, modelInfo, promptInfo, filePath, statistics
        // Legacy keys for backward compatibility (decoding only)
        case modelName
    }

    // Explicit encode method to handle custom CodingKeys
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(versionNumber, forKey: .versionNumber)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(modelInfo, forKey: .modelInfo)
        try container.encode(promptInfo, forKey: .promptInfo)
        try container.encode(filePath, forKey: .filePath)
        try container.encodeIfPresent(statistics, forKey: .statistics)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode standard fields
        self.id = try container.decode(UUID.self, forKey: .id)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.filePath = try container.decode(String.self, forKey: .filePath)

        // Decode model info with migration support
        self.modelInfo = decodeModelInfo(
            from: container,
            modelInfoKey: .modelInfo,
            modelNameKey: .modelName
        )

        // Decode prompt info with migration support
        self.promptInfo = decodePromptInfo(
            from: container,
            promptInfoKey: .promptInfo,
            defaultCategory: .asr
        )

        // Version number: use stored or default to 1
        self.versionNumber = try container.decodeIfPresent(Int.self, forKey: .versionNumber) ?? 1

        // Statistics: optional
        self.statistics = try container.decodeIfPresent(TranscriptStatistics.self, forKey: .statistics)
    }
}

extension SummaryVersion {
    enum CodingKeys: String, CodingKey {
        case id, versionNumber, timestamp, modelInfo, promptInfo, filePath
        case sourceTranscriptId, sourceTranscriptVersionNumber, statistics
        // Legacy keys (decoding only)
        case modelName
    }

    // Explicit encode method to handle custom CodingKeys
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(versionNumber, forKey: .versionNumber)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(modelInfo, forKey: .modelInfo)
        try container.encode(promptInfo, forKey: .promptInfo)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(sourceTranscriptId, forKey: .sourceTranscriptId)
        try container.encode(sourceTranscriptVersionNumber, forKey: .sourceTranscriptVersionNumber)
        try container.encodeIfPresent(statistics, forKey: .statistics)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.filePath = try container.decode(String.self, forKey: .filePath)
        self.sourceTranscriptId = try container.decode(UUID.self, forKey: .sourceTranscriptId)

        // Decode model info with migration support
        self.modelInfo = decodeModelInfo(
            from: container,
            modelInfoKey: .modelInfo,
            modelNameKey: .modelName
        )

        // Decode prompt info with migration support
        self.promptInfo = decodePromptInfo(
            from: container,
            promptInfoKey: .promptInfo,
            defaultCategory: .llm
        )

        self.versionNumber = try container.decodeIfPresent(Int.self, forKey: .versionNumber) ?? 1
        self.sourceTranscriptVersionNumber = try container.decodeIfPresent(Int.self, forKey: .sourceTranscriptVersionNumber) ?? 1
        self.statistics = try container.decodeIfPresent(SummaryStatistics.self, forKey: .statistics)
    }
}

// MARK: - Decoding Helpers

/// 解码 ModelVersionInfo，支持旧格式迁移
/// 用于 TranscriptVersion 和 SummaryVersion 的共享解码逻辑
private func decodeModelInfo<T: CodingKey>(
    from container: KeyedDecodingContainer<T>,
    modelInfoKey: T,
    modelNameKey: T
) -> ModelVersionInfo {
    // Try new format first
    if let modelInfo = try? container.decode(ModelVersionInfo.self, forKey: modelInfoKey) {
        return modelInfo
    }

    // Fallback to legacy format (modelName string)
    guard let modelName = try? container.decode(String.self, forKey: modelNameKey) else {
        // No model info available - return unknown
        return ModelVersionInfo(
            modelId: "unknown",
            displayName: "Unknown",
            provider: "Unknown",
            configuration: nil
        )
    }

    // Migrate from old format
    return ModelVersionInfo(
        modelId: "legacy",
        displayName: modelName,
        provider: "Legacy",
        configuration: nil
    )
}

/// 解码 PromptVersionInfo，支持旧格式迁移
/// 用于 TranscriptVersion 和 SummaryVersion 的共享解码逻辑
private func decodePromptInfo<T: CodingKey>(
    from container: KeyedDecodingContainer<T>,
    promptInfoKey: T,
    defaultCategory: PromptCategory
) -> PromptVersionInfo {
    // Try new format first
    if let promptInfo = try? container.decode(PromptVersionInfo.self, forKey: promptInfoKey) {
        return promptInfo
    }

    // No prompt info available - return default
    return PromptVersionInfo(
        promptId: "default",
        promptName: "Default",
        contentPreview: "",
        category: defaultCategory
    )
}
