//
//  OnlineModelConfig.swift
//  MeetingSonar
//
//  F-9.3: Online model configuration data structure
//

import Foundation

/// Configuration for an online AI model
struct OnlineModelConfig: Codable, Identifiable, Hashable {

    // MARK: - LLM Parameter Defaults

    /// Default LLM parameters
    enum LLMDefaults {
        /// Default temperature (controls randomness/creativity)
        /// 0.7 provides balanced creativity and coherence
        static let temperature: Double = 0.7
        /// Default maximum tokens for response
        /// 4096 tokens allows for comprehensive summaries
        static let maxTokens: Int = 4096
        /// Default top_p (nucleus sampling parameter)
        /// 0.95 focuses on the most likely 95% of tokens
        static let topP: Double = 0.95
    }

    /// Default ASR parameters
    enum ASRDefaults {
        /// Default temperature for ASR (should be 0 for consistent transcription)
        static let temperature: Double = 0.0
        /// Default maximum tokens for transcription
        /// 1000 tokens is sufficient for typical meeting segments
        static let maxTokens: Int = 1000
    }

    // MARK: - Core Properties

    /// Unique identifier
    let id: UUID

    /// Service provider
    var provider: OnlineServiceProvider

    /// Model name (e.g., "whisper-1", "glm-4.7")
    var modelName: String

    /// Base URL for API endpoint
    var baseURL: String

    /// Whether the configuration has been verified
    var isVerified: Bool

    // MARK: - Model Parameters (Optional)

    /// Temperature parameter (0.0-2.0)
    var temperature: Double?

    /// Max tokens for response
    var maxTokens: Int?

    /// Top P parameter (LLM only, 0.0-1.0)
    var topP: Double?
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        provider: OnlineServiceProvider,
        modelName: String,
        baseURL: String,
        isVerified: Bool = false,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil
    ) {
        self.id = id
        self.provider = provider
        self.modelName = modelName
        self.baseURL = baseURL
        self.isVerified = isVerified
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
    }
    
    // MARK: - Factory Methods
    
    /// Create a new configuration with default values for specified provider and type
    static func defaultConfig(provider: OnlineServiceProvider, type: OnlineModelType) -> OnlineModelConfig {
        return OnlineModelConfig(
            provider: provider,
            modelName: provider.defaultModel(for: type),
            baseURL: provider.defaultBaseURL,
            temperature: type == .llm ? LLMDefaults.temperature : ASRDefaults.temperature,
            maxTokens: type == .llm ? LLMDefaults.maxTokens : ASRDefaults.maxTokens,
            topP: type == .llm  ? LLMDefaults.topP : nil
        )
    }
}
