//
//  VersionManager.swift
//  MeetingSonar
//
//  F-11.1: Version Management Enhancement
//  Manages creation and persistence of transcript and summary versions
//

import Foundation
import OSLog

/// 版本管理器
/// 负责创建、存储和管理转录与摘要版本
@MainActor
final class VersionManager {
    static let shared = VersionManager()

    private let logger = Logger(subsystem: "com.meetingsonar", category: "VersionManager")

    private init() {}

    // MARK: - File Path Generation

    /// 生成转录文件路径
    /// - Parameters:
    ///   - basename: 录音文件基础名称（不含扩展名）
    ///   - versionNumber: 版本号
    /// - Returns: JSON和TXT文件的URL
    func generateTranscriptFilePaths(
        basename: String,
        versionNumber: Int
    ) -> (json: URL, txt: URL) {
        let timestamp = DateFormatter.versionTimestamp.string(from: Date())
        let baseName = "\(basename)_transcript_v\(versionNumber)_\(timestamp)"

        let rawDir = PathManager.shared.rawTranscriptsURL
        let jsonURL = rawDir.appendingPathComponent("\(baseName).json")
        let txtURL = rawDir.appendingPathComponent("\(baseName).txt")

        return (jsonURL, txtURL)
    }

    /// 生成摘要文件路径
    /// - Parameters:
    ///   - basename: 录音文件基础名称（不含扩展名）
    ///   - versionNumber: 版本号
    /// - Returns: Markdown文件的URL
    func generateSummaryFilePath(
        basename: String,
        versionNumber: Int
    ) -> URL {
        let timestamp = DateFormatter.versionTimestamp.string(from: Date())
        let filename = "\(basename)_summary_v\(versionNumber)_\(timestamp).md"

        return PathManager.shared.smartNotesURL.appendingPathComponent(filename)
    }

    // MARK: - Transcript Version Creation

    /// 创建新的转录版本
    /// - Parameters:
    ///   - meetingId: 会议记录ID
    ///   - result: ASR转录结果
    ///   - audioURL: 音频文件URL
    ///   - processingTime: 处理耗时（秒）
    /// - Returns: 创建的转录版本
    func createTranscriptVersion(
        meetingId: UUID,
        result: VersionTranscriptResult,
        audioURL: URL,
        processingTime: TimeInterval
    ) async throws -> TranscriptVersion {
        guard var meta = MetadataManager.shared.get(id: meetingId) else {
            throw VersionManagementError.meetingNotFound
        }

        // 1. 获取版本号
        let versionNumber = meta.nextTranscriptVersionNumber

        // 2. 获取当前模型信息
        let modelInfo = await getCurrentASRModelInfo()

        // 3. 获取当前提示词信息
        let promptInfo = await getCurrentPromptInfo(for: .asr)

        // 4. 生成文件路径
        let basename = audioURL.deletingPathExtension().lastPathComponent
        let (jsonURL, txtURL) = generateTranscriptFilePaths(
            basename: basename,
            versionNumber: versionNumber
        )

        // 5. 保存文件
        try await saveTranscriptFiles(result: result, jsonURL: jsonURL, txtURL: txtURL, processingTime: processingTime)

        // 6. 计算统计信息
        let statistics = TranscriptStatistics(
            audioDuration: result.segments.last?.endTime ?? 0,
            processingTime: processingTime,
            wordCount: result.text.count,
            segmentCount: result.segments.count
        )

        // 7. 创建版本记录
        let version = TranscriptVersion(
            id: UUID(),
            versionNumber: versionNumber,
            timestamp: Date(),
            modelInfo: modelInfo,
            promptInfo: promptInfo,
            filePath: relativePath(from: jsonURL),
            statistics: statistics
        )

        // 8. 更新元数据
        meta.transcriptVersions.append(version)
        await MetadataManager.shared.update(meta)

        logger.info("Created transcript version \(versionNumber) for meeting \(meetingId)")

        return version
    }

    // MARK: - Summary Version Creation

    /// 创建新的摘要版本
    /// - Parameters:
    ///   - meetingId: 会议记录ID
    ///   - summaryText: 摘要文本内容
    ///   - audioURL: 音频文件URL
    ///   - sourceTranscriptId: 来源转录版本ID
    ///   - processingTime: 处理耗时（秒）
    ///   - inputTokens: 输入token数（可选）
    ///   - outputTokens: 输出token数（可选）
    /// - Returns: 创建的摘要版本
    func createSummaryVersion(
        meetingId: UUID,
        summaryText: String,
        audioURL: URL,
        sourceTranscriptId: UUID,
        processingTime: TimeInterval,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil
    ) async throws -> SummaryVersion {
        guard var meta = MetadataManager.shared.get(id: meetingId) else {
            throw VersionManagementError.meetingNotFound
        }

        // 1. 获取版本号
        let versionNumber = meta.nextSummaryVersionNumber

        // 2. 获取来源转录版本号
        guard let sourceTranscript = meta.transcriptVersions.first(where: { $0.id == sourceTranscriptId }) else {
            throw VersionManagementError.sourceTranscriptNotFound
        }

        // 3. 获取当前模型信息
        let modelInfo = await getCurrentLLMModelInfo()

        // 4. 获取当前提示词信息
        let promptInfo = await getCurrentPromptInfo(for: .llm)

        // 5. 生成文件路径
        let basename = audioURL.deletingPathExtension().lastPathComponent
        let fileURL = generateSummaryFilePath(
            basename: basename,
            versionNumber: versionNumber
        )

        // 6. 保存文件
        try await saveSummaryFile(text: summaryText, url: fileURL)

        // 7. 计算统计信息
        let statistics = SummaryStatistics(
            processingTime: processingTime,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            wordCount: summaryText.count
        )

        // 8. 创建版本记录
        let version = SummaryVersion(
            id: UUID(),
            versionNumber: versionNumber,
            timestamp: Date(),
            modelInfo: modelInfo,
            promptInfo: promptInfo,
            filePath: relativePath(from: fileURL),
            sourceTranscriptId: sourceTranscriptId,
            sourceTranscriptVersionNumber: sourceTranscript.versionNumber,
            statistics: statistics
        )

        // 9. 更新元数据
        meta.summaryVersions.append(version)
        meta.status = .completed
        await MetadataManager.shared.update(meta)

        logger.info("Created summary version \(versionNumber) for meeting \(meetingId), based on transcript V\(sourceTranscript.versionNumber)")

        return version
    }

