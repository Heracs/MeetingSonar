import Foundation

struct CloudASRRuntimeAdapter: ASRRuntime {
    let config: AIProviderConfig

    var configID: UUID { config.id }
    var providerKey: String { config.providerKey }
    var modelName: String { config.asr?.modelName ?? config.displayName }

    func validate() async throws -> AIProviderValidationResult {
        guard config.enabledCapabilities.contains(.asr), config.asr != nil else {
            throw AIProviderRuntimeError.missingCapability(.asr)
        }
        guard config.onlineServiceProvider != nil else {
            return AIProviderValidationResult(isValid: false, message: "Unsupported cloud provider: \(config.providerKey)")
        }
        guard let apiKey = await CloudAIModelManager.shared.getAPIKey(for: config.id), !apiKey.isEmpty else {
            return AIProviderValidationResult(isValid: false, message: "Missing API key")
        }

        return AIProviderValidationResult(isValid: true, message: "Cloud ASR configuration is valid")
    }

    func transcribe(
        audioURL: URL,
        context: ASRRuntimeContext,
        progress: (@Sendable (ASRProgressEvent) async -> Void)?
    ) async throws -> TranscriptionResult {
        guard let asr = config.asr else {
            throw AIProviderRuntimeError.missingCapability(.asr)
        }
        guard let providerType = config.onlineServiceProvider else {
            throw AIProviderRuntimeError.invalidConfiguration("Unsupported cloud provider: \(config.providerKey)")
        }
        guard let apiKey = await CloudAIModelManager.shared.getAPIKey(for: config.id), !apiKey.isEmpty else {
            throw AIProviderRuntimeError.invalidConfiguration("Missing API key")
        }

        await progress?(.transcribing(progress: 0))

        let audioData = try Data(contentsOf: audioURL)
        let provider = await CloudServiceFactory.shared.createProvider(
            providerType,
            apiKey: apiKey,
            baseURL: asr.endpoint?.absoluteString
        )
        let result = try await provider.transcribe(
            audioData: audioData,
            model: asr.modelName,
            prompt: asr.prompt,
            hotwords: asr.hotwords.isEmpty ? nil : asr.hotwords
        )

        await progress?(.transcribing(progress: 1))

        return TranscriptionResult(
            text: result.text,
            segments: result.segments.map {
                ASRTranscriptSegment(startTime: $0.start, endTime: $0.end, text: $0.text)
            },
            language: result.language ?? context.language,
            processingTime: result.processingTime
        )
    }
}
