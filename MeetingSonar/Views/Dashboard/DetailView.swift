//
//  DetailView.swift
//  MeetingSonar
//
//  F-11.2: Recording Manager UI Redesign
//  Updated detail view with new header and AI toolbar layout
//

import SwiftUI

/// Detailed view for a single recording.
/// Implements F-6.3 Detail View, F-7.0 Audio Player, F-7.1 Transcript Viewer, F-9.1 Manual AI Trigger, and F-11.2 UI Redesign.
struct DetailView: View {

    let recordingID: UUID
    @ObservedObject private var manager = MetadataManager.shared
    @StateObject private var playerManager = AudioPlayerManager()
    @StateObject private var promptViewModel = PromptSelectionViewModel()
    @State private var transcriptSegments: [TranscriptSegment] = []

    @State private var summaryContent: String? = nil

    // MARK: - AI Processing State
    @State private var isProcessing = false
    @State private var processingStatus: String = ""
    @State private var showErrorAlert = false
    @State private var errorMessage: String = ""

    var meta: MeetingMeta? {
        manager.get(id: recordingID)
    }

    /// Check if AI features are available
    private var isAIAvailable: Bool {
        !AICapability.shared.isDisabled
    }

    /// Get audio file URL for current recording
    private var audioURL: URL? {
        guard let meta = meta else { return nil }
        return PathManager.shared.recordingsURL.appendingPathComponent(meta.filename)
    }

    // MARK: - Version Selection State
    @ObservedObject var settings = SettingsManager.shared

    @State private var showSourceTranscript: Bool = false

    @State private var selectedTranscriptVersionID: UUID?
    @State private var selectedSummaryVersionID: UUID?

    // Tab Selection State (0 = Transcript, 1 = Summary)
    @State private var selectedTab: Int = 0

    // MARK: - Streaming Config State
    @State private var streamingConfig: CloudAIModelConfig?
    @State private var streamingProvider: (any CloudServiceProvider)?
    @State private var isLoadingStreamingConfig = false

    // MARK: - Body

