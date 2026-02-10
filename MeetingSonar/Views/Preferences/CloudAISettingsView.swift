//
//  CloudAISettingsView.swift
//  MeetingSonar
//
//  Phase 3: 统一云端 AI 设置视图
//  使用 CloudAIModelManager 替代 OnlineModelManager
//

import SwiftUI

/// 统一云端 AI 设置视图
/// 展示所有云端模型配置，支持 ASR + LLM 双能力配置
@available(macOS 13.0, *)
struct CloudAISettingsView: View {
    // MARK: - State

    @State private var models: [CloudAIModelConfig] = []
    @State private var selectedTab: CloudAISettingsTab = .services
    @State private var showAddSheet = false
    @State private var editingConfig: CloudAIModelConfig? = nil
    @State private var showDeleteConfirm = false
    @State private var configToDelete: CloudAIModelConfig? = nil
    @State private var errorMessage: String? = nil
    @State private var showError = false

    // MARK: - Tab Enum

    enum CloudAISettingsTab: String, CaseIterable, Identifiable {
        case services = "services"
        case prompts = "prompts"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .services:
                return String(localized: "cloudai.tab.services", defaultValue: "服务配置")
            case .prompts:
                return String(localized: "cloudai.tab.prompts", defaultValue: "提示词")
            }
        }

        var icon: String {
            switch self {
            case .services:
                return "cloud"
            case .prompts:
                return "text.bubble"
            }
        }
    }

    // MARK: - Body

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with Done button
            HStack {
                Text("settings.aiServices.title")
                    .font(.headline)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("general.done")
                        .frame(minWidth: 60)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            // Tab Picker
            Picker("设置分类", selection: $selectedTab) {
                ForEach(CloudAISettingsTab.allCases) { tab in
                    Label(tab.displayName, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Content based on selected tab
            switch selectedTab {
            case .services:
                servicesView
            case .prompts:
                PromptSettingsView()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .sheet(isPresented: $showAddSheet) {
            CloudModelConfigSheet()
        }
        .sheet(item: $editingConfig) { config in
            CloudModelConfigSheet(existingConfig: config)
        }
        .alert("确认删除?", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { configToDelete = nil }
            Button("删除", role: .destructive) { deleteConfig() }
        } message: {
            Text("确定要删除这个云端服务配置吗?")
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .onAppear {
            loadModels()
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudAIModelManager.modelsDidChange)) { _ in
            loadModels()
        }
    }

    // MARK: - Services View

    private var servicesView: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Streaming Toggle Section (v1.1.0)
            streamingToggleSection

            Divider()

            // Content
            if models.isEmpty {
                emptyStateView
            } else {
                configListView
            }
        }
    }

    // MARK: - Streaming Toggle Section (v1.1.0)

    @AppStorage("enableStreamingSummary") private var enableStreamingSummary: Bool = true

    private var streamingToggleSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("启用流式摘要输出")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("实时显示摘要生成过程，可以看到 AI 逐步生成内容")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $enableStreamingSummary)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("云端 AI 服务")
                    .font(.headline)
                Text("配置语音识别(ASR)和语言模型(LLM)服务")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { showAddSheet = true }) {
                Label("添加服务", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("暂无云端服务配置")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("添加 DeepSeek、智谱AI、阿里云或 Kimi 服务")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showAddSheet = true }) {
                Label("添加服务", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Config List

    private var configListView: some View {
        List {
            Section {
                ForEach(models) { config in
                    CloudConfigRow(
                        config: config,
                        onEdit: { editingConfig = config },
                        onDelete: {
                            configToDelete = config
                            showDeleteConfirm = true
                        }
                    )
                }
            } header: {
                HStack {
                    Text("服务配置")
                    Spacer()
                    Text("支持能力")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                cloudInfoView
            } header: {
                Text("支持的服务提供商")
            }
        }
        .listStyle(.plain)
    }

    private var cloudInfoView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Provider info with capability badges
            ForEach(OnlineServiceProvider.allCases, id: \.self) { provider in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: provider.icon)
                        .foregroundColor(.accentColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            // Capability badges
                            HStack(spacing: 4) {
                                if provider.supportsASR {
                                    Text("ASR")
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(2)
                                }
                                Text("LLM")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.2))
                                    .cornerRadius(2)
                            }
                        }

                        Text(provider.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func loadModels() {
        Task {
            do {
                let configs = await CloudAIModelManager.shared.getModels(for: .asr)
                let llmConfigs = await CloudAIModelManager.shared.getModels(for: .llm)
                // 合并去重
                var uniqueConfigs: [UUID: CloudAIModelConfig] = [:]
                for config in configs + llmConfigs {
                    uniqueConfigs[config.id] = config
                }
                await MainActor.run {
                    self.models = Array(uniqueConfigs.values).sorted { $0.displayName < $1.displayName }
                }
            }
        }
    }

    private func deleteConfig() {
        guard let config = configToDelete else { return }
        Task {
            do {
                try await CloudAIModelManager.shared.deleteModel(id: config.id)
                await MainActor.run {
                    configToDelete = nil
                    loadModels()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    configToDelete = nil
                }
            }
        }
    }
}

// MARK: - Config Row

@available(macOS 13.0, *)
struct CloudConfigRow: View {
    let config: CloudAIModelConfig
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Provider Icon
            Image(systemName: providerIcon(config.provider))
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 40)

            // Config Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(config.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    if config.isVerified {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }

                Text(config.provider.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(config.baseURL)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Capabilities
            HStack(spacing: 8) {
                if config.supports(.asr) {
                    CapabilityBadge(text: "ASR", color: .blue)
                }
                if config.supports(.llm) {
                    CapabilityBadge(text: "LLM", color: .purple)
                }
            }

            // Actions
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("编辑")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("删除")
            }
        }
        .padding(.vertical, 8)
    }

    private func providerIcon(_ provider: OnlineServiceProvider) -> String {
        switch provider {
        case .zhipu: return "brain.head.profile"
        case .deepseek: return "sparkle"
        case .aliyun: return "cloud"
        case .kimi: return "moon.stars"
        }
    }
}

// MARK: - Capability Badge

@available(macOS 13.0, *)
struct CapabilityBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }
}

// MARK: - Preview

@available(macOS 13.0, *)
struct CloudAISettingsView_Previews: PreviewProvider {
    static var previews: some View {
        CloudAISettingsView()
    }
}
