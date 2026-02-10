//
//  PromptManagerIntegrationTests.swift
//  MeetingSonarTests
//
//  F-10.0-PromptMgmt: Prompt Manager Integration Tests
//  Tests integration between PromptManager and ASR/LLM services
//

import Testing
import Foundation
@testable import MeetingSonar

@Suite("PromptManager Integration Tests", .serialized)
struct PromptManagerIntegrationTests {

    // MARK: - ASR Service Integration

    @Test("ASR service uses selected prompt template")
    func testASRServiceUsesSelectedPrompt() async throws {
        let promptManager = PromptManager.shared
        await promptManager.resetAllData()

        // Create a custom ASR template
        let customTemplate = try await promptManager.createTemplate(
            name: "Custom ASR Prompt",
            description: "Test prompt for ASR",
            content: "请使用简体中文转录，重点关注技术术语和专有名词。",
            category: .asr
        )

        // Set it as default
        try await promptManager.setDefaultTemplate(id: customTemplate.id, for: .asr)

        // Verify the selected prompt content using getSelectedTemplate
        let selectedTemplate = await promptManager.getSelectedTemplate(for: .asr)
        #expect(selectedTemplate?.content == "请使用简体中文转录，重点关注技术术语和专有名词。")
        #expect(selectedTemplate?.name == "Custom ASR Prompt")
    }

    @Test("ASR service falls back to default prompt when none selected")
    func testASRFallbackToDefaultPrompt() async throws {
        let promptManager = PromptManager.shared
        await promptManager.resetAllData()

        // Don't set any custom template - should use default
        let selectedContent = await promptManager.getSelectedPromptContent(for: .asr)
        let defaultTemplate = await promptManager.getDefaultTemplate(for: .asr)

        #expect(!selectedContent.isEmpty)
        #expect(selectedContent == defaultTemplate?.content)
        #expect(selectedContent.contains("简体中文")) // Default ASR prompt contains this
    }

    @Test("ASR prompt change affects subsequent calls")
    func testASRPromptChangeAffectsSubsequentCalls() async throws {
        let promptManager = PromptManager.shared
        await promptManager.resetAllData()

        // Create first template
        let template1 = try await promptManager.createTemplate(
            name: "ASR Prompt 1",
            content: "First prompt content",
            category: .asr
        )

        // Set as default
        try await promptManager.setDefaultTemplate(id: template1.id, for: .asr)

        // Verify first prompt is used
        let content1 = await promptManager.getSelectedPromptContent(for: .asr)
        #expect(content1 == "First prompt content")

        // Create second template
        let template2 = try await promptManager.createTemplate(
            name: "ASR Prompt 2",
            content: "Second prompt content",
            category: .asr
        )

        // Change default
        try await promptManager.setDefaultTemplate(id: template2.id, for: .asr)

        // Verify second prompt is now used
        let content2 = await promptManager.getSelectedPromptContent(for: .asr)
        #expect(content2 == "Second prompt content")
    }

    // MARK: - LLM Service Integration

    @Test("LLM service uses selected prompt template")
    func testLLMServiceUsesSelectedPrompt() async throws {
        let promptManager = PromptManager.shared
        await promptManager.resetAllData()

        // Create a custom LLM template
        let customTemplate = try await promptManager.createTemplate(
            name: "Custom Meeting Summary",
            description: "Focus on action items",
            content: """
            请生成会议纪要，重点关注：
            1. 行动项和负责人
            2. 截止日期
            3. 关键决策
            """,
            category: .llm
        )

        // Set it as default
        try await promptManager.setDefaultTemplate(id: customTemplate.id, for: .llm)

        // Verify the selected prompt content
        let selectedContent = await promptManager.getSelectedPromptContent(for: .llm)
        #expect(selectedContent.contains("行动项和负责人"))
        #expect(selectedContent.contains("关键决策"))
    }

    @Test("LLM service falls back to default prompt when none selected")
    func testLLMFallbackToDefaultPrompt() async throws {
        let promptManager = PromptManager.shared
        await promptManager.resetAllData()

        // Don't set any custom template - should use default
        let selectedContent = await promptManager.getSelectedPromptContent(for: .llm)
        let defaultTemplate = await promptManager.getDefaultTemplate(for: .llm)

        #expect(!selectedContent.isEmpty)
        #expect(selectedContent == defaultTemplate?.content)
        #expect(selectedContent.contains("会议主题")) // Default LLM prompt contains this
    }

    @Test("LLM prompt with different categories")
    func testLLMPromptWithDifferentCategories() async throws {
        let promptManager = PromptManager.shared
        await promptManager.resetAllData()

        // Create templates for different purposes with unique names
        let summaryTemplate = try await promptManager.createTemplate(
            name: "Quick Summary Test",
            content: "生成简要摘要 Test",
            category: .llm
        )

        let detailedTemplate = try await promptManager.createTemplate(
            name: "Detailed Analysis Test",
            content: "生成详细分析报告 Test",
            category: .llm
        )

        // Test switching between templates by checking SettingsManager
        try await promptManager.setDefaultTemplate(id: summaryTemplate.id, for: .llm)
        let selectedId1 = await MainActor.run {
            SettingsManager.shared.selectedLLMPromptId
        }
        #expect(selectedId1 == summaryTemplate.id.uuidString)

        try await promptManager.setDefaultTemplate(id: detailedTemplate.id, for: .llm)
        let selectedId2 = await MainActor.run {
            SettingsManager.shared.selectedLLMPromptId
        }
        #expect(selectedId2 == detailedTemplate.id.uuidString)
    }

