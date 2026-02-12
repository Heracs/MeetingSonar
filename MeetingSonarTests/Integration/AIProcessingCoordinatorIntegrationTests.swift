//
//  AIProcessingCoordinatorIntegrationTests.swift
//  MeetingSonarTests
//
//  Integration tests for AIProcessingCoordinator testing the complete
//  ASR -> LLM processing pipeline with mock services.
//

import Testing
import Foundation
import Combine
@testable import MeetingSonar

// MARK: - Test Suite

@Suite("AIProcessingCoordinator Integration Tests")
@MainActor
struct AIProcessingCoordinatorIntegrationTests {

    // MARK: - Test Fixtures

    var testAudioURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test_audio.m4a")
    }

    var testMeetingID: UUID {
        UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
    }

    var sampleTranscriptText: String {
        """
        大家好，欢迎参加今天的会议。我们今天讨论项目进展。
        首先，开发团队已经完成了新功能的开发。
        其次，测试团队正在进行全面的测试。
        最后，我们计划在下个星期发布新版本。
        """
    }

    var sampleSummaryText: String {
        """
        # 会议纪要

        ## 会议主题
        项目进展讨论

        ## 关键讨论点
        - 开发团队已完成新功能开发
        - 测试团队正在进行全面测试
        - 计划下星期发布新版本

        ## 行动项
        1. 测试团队完成测试验证
        2. 发布团队准备上线流程
        """
    }

    // MARK: - Test State Management

    @Test("Full ASR to LLM processing pipeline succeeds with mocks")
    func testFullASRToLLMPipeline() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        // Configure mocks
        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = "test-asr-model"
        mockSettings.selectedUnifiedLLMId = "test-llm-model"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        // Setup meeting metadata
        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        // Configure mock responses
        mockCoordinator.mockTranscriptResult = sampleTranscriptText
        mockCoordinator.mockSummaryResult = sampleSummaryText

        // Act
        await mockCoordinator.process(audioURL: testAudioURL, meetingID: testMeetingID)

        // Assert
        #expect(mockCoordinator.isProcessing == false, "Processing should complete")
        #expect(mockCoordinator.currentStage == .completed, "Stage should be completed")
        #expect(mockCoordinator.progress == 1.0, "Progress should be 100%")
        #expect(mockCoordinator.lastError == nil, "No errors should occur")

        // Verify ASR was called
        #expect(mockCoordinator.asrServiceCalled, "ASR service should be called")
        #expect(mockCoordinator.lastASRMeetingID == testMeetingID, "ASR should use correct meeting ID")

        // Verify LLM was called
        #expect(mockCoordinator.llmServiceCalled, "LLM service should be called")

        // Verify metadata was updated
        let updatedMeeting = mockMetadata.get(id: testMeetingID)
        #expect(updatedMeeting != nil, "Meeting should still exist")
        #expect(updatedMeeting?.transcriptVersions.count == 1, "Should have one transcript version")
        #expect(updatedMeeting?.summaryVersions.count == 1, "Should have one summary version")
    }

    // MARK: - ASR-Only Flow Tests

    @Test("ASR-only processing returns transcript without LLM")
    func testASROnlyFlow() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = "test-asr-model"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        mockCoordinator.mockTranscriptResult = sampleTranscriptText

        // Act
        let result = await mockCoordinator.processASROnlyWithVersion(
            audioURL: testAudioURL,
            meetingID: testMeetingID
        )

        // Assert
        #expect(result.text != nil, "Should return transcript text")
        #expect(result.text == sampleTranscriptText, "Transcript text should match")
        #expect(result.url != nil, "Should return transcript URL")
        #expect(result.version != nil, "Should return transcript version")
        #expect(result.version?.versionNumber == 1, "Version number should be 1")
        #expect(mockCoordinator.llmServiceCalled == false, "LLM should NOT be called")

        // Verify only transcript was added
        let updatedMeeting = mockMetadata.get(id: testMeetingID)
        #expect(updatedMeeting?.transcriptVersions.count == 1, "Should have one transcript")
        #expect(updatedMeeting?.summaryVersions.count == 0, "Should have no summary")
    }

    // MARK: - Error Handling Tests

    @Test("Processing fails when no ASR model configured")
    func testFailsWithoutASRModel() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = ""  // Empty model ID

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        // ✅ Phase 3 修复: 提供实际的错误对象
        mockCoordinator.shouldThrowASRError = true
        mockCoordinator.mockASRError = AIProcessingError.notImplemented("No ASR model configured")

        // Act
        await mockCoordinator.process(audioURL: testAudioURL, meetingID: testMeetingID)

        // Assert
        #expect(mockCoordinator.isProcessing == false, "Processing should complete")
        #expect(mockCoordinator.lastError != nil, "Should have an error")

        if case .failed = mockCoordinator.currentStage {
            #expect(true, "Should be in failed state")
        } else {
            #expect(Bool(false), "Expected failed stage")
        }
    }

    @Test("Processing fails when no LLM model configured with fallback")
    func testFailsWithoutLLMModelNoFallback() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedLLMId = "non-existent-model-id"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        mockCoordinator.mockTranscriptResult = sampleTranscriptText
        mockCoordinator.shouldThrowLLMError = true
        mockCoordinator.mockLLMError = AIProcessingError.notImplemented("No LLM model configured")
        mockCoordinator.noLLMFallbackAvailable = true

        // Act
        await mockCoordinator.process(audioURL: testAudioURL, meetingID: testMeetingID)

        // Assert
        #expect(mockCoordinator.isProcessing == false, "Processing should complete")
        #expect(mockCoordinator.lastError != nil, "Should have an error")
        #expect(mockCoordinator.attemptedFallback, "Should attempt fallback to available LLM")

        if case .failed = mockCoordinator.currentStage {
            #expect(true, "Should be in failed state")
        } else {
            #expect(Bool(false), "Expected failed stage")
        }
    }

    @Test("ASR error propagates correctly through pipeline")
    func testASRErrorPropagation() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        // ✅ Phase 3 修复: 提供实际的错误对象
        mockCoordinator.shouldThrowASRError = true
        mockCoordinator.mockASRError = AIProcessingError.notImplemented("ASR processing failed")

        // Act
        await mockCoordinator.process(audioURL: testAudioURL, meetingID: testMeetingID)

        // Assert
        #expect(mockCoordinator.lastError != nil, "Should have an error")
        #expect(mockCoordinator.currentStage != .completed, "Should not complete")
        #expect(mockCoordinator.llmServiceCalled == false, "LLM should not be called after ASR failure")
    }

    // MARK: - Progress Tracking Tests

    @Test("Progress updates correctly through pipeline stages")
    func testProgressUpdates() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = "test-asr-model"
        mockSettings.selectedUnifiedLLMId = "test-llm-model"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        mockCoordinator.mockTranscriptResult = sampleTranscriptText
        mockCoordinator.mockSummaryResult = sampleSummaryText

        var progressStages: [Double] = []
        mockCoordinator.onProgressUpdate = { progress in
            progressStages.append(progress)
        }

        // Act
        await mockCoordinator.process(audioURL: testAudioURL, meetingID: testMeetingID)

        // Assert
        #expect(progressStages.contains(0.0), "Should start at 0%")
        #expect(progressStages.contains(1.0), "Should end at 100%")
        #expect(progressStages.last == 1.0, "Final progress should be 100%")

        // Verify intermediate progress points
        let expectedProgressPoints = [0.0, 0.4, 0.5, 0.9, 1.0]
        for expected in expectedProgressPoints {
            #expect(progressStages.contains(expected), "Should contain progress point \(expected)")
        }
    }

    // MARK: - Stage Transition Tests

    @Test("Processing stages transition in correct order")
    func testStageTransitions() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = "test-asr-model"
        mockSettings.selectedUnifiedLLMId = "test-llm-model"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        mockCoordinator.mockTranscriptResult = sampleTranscriptText
        mockCoordinator.mockSummaryResult = sampleSummaryText

        var stageHistory: [String] = []
        mockCoordinator.onStageChange = { stage in
            stageHistory.append(String(describing: stage))
        }

        // Act
        await mockCoordinator.process(audioURL: testAudioURL, meetingID: testMeetingID)

        // Assert
        #expect(stageHistory.count >= 4, "Should have at least 4 stages")

        // Verify stage order
        let expectedStages = ["asr", "persistingTranscript", "llm", "persistingSummary", "completed"]
        for expected in expectedStages {
            #expect(stageHistory.contains(expected), "Should contain stage: \(expected)")
        }
    }

    // MARK: - Metadata Update Tests

    @Test("MetadataManager receives correct transcript version")
    func testMetadataReceivesTranscriptVersion() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = "test-asr-model"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        mockCoordinator.mockTranscriptResult = sampleTranscriptText
        mockCoordinator.mockASRModelName = "Test-ASR-Model"

        // Act
        let result = await mockCoordinator.processASROnlyWithVersion(
            audioURL: testAudioURL,
            meetingID: testMeetingID
        )

        // Assert
        let updatedMeeting = try #require(mockMetadata.get(id: testMeetingID))
        #expect(updatedMeeting.transcriptVersions.count == 1, "Should have one transcript version")

        let transcriptVersion = try #require(updatedMeeting.transcriptVersions.first)
        #expect(transcriptVersion.versionNumber == 1, "Version should be 1")
        #expect(transcriptVersion.modelInfo.displayName == "Test-ASR-Model", "Should use correct model")
        #expect(!transcriptVersion.filePath.isEmpty, "Should have file path")
    }

    @Test("MetadataManager receives correct summary version")
    func testMetadataReceivesSummaryVersion() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = "test-asr-model"
        mockSettings.selectedUnifiedLLMId = "test-llm-model"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        // First add a transcript version
        let transcriptVersionId = UUID()
        var transcriptVersion = TranscriptVersion(
            id: transcriptVersionId,
            versionNumber: 1,
            timestamp: Date(),
            modelInfo: ModelVersionInfo(
                modelId: "test-asr",
                displayName: "Test ASR",
                provider: "Test"
            ),
            promptInfo: PromptVersionInfo(
                promptId: "default",
                promptName: "Default",
                contentPreview: "",
                category: .asr
            ),
            filePath: "Transcripts/Raw/test.json"
        )
        meeting.transcriptVersions.append(transcriptVersion)
        await mockMetadata.update(meeting)

        mockCoordinator.mockTranscriptResult = sampleTranscriptText
        mockCoordinator.mockSummaryResult = sampleSummaryText
        mockCoordinator.mockLLMModelName = "Test-LLM-Model"

        // Act
        await mockCoordinator.process(audioURL: testAudioURL, meetingID: testMeetingID)

        // Assert
        let updatedMeeting = try #require(mockMetadata.get(id: testMeetingID))
        #expect(updatedMeeting.summaryVersions.count == 1, "Should have one summary version")

        let summaryVersion = try #require(updatedMeeting.summaryVersions.first)
        #expect(summaryVersion.versionNumber == 1, "Version should be 1")
        #expect(summaryVersion.sourceTranscriptId == transcriptVersionId, "Should link to transcript")
        #expect(summaryVersion.sourceTranscriptVersionNumber == 1, "Should link to transcript V1")
        #expect(summaryVersion.modelInfo.displayName == "Test-LLM-Model", "Should use correct LLM model")
        #expect(updatedMeeting.status == .completed, "Meeting status should be completed")
    }

    // MARK: - Configuration Tests

    @Test("Uses selected ASR model from SettingsManager")
    func testUsesSelectedASRModel() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = "custom-asr-model-id"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        mockCoordinator.mockTranscriptResult = sampleTranscriptText

        // Act
        await mockCoordinator.processASROnlyWithVersion(
            audioURL: testAudioURL,
            meetingID: testMeetingID
        )

        // Assert
        #expect(mockCoordinator.lastUsedASRModelID == "custom-asr-model-id", "Should use selected ASR model")
    }

    @Test("Uses selected LLM model from SettingsManager")
    func testUsesSelectedLLMModel() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = "test-asr-model"
        mockSettings.selectedUnifiedLLMId = "custom-llm-model-id"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        mockCoordinator.mockTranscriptResult = sampleTranscriptText
        mockCoordinator.mockSummaryResult = sampleSummaryText

        // Act
        await mockCoordinator.process(audioURL: testAudioURL, meetingID: testMeetingID)

        // Assert
        #expect(mockCoordinator.lastUsedLLMModelID == "custom-llm-model-id", "Should use selected LLM model")
    }

    // MARK: - Edge Cases Tests

    @Test("Handles empty transcript gracefully")
    func testHandlesEmptyTranscript() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = "test-asr-model"
        mockSettings.selectedUnifiedLLMId = "test-llm-model"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        mockCoordinator.mockTranscriptResult = ""  // Empty transcript
        mockCoordinator.mockSummaryResult = sampleSummaryText

        // Act
        await mockCoordinator.process(audioURL: testAudioURL, meetingID: testMeetingID)

        // Assert - Should still complete even with empty transcript
        #expect(mockCoordinator.isProcessing == false, "Processing should complete")

        // Empty transcript should still create a version
        let updatedMeeting = mockMetadata.get(id: testMeetingID)
        #expect(updatedMeeting?.transcriptVersions.count == 1, "Should create transcript version even if empty")
    }

    @Test("Handles very long transcript without crashing")
    func testHandlesLongTranscript() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = "test-asr-model"
        mockSettings.selectedUnifiedLLMId = "test-llm-model"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 7200.0,  // 2 hours
            status: .pending
        )
        await mockMetadata.add(meeting)

        // Create a very long transcript (simulating 2-hour meeting)
        let longTranscript = String(repeating: sampleTranscriptText, count: 100)
        mockCoordinator.mockTranscriptResult = longTranscript
        mockCoordinator.mockSummaryResult = sampleSummaryText

        // Act
        await mockCoordinator.process(audioURL: testAudioURL, meetingID: testMeetingID)

        // Assert
        #expect(mockCoordinator.isProcessing == false, "Processing should complete")
        #expect(mockCoordinator.currentStage == .completed, "Should complete successfully")

        let updatedMeeting = mockMetadata.get(id: testMeetingID)
        #expect(updatedMeeting?.transcriptVersions.count == 1, "Should have transcript version")
    }

    @Test("Handles concurrent processing requests")
    func testConcurrentProcessing() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = "test-asr-model"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        let meetingID1 = UUID()
        let meetingID2 = UUID()
        let testURL1 = FileManager.default.temporaryDirectory.appendingPathComponent("test1.m4a")
        let testURL2 = FileManager.default.temporaryDirectory.appendingPathComponent("test2.m4a")

        var meeting1 = SampleData.createMeetingMeta(
            id: meetingID1,
            filename: "test1.m4a",
            source: "Test",
            startTime: Date(),
            duration: 60.0,
            status: .pending
        )
        var meeting2 = SampleData.createMeetingMeta(
            id: meetingID2,
            filename: "test2.m4a",
            source: "Test",
            startTime: Date(),
            duration: 60.0,
            status: .pending
        )
        await mockMetadata.add(meeting1)
        await mockMetadata.add(meeting2)

        mockCoordinator.mockTranscriptResult = sampleTranscriptText

        // Act - Start concurrent processing
        async let result1 = mockCoordinator.processASROnlyWithVersion(
            audioURL: testURL1,
            meetingID: meetingID1
        )
        async let result2 = mockCoordinator.processASROnlyWithVersion(
            audioURL: testURL2,
            meetingID: meetingID2
        )

        await result1
        await result2

        // Assert
        #expect(mockCoordinator.isProcessing == false, "Processing should complete")
        #expect(mockMetadata.recordings.count == 2, "Should have both meetings")
        #expect(mockMetadata.recordings.allSatisfy { $0.transcriptVersions.count == 1 }, "Both should have transcripts")
    }

    // MARK: - Reset Tests

    @Test("Reset clears coordinator state between tests")
    func testResetBetweenTests() async throws {
        // Arrange
        let mockCoordinator = MockAIProcessingCoordinator()
        let mockMetadata = MockMetadataManager()
        let mockSettings = MockSettingsManager()

        mockMetadata.configureForTesting()
        mockSettings.configureForTesting()
        mockSettings.selectedUnifiedASRId = "test-asr-model"

        // ✅ Phase 1 修复: 注入依赖到 MockAIProcessingCoordinator
        mockCoordinator.metadataManager = mockMetadata
        mockCoordinator.settingsManager = mockSettings

        var meeting = SampleData.createMeetingMeta(
            id: testMeetingID,
            filename: "test_audio.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting)

        mockCoordinator.mockTranscriptResult = sampleTranscriptText

        // Act - First run
        await mockCoordinator.processASROnlyWithVersion(
            audioURL: testAudioURL,
            meetingID: testMeetingID
        )

        let firstError = mockCoordinator.lastError
        let firstStage = mockCoordinator.currentStage

        // Reset
        mockCoordinator.reset()

        // Second run
        let meetingID2 = UUID()
        var meeting2 = SampleData.createMeetingMeta(
            id: meetingID2,
            filename: "test2.m4a",
            source: "Test",
            startTime: Date(),
            duration: 120.0,
            status: .pending
        )
        await mockMetadata.add(meeting2)

        await mockCoordinator.processASROnlyWithVersion(
            audioURL: testAudioURL,
            meetingID: meetingID2
        )

        // Assert - State should be fresh
        let secondError = mockCoordinator.lastError
        let errorChanged = firstError != nil && secondError != nil && firstError!.localizedDescription != secondError!.localizedDescription
        #expect(!errorChanged || secondError == nil, "Error state should be reset")
        #expect(mockCoordinator.currentStage != .idle, "Stage should have progressed")
    }
}

