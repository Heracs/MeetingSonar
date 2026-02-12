//
//  PromptManagerTests.swift
//  MeetingSonarTests
//
//  F-10.0-PromptMgmt: Prompt Management System Tests
//

import Testing
import Foundation
@testable import MeetingSonar

@Suite("PromptManager Tests")
struct PromptManagerTests {

    @Test("Create template")
    func testCreateTemplate() async throws {
        let manager = PromptManager.shared

        // Reset to clean state
        await manager.resetAllData()

        let template = try await manager.createTemplate(
            name: "Test Template",
            description: "Test description",
            content: "Test content",
            category: .llm
        )

        #expect(template.name == "Test Template")
        #expect(template.description == "Test description")
        #expect(template.content == "Test content")
        #expect(template.category == .llm)
        #expect(!template.isSystemTemplate)
    }

    @Test("Create template with empty name throws error")
    func testCreateTemplateWithEmptyName() async throws {
        let manager = PromptManager.shared

        await #expect(throws: PromptManagerError.invalidContent) {
            _ = try await manager.createTemplate(
                name: "",
                content: "Content",
                category: .asr
            )
        }
    }

    @Test("Create template with empty content throws error")
    func testCreateTemplateWithEmptyContent() async throws {
        let manager = PromptManager.shared

        await #expect(throws: PromptManagerError.invalidContent) {
            _ = try await manager.createTemplate(
                name: "Name",
                content: "",
                category: .asr
            )
        }
    }

    @Test("Update template")
    func testUpdateTemplate() async throws {
        let manager = PromptManager.shared
        await manager.resetAllData()

        let template = try await manager.createTemplate(
            name: "Original Name",
            content: "Original content",
            category: .llm
        )

        var updatedTemplate = template
        updatedTemplate.name = "Updated Name"
        updatedTemplate.content = "Updated content"

        try await manager.updateTemplate(updatedTemplate)

        let retrieved = await manager.getTemplate(byId: template.id)
        #expect(retrieved?.name == "Updated Name")
        #expect(retrieved?.content == "Updated content")
    }

    @Test("System template cannot be deleted")
    func testSystemTemplateCannotBeDeleted() async throws {
        let manager = PromptManager.shared

        // ✅ 修复: 确保系统模板已加载后再测试
        // 先加载确保有默认模板
        let templates = await manager.getTemplates(for: .asr)

        // 确保有系统模板
        guard !templates.isEmpty else {
            // 如果没有模板，先重置并等待
            await manager.resetAllData()
        }

        // 重新获取模板
        let updatedTemplates = await manager.getTemplates(for: .asr)
        guard let systemTemplate = updatedTemplates.first(where: { $0.isSystemTemplate }) else {
            Issue.record("System template not found after reset")
            return
        }

        await #expect(throws: PromptManagerError.systemTemplateCannotBeDeleted) {
            try await manager.deleteTemplate(id: systemTemplate.id)
        }
    }

    @Test("Duplicate template")
    func testDuplicateTemplate() async throws {
        let manager = PromptManager.shared
        await manager.resetAllData()

        let original = try await manager.createTemplate(
            name: "Original",
            content: "Content",
            category: .llm
        )

        let duplicate = try await manager.duplicateTemplate(id: original.id)

        #expect(duplicate.name.contains("Original"))
        #expect(duplicate.content == original.content)
        #expect(duplicate.id != original.id)
        #expect(!duplicate.isSystemTemplate)
    }

    @Test("Get templates by category")
    func testGetTemplatesByCategory() async throws {
        let manager = PromptManager.shared
        await manager.resetAllData()

        // Create ASR template
        _ = try await manager.createTemplate(
            name: "ASR Template",
            content: "ASR content",
            category: .asr
        )

        // Create LLM template
        _ = try await manager.createTemplate(
            name: "LLM Template",
            content: "LLM content",
            category: .llm
        )

        let asrTemplates = await manager.getTemplates(for: .asr)
        let llmTemplates = await manager.getTemplates(for: .llm)

        #expect(asrTemplates.count >= 1)
        #expect(llmTemplates.count >= 1)
    }

    @Test("Get selected prompt content")
    func testGetSelectedPromptContent() async throws {
        let manager = PromptManager.shared
        await manager.resetAllData()

        let content = await manager.getSelectedPromptContent(for: .asr)
        #expect(!content.isEmpty) // Should return default template content
    }

    @Test("Set default template")
    func testSetDefaultTemplate() async throws {
        let manager = PromptManager.shared
        await manager.resetAllData()

        // Create a new template
        let template = try await manager.createTemplate(
            name: "New Default",
            content: "New default content",
            category: .llm
        )

        // Set it as default
        try await manager.setDefaultTemplate(id: template.id, for: .llm)

        // Verify it was set
        let selectedId = await MainActor.run {
            SettingsManager.shared.selectedLLMPromptId
        }
        #expect(selectedId == template.id.uuidString)
    }

    @Test("Delete non-default template")
    func testDeleteNonDefaultTemplate() async throws {
        let manager = PromptManager.shared
        await manager.resetAllData()

        let template = try await manager.createTemplate(
            name: "To Delete",
            content: "Content",
            category: .llm
        )

        // Verify template exists
        let beforeDelete = await manager.getTemplate(byId: template.id)
        #expect(beforeDelete != nil)

        // Delete the template
        try await manager.deleteTemplate(id: template.id)

        // Verify template no longer exists
        let afterDelete = await manager.getTemplate(byId: template.id)
        #expect(afterDelete == nil)
    }
}
