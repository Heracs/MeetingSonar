//
//  DashboardView.swift
//  MeetingSonar
//
//  F-11.2: Recording Manager UI Redesign
//  Two-column layout with recording list and detail view
//

import SwiftUI

/// Main window for MeetingSonar, providing dashboard access to recordings.
/// Implements F-11.2 Two-Column Layout.
struct DashboardView: View {
    // MARK: - Properties

    @State private var selectedRecordingID: UUID?
    @State private var showPromptSettings = false

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            // Left Column: Recording List
            RecordingListColumn(selectedRecordingID: $selectedRecordingID)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            // Right Column: Detail View
            if let recordingID = selectedRecordingID {
                DetailView(recordingID: recordingID)
            } else {
                // Empty State
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("选择一个录音查看详情")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Text("或点击菜单栏图标开始新录音")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("录音管理")
        .frame(minWidth: 900, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .openPromptSettings)) { _ in
            showPromptSettings = true
        }
        .sheet(isPresented: $showPromptSettings) {
            PromptSettingsView()
                .frame(minWidth: 500, minHeight: 350)
        }
    }
}

// MARK: - Preview

#Preview("Dashboard View") {
    DashboardView()
}
