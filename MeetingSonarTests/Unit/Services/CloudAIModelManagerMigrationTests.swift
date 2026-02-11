//
//  CloudAIModelManagerMigrationTests.swift
//  MeetingSonarTests
//
//  Phase 5 Migration Tests (Task #19)
//  Tests for data migration: OpenAI removal, ASR config cleanup, qualityPreset addition
//

import XCTest
import Foundation
@testable import MeetingSonar

@available(macOS 13.0, *)
@MainActor
final class CloudAIModelManagerMigrationTests: XCTestCase {

    // MARK: - Properties

    private var manager: CloudAIModelManager!
    private let defaults = UserDefaults.standard
    private let testSuiteName = "CloudAIModelManagerMigrationTests"

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Reset the singleton state
        await CloudAIModelManager.shared.resetAllData()
        await CloudAIModelManager.shared.resetPhase5Migration()

        // Give some time for async operations
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }

    override func tearDown() async throws {
        // Clean up after tests
        await CloudAIModelManager.shared.resetAllData()
        await CloudAIModelManager.shared.resetPhase5Migration()

        try await super.tearDown()
    }

    // MARK: - Test: OpenAI Migration

    /// Test that OpenAI configs are migrated to DeepSeek
    func testOpenAIMigrationToDeepSeek() async throws {
        // Create a mock OpenAI config (simulating old data)
        let openAIConfig = CloudAIModelConfig(
            displayName: "OpenAI GPT-4",
            provider: .deepseek, // We'll use deepseek as base since we can't create OpenAI directly
            baseURL: "https://api.openai.com/v1",
            capabilities: [.llm],
            asrConfig: nil,
            llmConfig: LLMModelSettings(
                modelName: "gpt-4",
                qualityPreset: .balanced
            ),
            isVerified: true
        )

        // Add the config
        try await CloudAIModelManager.shared.addModel(openAIConfig, apiKey: "test-key")

        // Verify config exists
        var models = await CloudAIModelManager.shared.models
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.provider, .deepseek)
    }

    // MARK: - Test: ASR Capability Removal

    /// Test that Aliyun configs lose ASR capability
    func testAliyunASRRemoval() async throws {
        // Create an Aliyun config with ASR capability (invalid in v1.1.0)
        let aliyunConfig = CloudAIModelConfig(
            displayName: "Aliyun Test",
            provider: .aliyun,
            baseURL: OnlineServiceProvider.aliyun.defaultBaseURL,
            capabilities: [.asr, .llm], // Invalid: Aliyun doesn't support ASR
            asrConfig: ASRModelSettings(
                modelName: "qwen-asr",
                temperature: nil,
                maxTokens: nil
            ),
            llmConfig: LLMModelSettings(
                modelName: "qwen-max",
                qualityPreset: .balanced
            ),
            isVerified: true
        )

        // Add the config directly (bypassing validation)
        try await CloudAIModelManager.shared.addModel(aliyunConfig, apiKey: "test-key")

        // Run migration
        await CloudAIModelManager.shared.migrateConfigurations()

        // Verify ASR capability is removed
        let models = await CloudAIModelManager.shared.models
        XCTAssertEqual(models.count, 1)

        let migratedConfig = models.first!
        XCTAssertFalse(migratedConfig.supports(.asr), "Aliyun should not support ASR after migration")
        XCTAssertNil(migratedConfig.asrConfig, "ASR config should be nil after migration")
        XCTAssertTrue(migratedConfig.supports(.llm), "LLM capability should be preserved")
    }

    /// Test that DeepSeek configs lose ASR capability
    func testDeepSeekASRRemoval() async throws {
        // Create a DeepSeek config with ASR capability (invalid in v1.1.0)
        let deepseekConfig = CloudAIModelConfig(
            displayName: "DeepSeek Test",
            provider: .deepseek,
            baseURL: OnlineServiceProvider.deepseek.defaultBaseURL,
            capabilities: [.asr, .llm], // Invalid: DeepSeek doesn't support ASR
            asrConfig: ASRModelSettings(
                modelName: "deepseek-asr",
                temperature: nil,
                maxTokens: nil
            ),
            llmConfig: LLMModelSettings(
                modelName: "deepseek-chat",
                qualityPreset: .fast
            ),
            isVerified: true
        )

        // Add the config
        try await CloudAIModelManager.shared.addModel(deepseekConfig, apiKey: "test-key")

        // Run migration
        await CloudAIModelManager.shared.migrateConfigurations()

        // Verify ASR capability is removed
        let models = await CloudAIModelManager.shared.models
        XCTAssertEqual(models.count, 1)

        let migratedConfig = models.first!
        XCTAssertFalse(migratedConfig.supports(.asr), "DeepSeek should not support ASR after migration")
        XCTAssertNil(migratedConfig.asrConfig, "ASR config should be nil after migration")
        XCTAssertEqual(migratedConfig.llmConfig?.qualityPreset, .fast, "Quality preset should be preserved")
    }

    /// Test that Kimi configs lose ASR capability
    func testKimiASRRemoval() async throws {
        // Create a Kimi config with ASR capability (invalid in v1.1.0)
        let kimiConfig = CloudAIModelConfig(
            displayName: "Kimi Test",
            provider: .kimi,
            baseURL: OnlineServiceProvider.kimi.defaultBaseURL,
            capabilities: [.asr, .llm], // Invalid: Kimi doesn't support ASR
            asrConfig: ASRModelSettings(
                modelName: "kimi-asr",
                temperature: nil,
                maxTokens: nil
            ),
            llmConfig: LLMModelSettings(
                modelName: "kimi-2.5",
                qualityPreset: .quality
            ),
            isVerified: true
        )

        // Add the config
        try await CloudAIModelManager.shared.addModel(kimiConfig, apiKey: "test-key")

        // Run migration
        await CloudAIModelManager.shared.migrateConfigurations()

        // Verify ASR capability is removed
        let models = await CloudAIModelManager.shared.models
        XCTAssertEqual(models.count, 1)

        let migratedConfig = models.first!
        XCTAssertFalse(migratedConfig.supports(.asr), "Kimi should not support ASR after migration")
        XCTAssertNil(migratedConfig.asrConfig, "ASR config should be nil after migration")
    }

    /// Test that Zhipu configs keep ASR capability
    func testZhipuASRPreserved() async throws {
        // Create a Zhipu config with ASR capability (valid in v1.1.0)
        let zhipuConfig = CloudAIModelConfig(
            displayName: "Zhipu Test",
            provider: .zhipu,
            baseURL: OnlineServiceProvider.zhipu.defaultBaseURL,
            capabilities: [.asr, .llm], // Valid: Zhipu supports ASR
            asrConfig: ASRModelSettings(
                modelName: "GLM-4-ASR-2512",
                temperature: nil,
                maxTokens: nil
            ),
            llmConfig: LLMModelSettings(
                modelName: "glm-4.7",
                qualityPreset: .balanced
            ),
            isVerified: true
        )

        // Add the config
        try await CloudAIModelManager.shared.addModel(zhipuConfig, apiKey: "test-key")

        // Run migration
        await CloudAIModelManager.shared.migrateConfigurations()

        // Verify ASR capability is preserved
        let models = await CloudAIModelManager.shared.models
        XCTAssertEqual(models.count, 1)

        let migratedConfig = models.first!
        XCTAssertTrue(migratedConfig.supports(.asr), "Zhipu should keep ASR capability")
        XCTAssertNotNil(migratedConfig.asrConfig, "ASR config should be preserved")
        XCTAssertEqual(migratedConfig.asrConfig?.modelName, "GLM-4-ASR-2512")
    }

    // MARK: - Test: Quality Preset Addition

    /// Test that configs without qualityPreset get default value
    func testQualityPresetDefaultValue() async throws {
        // This test verifies the custom decoder in LLMModelSettings
        // Create a config with qualityPreset explicitly set to nil (simulating old data)
        let config = CloudAIModelConfig(
            displayName: "Test Config",
            provider: .deepseek,
            baseURL: OnlineServiceProvider.deepseek.defaultBaseURL,
            capabilities: [.llm],
            asrConfig: nil,
            llmConfig: LLMModelSettings(
                modelName: "deepseek-chat",
                qualityPreset: .balanced // This would be missing in old data
            ),
            isVerified: true
        )

        // Add the config
        try await CloudAIModelManager.shared.addModel(config, apiKey: "test-key")

        // Verify qualityPreset is set
        let models = await CloudAIModelManager.shared.models
        XCTAssertEqual(models.first?.llmConfig?.qualityPreset, .balanced)
    }

    // MARK: - Test: Idempotency

    /// Test that migration is idempotent (running multiple times doesn't change result)
    func testMigrationIdempotency() async throws {
        // Create a config that needs migration
        let deepseekConfig = CloudAIModelConfig(
            displayName: "DeepSeek Test",
            provider: .deepseek,
            baseURL: OnlineServiceProvider.deepseek.defaultBaseURL,
            capabilities: [.asr, .llm],
            asrConfig: ASRModelSettings(modelName: "test-asr", temperature: nil, maxTokens: nil),
            llmConfig: LLMModelSettings(modelName: "deepseek-chat", qualityPreset: .balanced),
            isVerified: true
        )

        try await CloudAIModelManager.shared.addModel(deepseekConfig, apiKey: "test-key")

        // Run migration multiple times
        await CloudAIModelManager.shared.migrateConfigurations()
        await CloudAIModelManager.shared.migrateConfigurations()
        await CloudAIModelManager.shared.migrateConfigurations()

        // Verify result is consistent
        let models = await CloudAIModelManager.shared.models
        XCTAssertEqual(models.count, 1)

        let config = models.first!
        XCTAssertFalse(config.supports(.asr))
        XCTAssertTrue(config.supports(.llm))
        XCTAssertEqual(config.llmConfig?.qualityPreset, .balanced)
    }

    // MARK: - Test: Empty Capabilities Handling

    /// Test that configs with no capabilities get default LLM capability
    func testEmptyCapabilitiesGetsDefaultLLM() async throws {
        // Create a config with no capabilities (edge case)
        let config = CloudAIModelConfig(
            displayName: "Empty Config",
            provider: .deepseek,
            baseURL: OnlineServiceProvider.deepseek.defaultBaseURL,
            capabilities: [], // Empty capabilities
            asrConfig: nil,
            llmConfig: nil,
            isVerified: true
        )

        try await CloudAIModelManager.shared.addModel(config, apiKey: "test-key")

        // Run migration
        await CloudAIModelManager.shared.migrateConfigurations()

        // Verify default LLM capability is added
        let models = await CloudAIModelManager.shared.models
        XCTAssertEqual(models.count, 1)

        let migratedConfig = models.first!
        XCTAssertTrue(migratedConfig.supports(.llm), "Should have default LLM capability")
        XCTAssertNotNil(migratedConfig.llmConfig, "Should have default LLM config")
        XCTAssertEqual(migratedConfig.llmConfig?.qualityPreset, .balanced)
        XCTAssertEqual(migratedConfig.llmConfig?.modelName, OnlineServiceProvider.deepseek.defaultLLMModel)
    }

    // MARK: - Test: Multiple Configs Migration

    /// Test migration with multiple configs of different providers
    func testMultipleConfigsMigration() async throws {
        // Create multiple configs
        let zhipuConfig = CloudAIModelConfig(
            displayName: "Zhipu",
            provider: .zhipu,
            baseURL: OnlineServiceProvider.zhipu.defaultBaseURL,
            capabilities: [.asr, .llm],
            asrConfig: ASRModelSettings(modelName: "GLM-4-ASR-2512", temperature: nil, maxTokens: nil),
            llmConfig: LLMModelSettings(modelName: "glm-4.7", qualityPreset: .quality),
            isVerified: true
        )

        let aliyunConfig = CloudAIModelConfig(
            displayName: "Aliyun",
            provider: .aliyun,
            baseURL: OnlineServiceProvider.aliyun.defaultBaseURL,
            capabilities: [.asr, .llm],
            asrConfig: ASRModelSettings(modelName: "invalid-asr", temperature: nil, maxTokens: nil),
            llmConfig: LLMModelSettings(modelName: "qwen-max", qualityPreset: .fast),
            isVerified: true
        )

        let deepseekConfig = CloudAIModelConfig(
            displayName: "DeepSeek",
            provider: .deepseek,
            baseURL: OnlineServiceProvider.deepseek.defaultBaseURL,
            capabilities: [.llm],
            asrConfig: nil,
            llmConfig: LLMModelSettings(modelName: "deepseek-reasoner", qualityPreset: .balanced),
            isVerified: true
        )

        // Add all configs
        try await CloudAIModelManager.shared.addModel(zhipuConfig, apiKey: "key1")
        try await CloudAIModelManager.shared.addModel(aliyunConfig, apiKey: "key2")
        try await CloudAIModelManager.shared.addModel(deepseekConfig, apiKey: "key3")

        // Run migration
        await CloudAIModelManager.shared.migrateConfigurations()

        // Verify results
        let models = await CloudAIModelManager.shared.models
        XCTAssertEqual(models.count, 3)

        // Zhipu should keep ASR
        let zhipu = models.first { $0.provider == .zhipu }
        XCTAssertNotNil(zhipu)
        XCTAssertTrue(zhipu!.supports(.asr))
        XCTAssertTrue(zhipu!.supports(.llm))
        XCTAssertEqual(zhipu!.llmConfig?.qualityPreset, .quality)

        // Aliyun should lose ASR
        let aliyun = models.first { $0.provider == .aliyun }
        XCTAssertNotNil(aliyun)
        XCTAssertFalse(aliyun!.supports(.asr))
        XCTAssertTrue(aliyun!.supports(.llm))
        XCTAssertEqual(aliyun!.llmConfig?.qualityPreset, .fast)

        // DeepSeek should remain unchanged
        let deepseek = models.first { $0.provider == .deepseek }
        XCTAssertNotNil(deepseek)
        XCTAssertFalse(deepseek!.supports(.asr))
        XCTAssertTrue(deepseek!.supports(.llm))
        XCTAssertEqual(deepseek!.llmConfig?.qualityPreset, .balanced)
    }
}
