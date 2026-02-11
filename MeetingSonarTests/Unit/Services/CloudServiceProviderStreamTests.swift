//
//  CloudServiceProviderStreamTests.swift
//  MeetingSonarTests
//
//  Swift Testing framework tests for CloudServiceProvider streaming functionality
//  Tests: SSE parsing, stream handling, error handling, cancellation
//

import Testing
import Foundation
@testable import MeetingSonar

/// Tests for CloudServiceProvider streaming using MockCloudServiceProvider
@Suite("CloudServiceProvider Stream Tests")
@MainActor
struct CloudServiceProviderStreamTests {

    // MARK: - Stream Tests

    @Test("Stream yields all chunks in order")
    func testStreamYieldsAllChunks() async throws {
        let mockProvider = MockCloudServiceProvider()
        let expectedChunks = ["Hello", " ", "World", "!"]
        mockProvider.configureForStreaming(chunks: expectedChunks, delay: 0.01)

        let messages = [
            ChatMessage(role: .system, content: "You are a helpful assistant"),
            ChatMessage(role: .user, content: "Say hello")
        ]

        let stream = try await mockProvider.generateChatCompletionStream(
            messages: messages,
            model: "test-model",
            temperature: 0.7,
            maxTokens: 100
        )

        var receivedChunks: [String] = []
        for await chunk in stream {
            receivedChunks.append(chunk)
        }

        #expect(receivedChunks == expectedChunks)
        #expect(mockProvider.generateChatCompletionStreamCalled)
    }

    @Test("Stream handles empty chunks")
    func testStreamHandlesEmptyChunks() async throws {
        let mockProvider = MockCloudServiceProvider()
        mockProvider.configureForStreaming(chunks: [], delay: 0)

        let messages = [ChatMessage(role: .user, content: "Test")]

        let stream = try await mockProvider.generateChatCompletionStream(
            messages: messages,
            model: "test-model",
            temperature: nil,
            maxTokens: nil
        )

        var receivedChunks: [String] = []
        for await chunk in stream {
            receivedChunks.append(chunk)
        }

        #expect(receivedChunks.isEmpty)
    }

    @Test("Stream handles single chunk")
    func testStreamHandlesSingleChunk() async throws {
        let mockProvider = MockCloudServiceProvider()
        mockProvider.configureForStreaming(chunks: ["Complete response"], delay: 0.01)

        let messages = [ChatMessage(role: .user, content: "Test")]

        let stream = try await mockProvider.generateChatCompletionStream(
            messages: messages,
            model: "test-model",
            temperature: nil,
            maxTokens: nil
        )

        var receivedChunks: [String] = []
        for await chunk in stream {
            receivedChunks.append(chunk)
        }

        #expect(receivedChunks.count == 1)
        #expect(receivedChunks.first == "Complete response")
    }

    @Test("Stream throws error when configured")
    func testStreamThrowsError() async {
        let mockProvider = MockCloudServiceProvider()
        mockProvider.configureForError(CloudServiceError.apiError("Test API error"))

        let messages = [ChatMessage(role: .user, content: "Test")]

        do {
            _ = try await mockProvider.generateChatCompletionStream(
                messages: messages,
                model: "test-model",
                temperature: nil,
                maxTokens: nil
            )
            Issue.record("Expected error to be thrown")
        } catch is CloudServiceError {
            // Expected
        } catch {
            Issue.record("Expected CloudServiceError, got \(type(of: error))")
        }
    }

    @Test("Stream handles cancellation gracefully")
    func testStreamHandlesCancellation() async throws {
        let mockProvider = MockCloudServiceProvider()
        mockProvider.configureForStreaming(
            chunks: Array(repeating: "word ", count: 100),
            delay: 0.1
        )

        let messages = [ChatMessage(role: .user, content: "Generate long text")]

        let stream = try await mockProvider.generateChatCompletionStream(
            messages: messages,
            model: "test-model",
            temperature: nil,
            maxTokens: nil
        )

        // Collect chunks with early termination
        var receivedChunks: [String] = []
        var chunkCount = 0

        for await chunk in stream {
            receivedChunks.append(chunk)
            chunkCount += 1
            if chunkCount >= 5 {
                break // Early exit simulates cancellation
            }
        }

        #expect(receivedChunks.count == 5)
    }

