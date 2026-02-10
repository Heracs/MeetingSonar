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

    // MARK: - Version Info
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    var filteredRecordings: [MeetingMeta] {
        var result = metadataManager.recordings

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

            // MARK: - Recording List
            List(selection: $selectedRecordingID) {
                Section {
                    ForEach(filteredRecordings) { recording in
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
                } header: {
                    HStack {
                        Text("录音列表")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(filteredRecordings.count) 个")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
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
        .frame(minWidth: 280, idealWidth: 320)
        .onAppear {
            // Auto-select the most recent recording if none selected
            if selectedRecordingID == nil, let first = filteredRecordings.first {
                selectedRecordingID = first.id
            }
        }
        .onReceive(metadataManager.$recordings) { _ in
            // If selected recording was deleted, select the first available
            if let selectedID = selectedRecordingID,
               !metadataManager.recordings.contains(where: { $0.id == selectedID }),
               let first = filteredRecordings.first {
                selectedRecordingID = first.id
            }
        }
        // MARK: - Delete Confirmation Alert
        .alert("确认删除", isPresented: .init(
            get: { recordingToDelete != nil },
            set: { if !$0 { recordingToDelete = nil } }
        )) {
            Button("取消", role: .cancel) {
                recordingToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let recording = recordingToDelete {
                    deleteRecording(recording)
                }
                recordingToDelete = nil
            }
        } message: {
            if let recording = recordingToDelete {
                Text("确定要删除「\(recording.title)」吗？此操作不可撤销。")
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
        Task {
            do {
                try await MetadataManager.shared.delete(id: recording.id)
            } catch {
                LoggerService.shared.log(
                    category: .ui,
                    level: .error,
                    message: "[RecordingListColumn] Failed to delete recording: \(error.localizedDescription)"
                )
            }
        }
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
            Label("删除", systemImage: "trash")
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
