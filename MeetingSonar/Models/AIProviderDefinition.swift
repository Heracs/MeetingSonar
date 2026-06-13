import Foundation

struct AIProviderDefinition: Identifiable, Equatable, Sendable {
    var id: String { key }
    let key: String
    let displayName: String
    let kind: AIProviderKind
    let capabilities: Set<AIProviderCapability>
    let asrTransports: Set<ASRTransportKind>
    let llmTransports: Set<LLMTransportKind>
    let defaultBaseURL: URL?
    let isConfigurableInV013: Bool
}

struct AIProviderRegistry: Sendable {
    let definitions: [AIProviderDefinition]

    static let builtIn = AIProviderRegistry(definitions: [
        AIProviderDefinition(
            key: "local.whispercpp",
            displayName: "Whisper.cpp",
            kind: .localCommand,
            capabilities: [.asr],
            asrTransports: [.localCommand],
            llmTransports: [],
            defaultBaseURL: nil,
            isConfigurableInV013: true
        ),
        AIProviderDefinition(
            key: "cloud.zhipu",
            displayName: "Zhipu GLM",
            kind: .cloudAPI,
            capabilities: [.asr, .llm],
            asrTransports: [.syncMultipart],
            llmTransports: [.zhipuNative],
            defaultBaseURL: URL(string: OnlineServiceProvider.zhipu.defaultBaseURL),
            isConfigurableInV013: true
        ),
        AIProviderDefinition(
            key: "cloud.aliyun",
            displayName: "Aliyun Qwen",
            kind: .cloudAPI,
            capabilities: [.llm],
            asrTransports: [.dashScopeAsync, .syncMultipart],
            llmTransports: [.dashScopeNative, .openAICompatible],
            defaultBaseURL: URL(string: OnlineServiceProvider.aliyun.defaultBaseURL),
            isConfigurableInV013: true
        ),
        AIProviderDefinition(
            key: "cloud.deepseek",
            displayName: "DeepSeek",
            kind: .cloudAPI,
            capabilities: [.llm],
            asrTransports: [],
            llmTransports: [.openAICompatible],
            defaultBaseURL: URL(string: OnlineServiceProvider.deepseek.defaultBaseURL),
            isConfigurableInV013: true
        ),
        AIProviderDefinition(
            key: "cloud.kimi",
            displayName: "Kimi",
            kind: .cloudAPI,
            capabilities: [.llm],
            asrTransports: [],
            llmTransports: [.openAICompatible],
            defaultBaseURL: URL(string: OnlineServiceProvider.kimi.defaultBaseURL),
            isConfigurableInV013: true
        )
    ])

    func definition(for key: String) -> AIProviderDefinition? {
        definitions.first { $0.key == key }
    }
}
