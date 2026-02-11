//
//  MockCloudServiceProvider.swift
//  MeetingSonar
//
//  Mock implementation of CloudServiceProvider for testing streaming functionality
//

import Foundation

/// Mock cloud service provider for testing streaming and API interactions
final class MockCloudServiceProvider: CloudServiceProvider, @unchecked Sendable {

    // MARK: - Properties

    let provider: OnlineServiceProvider
    let apiKey: String
    let baseURL: String

    // MARK: - Mock Configuration

    /// Chunks to return in the stream
    var mockStreamChunks: [String] = []

    /// Delay between chunks (in seconds)
    var mockStreamDelay: TimeInterval = 0.1

    /// Whether to throw an error
    var shouldThrowError: Bool = false

    /// Error to throw when shouldThrowError is true
    var mockError: Error = CloudServiceError.unknown

    /// Whether to simulate network delay
    var simulateNetworkDelay: Bool = false

    /// Network delay duration
    var networkDelay: TimeInterval = 0.5

    /// Track method calls
    private(set) var transcribeCalled = false
    private(set) var transcribeStreamCalled = false
    private(set) var generateChatCompletionCalled = false
    private(set) var generateChatCompletionStreamCalled = false
    private(set) var verifyAPIKeyCalled = false

    /// Last call parameters (for verification)
    private(set) var lastTranscribeModel: String?
    private(set) var lastChatModel: String?
    private(set) var lastMessages: [ChatMessage]?

    // MARK: - Initialization

    init(
        provider: OnlineServiceProvider = .deepseek,
        apiKey: String = "test-api-key",
        baseURL: String = "https://api.test.com/v1"
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    // MARK: - CloudServiceProvider Protocol

    func transcribe(
        audioData: Data,
        model: String,
        prompt: String?
    ) async throws -> CloudTranscriptionResult {
        transcribeCalled = true
        lastTranscribeModel = model

        if shouldThrowError {
            throw mockError
        }

        return CloudTranscriptionResult(
            text: "Mock transcription result",
            segments: [
                TranscriptSegment(start: 0.0, end: 2.0, text: "Mock segment 1"),
                TranscriptSegment(start: 2.0, end: 4.0, text: "Mock segment 2")
            ],
            language: "zh",
            processingTime: 1.0,
            audioDuration: 4.0,
            usage: TokenUsage(promptTokens: 100, completionTokens: 50)
        )
    }

    func transcribeStream(
        audioData: Data,
        model: String,
        prompt: String?,
        onProgress: (Double) -> Void
    ) async throws -> CloudTranscriptionResult {
        transcribeStreamCalled = true
        lastTranscribeModel = model

        if shouldThrowError {
            throw mockError
        }

        // Simulate progress
        for i in 1...5 {
            try await Task.sleep(nanoseconds: 100_000_000)
            onProgress(Double(i) * 0.2)
        }

        return CloudTranscriptionResult(
            text: "Mock streaming transcription result",
            segments: [
                TranscriptSegment(start: 0.0, end: 2.0, text: "Mock streaming segment")
            ],
            language: "zh",
            processingTime: 2.0,
            audioDuration: 10.0,
            usage: TokenUsage(promptTokens: 200, completionTokens: 100)
        )
    }

    func generateChatCompletion(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> CloudLLMResult {
        generateChatCompletionCalled = true
        lastChatModel = model
        lastMessages = messages

        if shouldThrowError {
            throw mockError
        }

        if simulateNetworkDelay {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }

        return CloudLLMResult(
            text: "Mock LLM response",
            inputTokens: 100,
            outputTokens: 50,
            processingTime: 0.5,
            model: model
        )
    }

    func generateChatCompletionStream(
        messages: [ChatMessage],
        model: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> AsyncStream<String> {
        generateChatCompletionStreamCalled = true
        lastChatModel = model
        lastMessages = messages

        if shouldThrowError {
            throw mockError
        }

        if simulateNetworkDelay {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }

        return AsyncStream { continuation in
            Task {
                for (index, chunk) in self.mockStreamChunks.enumerated() {
                    // Check for cancellation
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }

                    continuation.yield(chunk)

                    // Delay between chunks (except for the last one)
                    if index < self.mockStreamChunks.count - 1 {
                        try? await Task.sleep(
                            nanoseconds: UInt64(self.mockStreamDelay * 1_000_000_000)
                        )
                    }
                }
                continuation.finish()
            }
        }
    }

    func verifyAPIKey() async throws -> Bool {
        verifyAPIKeyCalled = true

        if shouldThrowError {
            throw mockError
        }

        return !apiKey.isEmpty && apiKey != "invalid"
    }

    // MARK: - Test Helpers

    /// Reset all tracking state
    func reset() {
        transcribeCalled = false
        transcribeStreamCalled = false
        generateChatCompletionCalled = false
        generateChatCompletionStreamCalled = false
        verifyAPIKeyCalled = false

        lastTranscribeModel = nil
        lastChatModel = nil
        lastMessages = nil

        shouldThrowError = false
        simulateNetworkDelay = false
    }

    /// Configure for successful streaming with given chunks
    func configureForStreaming(chunks: [String], delay: TimeInterval = 0.1) {
        self.mockStreamChunks = chunks
        self.mockStreamDelay = delay
        self.shouldThrowError = false
    }

    /// Configure for error
    func configureForError(_ error: Error) {
        self.shouldThrowError = true
        self.mockError = error
    }

    /// Configure for network delay simulation
    func configureWithNetworkDelay(_ delay: TimeInterval) {
        self.simulateNetworkDelay = true
        self.networkDelay = delay
    }
}

// MARK: - Convenience Extensions

extension MockCloudServiceProvider {
    /// Create a mock that simulates a successful streaming response
    static func successfulStreaming(chunks: [String] = ["Hello", " ", "World"]) -> MockCloudServiceProvider {
        let mock = MockCloudServiceProvider()
        mock.configureForStreaming(chunks: chunks)
        return mock
    }

    /// Create a mock that simulates an API error
    static func withError(_ error: CloudServiceError) -> MockCloudServiceProvider {
        let mock = MockCloudServiceProvider()
        mock.configureForError(error)
        return mock
    }

    /// Create a mock that simulates rate limiting
    static func rateLimited(retryAfter: TimeInterval? = 60) -> MockCloudServiceProvider {
        let mock = MockCloudServiceProvider()
        mock.configureForError(CloudServiceError.rateLimited(retryAfter: retryAfter))
        return mock
    }

    /// Create a mock that simulates authentication failure
    static func authenticationFailed() -> MockCloudServiceProvider {
        let mock = MockCloudServiceProvider()
        mock.configureForError(CloudServiceError.authenticationFailed)
        return mock
    }
}