    // MARK: - Error Handling Tests

    @Test("Authentication error is properly thrown")
    func testAuthenticationError() async {
        let mockProvider = MockCloudServiceProvider.authenticationFailed()

        let messages = [ChatMessage(role: .user, content: "Test")]

        do {
            _ = try await mockProvider.generateChatCompletionStream(
                messages: messages,
                model: "test-model",
                temperature: nil,
                maxTokens: nil
            )
            Issue.record("Expected authentication error to be thrown")
        } catch let error as CloudServiceError {
            if case .authenticationFailed = error {
                // Expected
            } else {
                Issue.record("Expected authenticationFailed error, got \(error)")
            }
        } catch {
            Issue.record("Expected CloudServiceError, got \(type(of: error))")
        }
    }

    @Test("Rate limit error includes retry after")
    func testRateLimitError() async {
        let mockProvider = MockCloudServiceProvider.rateLimited(retryAfter: 120)

        let messages = [ChatMessage(role: .user, content: "Test")]

        do {
            _ = try await mockProvider.generateChatCompletionStream(
                messages: messages,
                model: "test-model",
                temperature: nil,
                maxTokens: nil
            )
            Issue.record("Expected rate limit error to be thrown")
        } catch let error as CloudServiceError {
            if case .rateLimited(let retryAfter) = error {
                #expect(retryAfter == 120)
            } else {
                Issue.record("Expected rate limited error, got \(error)")
            }
        } catch {
            Issue.record("Expected CloudServiceError, got \(type(of: error))")
        }
    }

    @Test("Network error wraps underlying error")
    func testNetworkError() async {
        let underlyingError = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: nil)
        let mockProvider = MockCloudServiceProvider.withError(
            CloudServiceError.networkError(underlyingError)
        )

        let messages = [ChatMessage(role: .user, content: "Test")]

