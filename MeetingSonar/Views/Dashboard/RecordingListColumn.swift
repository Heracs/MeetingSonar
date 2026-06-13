//
//  RecordingListColumn.swift
//  MeetingSonar
//
//  F-11.2: Recording Manager UI Redesign
//  Left column with recording list, search, and filter
//

import SwiftUI
import Combine

/// 录音列表筛选类型
enum RecordingFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case unprocessed = "未处理"
    case withSummary = "有纪要"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "tray.fill"
        case .unprocessed: return "clock.badge.questionmark"
        case .withSummary: return "sparkles"
        }
    }
}

/// 左侧录音列表栏
struct RecordingListColumn: View {
    @Binding var selectedRecordingID: UUID?
    @State private var filter: RecordingFilter = .all
    @State private var searchText: String = ""
    @State private var recordings: [MeetingMeta] = []

    @StateObject private var metadataManager = MetadataManager.shared

    // MARK: - Rename/Delete State (hoisted from context menu)
    @State private var recordingToRename: MeetingMeta?
    @State private var recordingToDelete: MeetingMeta?
    @State private var renameText = ""
    @State private var deleteErrorMessage: String?

    // MARK: - Multi-Select State (F-0.10.17)
    @State private var isSelectionMode: Bool = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var isMerging: Bool = false
    @State private var mergeError: String?
    @State private var showMergeConfirm: Bool = false

    // MARK: - Version Info
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    /// 多选模式下选中的录音（按 startTime 排序）
    private var selectedRecordingsForMerge: [MeetingMeta] {
        metadataManager.recordings
            .filter { selectedIDs.contains($0.id) }
            .sorted { $0.startTime < $1.startTime }
    }