    // MARK: - Helper Methods

    /// 获取当前ASR模型信息
    private func getCurrentASRModelInfo() async -> ModelVersionInfo {
        let settings = SettingsManager.shared
        let selectedId = settings.selectedUnifiedASRId

        // 尝试从CloudAIModelManager获取详细信息
        if let config = await CloudAIModelManager.shared.getModel(byId: selectedId) {
            return ModelVersionInfo(
                modelId: config.id.uuidString,
                displayName: config.asrConfig?.modelName ?? config.displayName,
                provider: config.provider.displayName,
                configuration: [
                    "modelName": config.asrConfig?.modelName ?? "",
                    "temperature": String(config.asrConfig?.temperature ?? 0)
                ]
            )
        }

        // 回退：使用SettingsManager中的信息
        let currentModel = settings.currentASRModel
        return ModelVersionInfo(
            modelId: selectedId,
            displayName: currentModel?.name ?? "Unknown",
            provider: currentModel?.provider ?? "Unknown",
            configuration: nil
        )
    }

    /// 获取当前LLM模型信息
    private func getCurrentLLMModelInfo() async -> ModelVersionInfo {
        let settings = SettingsManager.shared
        let selectedId = settings.selectedUnifiedLLMId

        // 尝试从CloudAIModelManager获取详细信息
        if let config = await CloudAIModelManager.shared.getModel(byId: selectedId) {
            return ModelVersionInfo(
                modelId: config.id.uuidString,
                displayName: config.llmConfig?.modelName ?? config.displayName,
                provider: config.provider.displayName,
                configuration: [
                    "modelName": config.llmConfig?.modelName ?? "",
                    "temperature": String(config.llmConfig?.temperature ?? 0)
                ]
            )
        }

        // 回退：使用SettingsManager中的信息
        let currentModel = settings.currentLLMModel
        return ModelVersionInfo(
            modelId: selectedId,
            displayName: currentModel?.name ?? "Unknown",
            provider: currentModel?.provider ?? "Unknown",
            configuration: nil
        )
    }

    /// 获取当前提示词信息
    private func getCurrentPromptInfo(for category: PromptCategory) async -> PromptVersionInfo {
        let template = await PromptManager.shared.getSelectedTemplate(for: category)

        return PromptVersionInfo(
            promptId: template?.id.uuidString ?? "default",
            promptName: template?.name ?? "Default",
            contentPreview: String(template?.content.prefix(100) ?? ""),
            category: category
        )
    }

    /// 保存转录文件
    private func saveTranscriptFiles(
        result: VersionTranscriptResult,
        jsonURL: URL,
        txtURL: URL,
        processingTime: TimeInterval
    ) async throws {
        // 确保目录存在
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: jsonURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // 保存JSON格式（包含完整元数据和时间戳）
        let transcriptModel = TranscriptModel(
            metadata: TranscriptMetadata(
                duration: result.duration,
                processingTime: processingTime,
                rtf: processingTime / max(result.duration, 1.0)
            ),
            segments: result.segments.map { segment in
                TranscriptSegment(
                    start: segment.startTime,
                    end: segment.endTime,
                    text: segment.text
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(transcriptModel)
        try jsonData.write(to: jsonURL)

        // 保存TXT格式（纯文本，便于阅读）
        let textContent = result.segments.map { "[\(formatTime($0.startTime)) - \(formatTime($0.endTime))] \($0.text)" }.joined(separator: "\n")
        try textContent.write(to: txtURL, atomically: true, encoding: String.Encoding.utf8)

        logger.debug("Saved transcript files: \(jsonURL.lastPathComponent), \(txtURL.lastPathComponent)")
    }

    /// 保存摘要文件
    private func saveSummaryFile(text: String, url: URL) async throws {
        // 确保目录存在
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // 保存Markdown格式
        try text.write(to: url, atomically: true, encoding: .utf8)

        logger.debug("Saved summary file: \(url.lastPathComponent)")
    }

    /// 获取相对路径（相对于rootDataURL）
    private func relativePath(from url: URL) -> String {
        let rootPath = PathManager.shared.rootDataURL.path
        return url.path.replacingOccurrences(
            of: rootPath + "/",
            with: ""
        )
    }

    /// 格式化时间（用于TXT输出）
    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Supporting Types

/// 转录结果（用于VersionManager内部）
struct VersionTranscriptResult {
    let segments: [VersionTranscriptSegment]
    let text: String
    let language: String?
    let duration: TimeInterval
}

/// 转录分段（与TranscriptModel匹配）
struct VersionTranscriptSegment: Codable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let speaker: String?
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let versionTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

// MARK: - MeetingMeta Extension

extension MeetingMeta {
    /// 获取下一个转录版本号
    var nextTranscriptVersionNumber: Int {
        (transcriptVersions.map { $0.versionNumber }.max() ?? 0) + 1
    }

    /// 获取下一个摘要版本号
    var nextSummaryVersionNumber: Int {
        (summaryVersions.map { $0.versionNumber }.max() ?? 0) + 1
    }
}