        do {
            _ = try await mockProvider.generateChatCompletionStream(
                messages: messages,
                model: "test-model",
                temperature: nil,
                maxTokens: nil
            )
            Issue.record("Expected network error to be thrown")
        } catch let error as CloudServiceError {
            if case .networkError(let wrappedError) = error {
                let nsError = wrappedError as NSError
                #expect(nsError.code == -1009)
            } else {
                Issue.record("Expected network error, got \(error)")
            }
        } catch {
            Issue.record("Expected CloudServiceError, got \(type(of: error))")
        }
    }

    // MARK: - Parameter Tests

    @Test("Stream passes correct parameters")
    func testStreamPassesCorrectParameters() async throws {
        let mockProvider = MockCloudServiceProvider()
        mockProvider.configureForStreaming(chunks: ["Response"], delay: 0.01)

        let messages = [
            ChatMessage(role: .system, content: "System prompt"),
            ChatMessage(role: .user, content: "User message")
        ]

        _ = try await mockProvider.generateChatCompletionStream(
            messages: messages,
            model: "gpt-4",
            temperature: 0.5,
            maxTokens: 500
        )

        #expect(mockProvider.generateChatCompletionStreamCalled)
        #expect(mockProvider.lastChatModel == "gpt-4")
        #expect(mockProvider.lastMessages?.count == 2)
        #expect(mockProvider.lastMessages?.first?.role == .system)
        #expect(mockProvider.lastMessages?.first?.content == "System prompt")
    }

    @Test("Stream handles nil parameters")
    func testStreamHandlesNilParameters() async throws {
        let mockProvider = MockCloudServiceProvider()
        mockProvider.configureForStreaming(chunks: ["Response"], delay: 0.01)

        let messages = [ChatMessage(role: .user, content: "Test")]

        _ = try await mockProvider.generateChatCompletionStream(
            messages: messages,
            model: "test-model",
            temperature: nil,
            maxTokens: nil
        )

        #expect(mockProvider.generateChatCompletionStreamCalled)
    }

    // MARK: - Timeout and Delay Tests

    @Test("Stream respects configured delays")
    func testStreamRespectsDelays() async throws {
        let mockProvider = MockCloudServiceProvider()
        mockProvider.configureForStreaming(chunks: ["1", "2", "3"], delay: 0.05)

        let messages = [ChatMessage(role: .user, content: "Test")]

        let startTime = Date()
        let stream = try await mockProvider.generateChatCompletionStream(
            messages: messages,
            model: "test-model",
            temperature: nil,
            maxTokens: nil
        )

        var chunkCount = 0
        for await _ in stream {
            chunkCount += 1
        }

        let elapsed = Date().timeIntervalSince(startTime)

        #expect(chunkCount == 3)
        // Should take at least (3-1) * 0.05 = 0.1 seconds
        #expect(elapsed >= 0.08)
    }

    // MARK: - Non-streaming Method Tests

    @Test("Generate completion returns expected result")
    func testGenerateCompletion() async throws {
        let mockProvider = MockCloudServiceProvider()

        let messages = [ChatMessage(role: .user, content: "Test")]

        let result = try await mockProvider.generateChatCompletion(
            messages: messages,
            model: "test-model",
            temperature: 0.7,
            maxTokens: 100
        )

        #expect(mockProvider.generateChatCompletionCalled)
        #expect(result.text == "Mock LLM response")
        #expect(result.model == "test-model")
        #expect(result.inputTokens == 100)
        #expect(result.outputTokens == 50)
    }

    @Test("Transcribe returns expected result")
    func testTranscribe() async throws {
        let mockProvider = MockCloudServiceProvider()
        let audioData = Data("test audio".utf8)

        let result = try await mockProvider.transcribe(
            audioData: audioData,
            model: "whisper-1",
            prompt: "Test prompt"
        )

        #expect(mockProvider.transcribeCalled)
        #expect(mockProvider.lastTranscribeModel == "whisper-1")
        #expect(result.text == "Mock transcription result")
        #expect(result.language == "zh")
        #expect(result.segments.count == 2)
    }

    @Test("Verify API key returns correct result")
    func testVerifyAPIKey() async throws {
        let validProvider = MockCloudServiceProvider(apiKey: "valid-key")
        let isValid = try await validProvider.verifyAPIKey()
        #expect(isValid)
        #expect(validProvider.verifyAPIKeyCalled)

        let invalidProvider = MockCloudServiceProvider(apiKey: "")
        let isInvalid = try await invalidProvider.verifyAPIKey()
        #expect(!isInvalid)
    }

    // MARK: - Reset Tests

    @Test("Reset clears all state")
    func testResetClearsState() async throws {
        let mockProvider = MockCloudServiceProvider()
        mockProvider.configureForStreaming(chunks: ["test"], delay: 0.01)

        let messages = [ChatMessage(role: .user, content: "Test")]

        // Make a call
        _ = try await mockProvider.generateChatCompletionStream(
            messages: messages,
            model: "test-model",
            temperature: nil,
            maxTokens: nil
        )

        #expect(mockProvider.generateChatCompletionStreamCalled)

        // Reset
        mockProvider.reset()

        #expect(!mockProvider.generateChatCompletionStreamCalled)
        #expect(!mockProvider.transcribeCalled)
        #expect(!mockProvider.verifyAPIKeyCalled)
        #expect(mockProvider.lastMessages == nil)
    }

    // MARK: - Concurrent Access Tests

    @Test("Multiple concurrent stream requests are handled safely")
    func testConcurrentStreamRequests() async throws {
        let mockProvider = MockCloudServiceProvider()
        mockProvider.configureForStreaming(chunks: ["A"], delay: 0.01)

        let messages = [ChatMessage(role: .user, content: "Test")]

        // Launch multiple concurrent requests
        async let stream1 = mockProvider.generateChatCompletionStream(
            messages: messages,
            model: "model-1",
            temperature: nil,
            maxTokens: nil
        )

        async let stream2 = mockProvider.generateChatCompletionStream(
            messages: messages,
            model: "model-2",
            temperature: nil,
            maxTokens: nil
        )

        async let stream3 = mockProvider.generateChatCompletionStream(
            messages: messages,
            model: "model-3",
            temperature: nil,
            maxTokens: nil
        )

        // Collect results
        let (s1, s2, s3) = try await (stream1, stream2, stream3)

        var results: [String] = []
        for await chunk in s1 { results.append(chunk) }
        for await chunk in s2 { results.append(chunk) }
        for await chunk in s3 { results.append(chunk) }

        #expect(results.count == 3)
    }
}
