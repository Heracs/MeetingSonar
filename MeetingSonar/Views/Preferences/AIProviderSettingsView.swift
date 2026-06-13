import SwiftUI

@available(macOS 13.0, *)
struct AIProviderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    @State private var configs: [AIProviderConfig] = []
    @State private var activeSheet: ProviderSettingsSheet?
    @State private var deletingConfig: AIProviderConfig?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var asrConfigs: [AIProviderConfig] {
        configs
            .filter { $0.isVerified && $0.enabledCapabilities.contains(.asr) }
            .sortedForProviderSettings
    }

    private var llmConfigs: [AIProviderConfig] {
        configs
            .filter { $0.isVerified && $0.enabledCapabilities.contains(.llm) }
            .sortedForProviderSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    selectionSection
                    providerListSection

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .task {
            await loadConfigs()
        }
        .onReceive(NotificationCenter.default.publisher(for: AIProviderConfigStore.configsDidChange)) { _ in
            Task { await loadConfigs() }
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudAIModelManager.modelsDidChange)) { _ in
            Task { await loadConfigs() }
        }
        .sheet(item: $activeSheet) { sheet in
            AIProviderConfigSheet(existingConfig: sheet.config) {
                Task { await loadConfigs() }
            }
        }
        .alert("aiProvider.settings.delete.title", isPresented: deleteAlertBinding) {
            Button("general.cancel", role: .cancel) {
                deletingConfig = nil
            }
            Button("button.delete", role: .destructive) {
                if let deletingConfig {
                    Task { await deleteConfig(deletingConfig) }
                }
            }
        } message: {
            Text("aiProvider.settings.delete.message")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("aiProvider.settings.title")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("aiProvider.settings.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                activeSheet = .add
            } label: {
                Label("aiProvider.settings.add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Button {
                dismiss()
            } label: {
                Text("general.done")
                    .frame(minWidth: 60)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var selectionSection: some View {
        ProviderSettingsSection(titleKey: "aiProvider.settings.section.defaults", icon: "checkmark.circle") {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.aiServices.asrModel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $settings.selectedUnifiedASRId) {
                        ForEach(asrConfigs) { config in
                            Text(modelDisplayName(config, capability: .asr))
                                .tag(config.id.uuidString)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                    .disabled(asrConfigs.isEmpty)

                    if asrConfigs.isEmpty {
                        Text("aiProvider.settings.noVerifiedASR")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.aiServices.llmModel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $settings.selectedUnifiedLLMId) {
                        ForEach(llmConfigs) { config in
                            Text(modelDisplayName(config, capability: .llm))
                                .tag(config.id.uuidString)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                    .disabled(llmConfigs.isEmpty)

                    if llmConfigs.isEmpty {
                        Text("aiProvider.settings.noVerifiedLLM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
        }
    }

    private var providerListSection: some View {
        ProviderSettingsSection(titleKey: "aiProvider.settings.section.providers", icon: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("aiProvider.settings.loading")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                } else if configs.isEmpty {
                    HStack {
                        Text("settings.aiServices.noModelsConfigured")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            activeSheet = .add
                        } label: {
                            Label("aiProvider.settings.add", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(configs.sortedForProviderSettings) { config in
                        providerRow(config)

                        if config.id != configs.sortedForProviderSettings.last?.id {
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func providerRow(_ config: AIProviderConfig) -> some View {
        HStack(spacing: 10) {
            Image(systemName: config.isVerified ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(config.isVerified ? .green : .secondary)
                .frame(width: 22)
                .help(Text(LocalizedStringKey(config.isVerified ? "settings.aiServices.verified" : "settings.aiServices.notVerified")))

            VStack(alignment: .leading, spacing: 3) {
                Text(config.displayName)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(providerName(for: config))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(config.enabledCapabilities).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { capability in
                        Text(capability.rawValue.uppercased())
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundStyle(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            Spacer()

            Button {
                Task { await verifyConfig(config) }
            } label: {
                Image(systemName: "checkmark.shield")
            }
            .buttonStyle(.borderless)
            .help(Text("aiProvider.settings.verify"))

            Button {
                activeSheet = .edit(config)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(Text("button.edit"))

            Button(role: .destructive) {
                deletingConfig = config
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(Text("button.delete"))
        }
        .padding(.vertical, 9)
        .accessibilityIdentifier("Row_AIProvider_\(config.id.uuidString)")
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deletingConfig != nil },
            set: { isPresented in
                if !isPresented {
                    deletingConfig = nil
                }
            }
        )
    }

    private func loadConfigs() async {
        isLoading = true
        defer { isLoading = false }

        await settings.refreshAIProviderConfigs()
        await MainActor.run {
            configs = settings.cachedAIProviderConfigs
            repairSelectionsIfNeeded()
        }
    }

    private func verifyConfig(_ config: AIProviderConfig) async {
        do {
            let runtimeFactory = AIProviderRuntimeFactory()
            let result: AIProviderValidationResult
            if config.enabledCapabilities.contains(.asr), config.asr?.transport == .localCommand {
                result = try await runtimeFactory.makeASRRuntime(config: config).validate()
            } else if config.enabledCapabilities.contains(.llm) {
                result = try await runtimeFactory.makeLLMRuntime(config: config).validate()
            } else if config.enabledCapabilities.contains(.asr) {
                result = try await runtimeFactory.makeASRRuntime(config: config).validate()
            } else {
                result = AIProviderValidationResult(
                    isValid: false,
                    message: String(localized: "aiProvider.validation.capabilityRequired")
                )
            }

            var updated = config
            updated.isVerified = result.isValid
            updated.touch()
            await AIProviderConfigStore.shared.upsert(updated)
            await loadConfigs()

            if !result.isValid {
                await MainActor.run {
                    errorMessage = result.message
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteConfig(_ config: AIProviderConfig) async {
        if config.kind == .cloudAPI {
            do {
                try await CloudAIModelManager.shared.deleteModel(id: config.id)
            } catch {
                LoggerService.shared.log(
                    category: .ai,
                    level: .warning,
                    message: "[AIProviderSettingsView] Cloud compatibility cleanup failed: \(error.localizedDescription)"
                )
            }
        }

        await AIProviderConfigStore.shared.delete(id: config.id)
        await loadConfigs()
    }

    private func repairSelectionsIfNeeded() {
        if !asrConfigs.contains(where: { $0.id.uuidString == settings.selectedUnifiedASRId }),
           let firstASR = asrConfigs.first {
            settings.selectedUnifiedASRId = firstASR.id.uuidString
        }

        if !llmConfigs.contains(where: { $0.id.uuidString == settings.selectedUnifiedLLMId }),
           let firstLLM = llmConfigs.first {
            settings.selectedUnifiedLLMId = firstLLM.id.uuidString
        }
    }

    private func providerName(for config: AIProviderConfig) -> String {
        if config.providerKey == "local.whispercpp" {
            return "Whisper.cpp"
        }
        return config.onlineServiceProvider?.displayName ?? config.providerKey
    }

    private func modelDisplayName(_ config: AIProviderConfig, capability: AIProviderCapability) -> String {
        let modelName: String
        switch capability {
        case .asr:
            modelName = config.asr?.modelName ?? config.displayName
        case .llm:
            modelName = config.llm?.modelName ?? config.displayName
        }
        return "\(providerName(for: config)) · \(modelName)"
    }
}

private enum ProviderSettingsSheet: Identifiable {
    case add
    case edit(AIProviderConfig)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let config):
            return config.id.uuidString
        }
    }

    var config: AIProviderConfig? {
        switch self {
        case .add:
            return nil
        case .edit(let config):
            return config
        }
    }
}

@available(macOS 13.0, *)
private struct ProviderSettingsSection<Content: View>: View {
    let titleKey: LocalizedStringKey
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(titleKey)
                    .font(.headline)
            }

            content()
        }
    }
}

private extension Array where Element == AIProviderConfig {
    var sortedForProviderSettings: [AIProviderConfig] {
        sorted { left, right in
            if left.kind != right.kind {
                return left.kind.rawValue < right.kind.rawValue
            }
            return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
        }
    }
}
