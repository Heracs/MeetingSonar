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

    // MARK: - Auto Processing Migration (F-0.10.4)

    /// Migrate autoGenerateSummary boolean to autoProcessingMode enum
    func migrateAutoProcessingSetting() {
        // Check if already migrated
        guard !defaults.bool(forKey: Keys.hasMigratedAutoProcessing) else {
            return
        }

        // Check if old setting exists
        let oldValue = defaults.object(forKey: "autoGenerateSummary")

        // Only migrate if old setting was explicitly set
        if oldValue != nil {
            let oldBool = defaults.bool(forKey: "autoGenerateSummary")

            // Migrate: true → full, false → none
            let newValue: AutoProcessingMode = oldBool ? .full : .none

            defaults.set(newValue.rawValue, forKey: "autoProcessingMode")

            LoggerService.shared.log(
                category: .general,
                message: "[Settings] Migrated auto-processing: \(oldBool) -> \(newValue.rawValue)"
            )
        }

        // Mark as migrated
        defaults.set(true, forKey: Keys.hasMigratedAutoProcessing)
    }

    // MARK: - Teams Detection Migration (F-0.10.2)

    /// Migrate Teams detection settings to unified toggle
    /// - If either Classic or New was enabled, enable both (unified behavior)
    func migrateTeamsDetection() {
        // Check if already migrated
        guard !defaults.bool(forKey: Keys.hasMigratedTeamsDetection) else {
            return
        }

        let classicEnabled = defaults.bool(forKey: "detectTeamsClassic")
        let newEnabled = defaults.bool(forKey: "detectTeamsNew")

        // If either was enabled, enable both (OR logic for migration)
        // This ensures users who had only one version don't lose functionality
        let unifiedEnabled = classicEnabled || newEnabled

        defaults.set(unifiedEnabled, forKey: "detectTeamsClassic")
        defaults.set(unifiedEnabled, forKey: "detectTeamsNew")

        // Mark as migrated
        defaults.set(true, forKey: Keys.hasMigratedTeamsDetection)

        LoggerService.shared.log(
            category: .general,
            level: .info,
            message: "[Settings] Migrated Teams detection: classic=\(classicEnabled), new=\(newEnabled) -> unified=\(unifiedEnabled)"
        )
    }
}
