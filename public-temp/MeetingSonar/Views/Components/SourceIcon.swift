//
//  SourceIcon.swift
//  MeetingSonar
//
//  F-11.2: Recording Manager UI Redesign
//  Source icon component for indicating audio source
//

import SwiftUI

/// 录音来源类型
enum RecordingSource: String, CaseIterable {
    case zoom = "Zoom"
    case teams = "Teams"
    case meet = "Meet"
    case webex = "Webex"
    case manual = "Manual"
    case mic = "Mic"
    case systemAudio = "System Audio"
    case system = "System"
    case unknown = "Unknown"

    /// 从字符串识别来源
    init(from string: String) {
        let lowercased = string.lowercased()
        switch lowercased {
        case "zoom":
            self = .zoom
        case "teams", "microsoft teams":
            self = .teams
        case "meet", "google meet":
            self = .meet
        case "webex", "cisco webex":
            self = .webex
        case "manual", "mic", "microphone":
            self = .manual
        case "system audio", "system", "screen capture":
            self = .systemAudio
        default:
            self = .unknown
        }
    }
}

/// 来源图标视图
struct SourceIcon: View {
    let source: RecordingSource
    var size: SourceIconSize = .medium

    enum SourceIconSize {
        case small   // 20x20
        case medium  // 28x28
        case large   // 48x48

        var dimension: CGFloat {
            switch self {
            case .small: return 20
            case .medium: return 28
            case .large: return 48
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return 10
            case .medium: return 12
            case .large: return 20
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 8
            }
        }
    }

    var icon: String {
        switch source {
        case .zoom:
            return "video.fill"
        case .teams:
            return "person.2.fill"
        case .meet:
            return "video.bubble.fill"
        case .webex:
            return "globe"
        case .manual, .mic:
            return "mic.fill"
        case .systemAudio, .system:
            return "speaker.wave.2.fill"
        case .unknown:
            return "waveform"
        }
    }

    var color: Color {
        switch source {
        case .zoom:
            return .blue
        case .teams:
            return .purple
        case .meet:
            return .green
        case .webex:
            return .cyan
        case .manual, .mic:
            return .orange
        case .systemAudio, .system:
            return .gray
        case .unknown:
            return .secondary
        }
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size.iconSize, weight: .medium))
            .foregroundColor(color)
            .frame(width: size.dimension, height: size.dimension)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
    }
}

/// 带有文字的来源标签
struct SourceLabel: View {
    let source: String

    var recordingSource: RecordingSource {
        RecordingSource(from: source)
    }

    var body: some View {
        HStack(spacing: 4) {
            SourceIcon(source: recordingSource, size: .small)
            Text(recordingSource.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Source Icons") {
    VStack(spacing: 16) {
        HStack(spacing: 16) {
            VStack {
                SourceIcon(source: RecordingSource.zoom, size: .large)
                Text("Zoom")
                    .font(.caption2)
            }
            VStack {
                SourceIcon(source: RecordingSource.teams, size: .large)
                Text("Teams")
                    .font(.caption2)
            }
            VStack {
                SourceIcon(source: RecordingSource.meet, size: .large)
                Text("Meet")
                    .font(.caption2)
            }
            VStack {
                SourceIcon(source: RecordingSource.manual, size: .large)
                Text("Manual")
                    .font(.caption2)
            }
            VStack {
                SourceIcon(source: RecordingSource.systemAudio, size: .large)
                Text("System")
                    .font(.caption2)
            }
        }

        Divider()

        HStack(spacing: 16) {
            SourceIcon(source: RecordingSource.zoom, size: .medium)
            SourceIcon(source: RecordingSource.teams, size: .medium)
            SourceIcon(source: RecordingSource.meet, size: .medium)
            SourceIcon(source: RecordingSource.manual, size: .medium)
            SourceIcon(source: RecordingSource.systemAudio, size: .medium)
        }

        Divider()

        HStack(spacing: 16) {
            SourceIcon(source: RecordingSource.zoom, size: .small)
            SourceIcon(source: RecordingSource.teams, size: .small)
            SourceIcon(source: RecordingSource.meet, size: .small)
            SourceIcon(source: RecordingSource.manual, size: .small)
            SourceIcon(source: RecordingSource.systemAudio, size: .small)
        }
    }
    .padding()
}

#Preview("Source Label") {
    VStack(spacing: 8) {
        SourceLabel(source: "Zoom")
        SourceLabel(source: "Teams")
        SourceLabel(source: "Manual")
    }
    .padding()
}