    /// 选中录音的总时长文本
    private var selectedDurationText: String {
        let total = selectedRecordingsForMerge.reduce(0) { $0 + $1.duration }
        let totalSeconds = Int(total)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    var filteredRecordings: [MeetingMeta] {
        filteredRecordings(from: metadataManager.recordings)
    }

    private func filteredRecordings(from source: [MeetingMeta]) -> [MeetingMeta] {
        var result = source

        // Apply filter
        switch filter {
        case .all:
            break
        case .unprocessed:
            result = result.filter { !$0.hasTranscript }
        case .withSummary:
            result = result.filter { $0.hasSummary }
        }

        // Apply search
        if !searchText.isEmpty {
            result = result.filter { recording in
                recording.title.localizedCaseInsensitiveContains(searchText) ||
                recording.source.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort by start time (newest first)
        return result.sorted { $0.startTime > $1.startTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header with Search and Filter
            VStack(spacing: 8) {
                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    TextField("搜索录音...", text: $searchText)
                        .font(.system(size: 12))

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

                // Filter Segmented Control
                Picker("", selection: $filter) {
                    ForEach(RecordingFilter.allCases) { filter in
                        Label(filter.rawValue, systemImage: filter.icon)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // MARK: - Selection Toolbar (F-0.10.17)
            if isSelectionMode {
                HStack(spacing: 8) {
                    Button {
                        showMergeConfirm = true
                    } label: {
                        Label(
                            "合并 (\(selectedIDs.count))",
                            systemImage: "arrow.triangle.merge"
                        )
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selectedIDs.count < 2 || isMerging)

                    Spacer()

                    Button {
                        exitSelectionMode()
                    } label: {
                        Text(String(localized: "merge.action.cancel", defaultValue: "取消"))
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .disabled(isMerging)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.05))
            } else {
                HStack {
                    Spacer()
                    Button {
                        isSelectionMode = true
                        selectedIDs = []
                    } label: {
                        Label(
                            String(localized: "merge.action.select", defaultValue: "选择"),
                            systemImage: "checkmark.circle"
                        )
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // MARK: - Recording List
            List(selection: isSelectionMode ? nil : $selectedRecordingID) {
                Section {
                    ForEach(filteredRecordings) { recording in
                        recordingRow(for: recording)
                    }
                } header: {
                    listSectionHeader
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider()

            // MARK: - Footer with Settings Button and Version
            HStack(spacing: 12) {
                // Settings Button (左下角)
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("打开设置")

                // Version Info (to the right of settings)
                Text(appVersionString)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                // Recording Count
                Text("\(filteredRecordings.count) 个录音")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        // MARK: - Merge Progress Overlay (F-0.10.17)
        .overlay {
            if isMerging {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        Text(String(localized: "merge.status.merging", defaultValue: "正在合并..."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
        .onAppear {
            // Auto-select the most recent recording if none selected
            if selectedRecordingID == nil, let first = filteredRecordings.first {
                selectedRecordingID = first.id
            }
        }
        .onReceive(metadataManager.$recordings) { recordings in
            // If selected recording was deleted, select the first available
            if let selectedID = selectedRecordingID,
               !recordings.contains(where: { $0.id == selectedID }) {
                selectedRecordingID = DashboardSelectionPolicy.selectionAfterDeleting(
                    currentSelection: selectedID,
                    deletedID: selectedID,
                    remainingRecordings: filteredRecordings(from: recordings)
                )
            }
        }
        // MARK: - Merge Confirmation Alert (F-0.10.17)
        .alert(
            String(localized: "merge.confirm.title", defaultValue: "确认合并"),
            isPresented: $showMergeConfirm
        ) {
            Button(String(localized: "merge.action.cancel", defaultValue: "取消"), role: .cancel) {}
            Button(String(localized: "merge.action.merge.confirm", defaultValue: "合并")) {
                performMerge()
            }
        } message: {
            let count = selectedRecordingsForMerge.count
            Text("将合并 \(count) 条录音（总时长约 \(selectedDurationText)）。\n原始录音将保留不变。")
        }
        // MARK: - Merge Error Alert (F-0.10.17)
        .alert(
            String(localized: "merge.error.title", defaultValue: "合并失败"),
            isPresented: .init(
                get: { mergeError != nil },
                set: { if !$0 { mergeError = nil } }
            )
        ) {
            Button("OK") { mergeError = nil }
        } message: {
            if let error = mergeError {
                Text(error)
            }
        }
        // MARK: - Delete Confirmation Alert
        .alert(String(localized: "Delete Recording?"), isPresented: .init(
            get: { recordingToDelete != nil },
            set: { if !$0 { recordingToDelete = nil } }
        )) {
            Button(String(localized: "button.cancel"), role: .cancel) {
                recordingToDelete = nil
            }
            Button(String(localized: "button.delete"), role: .destructive) {
                if let recording = recordingToDelete {
                    deleteRecording(recording)
                }
                recordingToDelete = nil
            }
        } message: {
            if let recording = recordingToDelete {
                Text(String(
                    format: String(localized: "Are you sure you want to permanently delete '%@'? This cannot be undone."),
                    recording.title
                ))
            }
        }
        .alert(String(localized: "alert.deleteFailed"), isPresented: .init(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button(String(localized: "button.confirm"), role: .cancel) {
                deleteErrorMessage = nil
            }
        } message: {
            if let deleteErrorMessage {
                Text(deleteErrorMessage)
            }
        }
        // MARK: - Rename Sheet
        .sheet(isPresented: .init(
            get: { recordingToRename != nil },
            set: { if !$0 { recordingToRename = nil } }
        )) {
            if let recording = recordingToRename {
                RenameSheet(
                    title: recording.title,
                    onSave: { newTitle in
                        renameRecording(recording, to: newTitle)
                        recordingToRename = nil
                    },
                    onCancel: {
                        recordingToRename = nil
                    }
                )
            }
        }
    }

    // MARK: - Rename/Delete Actions

    private func renameRecording(_ recording: MeetingMeta, to newTitle: String) {
        Task {
            await MetadataManager.shared.rename(id: recording.id, newTitle: newTitle)
        }
    }

    private func deleteRecording(_ recording: MeetingMeta) {
        Task { @MainActor in
            do {
                try await MetadataManager.shared.delete(id: recording.id)
                selectedRecordingID = DashboardSelectionPolicy.selectionAfterDeleting(
                    currentSelection: selectedRecordingID,
                    deletedID: recording.id,
                    remainingRecordings: filteredRecordings
                )
            } catch {
                deleteErrorMessage = error.localizedDescription
                LoggerService.shared.log(
                    category: .ui,
                    level: .error,
                    message: "[RecordingListColumn] Failed to delete recording: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Multi-Select Actions (F-0.10.17)

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedIDs = []
    }

    private func performMerge() {
        let recordings = selectedRecordingsForMerge
        guard recordings.count >= 2 else { return }

        isMerging = true
        mergeError = nil

        Task {
            do {
                let result = try await AudioMergeService.merge(recordings: recordings)
                await MetadataManager.shared.add(result.metadata)

                exitSelectionMode()
                isMerging = false

                // 自动选中新录音
                selectedRecordingID = result.metadata.id
            } catch {
                isMerging = false
                mergeError = error.localizedDescription

                LoggerService.shared.log(
                    category: .audio,
                    level: .error,
                    message: "[RecordingListColumn] 合并失败：\(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Extracted Views (F-0.10.17: reduce type-checker complexity)

    @ViewBuilder
    private func recordingRow(for recording: MeetingMeta) -> some View {
        if isSelectionMode {
            RecordingRowView(
                meta: recording,
                isSelected: false,
                isSelectionMode: true,
                isChecked: selectedIDs.contains(recording.id)
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.visible)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleSelection(recording.id)
            }
        } else {
            RecordingRowView(
                meta: recording,
                isSelected: selectedRecordingID == recording.id
            )
            .tag(recording.id)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.visible)
            .contextMenu {
                RecordingContextMenu(
                    recording: recording,
                    onRename: { recordingToRename = recording },
                    onDelete: { recordingToDelete = recording }
                )
            }
        }
    }

    @ViewBuilder
    private var listSectionHeader: some View {
        HStack {
            if isSelectionMode {
                Text("已选择 \(selectedIDs.count) 条")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.accentColor)
                Spacer()
                if selectedIDs.count >= 2 {
                    Text("总时长: \(selectedDurationText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("录音列表")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(filteredRecordings.count) 个")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func openSettings() {
        NotificationCenter.default.post(name: Notification.Name("OpenPreferences"), object: nil)
    }
}

// MARK: - Context Menu

struct RecordingContextMenu: View {
    let recording: MeetingMeta
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onRename) {
            Label("重命名", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive, action: onDelete) {
            Label(String(localized: "button.delete"), systemImage: "trash")
        }
    }
}

// MARK: - Rename Sheet

struct RenameSheet: View {
    let title: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("重命名录音")
                .font(.headline)

            TextField("新名称", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack(spacing: 12) {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onSave(trimmed)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 350, height: 150)
        .onAppear {
            text = title
        }
    }
}

// MARK: - Preview

#Preview("Recording List Column") {
    RecordingListColumn(selectedRecordingID: .constant(nil))
        .frame(height: 600)
}
