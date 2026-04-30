//
//  RecordingRowView.swift
//  MeetingSonar
//
//  F-11.2: Recording Manager UI Redesign
//  Updated row design with source icons and improved layout
//

import SwiftUI

/// A row in the recording list.
/// Implements F-6.2 Recording List Row with F-11.2 redesign.
struct RecordingRowView: View {
    let meta: MeetingMeta
    let isSelected: Bool
    var isSelectionMode: Bool = false
    var isChecked: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox (multi-select mode, F-0.10.17)
            if isSelectionMode {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isChecked ? .accentColor : .secondary)
                    .animation(.easeInOut(duration: 0.15), value: isChecked)
            }

            // Source Icon
            SourceIcon(source: RecordingSource(from: meta.source), size: .medium)

            VStack(alignment: .leading, spacing: 3) {
                // Title
                Text(meta.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                // Metadata: Source • Relative Time
                HStack(spacing: 4) {
                    Text(meta.source)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(absoluteTime(from: meta.startTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Right Side Info
            VStack(alignment: .trailing, spacing: 3) {
                // Duration
                Text(formatDuration(meta.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                // AI Badges & Status
                HStack(spacing: 6) {
                    // Processing Status Icon
                    StatusIcon(status: meta.status)

                    // AI Content Badges
                    HStack(spacing: 4) {
                        if meta.hasTranscript {
                            Image(systemName: "doc.text")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        if meta.hasSummary {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                    }
                }
            }

            // Drag handle (F-0.11.4) — isolated from row selection
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.4))
                .onDrag {
                    let recordingsDir = PathManager.shared.recordingsURL
                    let fileURL = recordingsDir.appendingPathComponent(meta.filename)
                    guard FileManager.default.fileExists(atPath: fileURL.path) else {
                        return NSItemProvider()
                    }
                    return NSItemProvider(object: fileURL as NSURL)
                }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            (isSelected || (isSelectionMode && isChecked))
                ? Color.accentColor.opacity(0.1)
                : Color.clear
        )
        .contentShape(Rectangle())
    }

    // MARK: - Helper Methods

    /// 格式化时长为 mm:ss 或 hh:mm:ss
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

    /// 显示录音开始的绝对时间（如 "2026/04/30 12:05"）
    private func absoluteTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Status Icon

struct StatusIcon: View {
    let status: MeetingMeta.ProcessingStatus

    var body: some View {
        Group {
            switch status {
            case .recording:
                Image(systemName: "circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 8))
            case .pending:
                Image(systemName: "clock")
                    .foregroundColor(.orange)
                    .font(.caption)
            case .processing:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Preview

#Preview("Recording Row") {
    VStack(spacing: 0) {
        RecordingRowView(
            meta: MeetingMeta(
                filename: "20260205-1400_Zoom.m4a",
                title: "Weekly Team Standup",
                source: "Zoom",
                startTime: Date().addingTimeInterval(-3600),
                duration: 1800,
                status: .completed
            ),
            isSelected: false
        )

        Divider()

        RecordingRowView(
            meta: MeetingMeta(
                filename: "20260205-1000_Manual.m4a",
                title: "Client Interview",
                source: "Manual",
                startTime: Date().addingTimeInterval(-86400),
                duration: 3600,
                status: .completed
            ),
            isSelected: true
        )

        Divider()

        RecordingRowView(
            meta: MeetingMeta(
                filename: "20260205-0900_Teams.m4a",
                title: "Product Review",
                source: "Teams",
                startTime: Date().addingTimeInterval(-172800),
                duration: 2700,
                status: .processing
            ),
            isSelected: false
        )
    }
    .padding()
    .frame(width: 300)
}
