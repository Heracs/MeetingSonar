//
//  PromptManager.swift
//  MeetingSonar
//
//  F-10.0-PromptMgmt: Prompt Management System
//  Manages prompt templates for ASR and LLM with thread-safe operations
//

import Foundation
import OSLog

/// 提示词管理器
/// 使用 actor 模式保证线程安全
actor PromptManager {
    static let shared = PromptManager()

    private let logger = Logger(subsystem: "com.meetingsonar", category: "PromptManager")

    // MARK: - Storage Keys

    private enum Keys {
        static let templates = "promptTemplates_v1"
    }

    // MARK: - Storage Paths

    private enum StoragePaths {
        static var promptsDirectory: URL {
            PathManager.shared.rootDataURL.appendingPathComponent("Prompts", isDirectory: true)
        }

        static var promptsFile: URL {
            promptsDirectory.appendingPathComponent("prompts.json")
        }
    }

    // MARK: - Notification Names

    static let templatesDidChange = Notification.Name("PromptTemplatesDidChange")

    // MARK: - Published State

    /// 所有提示词模板
    private(set) var templates: [PromptTemplate] = []

    // MARK: - Initialization

    private init() {
        Task {
            await loadTemplates()
            // Notify that initialization is complete
            await notifyChange()
        }
    }

    // MARK: - CRUD Operations

    /// 创建新模板
    /// - Parameters:
    ///   - name: 模板名称
    ///   - description: 模板描述
    ///   - content: 提示词内容
    ///   - category: 分类 (ASR/LLM)
    /// - Returns: 创建的模板
    func createTemplate(
        name: String,
        description: String = "",
        content: String,
        category: PromptCategory
    ) async throws -> PromptTemplate {
        // 验证输入
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PromptManagerError.invalidContent
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PromptManagerError.invalidContent
        }

        let template = PromptTemplate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category
        )

        templates.append(template)
        try await saveTemplates()
        await notifyChange()

        logger.info("Created prompt template: \(template.name) (\(template.id))")
        return template
    }

    /// 更新模板
    /// - Parameter template: 要更新的模板
    func updateTemplate(_ template: PromptTemplate) async throws {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else {
            throw PromptManagerError.templateNotFound
        }

        let existingTemplate = templates[index]

        // 系统模板完全禁止修改
        guard !existingTemplate.isSystemTemplate else {
            throw PromptManagerError.systemTemplateCannotBeModified
        }

        // 验证输入
        let trimmedName = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = template.content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw PromptManagerError.invalidContent
        }

        guard !trimmedContent.isEmpty else {
            throw PromptManagerError.invalidContent
        }

        var updatedTemplate = template
        updatedTemplate.name = trimmedName
        updatedTemplate.description = template.description.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedTemplate.content = trimmedContent
        updatedTemplate.updatedAt = Date()

        templates[index] = updatedTemplate
        try await saveTemplates()
        await notifyChange()

        logger.info("Updated prompt template: \(updatedTemplate.name)")
    }

    /// 删除模板
    /// - Parameter id: 模板 ID
    func deleteTemplate(id: UUID) async throws {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            throw PromptManagerError.templateNotFound
        }

        let template = templates[index]

        // 系统预设模板不能删除
        guard !template.isSystemTemplate else {
            throw PromptManagerError.systemTemplateCannotBeDeleted
        }

        templates.remove(at: index)
        try await saveTemplates()
        await notifyChange()

        logger.info("Deleted prompt template: \(template.name)")
    }

    /// 复制模板
    /// - Parameter id: 要复制的模板 ID
    /// - Returns: 新创建的副本
    func duplicateTemplate(id: UUID) async throws -> PromptTemplate {
        guard let template = templates.first(where: { $0.id == id }) else {
            throw PromptManagerError.templateNotFound
        }

        let duplicated = template.duplicated()
        templates.append(duplicated)
        try await saveTemplates()
        await notifyChange()

        logger.info("Duplicated prompt template: \(template.name) -> \(duplicated.name)")
        return duplicated
    }

    // MARK: - Query Operations

    /// 获取指定分类的所有模板
    /// - Parameter category: 分类
    /// - Returns: 模板列表
    func getTemplates(for category: PromptCategory) -> [PromptTemplate] {
        templates.filter { $0.category == category }
    }

    /// 通过 ID 获取模板
    /// - Parameter id: 模板 ID
    /// - Returns: 模板，未找到返回 nil
    func getTemplate(byId id: UUID) -> PromptTemplate? {
        templates.first { $0.id == id }
    }

    /// 获取默认模板
    /// - Parameter category: 分类
    /// - Returns: 默认模板，如果没有则返回第一个
    func getDefaultTemplate(for category: PromptCategory) -> PromptTemplate? {
        let categoryTemplates = getTemplates(for: category)
        // 优先返回系统模板，如果没有则返回第一个用户模板
        return categoryTemplates.first { $0.isSystemTemplate } ?? categoryTemplates.first
    }

    /// 获取当前选中的模板
    /// - Parameter category: 分类
    /// - Returns: 选中的模板，如果没有选择则返回默认模板
    func getSelectedTemplate(for category: PromptCategory) async -> PromptTemplate? {
        let selectedId: String = await MainActor.run {
            switch category {
            case .asr:
                return SettingsManager.shared.selectedASRPromptId
            case .llm:
                return SettingsManager.shared.selectedLLMPromptId
            }
        }

        if !selectedId.isEmpty,
           let id = UUID(uuidString: selectedId),
           let template = getTemplate(byId: id),
           template.category == category {
            return template
        }

        // 返回默认模板
        return getDefaultTemplate(for: category)
    }

    /// 获取当前选中模板的内容
    /// - Parameter category: 分类
    /// - Returns: 提示词内容，如果没有则返回空字符串
    func getSelectedPromptContent(for category: PromptCategory) async -> String {
        await getSelectedTemplate(for: category)?.content ?? ""
    }

    // MARK: - Default Template Management

    /// 设置默认模板
    /// - Parameters:
    ///   - id: 模板 ID
    ///   - category: 分类
    func setDefaultTemplate(id: UUID, for category: PromptCategory) async throws {
        guard let template = templates.first(where: { $0.id == id }) else {
            throw PromptManagerError.templateNotFound
        }

        guard template.category == category else {
            throw PromptManagerError.invalidContent
        }

        // 更新 UserDefaults
        await MainActor.run {
            switch category {
            case .asr:
                SettingsManager.shared.selectedASRPromptId = id.uuidString
            case .llm:
                SettingsManager.shared.selectedLLMPromptId = id.uuidString
            }
        }

        logger.info("Set default template for \(category.rawValue): \(template.name)")
    }

    // MARK: - Persistence

    /// 确保存储目录存在
    private func ensureStorageDirectory() throws {
        let fileManager = FileManager.default
        let directory = StoragePaths.promptsDirectory

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            logger.info("Created prompts directory: \(directory.path)")
        }
    }

    /// 加载模板
    private func loadTemplates() async {
        let fileManager = FileManager.default
        let fileURL = StoragePaths.promptsFile

        guard fileManager.fileExists(atPath: fileURL.path) else {
            logger.info("No prompts file found, creating default templates")
            await createDefaultTemplates()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode([PromptTemplate].self, from: data)
            templates = loaded
            logger.info("Loaded \(self.templates.count) prompt templates")
        } catch {
            logger.error("Failed to load templates: \(error.localizedDescription)")
            // 加载失败时创建默认模板
            await createDefaultTemplates()
        }
    }

    /// 保存模板
    private func saveTemplates() async throws {
        try ensureStorageDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(templates)

        try data.write(to: StoragePaths.promptsFile, options: .atomic)
        logger.info("Saved \(self.templates.count) prompt templates")
    }

    /// 通知 UI 更新
    private func notifyChange() async {
        await MainActor.run {
            NotificationCenter.default.post(name: Self.templatesDidChange, object: nil)
        }
    }

    // MARK: - Default Templates

    /// 创建默认模板
    private func createDefaultTemplates() async {
        logger.info("Creating default prompt templates")

        let asrTemplate = PromptTemplate(
            name: String(localized: "prompt.system.asr.name", defaultValue: "标准转录"),
            description: String(localized: "prompt.system.asr.desc", defaultValue: "适用于一般会议的标准转录提示词"),
            content: """
            请将以下会议录音转录为文本。要求：
            1. 使用简体中文
            2. 区分不同说话人
            3. 过滤语气词和重复词
            4. 保持时间戳信息
            """,
            category: .asr,
            isSystemTemplate: true
        )

        let llmTemplate = PromptTemplate(
            name: String(localized: "prompt.system.llm.name", defaultValue: "标准内容总结"),
            description: String(localized: "prompt.system.llm.desc", defaultValue: "生成包含关键讨论点和行动项的标准内容总结"),
            content: """
            请根据以下会议转录文本生成内容总结。要求：
            1. 会议主题和参与人员
            2. 关键讨论点（分点列出）
            3. 达成的共识和决策
            4. 行动项（责任人 + 截止日期）
            5. 使用 Markdown 格式输出
            """,
            category: .llm,
            isSystemTemplate: true
        )

        templates = [asrTemplate, llmTemplate]

        do {
            try await saveTemplates()
            await notifyChange()
            logger.info("Created \(self.templates.count) default templates")
        } catch {
            logger.error("Failed to save default templates: \(error.localizedDescription)")
        }
    }

    // MARK: - Reset (Debug)

    /// 重置所有数据（调试用）
    func resetAllData() async {
        templates = []
        await MainActor.run {
            SettingsManager.shared.selectedASRPromptId = ""
            SettingsManager.shared.selectedLLMPromptId = ""
        }

        // 删除存储文件
        let fileManager = FileManager.default
        let fileURL = StoragePaths.promptsFile
        try? fileManager.removeItem(at: fileURL)

        // 重新创建默认模板
        await createDefaultTemplates()

        logger.info("All prompt data reset")
    }
}
