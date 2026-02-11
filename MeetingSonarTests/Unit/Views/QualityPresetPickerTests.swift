//
//  QualityPresetPickerTests.swift
//  MeetingSonarTests
//
//  Swift Testing framework tests for QualityPresetPicker
//  Tests: Preset selection, advanced settings button, state management
//

import Testing
import Foundation
@testable import MeetingSonar

/// Tests for QualityPresetPicker component
@Suite("QualityPresetPicker Tests")
@MainActor
struct QualityPresetPickerTests {

    // MARK: - LLMQualityPreset Tests

    @Test("All quality presets have valid display names")
    func testQualityPresetDisplayNames() {
        #expect(LLMQualityPreset.fast.displayName == "快速")
        #expect(LLMQualityPreset.balanced.displayName == "平衡")
        #expect(LLMQualityPreset.quality.displayName == "高质量")
    }

    @Test("All quality presets have valid descriptions")
    func testQualityPresetDescriptions() {
        #expect(LLMQualityPreset.fast.description == "响应快，摘要简洁")
        #expect(LLMQualityPreset.balanced.description == "速度与质量兼顾")
        #expect(LLMQualityPreset.quality.description == "详细摘要，响应较慢")
    }

    @Test("All quality presets have valid icons")
    func testQualityPresetIcons() {
        #expect(LLMQualityPreset.fast.icon == "bolt.fill")
        #expect(LLMQualityPreset.balanced.icon == "scale.3d")
        #expect(LLMQualityPreset.quality.icon == "wand.and.stars")
    }

    @Test("Quality preset recommended parameters are valid")
    func testQualityPresetParameters() {
        let fastParams = LLMQualityPreset.fast.recommendedParameters
        #expect(fastParams.temperature == 0.3)
        #expect(fastParams.maxTokens == 16384)

        let balancedParams = LLMQualityPreset.balanced.recommendedParameters
        #expect(balancedParams.temperature == 0.7)
        #expect(balancedParams.maxTokens == 32768)

        let qualityParams = LLMQualityPreset.quality.recommendedParameters
        #expect(qualityParams.temperature == 0.9)
        #expect(qualityParams.maxTokens == 65536)
    }

    @Test("All quality presets are identifiable")
    func testQualityPresetIdentifiable() {
        let presets = LLMQualityPreset.allCases
        #expect(presets.count == 3)

        let ids = presets.map { $0.id }
        #expect(ids.count == Set(ids).count) // All IDs are unique
    }

    @Test("Quality preset raw values are correct")
    func testQualityPresetRawValues() {
        #expect(LLMQualityPreset.fast.rawValue == "fast")
        #expect(LLMQualityPreset.balanced.rawValue == "balanced")
        #expect(LLMQualityPreset.quality.rawValue == "quality")
    }

    // MARK: - LLMQualityPreset Extension Tests

    @Test("Quality preset SwiftUI colors are correct")
    func testQualityPresetColors() {
        // Note: We can't directly compare Color instances, but we can verify they exist
        let fastColor = LLMQualityPreset.fast.swiftUIColor
        let balancedColor = LLMQualityPreset.balanced.swiftUIColor
        let qualityColor = LLMQualityPreset.quality.swiftUIColor

        // Just verify they don't crash and are different instances
        #expect(fastColor != balancedColor || balancedColor != qualityColor)
    }

    @Test("Quality preset description includes temperature")
    func testQualityPresetDescriptionWithTemperature() {
        let fastDesc = LLMQualityPreset.fast.descriptionWithRecommendation
        #expect(fastDesc.contains("0.3"))

        let balancedDesc = LLMQualityPreset.balanced.descriptionWithRecommendation
        #expect(balancedDesc.contains("0.7"))

        let qualityDesc = LLMQualityPreset.quality.descriptionWithRecommendation
        #expect(qualityDesc.contains("0.9"))
    }

    // MARK: - LLMModelSettings Tests

    @Test("LLMModelSettings default values are correct")
    func testLLMModelSettingsDefaults() {
        let settings = LLMModelSettings.default

        #expect(settings.modelName == "deepseek-reasoner")
        #expect(settings.qualityPreset == .balanced)
        #expect(settings.temperature == nil)
        #expect(settings.maxTokens == nil)
        #expect(settings.topP == nil)
        #expect(settings.enableStreaming == nil)
    }

    @Test("LLMModelSettings apiRequestParameters only includes configured values")
    func testApiRequestParametersFiltering() {
        // Settings with no optional parameters
        let emptySettings = LLMModelSettings(
            modelName: "test",
            qualityPreset: .balanced
        )
        let emptyParams = emptySettings.apiRequestParameters()
        #expect(emptyParams.isEmpty)

        // Settings with some parameters
        let partialSettings = LLMModelSettings(
            modelName: "test",
            qualityPreset: .balanced,
            temperature: 0.8,
            maxTokens: nil, // Not included
            topP: 0.9
        )
        let partialParams = partialSettings.apiRequestParameters()
        #expect(partialParams["temperature"] as? Double == 0.8)
        #expect(partialParams["top_p"] as? Double == 0.9)
        #expect(partialParams["max_tokens"] == nil)
    }

