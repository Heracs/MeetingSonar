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
            let startTime = Date()

            do {
                // Build messages
                let messages = buildMessages(transcript: transcript)

                // Get model settings
                let modelName = config.llmConfig?.modelName ?? provider.provider.defaultLLMModel
                let settings = config.llmConfig

                // Log detailed API request parameters for debugging
                logger.debug("""
                [StreamingSummary] API Request Parameters:
                ├─ Provider: \(provider.provider.displayName) (\(provider.provider.rawValue))
                ├─ Base URL: \(provider.baseURL)
                ├─ Model: \(modelName)
                ├─ Temperature: \(settings?.temperature.map { String($0) } ?? "not set (use provider default)")
                ├─ Max Tokens: \(settings?.maxTokens.map { String($0) } ?? "not set (use provider default)")
                ├─ Quality Preset: \(settings?.qualityPreset.rawValue ?? "none")
                ├─ Messages Count: \(messages.count)
                ├─ System Message Length: \(messages.first?.content.count ?? 0) chars
                ├─ User Message Length: \(messages.last?.content.count ?? 0) chars
                └─ Transcript Length: \(transcript.count) chars
                """)

                // Start streaming
                let stream = try await provider.generateChatCompletionStream(
                    messages: messages,
                    model: modelName,
                    temperature: settings?.temperature,
                    maxTokens: settings?.maxTokens
                )

                state = .streaming(progress: 0.0)

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
                await saveSummary(
                    text: streamingText,
                    meetingID: meetingID,
                    processingTime: Date().timeIntervalSince(startTime)
                )

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

    /// Start summary generation through the provider runtime abstraction.
    /// The current runtime protocol is request/response, so this preserves the view model state contract
    /// while keeping the legacy streaming entry point available for cloud providers that support token streams.
    func startStreaming(
        transcript: String,
        prompt: String,
        config: AIProviderConfig,
        runtime: any LLMRuntime,
        meetingID: UUID,
        sourceTranscriptId: UUID
    ) async {
        guard state == .idle || state.isTerminal else { return }

        state = .connecting
        streamingText = ""
        errorMessage = ""
        let startTime = Date()

        do {
            let result = try await runtime.generateSummary(
                messages: buildRuntimeMessages(transcript: transcript, prompt: prompt),
                context: LLMRuntimeContext(
                    meetingID: meetingID,
                    temperature: config.llm?.temperature ?? 0.7,
                    maxTokens: config.llm?.maxTokens ?? 4096
                )
            )

            streamingText = result.content
            state = .completed(text: result.content)

            await saveSummary(
                text: result.content,
                meetingID: meetingID,
                sourceTranscriptId: sourceTranscriptId,
                processingTime: Date().timeIntervalSince(startTime)
            )
        } catch is CancellationError {
            state = .cancelled
            logger.info("Streaming cancelled by user")
        } catch {
            state = .failed(error: error.localizedDescription)
            errorMessage = error.localizedDescription
            logger.error("Streaming failed: \(error.localizedDescription)")
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

    private func buildRuntimeMessages(transcript: String, prompt: String) -> [LLMMessage] {
        let systemPrompt = prompt.isEmpty
            ? "你是一个专业的会议纪要助手。请将以下会议转录文本整理成结构化的会议纪要。"
            : prompt

        return [
            LLMMessage(role: ChatMessage.MessageRole.system.rawValue, content: systemPrompt),
            LLMMessage(role: ChatMessage.MessageRole.user.rawValue, content: "请为以下会议生成纪要：\n\n\(transcript)")
        ]
    }

    private func saveSummary(
        text: String,
        meetingID: UUID,
        processingTime: TimeInterval
    ) async {
        do {
            // Get the meeting to find transcript version info
            guard let meeting = MetadataManager.shared.get(id: meetingID) else {
                logger.error("Meeting not found: \(meetingID)")
                return
            }

            // Get source transcript info (latest transcript version)
            guard let sourceTranscript = meeting.transcriptVersions.last else {
                logger.error("Cannot save summary without a source transcript: \(meetingID)")
                return
            }

            let audioURL = PathManager.shared.recordingsURL.appendingPathComponent(meeting.filename)
            let version = try await VersionManager.shared.createSummaryVersion(
                meetingId: meetingID,
                summaryText: text,
                audioURL: audioURL,
                sourceTranscriptId: sourceTranscript.id,
                processingTime: processingTime
            )

            let fullPath = PathManager.shared.rootDataURL.appendingPathComponent(version.filePath)
            logger.info("Summary saved: \(fullPath.path)")

        } catch {
            logger.error("Failed to save summary: \(error.localizedDescription)")
        }
    }

    private func saveSummary(
        text: String,
        meetingID: UUID,
        sourceTranscriptId: UUID,
        processingTime: TimeInterval
    ) async {
        do {
            guard let meeting = MetadataManager.shared.get(id: meetingID) else {
                logger.error("Meeting not found: \(meetingID)")
                return
            }

            let audioURL = PathManager.shared.recordingsURL.appendingPathComponent(meeting.filename)
            let version = try await VersionManager.shared.createSummaryVersion(
                meetingId: meetingID,
                summaryText: text,
                audioURL: audioURL,
                sourceTranscriptId: sourceTranscriptId,
                processingTime: processingTime
            )

            let fullPath = PathManager.shared.rootDataURL.appendingPathComponent(version.filePath)
            logger.info("Summary saved: \(fullPath.path)")

        } catch {
            logger.error("Failed to save summary: \(error.localizedDescription)")
        }
    }
}