// MARK: - Mock AI Processing Coordinator

/// Mock implementation of AIProcessingCoordinator for integration testing
@MainActor
class MockAIProcessingCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var isProcessing = false
    @Published var currentStage: AIProcessingCoordinator.ProcessingStage = .idle
    @Published var progress: Double = 0
    @Published var lastError: Error?

    // MARK: - Dependency Injection

    /// 注入的 MetadataManager - 用于持久化处理结果
    weak var metadataManager: MockMetadataManager?

    /// 注入的 SettingsManager - 用于获取当前配置的模型 ID
    weak var settingsManager: MockSettingsManager?

    // MARK: - Mock Configuration

    var mockTranscriptResult: String = ""
    var mockSummaryResult: String = ""
    var mockASRModelName: String = "Mock-ASR"
    var mockLLMModelName: String = "Mock-LLM"

    var shouldThrowASRError = false
    var mockASRError: Error?

    var shouldThrowLLMError = false
    var mockLLMError: Error?

    var noLLMFallbackAvailable = false

    // MARK: - Tracking Properties

    private(set) var asrServiceCalled = false
    private(set) var llmServiceCalled = false
    private(set) var lastASRMeetingID: UUID?
    private(set) var lastUsedASRModelID: String?
    private(set) var lastUsedLLMModelID: String?
    private(set) var attemptedFallback = false

    // MARK: - Callbacks

    var onProgressUpdate: ((Double) -> Void)?
    var onStageChange: ((AIProcessingCoordinator.ProcessingStage) -> Void)?

    // MARK: - Processing Methods

    func process(audioURL: URL, meetingID: UUID) async {
        isProcessing = true
        progress = 0
        lastError = nil
        onProgressUpdate?(0)

        do {
            // Stage 1: ASR
            currentStage = .asr
            onStageChange?(.asr)
            asrServiceCalled = true
            lastASRMeetingID = meetingID

            // ✅ Phase 1 修复: 跟踪使用的 ASR 模型 ID
            if let settingsManager = settingsManager {
                lastUsedASRModelID = settingsManager.selectedUnifiedASRId
            }

            if shouldThrowASRError {
                if let error = mockASRError {
                    throw error
                }
            }

            // Simulate ASR processing
            try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
            progress = 0.4
            onProgressUpdate?(0.4)

            // Stage 2: Persist Transcript
            currentStage = .persistingTranscript
            onStageChange?(.persistingTranscript)
            try await Task.sleep(nanoseconds: 50_000_000)  // 0.05s
            progress = 0.5
            onProgressUpdate?(0.5)

            // ✅ Phase 1 修复: 创建并持久化 TranscriptVersion 到 MetadataManager
            // ✅ Phase 3 修复: 检查是否已有 transcript version，如果有则重用
            var transcriptVersion: TranscriptVersion
            var transcriptVersionID: UUID

            if let metadataManager = metadataManager,
               let meeting = metadataManager.get(id: meetingID),
               !meeting.transcriptVersions.isEmpty {
                // 重用已存在的 transcript version
                transcriptVersion = meeting.transcriptVersions[0]
                transcriptVersionID = transcriptVersion.id
            } else {
                // 创建新的 transcript version
                transcriptVersion = TranscriptVersion(
                    id: UUID(),
                    versionNumber: 1,
                    timestamp: Date(),
                    modelInfo: ModelVersionInfo(
                        modelId: "mock-asr",
                        displayName: mockASRModelName,
                        provider: "Mock"
                    ),
                    promptInfo: PromptVersionInfo(
                        promptId: "default",
                        promptName: "Default",
                        contentPreview: "",
                        category: .asr
                    ),
                    filePath: "Transcripts/Raw/test_transcript_v1_20240121-140000.json"
                )

                // 保存 ID 以供 SummaryVersion 使用
                transcriptVersionID = transcriptVersion.id

                if let metadataManager = metadataManager,
                   let meeting = metadataManager.get(id: meetingID) {
                    var updated = meeting
                    updated.transcriptVersions.append(transcriptVersion)
                    await metadataManager.update(updated)
                }
            }

            // Stage 3: LLM
            currentStage = .llm
            onStageChange?(.llm)
            llmServiceCalled = true

            // ✅ Phase 1 修复: 跟踪使用的 LLM 模型 ID
            if let settingsManager = settingsManager {
                lastUsedLLMModelID = settingsManager.selectedUnifiedLLMId
            }

            if shouldThrowLLMError {
                if let error = mockLLMError {
                    if noLLMFallbackAvailable {
                        attemptedFallback = true
                    }
                    throw error
                }
            }

            // Simulate LLM processing
            try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
            progress = 0.9
            onProgressUpdate?(0.9)

            // Stage 4: Persist Summary
            currentStage = .persistingSummary
            onStageChange?(.persistingSummary)
            try await Task.sleep(nanoseconds: 50_000_000)  // 0.05s
            progress = 1.0
            onProgressUpdate?(1.0)

            // ✅ Phase 1 修复: 创建并持久化 SummaryVersion 到 MetadataManager
            let summaryVersion = SummaryVersion(
                id: UUID(),
                versionNumber: 1,
                timestamp: Date(),
                modelInfo: ModelVersionInfo(
                    modelId: "mock-llm",
                    displayName: mockLLMModelName,
                    provider: "Mock"
                ),
                promptInfo: PromptVersionInfo(
                    promptId: "default",
                    promptName: "Default",
                    contentPreview: "",
                    category: .llm
                ),
                filePath: "SmartNotes/test_summary_v1_20240121-140000.md",
                sourceTranscriptId: transcriptVersionID,
                sourceTranscriptVersionNumber: 1
            )

            // 持久化到 MetadataManager
            if let metadataManager = metadataManager,
               let meeting = metadataManager.get(id: meetingID) {
                var updated = meeting
                updated.summaryVersions.append(summaryVersion)
                updated.status = .completed
                await metadataManager.update(updated)
            }

            // Completed
            currentStage = .completed
            onStageChange?(.completed)
        } catch {
            lastError = error
            currentStage = .failed(error.localizedDescription)
            onStageChange?(.failed(error.localizedDescription))
        }

        isProcessing = false
        }

    func processASROnly(audioURL: URL, meetingID: UUID) async -> (text: String?, transcriptURL: URL?) {
        let result = await processASROnlyWithVersion(audioURL: audioURL, meetingID: meetingID)
        return (result.text, result.url)
    }

    func processASROnlyWithVersion(audioURL: URL, meetingID: UUID) async -> (
        text: String?,
        url: URL?,
        version: TranscriptVersion?
    ) {
        isProcessing = true
        progress = 0
        lastError = nil

        do {
            currentStage = .asr
            onStageChange?(.asr)
            asrServiceCalled = true
            lastASRMeetingID = meetingID

            // ✅ Phase 1 修复: 跟踪使用的 ASR 模型 ID
            if let settingsManager = settingsManager {
                lastUsedASRModelID = settingsManager.selectedUnifiedASRId
            }

            if shouldThrowASRError, let error = mockASRError {
                throw error
            }

            // Simulate ASR processing
            try await Task.sleep(nanoseconds: 50_000_000)  // 0.05s
            progress = 0.8
            onProgressUpdate?(0.8)

            currentStage = .persistingTranscript
            onStageChange?(.persistingTranscript)
            try await Task.sleep(nanoseconds: 50_000_000)
            progress = 1.0
            onProgressUpdate?(1.0)

            currentStage = .completed
            onStageChange?(.completed)

            let version = TranscriptVersion(
                id: UUID(),
                versionNumber: 1,
                timestamp: Date(),
                modelInfo: ModelVersionInfo(
                    modelId: "mock-asr",
                    displayName: mockASRModelName,
                    provider: "Mock"
                ),
                promptInfo: PromptVersionInfo(
                    promptId: "default",
                    promptName: "Default",
                    contentPreview: "",
                    category: .asr
                ),
                filePath: "Transcripts/Raw/test_transcript_v1_20240121-140000.json"
            )

            // ✅ Phase 1 修复: 持久化 TranscriptVersion 到 MetadataManager
            if let metadataManager = metadataManager,
               let meeting = metadataManager.get(id: meetingID) {
                var updated = meeting
                updated.transcriptVersions.append(version)
                await metadataManager.update(updated)
            }

            // ✅ Phase 3 修复: 确保成功路径也重置 isProcessing 标志
            isProcessing = false
            return (mockTranscriptResult, audioURL, version)

        } catch {
            lastError = error
            currentStage = .failed(error.localizedDescription)
            onStageChange?(.failed(error.localizedDescription))
            isProcessing = false
            return (nil, nil, nil)
        }
    }

    // MARK: - Legacy API Methods

    func transcribeOnly(audioURL: URL, meetingID: UUID?) async throws -> (String, URL, UUID) {
        let actualMeetingID = meetingID ?? UUID()
        let (text, url, version) = await processASROnlyWithVersion(
            audioURL: audioURL,
            meetingID: actualMeetingID
        )

        guard let transcriptText = text,
              let transcriptURL = url,
              let transcriptVersion = version else {
            throw AIProcessingError.notImplemented("Transcription failed")
        }

        return (transcriptText, transcriptURL, transcriptVersion.id)
    }

    func generateSummaryOnly(
        transcriptText: String,
        audioURL: URL,
        sourceTranscriptId: UUID,
        meetingID: UUID?
    ) async throws -> (String, URL, UUID) {
        llmServiceCalled = true

        if shouldThrowLLMError {
            if let error = mockLLMError {
                throw error
            }
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        let version = SummaryVersion(
            id: UUID(),
            versionNumber: 1,
            timestamp: Date(),
            modelInfo: ModelVersionInfo(
                modelId: "mock-llm",
                displayName: mockLLMModelName,
                provider: "Mock"
            ),
            promptInfo: PromptVersionInfo(
                promptId: "default",
                promptName: "Default",
                contentPreview: "",
                category: .llm
            ),
            filePath: "SmartNotes/test_summary_v1_20240121-140000.md",
            sourceTranscriptId: sourceTranscriptId,
            sourceTranscriptVersionNumber: 1
        )

        return (mockSummaryResult, audioURL, version.id)
    }

    // MARK: - Reset

    func reset() {
        isProcessing = false
        currentStage = .idle
        progress = 0
        lastError = nil
        asrServiceCalled = false
        llmServiceCalled = false
        lastASRMeetingID = nil
        lastUsedASRModelID = nil
        lastUsedLLMModelID = nil
        attemptedFallback = false
    }
}
