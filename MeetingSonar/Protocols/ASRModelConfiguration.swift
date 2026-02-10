//
//  ASRModelConfiguration.swift
//  MeetingSonar
//
//  F-5.13b: ASR Model Configuration Protocol
//  Configuration types for different ASR engines
//
//  Architecture Phase 1: Protocol Abstraction Layer
//  Created: 2025-02-05
//

import Foundation

// MARK: - Base Configuration Protocol

/// Base protocol for ASR model configuration
///
/// Each ASR engine defines its own configuration struct conforming to this protocol.
/// This allows type-safe configuration while maintaining a common interface.
///
/// # Example
/// ```swift
/// struct WhisperASRConfig: ASRModelConfiguration, Sendable {
///     let engineType: ASREngineType = .whisper
///     var nThreads: Int32
///     var translate: Bool
///     // ... engine-specific parameters
/// }
/// ```
protocol ASRModelConfiguration: Sendable {
    /// The engine type this configuration is for
    var engineType: ASREngineType { get }
}

// MARK: - Whisper Configuration

/// Whisper-specific ASR model configuration
///
/// Contains parameters specific to Whisper.cpp inference.
struct WhisperASRConfig: ASRModelConfiguration, Codable, Sendable {
    // MARK: - Engine Type

    let engineType: ASREngineType = .whisper

    // MARK: - Performance Parameters

    /// Number of threads to use for inference (0 = auto-detect CPU count)
    var nThreads: Int32

    /// Sampling strategy for inference
    var samplingStrategy: WhisperSamplingStrategy

    // MARK: - Language Parameters

    /// Whether to translate to English
    /// - Note: Set to `false` to keep transcription in original language
    var translate: Bool

    /// Language code (e.g., "zh", "en", "auto" for auto-detection)
    var language: String

    /// Initial prompt for context (e.g., "请使用简体中文进行记录。")
    /// - Note: This helps guide the model's output format
    var initialPrompt: String?

    // MARK: - Advanced Parameters

    /// Beam size for beam search (only used when strategy is .beamSearch)
    var beamSize: Int

    /// Temperature for sampling
    /// - Range: 0.0 to 1.0, lower values make output more deterministic
    var temperature: Float

    /// No speech threshold (skip silence detection)
    /// - Range: 0.0 to 1.0
    var noSpeechThreshold: Float

    // MARK: - Default Configuration

    /// Create a default Whisper configuration
    static func `default`() -> WhisperASRConfig {
        WhisperASRConfig(
            nThreads: Int32(ProcessInfo.processInfo.activeProcessorCount),
            samplingStrategy: .greedy,
            translate: false,
            language: "auto",
            initialPrompt: "请使用简体中文进行记录。",
            beamSize: 5,
            temperature: 0.0,
            noSpeechThreshold: 0.6
        )
    }
}

// MARK: - Whisper Sampling Strategy

/// Sampling strategy for Whisper inference
enum WhisperSamplingStrategy: String, Codable, Sendable {
    /// Greedy decoding (faster, deterministic)
    case greedy

    /// Beam search decoding (slower, potentially better quality)
    case beamSearch
}

// MARK: - Qwen3-ASR Configuration

/// Qwen3-ASR specific model configuration
///
/// Contains parameters specific to Qwen3-ASR inference.
/// Note: This is a placeholder implementation pending Qwen3-ASR API details.
struct Qwen3ASRConfig: ASRModelConfiguration, Codable, Sendable {
    // MARK: - Engine Type

    let engineType: ASREngineType = .qwen3asr

    // MARK: - Performance Parameters

    /// Batch size for inference
    /// - Note: Larger values may improve throughput but require more memory
    var batchSize: Int

    /// Number of threads for inference (0 = auto-detect)
    var nThreads: Int

    // MARK: - Audio Processing Parameters

    /// Whether to use Voice Activity Detection
    /// - Note: VAD helps skip silent portions in audio
    var useVAD: Bool

    /// Chunk duration in seconds for processing long audio
    /// - Note: Longer chunks may improve context but require more memory
    var chunkDurationSec: Double

    /// Overlap between chunks in seconds
    /// - Note: Helps prevent word boundaries from being cut
    var chunkOverlapSec: Double

    // MARK: - Language Parameters

    /// Language code (e.g., "zh", "en", "auto")
    var language: String

    // MARK: - Model-Specific Parameters

    /// Prompt for guiding output format
    var prompt: String?

    /// Temperature for sampling
    var temperature: Float

    // MARK: - Default Configuration

    /// Create a default Qwen3-ASR configuration
    static func `default`() -> Qwen3ASRConfig {
        Qwen3ASRConfig(
            batchSize: 1,
            nThreads: ProcessInfo.processInfo.activeProcessorCount,
            useVAD: true,
            chunkDurationSec: 30.0,
            chunkOverlapSec: 2.0,
            language: "zh",
            prompt: nil,
            temperature: 0.0
        )
    }
}

// MARK: - Online ASR Configuration

/// Configuration for online API-based ASR services
///
/// Used when ASR is performed by an external API rather than local models.
struct OnlineASRConfig: ASRModelConfiguration, Codable, Sendable {
    let engineType: ASREngineType = .online

