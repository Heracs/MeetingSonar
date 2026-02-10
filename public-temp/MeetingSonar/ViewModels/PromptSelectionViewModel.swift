//
//  PromptSelectionViewModel.swift
//  MeetingSonar
//
//  F-10.0-PromptMgmt: ViewModel for prompt selection state management
//

import SwiftUI
import Combine

/// 管理提示词选择状态的 ViewModel
@MainActor
final class PromptSelectionViewModel: ObservableObject {

    // MARK: - Published State

    @Published var asrTemplates: [PromptTemplate] = []
    @Published var llmTemplates: [PromptTemplate] = []
    @Published var selectedASRPromptId: String = ""
    @Published var selectedLLMPromptId: String = ""

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var isInitializing = true

    // MARK: - Initialization

    init() {
        // Load initial state from SettingsManager
        selectedASRPromptId = SettingsManager.shared.selectedASRPromptId
        selectedLLMPromptId = SettingsManager.shared.selectedLLMPromptId

        // Setup bidirectional binding
        setupBindings()

        // Load templates
        loadTemplates()

        // Listen for template changes
        NotificationCenter.default.publisher(for: PromptManager.templatesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadTemplates()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupBindings() {
        // When UI selection changes, update SettingsManager
        $selectedASRPromptId
            .dropFirst()
            .sink { [weak self] id in
                guard !(self?.isInitializing ?? true) else { return }
                SettingsManager.shared.selectedASRPromptId = id
            }
            .store(in: &cancellables)

        $selectedLLMPromptId
            .dropFirst()
            .sink { [weak self] id in
                guard !(self?.isInitializing ?? true) else { return }
                SettingsManager.shared.selectedLLMPromptId = id
            }
            .store(in: &cancellables)
    }

    // MARK: - Data Loading

    private func loadTemplates() {
        Task {
            let allTemplates = await PromptManager.shared.templates
            await MainActor.run {
                self.asrTemplates = allTemplates.filter { $0.category == .asr }
                self.llmTemplates = allTemplates.filter { $0.category == .llm }

                // Validate and update selections if needed
                self.validateAndUpdateSelections()

                self.isInitializing = false
            }
        }
    }

    // MARK: - Selection Validation

    private func validateAndUpdateSelections() {
        // If selected template no longer exists, reset to default
        if !selectedASRPromptId.isEmpty,
           !asrTemplates.contains(where: { $0.id.uuidString == selectedASRPromptId }) {
            selectedASRPromptId = asrTemplates.first { $0.isSystemTemplate }?.id.uuidString ?? asrTemplates.first?.id.uuidString ?? ""
        }

        if !selectedLLMPromptId.isEmpty,
           !llmTemplates.contains(where: { $0.id.uuidString == selectedLLMPromptId }) {
            selectedLLMPromptId = llmTemplates.first { $0.isSystemTemplate }?.id.uuidString ?? llmTemplates.first?.id.uuidString ?? ""
        }
    }

    // MARK: - Public Methods

    /// 获取当前选中的 ASR 提示词内容
    func getSelectedASRPromptContent() async -> String {
        await PromptManager.shared.getSelectedPromptContent(for: .asr)
    }

    /// 获取当前选中的 LLM 提示词内容
    func getSelectedLLMPromptContent() async -> String {
        await PromptManager.shared.getSelectedPromptContent(for: .llm)
    }

    /// 刷新模板列表
    func refreshTemplates() {
        loadTemplates()
    }
}
