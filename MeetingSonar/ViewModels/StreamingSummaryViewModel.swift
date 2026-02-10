//
//  StreamingSummaryViewModel.swift
//  MeetingSonar
//
//  Phase 3: Streaming summary generation ViewModel
//  v1.1.0: Real-time streaming LLM output for summary generation
//

import SwiftUI
import OSLog

/// Streaming state for summary generation
enum StreamingState: Equatable {
    case idle
    case connecting
    case streaming(progress: Double)
    case completed(text: String)
    case failed(error: String)
    case cancelled

    var isStreaming: Bool {
        if case .streaming = self { return true }
        return false
    }

    var isComplete: Bool {
        if case .completed = self { return true }
        return false
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}

/// ViewModel for streaming summary generation
@MainActor
final class StreamingSummaryViewModel: ObservableObject {

    // MARK: - Published State
    @Published private(set) var state: StreamingState = .idle
    @Published private(set) var streamingText: String = ""
    @Published private(set) var errorMessage: String = ""

    // MARK: - Private Properties
    private var streamingTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.meetingsonar", category: "StreamingSummaryViewModel")

    // MARK: - Computed Properties
    var isStreaming: Bool { state.isStreaming }
    var isComplete: Bool { state.isComplete }
    var wordCount: Int { streamingText.count }

    // MARK: - Streaming Control

    /// Start streaming summary generation
    /// - Parameters:
    ///   - transcript: Transcript text to summarize
    ///   - meetingID: Meeting identifier
    ///   - config: LLM configuration
    ///   - provider: Cloud service provider
    func startStreaming(
        transcript: String,
        meetingID: UUID,
        config: CloudAIModelConfig,
        provider: any CloudServiceProvider
    ) {
        guard state == .idle || state.isTerminal else { return }

        streamingTask = Task {
            state = .connecting
            streamingText = ""

            do {
                // Build messages
                let messages = buildMessages(transcript: transcript)

                // Get model settings
                let modelName = config.llmConfig?.modelName ?? provider.provider.defaultLLMModel
                let settings = config.llmConfig

                state = .streaming(progress: 0.0)

                // Start streaming
                let stream = try await provider.generateChatCompletionStream(
                    messages: messages,
                    model: modelName,
                    temperature: settings?.temperature,
                    maxTokens: settings?.maxTokens
                )

                var tokenCount = 0
                for await chunk in stream {
                    try Task.checkCancellation()

                    streamingText += chunk
                    tokenCount += chunk.count

                    // Estimate progress (max ~4000 tokens for summary)
                    let progress = min(Double(tokenCount) / 4000.0, 0.95)
                    state = .streaming(progress: progress)
                }

                state = .completed(text: streamingText)

                // Save to file
                await saveSummary(text: streamingText, meetingID: meetingID, config: config)

            } catch is CancellationError {
                state = .cancelled
                logger.info("Streaming cancelled by user")
            } catch {
                state = .failed(error: error.localizedDescription)
                errorMessage = error.localizedDescription
                logger.error("Streaming failed: \(error.localizedDescription)")
            }
        }
    }

    /// Stop streaming generation
    func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    /// Retry generation
    func retry(
        transcript: String,
        meetingID: UUID,
        config: CloudAIModelConfig,
        provider: any CloudServiceProvider
    ) {
        streamingText = ""
        state = .idle
        startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: provider
        )
    }

    // MARK: - Private Methods

    private func buildMessages(transcript: String) -> [ChatMessage] {
        let systemPrompt = "你是一个专业的会议纪要助手。请将以下会议转录文本整理成结构化的会议纪要。要求：\n1. 提取关键讨论点和决策\n2. 列出行动项和负责人（如果有）\n3. 使用简洁清晰的语言\n4. 保持客观，不添加未提及的内容"

        return [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: "请为以下会议生成纪要：\n\n\(transcript)")
        ]
    }

    private func saveSummary(
        text: String,
        meetingID: UUID,
        config: CloudAIModelConfig
    ) async {
        do {
            // Get the meeting to find transcript version info
            guard let meeting = MetadataManager.shared.get(id: meetingID) else {
                logger.error("Meeting not found: \(meetingID)")
                return
            }

            // Generate summary file path
            let summaryId = UUID()
            let fileName = "\(summaryId.uuidString)_summary.md"
            let relativePath = "SmartNotes/\(fileName)"

            let fullPath = PathManager.shared.rootDataURL.appendingPathComponent(relativePath)

            // Ensure directory exists
            let dir = fullPath.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            // Write file
            try text.write(to: fullPath, atomically: true, encoding: .utf8)

            // Determine version number
            let versionNumber = meeting.summaryVersions.count + 1

            // Get source transcript info (latest transcript version)
            let sourceTranscript = meeting.transcriptVersions.last

            // Create model info
            let modelInfo = ModelVersionInfo(
                modelId: config.id.uuidString,
                displayName: config.llmConfig?.modelName ?? config.provider.defaultLLMModel,
                provider: config.provider.displayName,
                configuration: [
                    "temperature": String(config.llmConfig?.temperature ?? 0.7),
                    "maxTokens": String(config.llmConfig?.maxTokens ?? 4096)
                ]
            )

            // Create prompt info
            let promptInfo = PromptVersionInfo(
                promptId: "streaming_summary",
                promptName: "Streaming Summary",
                contentPreview: "会议纪要点提取...",
                category: .llm
            )

            // Create summary version
            let version = SummaryVersion(
                id: summaryId,
                versionNumber: versionNumber,
                timestamp: Date(),
                modelInfo: modelInfo,
                promptInfo: promptInfo,
                filePath: relativePath,
                sourceTranscriptId: sourceTranscript?.id ?? meetingID,
                sourceTranscriptVersionNumber: sourceTranscript?.versionNumber ?? 1
            )

            // Update metadata directly
            if let index = MetadataManager.shared.recordings.firstIndex(where: { $0.id == meetingID }) {
                MetadataManager.shared.recordings[index].summaryVersions.append(version)
                await MetadataManager.shared.save()
                logger.info("Summary saved: \(fullPath.path)")
            }

        } catch {
            logger.error("Failed to save summary: \(error.localizedDescription)")
        }
    }
}
