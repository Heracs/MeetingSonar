//
//  ASRModelConfiguration.swift
//  MeetingSonar
//
//  ASR Model Configuration — Cloud-only architecture (v0.10.0+)
//  Local model configurations (Whisper, Qwen3, MLX) removed.
//

import Foundation

// MARK: - Base Configuration Protocol

/// Base protocol for ASR model configuration
protocol ASRModelConfiguration: Sendable {
    /// The engine type this configuration is for
    var engineType: ASREngineType { get }
}

// MARK: - Online ASR Configuration

/// Configuration for online API-based ASR services
struct OnlineASRConfig: ASRModelConfiguration, Codable, Sendable {
    let engineType: ASREngineType = .online

    /// Service provider
    var provider: OnlineServiceProvider

    /// API endpoint URL
    var endpoint: String

    /// API key for authentication
    var apiKey: String

    /// Provider-specific model identifier
    var model: String

    /// Language code
    var language: String

    /// Optional prompt for ASR
    var prompt: String?

    /// Optional hotwords to improve recognition of domain-specific terms.
    /// Sent as comma-separated values to providers that support it (e.g., Zhipu).
    /// Providers that don't support hotwords silently ignore this field.
    var hotwords: [String]?

    /// Create a default online ASR configuration
    static func `default`() -> OnlineASRConfig {
        OnlineASRConfig(
            provider: .aliyun,
            endpoint: OnlineServiceProvider.aliyun.defaultBaseURL,
            apiKey: "",
            model: OnlineServiceProvider.aliyun.defaultASRModel,
            language: "zh",
            prompt: nil,
            hotwords: nil
        )
    }

    /// Create from OnlineModelConfig
    static func from(config: OnlineModelConfig, apiKey: String) -> OnlineASRConfig {
        OnlineASRConfig(
            provider: config.provider,
            endpoint: config.baseURL,
            apiKey: apiKey,
            model: config.modelName,
            language: "zh",
            prompt: nil,
            hotwords: nil
        )
    }
}
