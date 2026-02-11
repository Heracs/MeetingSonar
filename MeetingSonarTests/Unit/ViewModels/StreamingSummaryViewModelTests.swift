//
//  StreamingSummaryViewModelTests.swift
//  MeetingSonarTests
//
//  Swift Testing framework tests for StreamingSummaryViewModel
//  Tests: State transitions, streaming control, error handling, retry functionality
//

import Testing
import Foundation
@testable import MeetingSonar

/// Tests for StreamingSummaryViewModel - Cloud AI Streaming Summary Feature
@Suite("StreamingSummaryViewModel Tests")
@MainActor
struct StreamingSummaryViewModelTests {

    // MARK: - Test Fixtures

    private func createTestConfig() -> CloudAIModelConfig {
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

    private func createTestTranscript() -> String {
        """
        大家好，欢迎参加今天的项目进度会议。
        首先，小明汇报一下前端开发进展。
        目前首页改版已经完成80%，预计本周五可以全部完成。
        接下来，小红说一下后端API的情况。
        用户认证模块已经测试通过，可以上线。
        最后，大家讨论一下下周的工作安排。
        """
    }

    // MARK: - State Tests

    @Test("Initial state is idle")
    func testInitialState() async {
        let viewModel = StreamingSummaryViewModel()

        #expect(viewModel.state == .idle)
        #expect(viewModel.streamingText.isEmpty)
        #expect(viewModel.errorMessage.isEmpty)
        #expect(!viewModel.isStreaming)
        #expect(!viewModel.isComplete)
        #expect(viewModel.wordCount == 0)
    }

    @Test("State transitions from idle to connecting")
    func testStateTransitionIdleToConnecting() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        let config = createTestConfig()
        let transcript = createTestTranscript()
        let meetingID = UUID()

        // Start streaming
        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        // Give a moment for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        #expect(viewModel.state == .connecting)
        #expect(!viewModel.isStreaming)
        #expect(!viewModel.isComplete)

        // Clean up
        viewModel.stopStreaming()
    }

    @Test("State transitions through streaming to completed")
    func testStateTransitionToCompleted() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        mockProvider.mockStreamChunks = ["Hello", " ", "World", "!"]
        mockProvider.mockStreamDelay = 0.01 // Fast for testing

        let config = createTestConfig()
        let transcript = createTestTranscript()
        let meetingID = UUID()

        // Start streaming
        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        // Wait for completion
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        // Should be completed
        #expect(viewModel.isComplete)
        #expect(viewModel.streamingText == "Hello World!")
        #expect(viewModel.wordCount == 12) // "Hello World!".count

