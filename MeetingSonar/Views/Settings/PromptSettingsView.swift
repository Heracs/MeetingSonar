//
//  PromptSettingsView.swift
//  MeetingSonar
//
//  F-10.0-PromptMgmt: Prompt Management System
//  Settings UI for managing ASR and LLM prompt templates
//

import SwiftUI

@available(macOS 13.0, *)
struct PromptSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var templates: [PromptTemplate] = []
    @State private var editingTemplate: PromptTemplate? = nil
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var templateToDelete: PromptTemplate? = nil
    @State private var errorMessage: String? = nil
    @State private var showError = false

    /// 系统模板（按类别排序）
    private var systemTemplates: [PromptTemplate] {
        templates.filter { $0.isSystemTemplate }
            .sorted { $0.category.rawValue < $1.category.rawValue }
    }

    /// 用户模板（按更新时间倒序）
    private var userTemplates: [PromptTemplate] {
        templates.filter { !$0.isSystemTemplate }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView

                Divider()

                if templates.isEmpty {
                    emptyStateView
                } else {
                    unifiedTemplateListView
                }
            }
            .navigationTitle("提示词管理")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        editingTemplate = nil
                        showEditor = true
                    }) {
                        Label("新建模板", systemImage: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 350)
        .sheet(item: $editingTemplate) { template in
            PromptEditorSheet(
                template: template,
                isNew: false,
                isSystemTemplate: template.isSystemTemplate,
                onSave: { updateTemplate($0) },
                onDelete: !template.isSystemTemplate ? {
                    templateToDelete = template
                    showDeleteConfirm = true
                } : nil,
                onDuplicate: !template.isSystemTemplate ? {
                    duplicateTemplate(template)
                } : nil
            )
        }
        .sheet(isPresented: $showEditor) {
            PromptEditorSheet(
                template: PromptTemplate(
                    name: "",
                    content: "",
                    category: .asr
                ),
                isNew: true,
                isSystemTemplate: false,
                onSave: { createTemplate($0) },
                onDelete: nil,
                onDuplicate: nil
            )
        }
        .alert("确认删除?", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { templateToDelete = nil }
            Button("删除", role: .destructive) {
                if let template = templateToDelete {
                    deleteTemplate(template)
                }
            }
        } message: {
            Text("确定要删除提示词模板「\(templateToDelete?.name ?? "")」吗?")
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .onAppear {
            loadTemplates()
        }
        .onReceive(NotificationCenter.default.publisher(for: PromptManager.templatesDidChange)) { _ in
            loadTemplates()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("自定义语音识别和内容总结的提示词模板")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("暂无提示词模板")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("点击右上角按钮创建新模板")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Unified Template List

    private var unifiedTemplateListView: some View {
        List {
            // 系统预设分组
            if !systemTemplates.isEmpty {
                Section {
                    ForEach(systemTemplates) { template in
                        SystemTemplateRow(
                            template: template,
                            isSelected: isTemplateSelected(template)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingTemplate = template
                        }
                    }
                } header: {
                    HStack {
                        Text("系统预设")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(systemTemplates.count) 个")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            }

            // 我的模板分组
            if !userTemplates.isEmpty {
                Section {
                    ForEach(userTemplates) { template in
                        UserTemplateRow(
                            template: template,
                            isSelected: isTemplateSelected(template)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingTemplate = template
                        }
                    }
                } header: {
                    HStack {
                        Text("我的模板")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(userTemplates.count) 个")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Helper Methods

    private func isTemplateSelected(_ template: PromptTemplate) -> Bool {
        let selectedId: String
        switch template.category {
        case .asr:
            selectedId = SettingsManager.shared.selectedASRPromptId
        case .llm:
            selectedId = SettingsManager.shared.selectedLLMPromptId
        }
        return template.id.uuidString == selectedId
    }

    // MARK: - Actions

    private func loadTemplates() {
        Task {
            let allTemplates = await PromptManager.shared.templates
            await MainActor.run {
                self.templates = allTemplates
            }
        }
    }

    private func createTemplate(_ template: PromptTemplate) {
        Task {
            do {
                try await PromptManager.shared.createTemplate(
                    name: template.name,
                    description: template.description,
                    content: template.content,
                    category: template.category
                )
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func updateTemplate(_ template: PromptTemplate) {
        Task {
            do {
                try await PromptManager.shared.updateTemplate(template)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func deleteTemplate(_ template: PromptTemplate) {
        Task {
            do {
                try await PromptManager.shared.deleteTemplate(id: template.id)
                await MainActor.run {
                    templateToDelete = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    templateToDelete = nil
                }
            }
        }
    }

    private func duplicateTemplate(_ template: PromptTemplate) {
        Task {
            do {
                _ = try await PromptManager.shared.duplicateTemplate(id: template.id)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - System Template Row (不可编辑)

@available(macOS 13.0, *)
struct SystemTemplateRow: View {
    let template: PromptTemplate
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 锁图标表示系统模板
            Image(systemName: "lock.fill")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(width: 20)

            // 模板信息
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    // 类别标签 - 灰色字体
                    Text("· \(template.category.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }

                if !template.description.isEmpty {
                    Text(template.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 系统标签
            Text("系统")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)

            // 查看指示器
            Image(systemName: "eye")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - User Template Row (可编辑)

@available(macOS 13.0, *)
struct UserTemplateRow: View {
    let template: PromptTemplate
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 选择指示器
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .font(.title3)
                .frame(width: 20)

            // 模板信息
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(.body)
                        .fontWeight(.medium)

                    // 类别标签 - 灰色字体
                    Text("· \(template.category.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !template.description.isEmpty {
                    Text(template.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 编辑指示器
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

@available(macOS 13.0, *)
struct PromptSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        PromptSettingsView()
    }
}
