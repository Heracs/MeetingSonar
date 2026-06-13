//
//  AIProcessingPipelineContractTests.swift
//  MeetingSonarTests
//
//  Contract tests for production AI processing persistence and error handling.
//

import Foundation
import Testing
@testable import MeetingSonar

@Suite("AI Processing Pipeline Contract Tests", .serialized)
@MainActor
struct AIProcessingPipelineContractTests {

    @Test("Full processing failure propagates and marks metadata failed")
    func fullProcessingFailurePropagatesAndMarksMetadataFailed() async throws {
        try await withIsolatedDataRoot { root in
            let meetingID = UUID()
            let metadata = SampleData.createMeetingMeta(
                id: meetingID,
                filename: "missing-audio.m4a",
                status: .pending
            )
            await MetadataManager.shared.add(metadata)

            let missingAudioURL = root.appendingPathComponent("missing-audio.m4a")
            var didThrow = false

            do {
                _ = try await AIProcessingCoordinator.shared.process(
                    audioURL: missingAudioURL,
                    meetingID: meetingID
                )
            } catch {
                didThrow = true
            }

            #expect(didThrow)

            let updated = try #require(MetadataManager.shared.get(id: meetingID))
            #expect(updated.status == .failed)
        }
    }

    @Test("Streaming summary persists a version and completes metadata")
    func streamingSummaryPersistsVersionAndCompletesMetadata() async throws {
        try await withIsolatedDataRoot { _ in
            let meetingID = UUID()
            let transcriptID = UUID()
            var metadata = SampleData.createMeetingMeta(
                id: meetingID,
                filename: "streaming-summary.m4a",
                status: .pending
            )
            metadata.transcriptVersions = [
                TranscriptVersion(
                    id: transcriptID,
                    versionNumber: 1,
                    modelInfo: ModelVersionInfo(
                        modelId: "test-asr",
                        displayName: "Test ASR",
                        provider: "Test"
                    ),
                    promptInfo: PromptVersionInfo(
                        promptId: "test-asr-prompt",
                        promptName: "Test ASR Prompt",
                        contentPreview: "Transcribe",
                        category: .asr
                    ),
                    filePath: "Transcripts/Raw/streaming-summary_transcript_v1.json"
                )
            ]
            await MetadataManager.shared.add(metadata)

            let viewModel = StreamingSummaryViewModel()
            let provider = MockCloudServiceProvider()
            provider.mockStreamChunks = ["Summary", " text"]
            provider.mockStreamDelay = 0.01

            viewModel.startStreaming(
                transcript: "Transcript text",
                meetingID: meetingID,
                config: createLLMConfig(),
                provider: provider
            )

            try await Task.sleep(nanoseconds: 500_000_000)

            let updated = try #require(MetadataManager.shared.get(id: meetingID))
            let summaryVersion = try #require(updated.summaryVersions.first)

            #expect(viewModel.isComplete)
            #expect(updated.status == .completed)
            #expect(updated.summaryVersions.count == 1)
            #expect(summaryVersion.sourceTranscriptId == transcriptID)
            #expect(
                FileManager.default.fileExists(
                    atPath: PathManager.shared.rootDataURL
                        .appendingPathComponent(summaryVersion.filePath)
                        .path
                )
            )
        }
    }

    private func createLLMConfig() -> CloudAIModelConfig {
        CloudAIModelConfig(
            displayName: "Test DeepSeek",
            provider: .deepseek,
            baseURL: "https://api.deepseek.com/v1",
            capabilities: [.llm],
            asrConfig: nil,
            llmConfig: LLMModelSettings(
                modelName: "deepseek-chat",
                qualityPreset: .balanced
            ),
            isVerified: true
        )
    }

    private func withIsolatedDataRoot(
        _ body: (URL) async throws -> Void
    ) async throws {
        let defaults = UserDefaults.standard
        let originalRoot = defaults.string(forKey: "customDataRoot")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingSonar_AIProcessingPipelineContractTests")
            .appendingPathComponent(UUID().uuidString)

        defaults.set(root.path, forKey: "customDataRoot")
        PathManager.shared.ensureDataDirectories()
        MetadataManager.shared.recordings = []
        AIProcessingCoordinator.shared.reset()

        defer {
            MetadataManager.shared.recordings = []
            AIProcessingCoordinator.shared.reset()
            if let originalRoot {
                defaults.set(originalRoot, forKey: "customDataRoot")
            } else {
                defaults.removeObject(forKey: "customDataRoot")
            }
            try? FileManager.default.removeItem(at: root)
        }

        try await body(root)
    }
}