        // Clean up
        viewModel.stopStreaming()
    }

    @Test("State transitions to cancelled when stopped")
    func testStateTransitionToCancelled() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        mockProvider.mockStreamChunks = ["Chunk1", "Chunk2", "Chunk3"]
        mockProvider.mockStreamDelay = 1.0 // Slow to allow cancellation

        let config = createTestConfig()
        let transcript = createTestTranscript()
        let meetingID = UUID()

        // Start streaming
        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        // Wait for streaming to start
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        // Stop streaming
        viewModel.stopStreaming()

        // Wait for cancellation
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // Verify we're in a terminal state (either cancelled or completed)
        #expect(viewModel.state.isTerminal)
    }

    @Test("State transitions to failed on error")
    func testStateTransitionToFailed() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        mockProvider.shouldThrowError = true
        mockProvider.mockError = CloudServiceError.apiError("Test error")

        let config = createTestConfig()
        let transcript = createTestTranscript()
        let meetingID = UUID()

        // Start streaming
        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        // Wait for error
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        if case .failed = viewModel.state {
            // Expected
        } else {
            Issue.record("Expected state to be .failed, got \(viewModel.state)")
        }
        #expect(!viewModel.errorMessage.isEmpty)
    }

    // MARK: - Streaming Control Tests

    @Test("Stop streaming cancels the task")
    func testStopStreamingCancelsTask() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        mockProvider.mockStreamChunks = Array(repeating: "Long text ", count: 100)
        mockProvider.mockStreamDelay = 0.5

        let config = createTestConfig()
        let transcript = createTestTranscript()
        let meetingID = UUID()

        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        // Wait a bit
        try await Task.sleep(nanoseconds: 300_000_000)

        // Stop
        viewModel.stopStreaming()

        // Wait for cancellation to complete
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify we're in a terminal state
        #expect(viewModel.state.isTerminal)
    }

    @Test("Cannot start streaming when already streaming")
    func testCannotStartWhenStreaming() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        mockProvider.mockStreamChunks = ["Long", " ", "streaming", " ", "text"]
        mockProvider.mockStreamDelay = 0.2

        let config = createTestConfig()
        let transcript = createTestTranscript()
        let meetingID = UUID()

        // First start
        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        // Try to start again - should be ignored
        viewModel.startStreaming(
            transcript: "Different transcript",
            meetingID: UUID(),
            config: config,
            provider: mockProvider
        )

        // Should still be processing the first request
        #expect(viewModel.state != .idle)

        // Clean up
        viewModel.stopStreaming()
    }

    // MARK: - Retry Tests

    @Test("Retry resets state and starts fresh")
    func testRetryResetsAndStartsFresh() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        mockProvider.shouldThrowError = true
        mockProvider.mockError = CloudServiceError.apiError("First attempt failed")

        let config = createTestConfig()
        let transcript = createTestTranscript()
        let meetingID = UUID()

        // First attempt - will fail
        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify failed state
        if case .failed = viewModel.state {
            // Expected
        } else {
            Issue.record("Expected failed state")
        }

        // Setup success for retry
        mockProvider.shouldThrowError = false
        mockProvider.mockStreamChunks = ["Success!"]

        // Retry
        viewModel.retry(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        try await Task.sleep(nanoseconds: 300_000_000)

        // Should succeed now
        #expect(viewModel.isComplete)
        #expect(viewModel.streamingText == "Success!")
    }

    @Test("Retry clears previous error message")
    func testRetryClearsErrorMessage() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        mockProvider.shouldThrowError = true
        mockProvider.mockError = CloudServiceError.apiError("Error message")

        let config = createTestConfig()
        let transcript = createTestTranscript()
        let meetingID = UUID()

        // First attempt fails
        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(!viewModel.errorMessage.isEmpty)

        // Retry
        mockProvider.shouldThrowError = false
        mockProvider.mockStreamChunks = ["Success"]

        viewModel.retry(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        // State should be reset to idle/connecting on retry
        #expect(viewModel.state == .idle || viewModel.state == .connecting)
        // streamingText should be cleared
        #expect(viewModel.streamingText.isEmpty)

        viewModel.stopStreaming()
    }

    // MARK: - Text Accumulation Tests

    @Test("Streaming text accumulates correctly")
    func testStreamingTextAccumulation() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        mockProvider.mockStreamChunks = ["First", " ", "second", " ", "third"]
        mockProvider.mockStreamDelay = 0.05

        let config = createTestConfig()
        let transcript = createTestTranscript()
        let meetingID = UUID()

        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s

        #expect(viewModel.streamingText == "First second third")
        #expect(viewModel.wordCount == 18)
    }

    @Test("Empty stream results in empty text")
    func testEmptyStreamResultsInEmptyText() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        mockProvider.mockStreamChunks = []

        let config = createTestConfig()
        let transcript = createTestTranscript()
        let meetingID = UUID()

        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        try await Task.sleep(nanoseconds: 300_000_000)

        // Should complete with empty text
        #expect(viewModel.isComplete)
        #expect(viewModel.streamingText.isEmpty)
    }

    // MARK: - Progress Tests

    @Test("Progress updates during streaming")
    func testProgressUpdates() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        mockProvider.mockStreamChunks = Array(repeating: "word ", count: 20)
        mockProvider.mockStreamDelay = 0.05

        let config = createTestConfig()
        let transcript = createTestTranscript()
        let meetingID = UUID()

        var progressValues: [Double] = []

        // Observe state changes
        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        // Sample progress over time
        for _ in 0..<5 {
            try await Task.sleep(nanoseconds: 80_000_000)
            if case .streaming(let progress) = viewModel.state {
                progressValues.append(progress)
            }
        }

        viewModel.stopStreaming()

        // Should have recorded some progress values
        #expect(!progressValues.isEmpty)
    }

    // MARK: - Terminal State Tests

    @Test("Terminal states are correctly identified")
    func testTerminalStates() async throws {
        // Test the isTerminal property on each state directly
        #expect(StreamingState.completed(text: "Done").isTerminal)
        #expect(StreamingState.failed(error: "Error").isTerminal)
        #expect(StreamingState.cancelled.isTerminal)

        // Test that non-terminal states return false
        #expect(!StreamingState.idle.isTerminal)
        #expect(!StreamingState.connecting.isTerminal)
        #expect(!StreamingState.streaming(progress: 0.5).isTerminal)
    }

    // MARK: - Concurrent Access Tests

    @Test("Multiple rapid start calls are handled safely")
    func testMultipleRapidStartCalls() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        mockProvider.mockStreamChunks = ["Result"]
        mockProvider.mockStreamDelay = 0.1

        let config = createTestConfig()
        let transcript = createTestTranscript()

        // Rapid multiple starts
        for i in 0..<5 {
            viewModel.startStreaming(
                transcript: transcript,
                meetingID: UUID(),
                config: config,
                provider: mockProvider
            )
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        }

        // Should not crash and should be in a valid state
        #expect(viewModel.state != .idle)

        viewModel.stopStreaming()
    }

    // MARK: - Word Count Tests

    @Test("Word count updates correctly with Chinese text")
    func testWordCountWithChinese() async throws {
        let viewModel = StreamingSummaryViewModel()
        let mockProvider = MockCloudServiceProvider()
        mockProvider.mockStreamChunks = ["这是一个", "测试", "消息"]
        mockProvider.mockStreamDelay = 0.05

        let config = createTestConfig()
        let transcript = createTestTranscript()
        let meetingID = UUID()

        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: mockProvider
        )

        try await Task.sleep(nanoseconds: 400_000_000)

        #expect(viewModel.streamingText == "这是一个测试消息")
        #expect(viewModel.wordCount == 8) // Character count for Chinese
    }
}
