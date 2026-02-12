import Foundation

extension SettingsManager {

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
    func migrateLegacySettings() {
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
}
