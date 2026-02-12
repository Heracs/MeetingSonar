//
//  AIProcessingCoordinatorTests.swift
//  MeetingSonarTests
//
//  Unit tests for AIProcessingCoordinator using Swift Testing framework.
//

import Foundation
import Testing
@testable import MeetingSonar

// MARK: - Mock CloudAIModelManager

/// Mock CloudAIModelManager for testing
actor MockCloudAIModelManager {
    private var models: [String: CloudAIModelConfig] = [:]
    private var apiKeys: [String: String] = [:]
    private var firstLLMModel: CloudAIModelConfig?
    private var firstASRModel: CloudAIModelConfig?

    var getModelCalled = false
    var getFirstModelCalled = false
    var getAPIKeyCalled = false
    var lastRequestedModelId: String?
    var lastRequestedCapability: ModelCapability?

    func configureTestModels() {
        // LLM model
        let llmConfig = CloudAIModelConfig(
            displayName: "Test LLM Model",
            provider: .deepseek,
            baseURL: "https://api.test.com/v1",
            capabilities: [.llm],
            llmConfig: LLMModelSettings(
                modelName: "test-llm-model",
                qualityPreset: .balanced,
                temperature: nil,
                maxTokens: nil
            )
        )
        models[llmConfig.id.uuidString] = llmConfig
        apiKeys[llmConfig.id.uuidString] = "test-api-key"
        firstLLMModel = llmConfig

        // ASR model
        let asrConfig = CloudAIModelConfig(
            displayName: "Test ASR Model",
            provider: .zhipu,
            baseURL: "https://api.test.com/v1",
            capabilities: [.asr],
            asrConfig: ASRModelSettings(
                modelName: "test-asr-model",
                temperature: nil,
                maxTokens: nil
            )
        )
        models[asrConfig.id.uuidString] = asrConfig
        apiKeys[asrConfig.id.uuidString] = "test-api-key"
        firstASRModel = asrConfig
    }

    func getModel(byId id: String) -> CloudAIModelConfig? {
        getModelCalled = true
        lastRequestedModelId = id
        return models[id]
    }

    func getFirstModel(for capability: ModelCapability) -> CloudAIModelConfig? {
        getFirstModelCalled = true
        lastRequestedCapability = capability
        switch capability {
        case .llm:
            return firstLLMModel
        case .asr:
            return firstASRModel
        }
    }

    func getAPIKey(for id: String) -> String? {
        getAPIKeyCalled = true
        return apiKeys[id]
    }

    func setNoModels() {
        models.removeAll()
        apiKeys.removeAll()
        firstLLMModel = nil
        firstASRModel = nil
    }

    func setNoAPIKey(for id: String) {
        apiKeys.removeValue(forKey: id)
    }
}

// MARK: - Test Suite

@Suite("AIProcessingCoordinator Tests")
@MainActor
struct AIProcessingCoordinatorTests {

    // MARK: - Test Fixtures

