import Foundation

struct CloudLLMRuntimeAdapter: LLMRuntime {
    let config: AIProviderConfig

    var configID: UUID { config.id }
    var providerKey: String { config.providerKey }
    var modelName: String { config.llm?.modelName ?? config.displayName }

    func validate() async throws -> AIProviderValidationResult {
        guard config.enabledCapabilities.contains(.llm), config.llm != nil else {
            throw AIProviderRuntimeError.missingCapability(.llm)
        }
        guard config.onlineServiceProvider != nil else {
            return AIProviderValidationResult(isValid: false, message: "Unsupported cloud provider: \(config.providerKey)")
        }
        guard let apiKey = await CloudAIModelManager.shared.getAPIKey(for: config.id), !apiKey.isEmpty else {
            return AIProviderValidationResult(isValid: false, message: "Missing API key")
        }

        return AIProviderValidationResult(isValid: true, message: "Cloud LLM configuration is valid")
    }

    func generateSummary(
        messages: [LLMMessage],
        context: LLMRuntimeContext
    ) async throws -> LLMCompletionResult {
        guard let llm = config.llm else {
            throw AIProviderRuntimeError.missingCapability(.llm)
        }
        guard let providerType = config.onlineServiceProvider else {
            throw AIProviderRuntimeError.invalidConfiguration("Unsupported cloud provider: \(config.providerKey)")
        }
        guard let apiKey = await CloudAIModelManager.shared.getAPIKey(for: config.id), !apiKey.isEmpty else {
            throw AIProviderRuntimeError.invalidConfiguration("Missing API key")
        }

        let provider = await CloudServiceFactory.shared.createProvider(
            providerType,
            apiKey: apiKey,
            baseURL: llm.endpoint?.absoluteString
        )
        let chatMessages = messages.map { message in
            ChatMessage(
                role: ChatMessage.MessageRole(rawValue: message.role) ?? .user,
                content: message.content
            )
        }
        let result = try await provider.generateChatCompletion(
            messages: chatMessages,
            model: llm.modelName,
            temperature: llm.temperature ?? context.temperature,
            maxTokens: llm.maxTokens ?? context.maxTokens
        )

        return LLMCompletionResult(
            content: result.text,
            modelName: result.model,
            usage: result.usage
        )
    }
}
