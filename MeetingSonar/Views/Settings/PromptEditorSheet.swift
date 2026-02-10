//
//  PromptEditorSheet.swift
//  MeetingSonar
//
//  F-10.0-PromptMgmt: Prompt Management System
//  Editor sheet for creating and editing prompt templates
//

import SwiftUI

@available(macOS 13.0, *)
struct PromptEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var template: PromptTemplate
    let isNew: Bool
    let isSystemTemplate: Bool
    let onSave: (PromptTemplate) -> Void
    var onDelete: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil

    @State private var content: String = ""
    @State private var showingSetDefaultConfirmation = false

    private var canSave: Bool {
        !template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Basic Info Section
                Section {
                    TextField("名称", text: $template.name)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSystemTemplate)

                    TextField("描述", text: $template.description)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSystemTemplate)

                    // 类型选择 - 新建时可选，编辑时显示但禁用
                    Picker("类型", selection: $template.category) {
                        ForEach(PromptCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                    .disabled(!isNew)
                } header: {
                    Text("基本信息")
                }

                // MARK: - Content Section
                Section {
                    ZStack(alignment: .topLeading) {
                        if content.isEmpty && !isSystemTemplate {
                            Text("在此输入提示词内容...")
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }

                        TextEditor(text: $content)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 200)
                            .disabled(isSystemTemplate)
                    }
                } header: {
                    Text("提示词内容")
                } footer: {
                    Text("\(content.count) 字符")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - System Template Info
                if isSystemTemplate {
                    Section {
                        Label("这是系统预设模板，仅可查看不可修改", systemImage: "info.circle")
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - Set as Default (仅用户模板可设为默认)
                if !isNew && !isSystemTemplate {
                    Section {
                        Button(action: {
                            showingSetDefaultConfirmation = true
                        }) {
                            Label("设为默认模板", systemImage: "checkmark.circle")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isSystemTemplate ? "关闭" : "取消") { dismiss() }
                }

                // 仅非系统模板显示保存按钮
                if !isSystemTemplate {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            saveTemplate()
                        }
                        .disabled(!canSave)
                    }
                }

                // 操作菜单（复制/删除）- 仅用户模板
                if !isNew && !isSystemTemplate {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            if let onDuplicate = onDuplicate {
                                Button(action: {
                                    onDuplicate()
                                    dismiss()
                                }) {
                                    Label("复制模板", systemImage: "doc.on.doc")
                                }
                            }

                            if let onDelete = onDelete {
                                Divider()
                                Button(role: .destructive, action: {
                                    onDelete()
                                    dismiss()
                                }) {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert("设为默认?", isPresented: $showingSetDefaultConfirmation) {
                Button("取消", role: .cancel) {}
                Button("确定") {
                    setAsDefault()
                }
            } message: {
                Text("将此模板设为 \(template.category.displayName) 的默认提示词?")
            }
        }
        .frame(minWidth: 550, minHeight: 400)
        .onAppear {
            content = template.content
        }
    }

    // MARK: - Computed Properties

    private var navigationTitle: String {
        if isSystemTemplate {
            return "查看提示词"
        }
        return isNew ? "新建提示词" : "编辑提示词"
    }

    // MARK: - Actions

    private func saveTemplate() {
        var updatedTemplate = template
        updatedTemplate.content = content
        onSave(updatedTemplate)
        dismiss()
    }

    private func setAsDefault() {
        Task {
            do {
                try await PromptManager.shared.setDefaultTemplate(
                    id: template.id,
                    for: template.category
                )
            } catch {
                // Error is logged in PromptManager
            }
        }
    }
}

// MARK: - Preview

@available(macOS 13.0, *)
struct PromptEditorSheet_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 编辑用户模板
            PromptEditorSheet(
                template: PromptTemplate(
                    name: "标准内容总结",
                    description: "适用于一般会议",
                    content: "请生成内容总结...",
                    category: .llm,
                    isSystemTemplate: false
                ),
                isNew: false,
                isSystemTemplate: false,
                onSave: { _ in }
            )

            // 查看系统模板
            PromptEditorSheet(
                template: PromptTemplate(
                    name: "标准转录",
                    description: "系统预设语音识别模板",
                    content: "请将以下会议录音转录为文本...",
                    category: .asr,
                    isSystemTemplate: true
                ),
                isNew: false,
                isSystemTemplate: true,
                onSave: { _ in }
            )

            // 新建模板
            PromptEditorSheet(
                template: PromptTemplate(
                    name: "",
                    content: "",
                    category: .asr
                ),
                isNew: true,
                isSystemTemplate: false,
                onSave: { _ in }
            )
        }
    }
}
