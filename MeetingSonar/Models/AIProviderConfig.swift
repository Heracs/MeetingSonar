import Foundation

enum AIProviderCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case asr
    case llm
}

enum AIProviderKind: String, Codable, Sendable {
    case cloudAPI
    case localCommand
    case customEndpoint
}

enum ASRTransportKind: String, Codable, CaseIterable, Hashable, Sendable {
    case localCommand
    case syncMultipart
    case dashScopeAsync
    case jobPolling
    case webSocketStreaming
}

enum LLMTransportKind: String, Codable, CaseIterable, Hashable, Sendable {
    case openAICompatible
    case dashScopeNative
    case zhipuNative
}

struct ASRAudioInputPolicy: Codable, Equatable, Sendable {
    var acceptedFormats: Set<String>
    var requiresWAVConversion: Bool
    var maxChunkDurationSeconds: TimeInterval?
    var prefersSingleFile: Bool

    static let whisperCpp = ASRAudioInputPolicy(
        acceptedFormats: ["wav"],
        requiresWAVConversion: true,
        maxChunkDurationSeconds: nil,
        prefersSingleFile: true
    )

    static let zhipuMultipart = ASRAudioInputPolicy(
        acceptedFormats: ["wav"],
        requiresWAVConversion: true,
        maxChunkDurationSeconds: 28,
        prefersSingleFile: false
    )
}

struct LocalCommandConfig: Codable, Equatable, Sendable {
    var executablePath: String
    var modelPath: String
    var extraArguments: [String]
    var timeoutSeconds: Int
}

struct ASRProviderConfig: Codable, Equatable, Sendable {
    var modelName: String
    var transport: ASRTransportKind
    var language: String?
    var prompt: String?
    var hotwords: [String]
    var endpoint: URL?
    var localCommand: LocalCommandConfig?
    var audioInputPolicy: ASRAudioInputPolicy
}

struct LLMProviderConfig: Codable, Equatable, Sendable {
    var modelName: String
    var transport: LLMTransportKind
    var endpoint: URL?
    var temperature: Double?
    var maxTokens: Int?
    var supportsStreaming: Bool
}

struct AIProviderConfig: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var providerKey: String
    var kind: AIProviderKind
    var enabledCapabilities: Set<AIProviderCapability>
    var asr: ASRProviderConfig?
    var llm: LLMProviderConfig?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var isVerified: Bool

    mutating func touch(now: Date = Date()) {
        updatedAt = now
        revision += 1
    }

    static func localWhisperCpp(
        id: UUID = UUID(),
        displayName: String,
        executablePath: String,
        modelPath: String,
        now: Date = Date()
    ) -> AIProviderConfig {
        AIProviderConfig(
            id: id,
            displayName: displayName,
            providerKey: "local.whispercpp",
            kind: .localCommand,
            enabledCapabilities: [.asr],
            asr: ASRProviderConfig(
                modelName: URL(fileURLWithPath: modelPath).lastPathComponent,
                transport: .localCommand,
                language: nil,
                prompt: nil,
                hotwords: [],
                endpoint: nil,
                localCommand: LocalCommandConfig(
                    executablePath: executablePath,
                    modelPath: modelPath,
                    extraArguments: [],
                    timeoutSeconds: 1800
                ),
                audioInputPolicy: .whisperCpp
            ),
            llm: nil,
            createdAt: now,
            updatedAt: now,
            revision: 1,
            isVerified: false
        )
    }
}
