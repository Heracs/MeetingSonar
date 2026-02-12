import Foundation

// MARK: - Supporting Types

/// Supported audio output formats
enum AudioFormat: String, CaseIterable {
    case m4a = "m4a"
    case mp3 = "mp3"

    var fileExtension: String {
        return rawValue
    }

    var displayName: String {
        switch self {
        case .m4a: return "M4A (AAC)"
        case .mp3: return "MP3"
        }
    }
}

/// Audio encoding quality levels
enum AudioQuality: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    var displayName: String {
        return localizedDisplayName // Alias for existing codebase compatibility
    }

    var localizedDisplayName: String {
        switch self {
        case .low: return "Low (64 kbps)"
        case .medium: return "Medium (128 kbps)"
        case .high: return "High (256 kbps)"
        }
    }

    var bitRate: Int {
        switch self {
        case .low: return 64_000
        case .medium: return 128_000
        case .high: return 256_000
        }
    }

    var sampleRate: Double {
        return 48000.0  // Standard for digital audio/video
    }
}

/// Mode for AI Processing
enum AIProcessingMode: String, CaseIterable, Identifiable {
    case local = "local"
    case online = "online"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .local: return "本地处理 (Local)"
        case .online: return "在线服务 (Online)"
        }
    }
}

// MARK: - Unified Model Types

struct UnifiedModel: Identifiable, Hashable {
    let id: String
    let name: String
    let type: UnifiedModelType
    let provider: String

    var displayName: String {
        return "[\(type.icon)] \(name)"
    }
}

enum UnifiedModelType: String {
    case local
    case online

    var icon: String {
        switch self {
        case .local: return "🏠"
        case .online: return "☁️"
        }
    }
}

extension SettingsManager {

    // MARK: - Unified Model Lists

    var availableASRModels: [UnifiedModel] {
        // Cloud-only: Return models from CloudAIModelManager
        return cachedCloudASRModels
            .filter { $0.isVerified && $0.supports(.asr) }
            .map { config in
                UnifiedModel(
                    id: config.id.uuidString,
                    name: config.asrConfig?.modelName ?? config.displayName,
                    type: .online,
                    provider: config.provider.displayName
                )
            }
    }

    var availableLLMModels: [UnifiedModel] {
        // Cloud-only: Return models from CloudAIModelManager
        return cachedCloudLLMModels
            .filter { $0.isVerified && $0.supports(.llm) }
            .map { config in
                UnifiedModel(
                    id: config.id.uuidString,
                    name: config.llmConfig?.modelName ?? config.displayName,
                    type: .online,
                    provider: config.provider.displayName
                )
            }
    }

    // MARK: - Unified Selection Helpers

    /// Get the currently selected ASR model configuration
    var currentASRModel: UnifiedModel? {
        // Use the unified selection ID
        let id = selectedUnifiedASRId
        return availableASRModels.first(where: { $0.id == id }) ?? availableASRModels.first
    }

    /// Get the currently selected LLM model configuration
    var currentLLMModel: UnifiedModel? {
        let id = selectedUnifiedLLMId
        return availableLLMModels.first(where: { $0.id == id }) ?? availableLLMModels.first
    }
}
