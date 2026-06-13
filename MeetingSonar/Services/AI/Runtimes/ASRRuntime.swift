import Foundation

struct ASRRuntimeContext: Sendable {
    let meetingID: UUID?
    let language: String
}

enum ASRProgressEvent: Sendable, Equatable {
    case preparingAudio
    case transcribing(progress: Double)
    case chunk(current: Int, total: Int)
}

struct AIProviderValidationResult: Sendable, Equatable {
    let isValid: Bool
    let message: String
}

enum AIProviderRuntimeError: LocalizedError, Equatable {
    case missingCapability(AIProviderCapability)
    case invalidConfiguration(String)
    case unsupportedTransport(String)
    case localCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCapability(let capability):
            return "Missing provider capability: \(capability.rawValue)"
        case .invalidConfiguration(let message):
            return message
        case .unsupportedTransport(let transport):
            return "Unsupported transport: \(transport)"
        case .localCommandFailed(let message):
            return message
        }
    }
}

protocol ASRRuntime: Sendable {
    var configID: UUID { get }
    var providerKey: String { get }
    var modelName: String { get }

    func validate() async throws -> AIProviderValidationResult
    func transcribe(
        audioURL: URL,
        context: ASRRuntimeContext,
        progress: (@Sendable (ASRProgressEvent) async -> Void)?
    ) async throws -> TranscriptionResult
}
