//
//  PromptPicker.swift
//  MeetingSonar
//
//  F-10.0-PromptMgmt: Reusable prompt selection component
//

import SwiftUI

/// 提示词选择器组件
/// 用于在多个界面中统一展示提示词下拉选择
struct PromptPicker: View {
    let category: PromptCategory
    @Binding var selection: String
    let templates: [PromptTemplate]

    var body: some View {
        Menu {
            ForEach(templates) { template in
                Button(action: {
                    selection = template.id.uuidString
                }) {
                    HStack {
                        Text(template.name)
                            .lineLimit(1)
                        if template.id.uuidString == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if templates.isEmpty {
                Text("无可用提示词")
                    .foregroundColor(.secondary)
            }

            Divider()

            Button(action: {
                NotificationCenter.default.post(name: .openPromptSettings, object: nil)
            }) {
                Label("管理提示词...", systemImage: "gear")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.caption)
                Text(selectedTemplateName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .help(selectedTemplateDescription)
        .frame(minWidth: 80, maxWidth: 140)
    }

    private var selectedTemplate: PromptTemplate? {
        templates.first { $0.id.uuidString == selection }
    }

    private var selectedTemplateName: String {
        selectedTemplate?.name ?? "默认"
    }

    private var selectedTemplateDescription: String {
        selectedTemplate?.description ?? "使用默认提示词"
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openPromptSettings = Notification.Name("openPromptSettings")
}
