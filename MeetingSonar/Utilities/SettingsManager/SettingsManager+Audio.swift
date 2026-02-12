import Foundation

extension SettingsManager {

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
}