    /// Service provider
    var provider: OnlineServiceProvider

    /// API endpoint URL (String for flexibility)
    var endpoint: String

    /// API key for authentication
    var apiKey: String

    /// Provider-specific model identifier
    var model: String

    /// Language code
    var language: String

    /// Optional prompt for ASR
    var prompt: String?

    /// Create a default online ASR configuration
    static func `default`() -> OnlineASRConfig {
        OnlineASRConfig(
            provider: .aliyun,
            endpoint: OnlineServiceProvider.aliyun.defaultBaseURL,
            apiKey: "",
            model: OnlineServiceProvider.aliyun.defaultASRModel,
            language: "zh",
            prompt: nil
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
            prompt: nil
        )
    }
}

// MARK: - Qwen3-ASR MLX Configuration

/// Qwen3-ASR specific model configuration for MLX backend
///
/// MLX (Apple Silicon optimized) configuration for Qwen3-ASR inference.
/// MLX provides faster inference on Apple Silicon compared to PyTorch.
///
/// # F-5.14: MLX Integration
/// Phase 1: Core MLX Integration
struct Qwen3ASRMLXConfig: ASRModelConfiguration, Codable, Sendable {
    // MARK: - Engine Type

    let engineType: ASREngineType = .qwen3asr

    // MARK: - Model Selection

    /// Model variant for MLX inference
    var modelVariant: MLXModelVariant

    /// Available MLX model variants
    enum MLXModelVariant: String, Codable, Sendable {
        case qwen0_6B = "Qwen3-ASR-0.6B"
        case qwen1_7B = "Qwen3-ASR-1.7B"

        var modelSize: String {
            switch self {
            case .qwen0_6B: return "0.6B"
            case .qwen1_7B: return "1.7B"
            }
        }
    }

    // MARK: - MLX-Specific Parameters

    /// Whether to use MLX backend (vs PyTorch)
    var useMLX: Bool

    /// Batch size for MLX inference
    /// - Note: MLX can handle larger batches efficiently on Apple Silicon
    var batchSize: Int

    /// Whether to use quantized models (reduced memory footprint)
    /// - Note: Quantization may slightly reduce accuracy but improves memory usage
    var useQuantization: Bool

    // MARK: - Audio Processing Parameters

    /// Whether to use Voice Activity Detection
    /// - Note: VAD helps skip silent portions in audio
    var useVAD: Bool

    /// Chunk duration in seconds for processing long audio
    /// - Note: Longer chunks may improve context but require more memory
    var chunkDurationSec: Double

    /// Overlap between chunks in seconds
    /// - Note: Helps prevent word boundaries from being cut
    var chunkOverlapSec: Double

    // MARK: - Language Parameters

    /// Language code (e.g., "zh", "en", "auto")
    var language: String

    // MARK: - Python Environment Options

    /// Path to project-specific Python virtual environment
    /// - Note: If nil, uses system Python or default uv environment
    var projectEnvironmentPath: String?

    /// Whether to use isolated Python environment for MLX
    var useIsolatedEnvironment: Bool

    // MARK: - Model-Specific Parameters

    /// Prompt for guiding output format
    var prompt: String?

    /// Temperature for sampling (MLX-specific)
    var temperature: Float

    // MARK: - Default Configuration

    /// Create a default Qwen3-ASR MLX configuration
    static func `default`() -> Qwen3ASRMLXConfig {
        Qwen3ASRMLXConfig(
            modelVariant: .qwen0_6B,
            useMLX: true,
            batchSize: 1,
            useQuantization: false,
            useVAD: true,
            chunkDurationSec: 30.0,
            chunkOverlapSec: 2.0,
            language: "zh",
            projectEnvironmentPath: nil,
            useIsolatedEnvironment: true,
            prompt: nil,
            temperature: 0.0
        )
    }

    /// Create default configuration for specific model variant
    static func `default`(for variant: MLXModelVariant) -> Qwen3ASRMLXConfig {
        var config = Qwen3ASRMLXConfig.`default`()
        config.modelVariant = variant
        return config
    }
}

// MARK: - Configuration Factory

/// Factory for creating default configurations based on engine type
enum ASRConfigurationFactory {
    /// Create a default configuration for the specified engine type
    static func defaultConfig(for engineType: ASREngineType) -> any ASRModelConfiguration {
        switch engineType {
        case .whisper:
            return WhisperASRConfig.default()
        case .qwen3asr:
            return Qwen3ASRConfig.default()
        case .online:
            return OnlineASRConfig.default()
        }
    }

    /// Create a default MLX configuration for Qwen3-ASR
    ///
    /// - Parameter variant: MLX model variant (default: 0.6B)
    /// - Returns: Qwen3ASRMLXConfig with default settings
    static func defaultMLXConfig(
        for variant: Qwen3ASRMLXConfig.MLXModelVariant = .qwen0_6B
    ) -> Qwen3ASRMLXConfig {
        Qwen3ASRMLXConfig.default(for: variant)
    }
}
