//
//  SettingsManager.swift
//  MeetingSonar
//
//  Manages user preferences and settings using UserDefaults.
//  v0.1-rebuild: Core settings only.
//

import Foundation
import AppKit
import SwiftUI
import ServiceManagement
import Combine

/// Manages application settings and user preferences
@MainActor
final class SettingsManager: ObservableObject, SettingsManagerProtocol {
    
    // MARK: - Singleton
    
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        registerDefaults()
        loadSettings()
        setupModelObservers()
    }

    // MARK: - Cloud Model Cache

    /// Cached cloud AI models (synchronous access for UI)
    @Published private(set) var cachedCloudASRModels: [CloudAIModelConfig] = []
    @Published private(set) var cachedCloudLLMModels: [CloudAIModelConfig] = []

    /// Subscribe to model manager changes to trigger UI updates
    private func setupModelObservers() {
        // Listen to CloudAIModelManager changes
        NotificationCenter.default.publisher(for: CloudAIModelManager.modelsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshCloudModels()
                }
            }
            .store(in: &cancellables)

        // Initial load
        Task { @MainActor in
            await refreshCloudModels()
        }

        // Refresh local model cache on init
        refreshReadyLocalModels()
    }

    /// Refresh cloud models from CloudAIModelManager
    @MainActor
    private func refreshCloudModels() async {
        // Try multiple times to handle async initialization race condition
        var asrModels: [CloudAIModelConfig] = []
        var llmModels: [CloudAIModelConfig] = []

        for attempt in 0..<3 {
            asrModels = await CloudAIModelManager.shared.getModels(for: .asr)
            llmModels = await CloudAIModelManager.shared.getModels(for: .llm)

            // If we have models, break early
            if !asrModels.isEmpty || !llmModels.isEmpty {
                break
            }

            // Otherwise wait a bit and retry
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }

        self.cachedCloudASRModels = asrModels
        self.cachedCloudLLMModels = llmModels

        objectWillChange.send()

        LoggerService.shared.log(category: .ai, message: """
        [SettingsManager] Cloud models refreshed
        ├─ ASR Models: \(asrModels.count)
        └─ LLM Models: \(llmModels.count)
        """)
    }
    
    // MARK: - Local Model Availability Cache
    
    /// Cached set of local ModelTypes that are downloaded and verified 
    @Published private(set) var readyLocalModelTypes: Set<ModelType> = []
    
    /// Refresh the cache of available models (cloud-only version)
    func refreshReadyLocalModels() {
        // Cloud-only: No local models to check
        Task {
            await MainActor.run {
                self.readyLocalModelTypes = []
            }
        }
    }
    
    // MARK: - Keys

    private enum Keys {
        static let savePath = "savePath"
        static let savePathBookmark = "savePathBookmark"
        static let audioFormat = "audioFormat"
        static let launchAtLogin = "launchAtLogin"
        static let audioQuality = "audioQuality"
        static let includeSystemAudio = "includeSystemAudio"
        static let includeMicrophone = "includeMicrophone"
        static let smartDetectionEnabled = "smartDetectionEnabled"
        static let smartDetectionMode = "smartDetectionMode"
        static let asrEngineType = "asrEngineType"  // F-5.14: ASR engine selection
        static let qwen3UseMLXBackend = "qwen3UseMLXBackend"  // F-5.14 Phase 3: MLX backend preference
        static let selectedASRPromptId = "selectedASRPromptId"  // F-10.0-PromptMgmt: Selected ASR prompt
        static let selectedLLMPromptId = "selectedLLMPromptId"  // F-10.0-PromptMgmt: Selected LLM prompt

        // MARK: - Cloud AI Settings (v1.1.0)
        static let enableStreamingSummary = "enableStreamingSummary"
        static let defaultLLMQualityPreset = "defaultLLMQualityPreset"

        // MARK: - Recording Scenario Optimization (v1.0)
        /// 存储自动检测录音的默认配置（JSON 编码的 AudioSourceConfig）
        static let autoRecordingDefaultConfig = "autoRecordingDefaultConfig"
        /// 存储手动录音的默认配置（JSON 编码的 AudioSourceConfig）
        static let manualRecordingDefaultConfig = "manualRecordingDefaultConfig"
        /// 标记是否已完成设置迁移
        static let hasMigratedScenarioSettings = "hasMigratedScenarioSettings"
    }
    
    enum SmartDetectionMode: String, CaseIterable, Identifiable {
        case auto = "auto"
        case remind = "remind"

        var id: String { self.rawValue }

        var localizedDisplayName: String {
            switch self {
            case .auto:
                return String(localized: "smartDetection.mode.auto")
            case .remind:
                return String(localized: "smartDetection.mode.remind")
            }
        }
    }
    
    // MARK: - Default Values
    
    private func registerDefaults() {
        let defaultSavePath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "~/Documents"

        defaults.register(defaults: [
            Keys.savePath: defaultSavePath,
            Keys.audioFormat: AudioFormat.m4a.rawValue,
            Keys.launchAtLogin: false,
            Keys.audioQuality: AudioQuality.high.rawValue,
            Keys.includeSystemAudio: true,
            Keys.includeMicrophone: true,
            // v1.1.0: Cloud AI Settings
            Keys.enableStreamingSummary: true,
            Keys.defaultLLMQualityPreset: LLMQualityPreset.balanced.rawValue
        ])

        // Register scenario default configs (Recording Scenario Optimization v1.0)
        let defaultAutoConfig = AudioSourceConfig.default
        let defaultManualConfig = AudioSourceConfig.systemOnly

        if let autoData = try? JSONEncoder().encode(defaultAutoConfig),
           let manualData = try? JSONEncoder().encode(defaultManualConfig) {
            defaults.register(defaults: [
                Keys.autoRecordingDefaultConfig: autoData,
                Keys.manualRecordingDefaultConfig: manualData
            ])
        }
    }
    
    // MARK: - Save Path
    
    /// Active security-scoped URL (retained to keep permission alive)
    private var securityScopedURL: URL?
    
    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }
    
    /// Directory path where recordings are saved
    var savePath: URL {
        get {
            // 1. Return active URL if already accessed
            if let secureURL = securityScopedURL {
                return secureURL
            }
            
            // 2. Try to resolve Custom Path from Bookmark
            if let bookmarkData = defaults.data(forKey: Keys.savePathBookmark) {
                var isStale = false
                do {
                    let url = try URL(resolvingBookmarkData: bookmarkData,
                                      options: .withSecurityScope,
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &isStale)
                    
                    if isStale {
                        saveBookmark(for: url)
                    }
                    
                    if url.startAccessingSecurityScopedResource() {
                        securityScopedURL = url
                        return url
                    }
                } catch {
                    LoggerService.shared.log(category: .general, level: .error, message: "Failed to resolve bookmark: \(error)")
                }
            }
            
            // 3. Fallback to Sandbox Documents (Default)
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }
        set {
            // Validate path before accepting it
            do {
                try PathValidator.validatePathString(newValue.path)

                // For external paths, also validate they're within a reasonable directory
                if !newValue.path.hasPrefix(PathManager.shared.rootDataURL.path) {
                    // Additional validation for external paths could go here
                    LoggerService.shared.log(category: .general, level: .info, message: "[Settings] External path selected: \(newValue.path)")
                }
            } catch {
                LoggerService.shared.log(category: .general, level: .error, message: "[Settings] Path validation failed: \(error.localizedDescription)")
                // Reject the invalid path by not updating
                return
            }

            // Stop accessing old resource
            securityScopedURL?.stopAccessingSecurityScopedResource()
            securityScopedURL = nil

            // Create and save bookmark coverage for new path
            saveBookmark(for: newValue)

            // Start accessing new resource (if applicable)
            if newValue.startAccessingSecurityScopedResource() {
                securityScopedURL = newValue
            }

            defaults.set(newValue.path, forKey: Keys.savePath)
            objectWillChange.send()
        }
    }
    
    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            defaults.set(data, forKey: Keys.savePathBookmark)
        } catch {
            LoggerService.shared.log(category: .general, level: .error, message: "Failed to create bookmark: \(error)")
        }
    }
    
    // MARK: - Audio Format
    
    /// Output audio format (M4A or MP3)
    @Published var audioFormat: AudioFormat = .m4a {
        didSet {
            defaults.set(audioFormat.rawValue, forKey: Keys.audioFormat)
        }
    }
    
    // MARK: - Audio Quality
    
    /// Audio encoding quality
    @Published var audioQuality: AudioQuality = .high {
        didSet {
            defaults.set(audioQuality.rawValue, forKey: Keys.audioQuality)
        }
    }
    
    // MARK: - Audio Sources

    /// Whether to include system/application audio
    /// - Note: This property is now a computed property for backward compatibility.
    ///   It maps to the current active config and syncs both scenario configs.
    var includeSystemAudio: Bool {
        get { currentActiveConfig.includeSystemAudio }
        set {
            currentActiveConfig.includeSystemAudio = newValue
            // Sync both scenario configs for backward compatibility
            autoRecordingDefaultConfig.includeSystemAudio = newValue
            manualRecordingDefaultConfig.includeSystemAudio = newValue
            // Also save to legacy key for compatibility with old code
            defaults.set(newValue, forKey: Keys.includeSystemAudio)
        }
    }

    /// Whether to include microphone input
    /// - Note: This property is now a computed property for backward compatibility.
    ///   It maps to the current active config and syncs both scenario configs.
    var includeMicrophone: Bool {
        get { currentActiveConfig.includeMicrophone }
        set {
            currentActiveConfig.includeMicrophone = newValue
            // Sync both scenario configs for backward compatibility
            autoRecordingDefaultConfig.includeMicrophone = newValue
            manualRecordingDefaultConfig.includeMicrophone = newValue
            // Also save to legacy key for compatibility with old code
            defaults.set(newValue, forKey: Keys.includeMicrophone)
        }
    }

    // MARK: - Recording Scenario Optimization (v1.0)

    /// 自动检测录音的默认配置
    /// - 默认：系统音频 + 麦克风（适合会议场景）
    /// - 当 DetectionService 检测到会议应用并触发自动录音时使用此配置
    @Published var autoRecordingDefaultConfig: AudioSourceConfig = .default {
        didSet {
            autoRecordingDefaultConfig.save(toDefaults: Keys.autoRecordingDefaultConfig)
        }
    }

    /// 手动录音的默认配置
    /// - 默认：仅系统音频（适合录制视频/音乐）
    /// - 当用户手动点击"开始录音"时使用此配置
    @Published var manualRecordingDefaultConfig: AudioSourceConfig = .systemOnly {
        didSet {
            manualRecordingDefaultConfig.save(toDefaults: Keys.manualRecordingDefaultConfig)
        }
    }

    /// 当前活动的音频源配置（根据最后一次录音类型）
    /// 用于支持旧代码读取当前配置状态
    private var currentActiveConfig: AudioSourceConfig = .default

    /// 根据触发类型获取对应的默认配置
    /// - Parameter trigger: 录音触发类型
    /// - Returns: 对应的音频源配置
    /// - 使用场景：RecordingService.startRecording(trigger:) 中调用此方法获取配置
    func defaultConfig(for trigger: RecordingTrigger) -> AudioSourceConfig {
        switch trigger {
        case .manual:
            return manualRecordingDefaultConfig
        case .auto, .smartReminder:
            return autoRecordingDefaultConfig
        }
    }

    /// 设置当前活动配置
    /// - Parameter config: 要设置的配置
    /// - Note: 在录音开始时调用，用于同步旧版属性
    func setCurrentActiveConfig(_ config: AudioSourceConfig) {
        currentActiveConfig = config
    }
    
    // MARK: - Smart Detection

    /// Whether smart detection is enabled
    @AppStorage(Keys.smartDetectionEnabled) var smartDetectionEnabled: Bool = true

    /// Mode for smart detection (auto-record or remind)
    @AppStorage(Keys.smartDetectionMode) var smartDetectionMode: SmartDetectionMode = .remind

    // MARK: - Per-App Detection Settings

    // MARK: Western Apps

    /// Enable Zoom detection
    @AppStorage("detectZoom") var detectZoom: Bool = true

    /// Enable Microsoft Teams (Classic) detection
    @AppStorage("detectTeamsClassic") var detectTeamsClassic: Bool = true

    /// Enable Microsoft Teams (New) detection
    @AppStorage("detectTeamsNew") var detectTeamsNew: Bool = true

    /// Enable Webex detection
    @AppStorage("detectWebex") var detectWebex: Bool = true

    // MARK: Chinese Apps

    /// Enable Tencent Meeting detection
    @AppStorage("detectTencentMeeting") var detectTencentMeeting: Bool = true

    /// Enable Feishu/Lark detection
    @AppStorage("detectFeishu") var detectFeishu: Bool = true

    /// Enable WeChat voice call detection (default: false for privacy)
    @AppStorage("detectWeChat") var detectWeChat: Bool = false

    // MARK: - Transcripts Settings

    /// Automatically generate summaries after recording
    @AppStorage("autoGenerateSummary") var autoGenerateSummary: Bool = true

    /// Transcript language preference ("auto", "en", "zh", etc.)
    @AppStorage("transcriptLanguage") var transcriptLanguage: String = "auto"

    // MARK: - AI Models Selection (F-7.4)

    // MARK: - ASR Engine Type Selection (F-5.14)

    /// Selected ASR engine type (whisper, qwen3asr, online)
    @AppStorage(Keys.asrEngineType) var asrEngineType: ASREngineType = .whisper

    // MARK: - Qwen3-ASR Backend Preference (F-5.14 Phase 3)

    /// Whether to use MLX backend for Qwen3-ASR (default: true for Apple Silicon)
    @AppStorage(Keys.qwen3UseMLXBackend) var qwen3UseMLXBackend: Bool = true

    // MARK: - Prompt Management (F-10.0-PromptMgmt)

    /// Selected ASR Prompt Template ID
    @AppStorage(Keys.selectedASRPromptId) var selectedASRPromptId: String = ""

    /// Selected LLM Prompt Template ID
    @AppStorage(Keys.selectedLLMPromptId) var selectedLLMPromptId: String = ""

    // MARK: - Cloud AI Settings (v1.1.0)

    /// Enable streaming summary output
    /// v1.1.0: Global toggle for streaming LLM output
    @AppStorage("enableStreamingSummary") var enableStreamingSummary: Bool = true

    /// Default LLM quality preset for new configurations
    /// v1.1.0: Default quality preset (fast/balanced/quality)
    @AppStorage("defaultLLMQualityPreset") var defaultLLMQualityPresetRaw: String = "balanced"

    /// Default LLM quality preset as enum
    var defaultLLMQualityPreset: LLMQualityPreset {
        get {
            LLMQualityPreset(rawValue: defaultLLMQualityPresetRaw) ?? .balanced
        }
        set {
            defaultLLMQualityPresetRaw = newValue.rawValue
        }
    }

    // MARK: - Unified Model Selection (v0.8.4)
    
    /// Selected ASR Model ID (Unified: "local_..." or UUID string)
    @AppStorage("selectedUnifiedASRId") var selectedUnifiedASRId: String = "local_whisper_base"
    
    /// Selected LLM Model ID (Unified: "local_..." or UUID string)
    @AppStorage("selectedUnifiedLLMId") var selectedUnifiedLLMId: String = "local_qwen_1_5b"
    
    // Deprecated: Legacy separate modes (kept for migration if needed, but UI uses Unified)
    @AppStorage("aiProcessingMode") var aiProcessingMode: AIProcessingMode = .local
    @AppStorage("selectedOnlineASRId") var selectedOnlineASRId: String = "" 
    @AppStorage("selectedOnlineLLMId") var selectedOnlineLLMId: String = ""
    
    // MARK: - Launch at Login
    
    /// Whether app should launch at login
    @Published var launchAtLogin: Bool = false {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLaunchAtLoginStatus()
        }
    }
    
    /// Register or unregister launch at login using SMAppService (macOS 13+)
    private func updateLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if launchAtLogin {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                LoggerService.shared.log(category: .general, level: .error, message: "Failed to update launch at login: \(error)")
            }
        }
    }
    
    /// Load launch at login state from system
    private func loadLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            launchAtLogin = service.status == .enabled
        } else {
            launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        }
    }
    
    /// Load all published settings from UserDefaults
    private func loadSettings() {
        let formatRaw = defaults.string(forKey: Keys.audioFormat) ?? AudioFormat.m4a.rawValue
        audioFormat = AudioFormat(rawValue: formatRaw) ?? .m4a

        let qualityRaw = defaults.string(forKey: Keys.audioQuality) ?? AudioQuality.high.rawValue
        audioQuality = AudioQuality(rawValue: qualityRaw) ?? .high

        // Load scenario configs first (Recording Scenario Optimization v1.0)
        autoRecordingDefaultConfig = AudioSourceConfig.fromDefaults(
            key: Keys.autoRecordingDefaultConfig
        ) ?? .default

        manualRecordingDefaultConfig = AudioSourceConfig.fromDefaults(
            key: Keys.manualRecordingDefaultConfig
        ) ?? .systemOnly

        // Initialize current active config to manual config (most common initial state)
        currentActiveConfig = manualRecordingDefaultConfig

        // Migrate legacy settings if needed
        migrateLegacySettings()

        loadLaunchAtLoginState()
    }

    // MARK: - Migration

    /// 从旧版本设置迁移
    /// - 将现有的 includeSystemAudio/includeMicrophone 同步到新配置
    ///
    /// 迁移策略：
    /// 1. 检查是否已迁移（通过标志位）
    /// 2. 读取旧设置值
    /// 3. 将旧设置应用到两个场景配置（保持行为一致性）
    /// 4. 标记已迁移
    ///
    /// 注意：两个场景使用相同的迁移值，因为旧版本不区分场景
    private func migrateLegacySettings() {
        // Check if already migrated
        guard !defaults.bool(forKey: Keys.hasMigratedScenarioSettings) else {
            return
        }

        // Read legacy settings (only if they exist and differ from defaults)
        let legacySystem = defaults.bool(forKey: Keys.includeSystemAudio)
        let legacyMic = defaults.bool(forKey: Keys.includeMicrophone)

        // Create migrated config
        let migratedConfig = AudioSourceConfig(
            includeSystemAudio: legacySystem,
            includeMicrophone: legacyMic
        )

        // Apply to both scenarios (legacy version didn't distinguish scenarios)
        autoRecordingDefaultConfig = migratedConfig
        manualRecordingDefaultConfig = migratedConfig

        // Update current active config
        currentActiveConfig = migratedConfig

        // Mark as migrated
        defaults.set(true, forKey: Keys.hasMigratedScenarioSettings)

        LoggerService.shared.log(
            category: .general,
            message: "Migrated legacy audio settings: system=\(legacySystem), mic=\(legacyMic)"
        )
    }
    
    // MARK: - File Naming
    
    /// Generate filename for a new recording
    /// - Parameter appName: Name of the application being recorded (optional)
    /// - Returns: Filename in format `{AppName}_{YYYY-MM-DD}_{HH-mm-ss}.{ext}`
    func generateFilename(appName: String? = nil) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let name = appName ?? "Recording"
        let sanitizedName = name.replacingOccurrences(of: " ", with: "_")
        
        return "\(sanitizedName)_\(timestamp).\(audioFormat.fileExtension)"
    }
    
    /// Get full file URL for a new recording
    ///
    /// - Parameter appName: Optional application name for the filename
    /// - Returns: A validated URL within the configured save path
    func generateFileURL(appName: String? = nil) -> URL {
        let filename = generateFilename(appName: appName)

        do {
            return try PathValidator.safeAppendingPathComponent(to: savePath, component: filename)
        } catch {
            LoggerService.shared.log(category: .general, level: .error, message: "[Settings] Failed to generate file URL: \(error.localizedDescription)")
            // Fallback to unsafe construction
            return savePath.appendingPathComponent(filename)
        }
    }
}

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

