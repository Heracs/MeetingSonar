import Foundation

struct AIProviderRuntimeFactory {
    func makeASRRuntime(config: AIProviderConfig) throws -> any ASRRuntime {
        guard config.enabledCapabilities.contains(.asr), let asr = config.asr else {
            throw AIProviderRuntimeError.missingCapability(.asr)
        }

        switch asr.transport {
        case .localCommand:
            return LocalWhisperCppASRRuntime(config: config)
        case .syncMultipart:
            return CloudASRRuntimeAdapter(config: config)
        case .dashScopeAsync, .jobPolling, .webSocketStreaming:
            throw AIProviderRuntimeError.unsupportedTransport(asr.transport.rawValue)
        }
    }

    func makeLLMRuntime(config: AIProviderConfig) throws -> any LLMRuntime {
        guard config.enabledCapabilities.contains(.llm), config.llm != nil else {
            throw AIProviderRuntimeError.missingCapability(.llm)
        }

        return CloudLLMRuntimeAdapter(config: config)
    }
}

extension AIProviderConfig {
    var onlineServiceProvider: OnlineServiceProvider? {
        switch providerKey {
        case "cloud.aliyun":
            return .aliyun
        case "cloud.zhipu":
            return .zhipu
        case "cloud.deepseek":
            return .deepseek
        case "cloud.kimi":
            return .kimi
        default:
            return nil
        }
    }
}
