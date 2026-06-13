import Foundation

extension TokenUsage: Sendable {}

struct LLMMessage: Sendable, Equatable {
    let role: String
    let content: String
}

struct LLMRuntimeContext: Sendable {
    let meetingID: UUID?
    let temperature: Double
    let maxTokens: Int
}

struct LLMCompletionResult: Sendable {
    let content: String
    let modelName: String
    let usage: TokenUsage?
}

enum LLMStreamEvent: Sendable {
    case delta(String)
    case completed(LLMCompletionResult)
}

protocol LLMRuntime: Sendable {
    var configID: UUID { get }
    var providerKey: String { get }
    var modelName: String { get }

    func validate() async throws -> AIProviderValidationResult
    func generateSummary(
        messages: [LLMMessage],
        context: LLMRuntimeContext
    ) async throws -> LLMCompletionResult
}