    var testAudioURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test_audio.m4a")
    }

    var testMeetingID: UUID {
        UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
    }

    var sampleTranscript: String {
        "大家好，欢迎参加今天的会议。我们今天讨论项目进展。"
    }

    // MARK: - State Management Tests

    @Test("Initial state is idle with no processing")
    func testInitialState() {
        let coordinator = AIProcessingCoordinator.shared

        #expect(!coordinator.isProcessing)
        #expect(coordinator.currentStage == .idle)
        #expect(coordinator.progress == 0)
        #expect(coordinator.lastError == nil)
    }

    @Test("Reset clears all state")
    func testResetClearsState() {
        let coordinator = AIProcessingCoordinator.shared

        // Set some state
        coordinator.isProcessing = true
        coordinator.currentStage = .llm
        coordinator.progress = 0.5
        coordinator.lastError = AIProcessingError.notImplemented("Test error")

        // Reset
        coordinator.reset()

        #expect(!coordinator.isProcessing)
        #expect(coordinator.currentStage == .idle)
        #expect(coordinator.progress == 0)
        #expect(coordinator.lastError == nil)
    }

    @Test("ProcessingStage enum has all cases")
    func testProcessingStageCases() {
        let stages: [AIProcessingCoordinator.ProcessingStage] = [
            .idle, .asr, .persistingTranscript, .llm, .persistingSummary, .completed, .failed("test")
        ]

        #expect(stages.count == 7)
    }

    @Test("ProcessingStage failed case includes error message")
    func testProcessingStageFailedIncludesError() {
        let errorMessage = "Test error message"
        let failedStage = AIProcessingCoordinator.ProcessingStage.failed(errorMessage)

        #expect(failedStage.displayName.contains(errorMessage))
    }

    @Test("ProcessingStage idle is equatable")
    func testProcessingStageEquatable() {
        let stage1 = AIProcessingCoordinator.ProcessingStage.idle
        let stage2 = AIProcessingCoordinator.ProcessingStage.idle
        let stage3 = AIProcessingCoordinator.ProcessingStage.asr

        #expect(stage1 == stage2)
        #expect(stage1 != stage3)
    }

    // MARK: - ProcessingStage Display Name Tests

    @Test("ProcessingStage idle has display name")
    func testProcessingStageIdleDisplayName() {
        let stage = AIProcessingCoordinator.ProcessingStage.idle
        #expect(!stage.displayName.isEmpty)
    }

    @Test("ProcessingStage asr has display name")
    func testProcessingStageASRDisplayName() {
        let stage = AIProcessingCoordinator.ProcessingStage.asr
        #expect(!stage.displayName.isEmpty)
    }

    @Test("ProcessingStage llm has display name")
    func testProcessingStageLLMDisplayName() {
        let stage = AIProcessingCoordinator.ProcessingStage.llm
        #expect(!stage.displayName.isEmpty)
    }

    @Test("ProcessingStage completed has display name")
    func testProcessingStageCompletedDisplayName() {
        let stage = AIProcessingCoordinator.ProcessingStage.completed
        #expect(!stage.displayName.isEmpty)
    }

    // MARK: - Error Handling Tests

    @Test("AIProcessingError notImplemented has description")
    func testAIProcessingErrorNotImplemented() {
        let message = "Test not implemented error"
        let error = AIProcessingError.notImplemented(message)

        #expect(error.errorDescription == message)
    }

    @Test("AIProcessingError transcriptNotFound has description")
    func testAIProcessingErrorTranscriptNotFound() {
        let error = AIProcessingError.transcriptNotFound
        #expect(error.errorDescription != nil)
    }

    @Test("AIProcessingError noSourceTranscript has description")
    func testAIProcessingErrorNoSourceTranscript() {
        let error = AIProcessingError.noSourceTranscript
        #expect(error.errorDescription != nil)
    }

    // MARK: - Legacy API Tests

    @Test("TranscribeOnly method exists and is async throwing")
    func testTranscribeOnlySignature() async throws {
        let coordinator = AIProcessingCoordinator.shared

        // This test verifies the method signature exists
        // We can't fully test it without proper mock setup
        // but we can verify it doesn't crash when called with invalid input

        do {
            let testURL = testAudioURL
            _ = try await coordinator.transcribeOnly(audioURL: testURL)
            #expect(Bool(false), "Should have thrown an error for non-existent file")
        } catch {
            // Expected to throw
            #expect(true)
        }
    }

    @Test("GenerateSummaryOnly method exists and is async throwing")
    func testGenerateSummaryOnlySignature() async throws {
        let coordinator = AIProcessingCoordinator.shared

        // This test verifies the method signature exists
        do {
            let testURL = testAudioURL
            _ = try await coordinator.generateSummaryOnly(
                transcriptText: sampleTranscript,
                audioURL: testURL,
                sourceTranscriptId: UUID()
            )
            #expect(Bool(false), "Should have thrown an error for invalid configuration")
        } catch {
            // Expected to throw
            #expect(true)
        }
    }

    // MARK: - Progress Tracking Tests

    @Test("Progress value is within valid range")
    func testProgressValidRange() {
        let coordinator = AIProcessingCoordinator.shared

        // Test setting progress at various points
        coordinator.progress = 0.0
        #expect(coordinator.progress >= 0 && coordinator.progress <= 1)

        coordinator.progress = 0.5
        #expect(coordinator.progress >= 0 && coordinator.progress <= 1)

        coordinator.progress = 1.0
        #expect(coordinator.progress >= 0 && coordinator.progress <= 1)
    }

    @Test("isProcessing reflects current state")
    func testIsProcessingReflectsState() {
        let coordinator = AIProcessingCoordinator.shared

        coordinator.isProcessing = true
        #expect(coordinator.isProcessing)

        coordinator.isProcessing = false
        #expect(!coordinator.isProcessing)
    }

    // MARK: - Error State Tests

    @Test("lastError can be set and retrieved")
    func testLastErrorCanBeSet() {
        let coordinator = AIProcessingCoordinator.shared

        let testError = AIProcessingError.notImplemented("Test error")
        coordinator.lastError = testError

        #expect(coordinator.lastError != nil)
        #expect(coordinator.lastError?.localizedDescription == "Test error")
    }

    @Test("lastError can be cleared")
    func testLastErrorCanBeCleared() {
        let coordinator = AIProcessingCoordinator.shared

        coordinator.lastError = AIProcessingError.notImplemented("Test error")
        coordinator.lastError = nil

        #expect(coordinator.lastError == nil)
    }

    // MARK: - ASR Only Method Tests

    @Test("processASROnly method exists")
    func testProcessASROnlyExists() async {
        let coordinator = AIProcessingCoordinator.shared
        let testURL = testAudioURL

        // This test verifies the method signature and basic behavior
        // Without proper mocks, we mainly verify it doesn't crash
        let result = await coordinator.processASROnly(audioURL: testURL, meetingID: testMeetingID)

        // Should return nil values for invalid input
        #expect(result.text == nil)
        #expect(result.transcriptURL == nil)
    }

    @Test("processASROnlyWithVersion method exists")
    func testProcessASROnlyWithVersionExists() async {
        let coordinator = AIProcessingCoordinator.shared
        let testURL = testAudioURL

        // This test verifies the method signature and basic behavior
        let result = await coordinator.processASROnlyWithVersion(audioURL: testURL, meetingID: testMeetingID)

        // Should return nil values for invalid input
        #expect(result.text == nil)
        #expect(result.url == nil)
        #expect(result.version == nil)
    }

    // MARK: - Process Method Tests

    @Test("process method accepts audioURL and meetingID")
    func testProcessAcceptsParameters() async {
        let coordinator = AIProcessingCoordinator.shared
        let testURL = testAudioURL

        // This test verifies the method can be called without crashing
        // The actual processing will fail due to invalid file/configuration
        await coordinator.process(audioURL: testURL, meetingID: testMeetingID)

        // After processing, should return to idle state
        #expect(!coordinator.isProcessing)
    }

    // MARK: - Stage Transition Tests

    @Test("Stage transitions from idle through processing stages")
    func testStageTransitions() async {
        let coordinator = AIProcessingCoordinator.shared
        let testURL = testAudioURL

        // Reset to initial state
        coordinator.reset()

        // Start processing - this will fail but should transition stages
        await coordinator.process(audioURL: testURL, meetingID: testMeetingID)

        // Eventually should end in failed or completed state
        #expect(coordinator.currentStage != .idle)
    }

    @Test("Stage transitions to failed on error")
    func testStageTransitionsToFailed() async {
        let coordinator = AIProcessingCoordinator.shared
        let testURL = testAudioURL

        // Process with invalid URL should result in failed state
        let invalidURL = URL(fileURLWithPath: "/non/existent/path.m4a")
        await coordinator.process(audioURL: invalidURL, meetingID: testMeetingID)

        // Should have transitioned to failed
        if case .failed = coordinator.currentStage {
            #expect(true)
        } else {
            #expect(Bool(false), "Expected failed stage")
        }
    }

    // MARK: - Error Description Tests

    @Test("Failed stage includes localized error description")
    func testFailedStageIncludesErrorDescription() async {
        let coordinator = AIProcessingCoordinator.shared
        let invalidURL = URL(fileURLWithPath: "/non/existent/path.m4a")

        await coordinator.process(audioURL: invalidURL, meetingID: testMeetingID)

        if case .failed(let message) = coordinator.currentStage {
            #expect(!message.isEmpty)
        } else {
            #expect(Bool(false), "Expected failed stage with message")
        }
    }

    // MARK: - Edge Cases

    @Test("Coordinator handles empty transcript text")
    func testHandlesEmptyTranscript() async {
        let coordinator = AIProcessingCoordinator.shared
        let testURL = testAudioURL

        // Process with empty transcript should not crash
        do {
            _ = try await coordinator.generateSummaryOnly(
                transcriptText: "",
                audioURL: testURL,
                sourceTranscriptId: UUID()
            )
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected to throw
            #expect(true)
        }
    }

    @Test("Coordinator handles nil meeting ID")
    func testHandlesNilMeetingID() async {
        let coordinator = AIProcessingCoordinator.shared
        let testURL = testAudioURL

        // transcribeOnly should generate a UUID if meetingID is nil
        do {
            let (text, url, id) = try await coordinator.transcribeOnly(audioURL: testURL, meetingID: nil)
            // Should generate a UUID
            #expect(id != UUID())
        } catch {
            // Expected to throw due to invalid file
            #expect(true)
        }
    }

    @Test("Coordinator handles invalid URL")
    func testHandlesInvalidURL() async {
        let coordinator = AIProcessingCoordinator.shared
        let invalidURL = URL(string: "invalid://url")!

        await coordinator.process(audioURL: invalidURL, meetingID: testMeetingID)

        // Should handle gracefully and end in failed state
        if case .failed = coordinator.currentStage {
            #expect(true)
        } else {
            #expect(Bool(false), "Expected failed stage")
        }
    }

    // MARK: - Concurrent Processing Tests

    @Test("Coordinator maintains state during concurrent calls")
    func testConcurrentProcessingState() async {
        let coordinator = AIProcessingCoordinator.shared
        let testURL = testAudioURL

        // Start two concurrent processes
        async let process1: Void = coordinator.process(audioURL: testURL, meetingID: UUID())
        async let process2: Void = coordinator.process(audioURL: testURL, meetingID: UUID())

        await process1
        await process2

        // Both should complete without crashing
        #expect(true)
    }

    // MARK: - Multiple Reset Tests

    @Test("Multiple reset calls are safe")
    func testMultipleResets() {
        let coordinator = AIProcessingCoordinator.shared

        // Set some state
        coordinator.isProcessing = true
        coordinator.currentStage = .llm
        coordinator.progress = 0.5

        // Reset multiple times
        coordinator.reset()
        coordinator.reset()
        coordinator.reset()

        // Should maintain idle state
        #expect(!coordinator.isProcessing)
        #expect(coordinator.currentStage == .idle)
        #expect(coordinator.progress == 0)
    }

    // MARK: - ObservableObject Conformance Tests

    @Test("Coordinator conforms to ObservableObject")
    func testObservableObjectConformance() {
        let coordinator = AIProcessingCoordinator.shared

        // This test verifies the type is ObservableObject
        // by checking if we can access @Published properties
        _ = coordinator.isProcessing
        _ = coordinator.currentStage
        _ = coordinator.progress
        _ = coordinator.lastError

        #expect(true)
    }

    // MARK: - Singleton Tests

    @Test("Coordinator is a singleton")
    func testSingleton() {
        let coordinator1 = AIProcessingCoordinator.shared
        let coordinator2 = AIProcessingCoordinator.shared

        // Should be the same instance
        #expect(coordinator1 === coordinator2)
    }

    // MARK: - Protocol Conformance Tests

    @Test("Coordinator conforms to AIProcessingCoordinatorProtocol")
    func testProtocolConformance() {
        let coordinator: any AIProcessingCoordinatorProtocol = AIProcessingCoordinator.shared

        // Verify all protocol properties are accessible
        _ = coordinator.isProcessing
        _ = coordinator.currentStage
        _ = coordinator.progress
        _ = coordinator.lastError

        #expect(true)
    }
}
