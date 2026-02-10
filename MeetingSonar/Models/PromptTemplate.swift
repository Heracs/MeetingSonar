//
//  PromptTemplate.swift
//  MeetingSonar
//
//  F-10.0-PromptMgmt: Prompt Management System
//  Data models for ASR and LLM prompt templates
//

import Foundation

/// 提示词分类
enum PromptCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case asr = "asr"
    case llm = "llm"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .asr:
            return String(localized: "prompt.category.asr", defaultValue: "语音识别")
        case .llm:
            return String(localized: "prompt.category.llm", defaultValue: "内容总结")
        }
    }

    var icon: String {
        switch self {
        case .asr:
            return "waveform"
        case .llm:
            return "text.bubble"
        }
    }

    var description: String {
        switch self {
        case .asr:
            return String(localized: "prompt.category.asr.desc", defaultValue: "用于语音转文字的提示词")
        case .llm:
            return String(localized: "prompt.category.llm.desc", defaultValue: "用于生成内容总结的提示词")
        }
    }
}

/// 提示词模板
/// 用于 ASR 和 LLM 的自定义提示词配置
struct PromptTemplate: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var description: String
    var content: String
    var category: PromptCategory
    /// 是否为系统预设模板（不可编辑、不可删除）
    var isSystemTemplate: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        content: String,
        category: PromptCategory,
        isSystemTemplate: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.content = content
        self.category = category
        self.isSystemTemplate = isSystemTemplate
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// 创建副本，自动修改名称
    func duplicated() -> PromptTemplate {
        PromptTemplate(
            name: "\(name) \(String(localized: "prompt.duplicate.suffix", defaultValue: "副本"))",
            description: description,
            content: content,
            category: category,
            isSystemTemplate: false
        )
    }
}

// MARK: - Errors

enum PromptManagerError: LocalizedError, Equatable {
    case templateNotFound
    case invalidContent
    case persistenceFailed(Error)
    case systemTemplateCannotBeDeleted
    case systemTemplateCannotBeModified

    var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return String(localized: "error.prompt.not_found", defaultValue: "提示词模板不存在")
        case .invalidContent:
            return String(localized: "error.prompt.invalid_content", defaultValue: "提示词内容无效")
        case .persistenceFailed(let error):
            return String(localized: "error.prompt.persistence_failed", defaultValue: "保存失败: \(error.localizedDescription)")
        case .systemTemplateCannotBeDeleted:
            return String(localized: "error.prompt.system_cannot_delete", defaultValue: "系统预设模板不能删除")
        case .systemTemplateCannotBeModified:
            return String(localized: "error.prompt.system_cannot_modify", defaultValue: "系统预设模板不能修改")
        }
    }

    // MARK: - Equatable
    // Manual implementation because persistenceFailed(Error) contains non-Equatable Error type
    static func == (lhs: PromptManagerError, rhs: PromptManagerError) -> Bool {
        switch (lhs, rhs) {
        case (.templateNotFound, .templateNotFound),
             (.invalidContent, .invalidContent),
             (.systemTemplateCannotBeDeleted, .systemTemplateCannotBeDeleted),
             (.systemTemplateCannotBeModified, .systemTemplateCannotBeModified):
            return true
        case (.persistenceFailed, .persistenceFailed):
            // Compare by localized description as a best-effort comparison
            return lhs.errorDescription == rhs.errorDescription
        default:
            return false
        }
    }
}