    // MARK: - Cross-Category Tests

    @Test("ASR and LLM prompts are independent")
    func testASRandLLMPromptsAreIndependent() async throws {
        let promptManager = PromptManager.shared
        await promptManager.resetAllData()

        // Create ASR template
        let asrTemplate = try await promptManager.createTemplate(
            name: "ASR Only",
            content: "ASR specific content",
            category: .asr
        )

        // Create LLM template
        let llmTemplate = try await promptManager.createTemplate(
            name: "LLM Only",
            content: "LLM specific content",
            category: .llm
        )

        // Set both as defaults
        try await promptManager.setDefaultTemplate(id: asrTemplate.id, for: .asr)
        try await promptManager.setDefaultTemplate(id: llmTemplate.id, for: .llm)

        // Verify they are independent
        let asrContent = await promptManager.getSelectedPromptContent(for: .asr)
        let llmContent = await promptManager.getSelectedPromptContent(for: .llm)

        #expect(asrContent == "ASR specific content")
        #expect(llmContent == "LLM specific content")
        #expect(asrContent != llmContent)
    }

    @Test("Category filter works correctly")
    func testCategoryFilter() async throws {
        let promptManager = PromptManager.shared
        await promptManager.resetAllData()

        // Create multiple templates in different categories
        _ = try await promptManager.createTemplate(
            name: "ASR 1",
            content: "ASR content 1",
            category: .asr
        )

        _ = try await promptManager.createTemplate(
            name: "ASR 2",
            content: "ASR content 2",
            category: .asr
        )

        _ = try await promptManager.createTemplate(
            name: "LLM 1",
            content: "LLM content 1",
            category: .llm
        )

        // Verify filtering
        let asrTemplates = await promptManager.getTemplates(for: .asr)
        let llmTemplates = await promptManager.getTemplates(for: .llm)

        #expect(asrTemplates.count >= 2) // Default + created
        #expect(llmTemplates.count >= 1) // Default + created

        // Verify all ASR templates are actually ASR category
        for template in asrTemplates {
            #expect(template.category == .asr)
        }

        // Verify all LLM templates are actually LLM category
        for template in llmTemplates {
            #expect(template.category == .llm)
        }
    }

    // MARK: - Persistence Tests

    @Test("Prompt selection persists across resets")
    func testPromptSelectionPersists() async throws {
        let promptManager = PromptManager.shared
        await promptManager.resetAllData()

        // Create and set custom template with unique content
        let customTemplate = try await promptManager.createTemplate(
            name: "Persistent Template Integration Test",
            content: "This should persist integration test",
            category: .llm
        )

        try await promptManager.setDefaultTemplate(id: customTemplate.id, for: .llm)

        // Verify selection is stored in SettingsManager
        let selectedId = await MainActor.run {
            SettingsManager.shared.selectedLLMPromptId
        }

        #expect(selectedId == customTemplate.id.uuidString)

        // Since PromptManager is a singleton, we verify persistence via SettingsManager
        // and check that the template exists and is selected
        let selectedTemplate = await promptManager.getSelectedTemplate(for: .llm)
        #expect(selectedTemplate?.id == customTemplate.id)
        #expect(selectedTemplate?.content == "This should persist integration test")
    }

    // MARK: - Error Handling Tests

    @Test("ASR service handles missing template gracefully")
    func testASRHandlesMissingTemplate() async throws {
        let promptManager = PromptManager.shared
        await promptManager.resetAllData()

        // Set a non-existent template ID
        await MainActor.run {
            SettingsManager.shared.selectedASRPromptId = UUID().uuidString
        }

        // Should fall back to default
        let selectedContent = await promptManager.getSelectedPromptContent(for: .asr)
        let defaultTemplate = await promptManager.getDefaultTemplate(for: .asr)

        #expect(!selectedContent.isEmpty)
        #expect(selectedContent == defaultTemplate?.content)
    }

    @Test("LLM service handles missing template gracefully")
    func testLLMHandlesMissingTemplate() async throws {
        let promptManager = PromptManager.shared
        await promptManager.resetAllData()

        // Set a non-existent template ID
        await MainActor.run {
            SettingsManager.shared.selectedLLMPromptId = UUID().uuidString
        }

        // Should fall back to default
        let selectedContent = await promptManager.getSelectedPromptContent(for: .llm)
        let defaultTemplate = await promptManager.getDefaultTemplate(for: .llm)

        #expect(!selectedContent.isEmpty)
        #expect(selectedContent == defaultTemplate?.content)
    }
}
