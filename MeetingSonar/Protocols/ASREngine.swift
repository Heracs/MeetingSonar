//
//  ASREngine.swift
//  MeetingSonar
//
//  F-5.13a: ASR Engine Protocol
//  Unified interface for ASR engines (Whisper, Qwen3-ASR, etc.)
//
//  Architecture Phase 1: Protocol Abstraction Layer
//  Created: 2025-02-05
//

import Foundation

// MARK: - ASR Engine Type

/// ASR engine type identifier
enum ASREngineType: String, Codable, Sendable {
    case whisper = "whisper"
    case qwen3asr = "qwen3asr"
    case online = "online"  // For online API-based engines
}

// MARK: - ASR Engine Protocol

/// Unified ASR engine protocol for speech recognition
///
/// All ASR engines must conform to this protocol to provide a consistent
/// interface for model loading, audio transcription, and resource management.
///
/// # Thread Safety
/// Implementations MUST use `actor` for thread-safe access to model state
/// and C API pointers. This ensures safe concurrent access from multiple callers.
///
/// # Example Implementation
/// ```swift
/// actor WhisperASREngine: ASREngine {
///     let engineType: ASREngineType = .whisper
///     private var context: OpaquePointer?
///
///     func loadModel(modelPath: URL, config: some ASRModelConfiguration) async throws {
///         // Load model using C API
///     }
///
///     func transcribe(audioURL: URL, language: String, progress: ((Double) -> Void)?) async throws -> TranscriptResult {
///         // Perform transcription
///     }
///
///     func unload() async {
///         // Release resources
///     }
/// }
/// ```
protocol ASREngine: Actor {

    // MARK: - Required Properties

    /// Engine type identifier
    var engineType: ASREngineType { get }

    /// Whether a model is currently loaded
    var isLoaded: Bool { get }

    // MARK: - Model Management

    /// Load ASR model from file path
    ///
    /// - Parameters:
    ///   - modelPath: URL to the model file
    ///   - config: Model configuration (engine-specific, conforming to ASRModelConfiguration)
    ///
    /// - Throws: ASREngineError if loading fails
    ///
    /// # Precondition
    /// The model file must exist at the specified path.
    ///
    /// # Postcondition
    /// After successful loading, `isLoaded` returns `true`.
    func loadModel(modelPath: URL, config: some ASRModelConfiguration) async throws

    // MARK: - Transcription

    /// Transcribe audio file to text
    ///
    /// - Parameters:
    ///   - audioURL: URL to the audio file (must be in a supported format)
    ///   - language: Language code (e.g., "zh", "en", "auto" for auto-detection)
    ///   - progress: Optional progress callback with values from 0.0 to 1.0
    ///
    /// - Returns: Transcription result containing segments and full text
    ///
    /// - Throws: ASREngineError if transcription fails
    ///
    /// # Implementation Notes
    /// - Engines should handle audio format conversion internally if needed
    /// - Progress callbacks should be invoked on the actor's executor
    /// - The returned result must include timing information
    func transcribe(
        audioURL: URL,
        language: String,
        progress: ((Double) -> Void)?
    ) async throws -> TranscriptionResult

    /// Unload the current model and release resources
    ///
    /// After calling this method, `isLoaded` returns `false` and any
    /// associated memory (especially C API pointers) should be freed.
    func unload() async
}

// MARK: - ASR Engine Errors

/// Unified error type for ASR engine operations
///
/// All ASR engines should throw these errors for consistent error handling
/// across different implementations.
enum ASREngineError: LocalizedError, Equatable, Sendable {
    case modelNotLoaded
    case modelNotFound(path: String)
    case modelLoadFailed(reason: String)
    case audioConversionFailed(reason: String)
    case transcriptionFailed(reason: String)
    case unsupportedAudioFormat(format: String)
    case audioFileNotFound(path: String)
    case insufficientMemory(required: UInt64, available: UInt64)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return String(localized: "error.asr.modelNotLoaded")
        case .modelNotFound(let path):
            return String(format: String(localized: "error.asr.modelNotFound.%@"), path)
        case .modelLoadFailed(let reason):
            return String(format: String(localized: "error.asr.modelLoadFailed.%@"), reason)
        case .audioConversionFailed(let reason):
            return String(format: String(localized: "error.asr.audioConversionFailed.%@"), reason)
        case .transcriptionFailed(let reason):
            return String(format: String(localized: "error.asr.transcriptionFailed.%@"), reason)
        case .unsupportedAudioFormat(let format):
            return String(format: String(localized: "error.asr.unsupportedAudioFormat.%@"), format)
        case .audioFileNotFound(let path):
            return String(format: String(localized: "error.asr.audioFileNotFound.%@"), path)
        case .insufficientMemory(let required, let available):
            return String(format: String(localized: "error.asr.insufficientMemory.%llu.%llu"), required, available)
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelNotLoaded:
            return String(localized: "error.asr.modelNotLoaded.recovery")
        case .modelNotFound:
            return String(localized: "error.asr.modelNotFound.recovery")
        case .modelLoadFailed:
            return String(localized: "error.asr.modelLoadFailed.recovery")
        case .audioConversionFailed:
            return String(localized: "error.asr.audioConversionFailed.recovery")
        case .transcriptionFailed:
            return String(localized: "error.asr.transcriptionFailed.recovery")
        case .unsupportedAudioFormat:
            return String(localized: "error.asr.unsupportedAudioFormat.recovery")
        case .audioFileNotFound:
            return String(localized: "error.asr.audioFileNotFound.recovery")
        case .insufficientMemory:
            return String(localized: "error.asr.insufficientMemory.recovery")
        }
    }
}

// MARK: - Transcription Result

/// Result of ASR transcription (Engine level)
struct TranscriptionResult {
    /// Full transcribed text
    let text: String

    /// Individual transcription segments with timestamps
    let segments: [ASRTranscriptSegment]

    /// Detected language code
    let language: String?

    /// Processing time in seconds
    let processingTime: TimeInterval
}

/// Individual transcription segment for ASR
struct ASRTranscriptSegment {
    /// Start time in seconds
    let startTime: TimeInterval

    /// End time in seconds
    let endTime: TimeInterval

    /// Transcribed text for this segment
    let text: String
}