    @Test("LLMModelSettings resolvedParameters uses recommended values")
    func testResolvedParameters() {
        let settings = LLMModelSettings(
            modelName: "test",
            qualityPreset: .fast,
            temperature: nil, // Should use recommended
            maxTokens: nil,   // Should use recommended
            topP: nil         // Should use default 1.0
        )

        let resolved = settings.resolvedParameters()
        #expect(resolved.temperature == 0.3) // Fast preset recommendation
        #expect(resolved.maxTokens == 16384) // Fast preset recommendation
        #expect(resolved.topP == 1.0)
    }

    @Test("LLMModelSettings resolvedParameters uses explicit values over recommended")
    func testResolvedParametersWithExplicitValues() {
        let settings = LLMModelSettings(
            modelName: "test",
            qualityPreset: .fast,
            temperature: 0.5, // Explicit override
            maxTokens: 8192,  // Explicit override
            topP: 0.95        // Explicit override
        )

        let resolved = settings.resolvedParameters()
        #expect(resolved.temperature == 0.5) // Not the recommended 0.3
        #expect(resolved.maxTokens == 8192)  // Not the recommended 16384
        #expect(resolved.topP == 0.95)
    }

    // MARK: - CloudAIModelConfig Tests

    @Test("CloudAIModelConfig supports capability check")
    func testCloudAIModelConfigCapabilityCheck() {
        let asrOnlyConfig = CloudAIModelConfig.default(for: .zhipu, capabilities: [.asr])
        #expect(asrOnlyConfig.supports(.asr))
        #expect(!asrOnlyConfig.supports(.llm))

        let llmOnlyConfig = CloudAIModelConfig.default(for: .deepseek, capabilities: [.llm])
        #expect(!llmOnlyConfig.supports(.asr))
        #expect(llmOnlyConfig.supports(.llm))

        let bothConfig = CloudAIModelConfig.default(for: .zhipu, capabilities: [.asr, .llm])
        #expect(bothConfig.supports(.asr))
        #expect(bothConfig.supports(.llm))
    }

    @Test("CloudAIModelConfig defaultLLMConfig creates valid config")
    func testDefaultLLMConfig() {
        let config = CloudAIModelConfig.defaultLLMConfig()

        #expect(config.supports(.llm))
        #expect(!config.supports(.asr))
        #expect(config.provider == .deepseek)
        #expect(config.llmConfig?.qualityPreset == .balanced)
    }

    @Test("CloudAIModelConfig default for provider filters invalid capabilities")
    func testDefaultFiltersInvalidCapabilities() {
        // DeepSeek doesn't support ASR, so ASR capability should be filtered out
        let deepseekConfig = CloudAIModelConfig.default(for: .deepseek, capabilities: [.asr, .llm])
        #expect(!deepseekConfig.supports(.asr))
        #expect(deepseekConfig.supports(.llm))

        // Zhipu supports both
        let zhipuConfig = CloudAIModelConfig.default(for: .zhipu, capabilities: [.asr, .llm])
        #expect(zhipuConfig.supports(.asr))
        #expect(zhipuConfig.supports(.llm))
    }

    // MARK: - ModelCapability Tests

    @Test("ModelCapability display names are correct")
    func testModelCapabilityDisplayNames() {
        #expect(ModelCapability.asr.displayName == "语音识别")
        #expect(ModelCapability.llm.displayName == "文本生成")
    }

    @Test("ModelCapability icons are correct")
    func testModelCapabilityIcons() {
        #expect(ModelCapability.asr.icon == "waveform")
        #expect(ModelCapability.llm.icon == "text.bubble")
    }

    @Test("All model capabilities are identifiable")
    func testModelCapabilityIdentifiable() {
        let capabilities = ModelCapability.allCases
        #expect(capabilities.count == 2)

        let ids = capabilities.map { $0.id }
        #expect(ids.count == Set(ids).count)
    }

    // MARK: - Integration Tests

    @Test("Quality preset selection flow")
    func testQualityPresetSelectionFlow() async {
        // Simulate the selection flow
        var selectedPreset: LLMQualityPreset = .balanced

        // User selects fast
        selectedPreset = .fast
        #expect(selectedPreset == .fast)

        // User selects quality
        selectedPreset = .quality
        #expect(selectedPreset == .quality)

        // User goes back to balanced
        selectedPreset = .balanced
        #expect(selectedPreset == .balanced)
    }

    @Test("Quality preset affects model settings")
    func testQualityPresetAffectsModelSettings() {
        let presets: [LLMQualityPreset] = [.fast, .balanced, .quality]

        for preset in presets {
            let settings = LLMModelSettings(
                modelName: "test-model",
                qualityPreset: preset
            )

            let resolved = settings.resolvedParameters()
            let recommended = preset.recommendedParameters

            #expect(resolved.temperature == recommended.temperature)
            #expect(resolved.maxTokens == recommended.maxTokens)
        }
    }

    @Test("CloudAIModelConfig with different quality presets")
    func testCloudAIConfigWithDifferentPresets() {
        for preset in LLMQualityPreset.allCases {
            let config = CloudAIModelConfig(
                displayName: "Test \(preset.displayName)",
                provider: .deepseek,
                baseURL: "https://api.test.com",
                capabilities: [.llm],
                asrConfig: nil,
                llmConfig: LLMModelSettings(
                    modelName: "test-model",
                    qualityPreset: preset
                ),
                isVerified: true
            )

            #expect(config.llmConfig?.qualityPreset == preset)
        }
    }
}