    var body: some View {
        Group {
            if let meta = meta {
                VStack(spacing: 0) {
                    // MARK: - Header
                    headerView(meta)

                    Divider()

                    // MARK: - AI Toolbar (F-11.2 Redesigned)
                    if isAIAvailable {
                        aiToolbar(meta)
                        Divider()
                    }

                    // MARK: - Player Controls
                    PlayerControlsView(playerManager: playerManager)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)

                    Divider()

                    // MARK: - Content Area (Tabs)
                    TabView(selection: $selectedTab) {
                        // Tab 1: Transcript
                        transcriptTab(meta: meta)
                            .tabItem { Label("转录", systemImage: "text.bubble") }
                            .tag(0)

                        // Tab 2: Summary
                        summaryTab(meta: meta)
                            .tabItem { Label("纪要", systemImage: "doc.text") }
                            .tag(1)
                    }
                }
                .onChange(of: recordingID) { newID in
                    handleRecordingChanged(to: newID)
                }
                .onChange(of: selectedTranscriptVersionID) { _ in
                    loadTranscript(for: recordingID)
                }
                .onChange(of: selectedSummaryVersionID) { newID in
                    handleSummaryVersionChanged(to: newID)
                }
                .onAppear {
                    loadAudio(for: recordingID)
                    loadTranscript(for: recordingID)
                    loadSummary(for: recordingID)
                }
                .onDisappear {
                    playerManager.stop()
                }
                .alert(String(localized: "alert.processingFailed"), isPresented: $showErrorAlert) {
                    processingFailedAlertActions()
                } message: {
                    Text(errorMessage)
                }
                .alert(String(localized: "alert.noTranscript"), isPresented: $showMissingTranscriptAlert) {
                    noTranscriptAlertActions()
                } message: {
                    Text(String(localized: "alert.noTranscriptMessage"))
                }
            } else {
                Text("Recording not found")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Header View (F-11.2 Redesigned)

    private func headerView(_ meta: MeetingMeta) -> some View {
        HStack(spacing: 16) {
            // Source Icon (NEW)
            SourceIcon(source: RecordingSource(from: meta.source), size: .large)

            VStack(alignment: .leading, spacing: 4) {
                // Title (Editable)
                Text(meta.title)
                    .font(.title3)
                    .fontWeight(.semibold)

                // Metadata Row
                HStack(spacing: 8) {
                    // Status Badge
                    StatusBadge(status: meta.status)

                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))

                    // Date and Time
                    Text(meta.startTime, style: .date)
                    Text(meta.startTime, style: .time)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))

                    // Duration
                    Text(formatDuration(meta.duration))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .font(.caption)
            }

            Spacer()

            // Action Menu
            Menu {
                Button(action: { openInFinder(meta) }) {
                    Label("在 Finder 中显示", systemImage: "folder")
                }

                if meta.hasSummary {
                    Button(action: { openSummary(meta) }) {
                        Label("打开纪要文件", systemImage: "doc.text")
                    }
                }

                Divider()

                Button(role: .destructive, action: { deleteRecording(meta) }) {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - AI Toolbar (F-11.2 Redesigned)

    private func aiToolbar(_ meta: MeetingMeta) -> some View {
        HStack(spacing: 16) {
            // Model Configuration Section
            HStack(spacing: 12) {
                // ASR Model Picker
                VStack(alignment: .leading, spacing: 2) {
                    Text("语音识别模型")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Picker("", selection: $settings.selectedUnifiedASRId) {
                        ForEach(settings.availableASRModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    .controlSize(.small)
                }

                // LLM Model Picker
                VStack(alignment: .leading, spacing: 2) {
                    Text("总结模型")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Picker("", selection: $settings.selectedUnifiedLLMId) {
                        ForEach(settings.availableLLMModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    .controlSize(.small)
                }
            }

            Divider()
                .frame(height: 32)

            // Prompt Configuration Section
            HStack(spacing: 12) {
                // ASR Prompt Picker
                VStack(alignment: .leading, spacing: 2) {
                    Text("转录提示词")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    PromptPicker(
                        category: .asr,
                        selection: $promptViewModel.selectedASRPromptId,
                        templates: promptViewModel.asrTemplates
                    )
                }

                // LLM Prompt Picker
                VStack(alignment: .leading, spacing: 2) {
                    Text("纪要提示词")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    PromptPicker(
                        category: .llm,
                        selection: $promptViewModel.selectedLLMPromptId,
                        templates: promptViewModel.llmTemplates
                    )
                }
            }

            Spacer()

            // Processing Actions
            if isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(processingStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Consolidated Process Menu
                Menu {
                    if !meta.hasTranscript {
                        Button(action: { onReprocessPressed() }) {
                            Label("开始处理", systemImage: "sparkles")
                        }
                    } else {
                        Button(action: { onTranscribePressed() }) {
                            Label("重新转录", systemImage: "waveform")
                        }

                        Button(action: { onGenerateSummaryPressed() }) {
                            Label("生成纪要", systemImage: "doc.text")
                        }

                        Divider()

                        Button(action: { onReprocessPressed() }) {
                            Label("全部重新处理", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } label: {
                    Label("处理", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.borderedButton)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Transcript Tab

    private func transcriptTab(meta: MeetingMeta) -> some View {
        VStack(spacing: 0) {
            if !meta.transcriptVersions.isEmpty {
                // Version Bar
                HStack {
                    TranscriptVersionPicker(
                        versions: meta.transcriptVersions,
                        selectedVersionId: $selectedTranscriptVersionID
                    )
                    Spacer()
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                if !transcriptSegments.isEmpty {
                    TranscriptView(
                        segments: transcriptSegments,
                        currentTime: playerManager.currentTime,
                        onSeek: { time in
                            playerManager.seek(to: time)
                        }
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("无法加载转录数据")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // Empty State
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("暂无转录")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Text("点击上方「处理」按钮开始转录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Summary Tab

    @AppStorage("enableStreamingSummary") private var enableStreamingSummary: Bool = true
    @State private var showStreamingView: Bool = false

    private func summaryTab(meta: MeetingMeta) -> some View {
        VStack(spacing: 0) {
            if showStreamingView {
                // Streaming Summary View (v1.1.0)
                streamingSummaryContent()
                    .task {
                        await loadStreamingConfig()
                    }
            } else if !meta.summaryVersions.isEmpty {
                // Static Summary View
                staticSummaryContent(meta: meta)
            } else {
                // Empty State
                emptySummaryState()
            }
        }
    }

    @ViewBuilder
    private func streamingSummaryContent() -> some View {
        if isLoadingStreamingConfig {
            loadingConfigView()
        } else if let config = streamingConfig,
                  let provider = streamingProvider {
            let transcriptText = transcriptSegments.map { $0.text }.joined(separator: "\n")

            StreamingSummaryView(
                transcript: transcriptText,
                meetingID: recordingID,
                config: config,
                provider: provider
            )
            .onDisappear {
                // Reload summary when streaming view closes
                loadSummary(for: recordingID)
            }
        } else {
            configErrorView()
        }
    }

    private func loadingConfigView() -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("加载配置中...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func configErrorView() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("未配置语言模型")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("请在设置中配置云端 AI 服务")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadStreamingConfig() async {
        isLoadingStreamingConfig = true
        defer { isLoadingStreamingConfig = false }

        guard let modelId = settings.currentLLMModel?.id,
              let config = await CloudAIModelManager.shared.getModel(byId: modelId) else {
            return
        }

        let apiKey = await CloudAIModelManager.shared.getAPIKey(for: config.id) ?? ""
        let provider = await CloudServiceFactory.shared.createProvider(
            config.provider,
            apiKey: apiKey,
            baseURL: config.baseURL
        )

        streamingConfig = config
        streamingProvider = provider
    }

    private func staticSummaryContent(meta: MeetingMeta) -> some View {
        VStack(spacing: 0) {
            // Version Bar
            HStack {
                SummaryVersionPicker(
                    versions: meta.summaryVersions,
                    transcriptVersions: meta.transcriptVersions,
                    selectedVersionId: $selectedSummaryVersionID
                )
                Spacer()
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            GeometryReader { geo in
                if showSourceTranscript {
                    VSplitView {
                        SummaryView(content: summaryContent ?? String(localized: "summary.noContent"))
                            .frame(minHeight: 100)

                        VStack(alignment: .leading, spacing: 0) {
                            Divider()
                            HStack {
                                Text("来源转录")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(4)
                            .background(Color(nsColor: .windowBackgroundColor))

                            TranscriptView(
                                segments: transcriptSegments,
                                currentTime: playerManager.currentTime,
                                onSeek: { time in playerManager.seek(to: time) }
                            )
                        }
                        .frame(minHeight: 100)
                    }
                } else {
                    SummaryView(content: summaryContent ?? String(localized: "summary.noContent"))
                }
            }

            Divider()

            // Bottom Bar: Show/Hide Source
            HStack {
                Spacer()
                Button(action: {
                    withAnimation {
                        showSourceTranscript.toggle()

                        if showSourceTranscript,
                           let currentSummaryID = selectedSummaryVersionID,
                           let sv = meta.summaryVersions.first(where: { $0.id == currentSummaryID }),
                           selectedTranscriptVersionID != sv.sourceTranscriptId {
                            selectedTranscriptVersionID = sv.sourceTranscriptId
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showSourceTranscript ? "chevron.down" : "chevron.up")
                        Text(showSourceTranscript ? "隐藏来源" : "显示来源")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func emptySummaryState() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("暂无纪要")
                .font(.title3)
                .foregroundColor(.secondary)

            Text(enableStreamingSummary ? "点击上方「生成纪要」按钮开始流式生成" : "点击上方「处理」按钮生成纪要")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status Badge

    private func StatusBadge(status: MeetingMeta.ProcessingStatus) -> some View {
        HStack(spacing: 4) {
            StatusIcon(status: status)
            Text(statusDisplayName(status))
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(statusColor(status))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor(status).opacity(0.15))
        .cornerRadius(4)
    }

    private func statusDisplayName(_ status: MeetingMeta.ProcessingStatus) -> String {
        switch status {
        case .recording: return "录制中"
        case .pending: return "待处理"
        case .processing: return "处理中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }

    private func statusColor(_ status: MeetingMeta.ProcessingStatus) -> Color {
        switch status {
        case .recording: return .red
        case .pending: return .orange
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }

    // MARK: - Helper Methods

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    // MARK: - AI Processing Actions

    private func onTranscribePressed() {
        guard let url = audioURL else { return }

        Task {
            isProcessing = true
            processingStatus = String(localized: "status.transcribing")

            do {
                let (_, _, versionId) = try await AIProcessingCoordinator.shared.transcribeOnly(audioURL: url, meetingID: recordingID)
                selectedTranscriptVersionID = versionId

                await MainActor.run {
                    loadTranscript(for: recordingID)
                }
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }

            isProcessing = false
            processingStatus = ""
        }
    }

    @State private var showMissingTranscriptAlert = false

    private func onGenerateSummaryPressed() {
        guard let url = audioURL else { return }

        if transcriptSegments.isEmpty {
            showMissingTranscriptAlert = true
            return
        }

        runSummaryGenerationOnly(audioURL: url)
    }

    private func runSummaryGenerationOnly(audioURL: URL) {
        // v1.1.0: Check if streaming is enabled
        if enableStreamingSummary {
            // Use streaming summary view
            // Reset config state before showing to avoid race condition
            streamingConfig = nil
            streamingProvider = nil
            isLoadingStreamingConfig = true
            showStreamingView = true
            selectedTab = 1
            return
        }

        // Fall back to non-streaming generation
        Task {
            isProcessing = true
            processingStatus = String(localized: "status.generating")

            do {
                let fullText = transcriptSegments.map { $0.text }.joined(separator: "\n")

                guard let sourceTranscriptId = selectedTranscriptVersionID ?? meta?.transcriptVersions.last?.id else {
                    throw AIProcessingError.noSourceTranscript
                }

                let (_, _, versionId) = try await AIProcessingCoordinator.shared.generateSummaryOnly(
                    transcriptText: fullText,
                    audioURL: audioURL,
                    sourceTranscriptId: sourceTranscriptId,
                    meetingID: recordingID
                )

                selectedSummaryVersionID = versionId

                await MainActor.run {
                    loadSummary(for: recordingID)
                    selectedTab = 1
                }
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }

            isProcessing = false
            processingStatus = ""
        }
    }

    private func runFullProcessing(audioURL: URL) {
        Task {
            isProcessing = true

            do {
                processingStatus = "转录中..."

                let (_, _, transcriptVersionId) = try await AIProcessingCoordinator.shared.transcribeOnly(
                    audioURL: audioURL,
                    meetingID: recordingID
                )

                selectedTranscriptVersionID = transcriptVersionId

                await MainActor.run {
                    loadTranscript(for: recordingID)
                }

                processingStatus = "生成纪要..."

                guard let meta = manager.get(id: recordingID),
                      let latestTranscript = meta.transcriptVersions.first(where: { $0.id == transcriptVersionId }) else {
                    throw AIProcessingError.noSourceTranscript
                }

                let transcriptFileURL = PathManager.shared.rootDataURL.appendingPathComponent(latestTranscript.filePath)
                guard let transcriptData = try? Data(contentsOf: transcriptFileURL),
                      let transcriptModel = try? JSONDecoder().decode(TranscriptModel.self, from: transcriptData) else {
                    throw AIProcessingError.noSourceTranscript
                }

                let fullText = transcriptModel.segments.map { $0.text }.joined(separator: "\n")

                let (_, _, summaryVersionId) = try await AIProcessingCoordinator.shared.generateSummaryOnly(
                    transcriptText: fullText,
                    audioURL: audioURL,
                    sourceTranscriptId: transcriptVersionId,
                    meetingID: recordingID
                )

                selectedSummaryVersionID = summaryVersionId

                await MainActor.run {
                    loadSummary(for: recordingID)
                    selectedTab = 1
                }

            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }

            isProcessing = false
            processingStatus = ""
        }
    }

    private func onReprocessPressed() {
        if let url = audioURL {
            runFullProcessing(audioURL: url)
        }
    }

    // MARK: - Loaders

    private func loadAudio(for id: UUID) {
        guard let meta = manager.get(id: id) else { return }
        let url = PathManager.shared.recordingsURL.appendingPathComponent(meta.filename)
        playerManager.load(url: url)
    }

    private func loadTranscript(for id: UUID) {
        transcriptSegments = []
        guard let meta = manager.get(id: id) else { return }

        // Early return if no versions available
        guard !meta.transcriptVersions.isEmpty else {
            selectedTranscriptVersionID = nil
            LoggerService.shared.log(category: .ai, message: "[DetailView] No transcript versions available for recording \(id)")
            return
        }

        // Determine target version (use selected or auto-select latest)
        let targetVersion: TranscriptVersion?
        if let selectedID = selectedTranscriptVersionID,
           let version = meta.transcriptVersions.first(where: { $0.id == selectedID }) {
            targetVersion = version
            LoggerService.shared.log(category: .ai, message: "[DetailView] Loading selected transcript version: \(version.modelInfo.displayName)")
        } else {
            targetVersion = meta.transcriptVersions.last
            selectedTranscriptVersionID = targetVersion?.id
            LoggerService.shared.log(category: .ai, message: "[DetailView] Auto-selecting latest transcript version: \(targetVersion?.modelInfo.displayName ?? "None")")
        }

        guard let version = targetVersion else {
            LoggerService.shared.log(category: .ai, message: "[DetailView] No valid transcript version. Trying legacy fallback.")
            loadLegacyTranscript(meta: meta)
            return
        }

        let fullPath = PathManager.shared.rootDataURL.appendingPathComponent(version.filePath)
        LoggerService.shared.log(category: .ai, message: "[DetailView] Loading transcript from: \(fullPath.path)")

        // Check file exists
        guard FileManager.default.fileExists(atPath: fullPath.path) else {
            LoggerService.shared.log(category: .ai, level: .warning, message: "[DetailView] Transcript file missing at \(fullPath.path). Trying legacy fallback.")
            loadLegacyTranscript(meta: meta)
            return
        }

        do {
            let data = try Data(contentsOf: fullPath)
            let model = try JSONDecoder().decode(TranscriptModel.self, from: data)
            self.transcriptSegments = model.segments
            LoggerService.shared.log(category: .ai, message: "[DetailView] Successfully loaded transcript: \(version.modelInfo.displayName)")
        } catch {
            LoggerService.shared.log(category: .ai, level: .error, message: "[DetailView] Failed to decode transcript: \(error.localizedDescription)")
            loadLegacyTranscript(meta: meta)
        }
    }

    private func loadLegacyTranscript(meta: MeetingMeta) {
        let basename = (meta.filename as NSString).deletingPathExtension
        let transcriptsDir = PathManager.shared.transcriptsURL
        let cleansedDir = transcriptsDir.appendingPathComponent("Cleansed")
        let rawDir = transcriptsDir.appendingPathComponent("Raw")

        var candidates: [URL] = []

        candidates.append(rawDir.appendingPathComponent("\(basename)_transcript.json"))

        if let files = try? FileManager.default.contentsOfDirectory(at: rawDir, includingPropertiesForKeys: nil) {
            let matchingFiles = files.filter { url in
                let name = url.deletingPathExtension().lastPathComponent
                return name.hasPrefix("\(basename)_transcript")
            }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            candidates.append(contentsOf: matchingFiles)
        }

        candidates.append(cleansedDir.appendingPathComponent("\(basename).json"))
        candidates.append(rawDir.appendingPathComponent("\(basename).json"))

        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url),
               let model = try? JSONDecoder().decode(TranscriptModel.self, from: data) {
                self.transcriptSegments = model.segments
                LoggerService.shared.log(
                    category: .ai,
                    message: "[DetailView] Loaded legacy transcript: \(url.lastPathComponent)"
                )
                return
            }
        }

        LoggerService.shared.log(
            category: .ai,
            level: .error,
            message: "[DetailView] Failed to load legacy transcript for \(basename). Tried \(candidates.count) candidates."
        )
    }

    private func loadSummary(for id: UUID) {
        summaryContent = nil
        guard let meta = manager.get(id: id) else { return }

        // Early return if no versions available
        guard !meta.summaryVersions.isEmpty else {
            selectedSummaryVersionID = nil
            LoggerService.shared.log(category: .ui, message: "[DetailView] No summary versions available for recording \(id)")
            loadLegacySummary(meta: meta)
            return
        }

        // Determine target version (use selected or auto-select latest)
        let targetVersion: SummaryVersion?
        if let selectedID = selectedSummaryVersionID,
           let version = meta.summaryVersions.first(where: { $0.id == selectedID }) {
            targetVersion = version
            LoggerService.shared.log(category: .ui, message: "[DetailView] Loading selected summary version: \(version.modelInfo.displayName)")
        } else {
            targetVersion = meta.summaryVersions.last
            selectedSummaryVersionID = targetVersion?.id
            LoggerService.shared.log(category: .ui, message: "[DetailView] Auto-selecting latest summary version: \(targetVersion?.modelInfo.displayName ?? "None")")
        }

        guard let version = targetVersion else {
            LoggerService.shared.log(category: .ui, message: "[DetailView] No valid summary version. Trying legacy fallback.")
            loadLegacySummary(meta: meta)
            return
        }

        let fullPath = PathManager.shared.rootDataURL.appendingPathComponent(version.filePath)
        LoggerService.shared.log(category: .ui, message: "[DetailView] Loading summary from: \(fullPath.path)")

        // Check file exists
        guard FileManager.default.fileExists(atPath: fullPath.path) else {
            LoggerService.shared.log(category: .ui, level: .warning, message: "[DetailView] Summary file missing at \(fullPath.path). Trying legacy fallback.")
            loadLegacySummary(meta: meta)
            return
        }

        do {
            let content = try String(contentsOf: fullPath, encoding: .utf8)
            self.summaryContent = content
            LoggerService.shared.log(category: .ui, message: "[DetailView] Successfully loaded summary: \(version.modelInfo.displayName)")
        } catch {
            LoggerService.shared.log(category: .ui, level: .error, message: "[DetailView] Failed to load summary: \(error)")
            loadLegacySummary(meta: meta)
        }
    }

    private func loadLegacySummary(meta: MeetingMeta) {
        let basename = (meta.filename as NSString).deletingPathExtension
        let candidates = ["\(basename)_Summary.md", "\(basename)_summary.md"]

        for filename in candidates {
            let url = PathManager.shared.smartNotesURL.appendingPathComponent(filename)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                summaryContent = content
                return
            }
        }
    }

    // MARK: - Event Handlers

    private func handleRecordingChanged(to newID: UUID) {
        playerManager.stop()
        // Reset state for new recording - loadTranscript/loadSummary will auto-select latest versions
        transcriptSegments = []
        summaryContent = nil
        selectedTranscriptVersionID = nil
        selectedSummaryVersionID = nil

        loadAudio(for: newID)
        loadTranscript(for: newID)
        loadSummary(for: newID)
    }

    private func handleSummaryVersionChanged(to newID: UUID?) {
        loadSummary(for: recordingID)

        if showSourceTranscript,
           let meta = manager.get(id: recordingID),
           let sv = meta.summaryVersions.first(where: { $0.id == newID }),
           selectedTranscriptVersionID != sv.sourceTranscriptId {
            selectedTranscriptVersionID = sv.sourceTranscriptId
        }
    }

    // MARK: - Alert Actions

    @ViewBuilder
    private func processingFailedAlertActions() -> some View {
        Button(String(localized: "button.retry")) {
            onReprocessPressed()
        }
        Button(String(localized: "button.cancel"), role: .cancel) {}
    }

    @ViewBuilder
    private func noTranscriptAlertActions() -> some View {
        Button(String(localized: "button.transcribeAndGenerate")) {
            if let url = audioURL {
                runFullProcessing(audioURL: url)
            }
        }
        Button(String(localized: "button.cancel"), role: .cancel) {}
    }

    // MARK: - Actions

    private func openInFinder(_ meta: MeetingMeta) {
        let url = PathManager.shared.recordingsURL.appendingPathComponent(meta.filename)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(PathManager.shared.recordingsURL)
        }
    }

    private func openSummary(_ meta: MeetingMeta) {
        if let selectedID = selectedSummaryVersionID,
           let version = meta.summaryVersions.first(where: { $0.id == selectedID }) {
            let url = PathManager.shared.rootDataURL.appendingPathComponent(version.filePath)
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.open(url)
                return
            }
        }

        let basename = (meta.filename as NSString).deletingPathExtension
        let url = PathManager.shared.smartNotesURL.appendingPathComponent("\(basename)_Summary.md")
        NSWorkspace.shared.open(url)
    }

    private func deleteRecording(_ meta: MeetingMeta) {
        // TODO: Implement delete functionality
    }
}
