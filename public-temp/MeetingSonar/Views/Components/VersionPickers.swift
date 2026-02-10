//
//  VersionPickers.swift
//  MeetingSonar
//
//  F-11.1: Version Management Enhancement
//  Version picker components for transcript and summary
//

import SwiftUI

// MARK: - Transcript Version Picker

/// 转录版本选择器
struct TranscriptVersionPicker: View {
    let versions: [TranscriptVersion]
    @Binding var selectedVersionId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 主选择器
            HStack(spacing: 8) {
                Text("版本:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $selectedVersionId) {
                    ForEach(sortedVersions) { version in
                        Text(version.displayName)
                            .tag(version.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
                .controlSize(.small)
            }

            // 选中版本的详细信息
            if let selectedId = selectedVersionId,
               let version = versions.first(where: { $0.id == selectedId }) {
                VersionDetailView(version: version)
                    .padding(.leading, 4)
            }
        }
    }

    private var sortedVersions: [TranscriptVersion] {
        versions.sorted { $0.versionNumber > $1.versionNumber }
    }
}

// MARK: - Summary Version Picker

/// 摘要版本选择器（包含来源转录信息）
struct SummaryVersionPicker: View {
    let versions: [SummaryVersion]
    let transcriptVersions: [TranscriptVersion]
    @Binding var selectedVersionId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 主选择器
            HStack(spacing: 8) {
                Text("版本:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $selectedVersionId) {
                    ForEach(sortedVersions) { version in
                        Text(version.displayName)
                            .tag(version.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
                .controlSize(.small)
            }

            // 选中版本的详细信息
            if let selectedId = selectedVersionId,
               let version = versions.first(where: { $0.id == selectedId }) {
                SummaryVersionDetailView(
                    version: version,
                    sourceTranscript: transcriptVersions.first { $0.id == version.sourceTranscriptId }
                )
                .padding(.leading, 4)
            }
        }
    }

    private var sortedVersions: [SummaryVersion] {
        versions.sorted { $0.versionNumber > $1.versionNumber }
    }
}

// MARK: - Version Detail Views

/// 转录版本详细信息视图
private struct VersionDetailView: View {
    let version: TranscriptVersion

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 模型信息
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(version.modelInfo.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // 提示词信息
            HStack(spacing: 4) {
                Image(systemName: "text.quote")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(version.promptInfo.promptName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // 统计信息
            if let stats = version.statistics {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("RTF: \(String(format: "%.2f", stats.rtf)) · \(stats.wordCount) 字")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

/// 摘要版本详细信息视图（包含来源链）
private struct SummaryVersionDetailView: View {
    let version: SummaryVersion
    let sourceTranscript: TranscriptVersion?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 模型信息
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(version.modelInfo.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // 提示词信息
            HStack(spacing: 4) {
                Image(systemName: "text.quote")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(version.promptInfo.promptName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // 来源转录版本（关键信息）
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundColor(.blue)

                if let source = sourceTranscript {
                    Text("基于: 转录 V\(source.versionNumber)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                } else {
                    Text("基于: 转录 V\(version.sourceTranscriptVersionNumber)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            .help("此摘要基于转录版本 \(version.sourceTranscriptVersionNumber) 生成")

            // 统计信息
            if let stats = version.statistics {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let inputTokens = stats.inputTokens,
                       let outputTokens = stats.outputTokens {
                        Text("\(inputTokens)/\(outputTokens) tokens · \(stats.wordCount) 字")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(stats.wordCount) 字")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Compact Version Pickers (for toolbar use)

/// 紧凑版转录版本选择器（用于空间有限的场景）
struct CompactTranscriptVersionPicker: View {
    let versions: [TranscriptVersion]
    @Binding var selectedVersionId: UUID?

    var body: some View {
        HStack(spacing: 6) {
            Text("版本")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("", selection: $selectedVersionId) {
                ForEach(sortedVersions) { version in
                    Text("V\(version.versionNumber)")
                        .tag(version.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(width: 80)
            .controlSize(.small)
        }
    }

    private var sortedVersions: [TranscriptVersion] {
        versions.sorted { $0.versionNumber > $1.versionNumber }
    }
}

/// 紧凑版摘要版本选择器
struct CompactSummaryVersionPicker: View {
    let versions: [SummaryVersion]
    @Binding var selectedVersionId: UUID?

    var body: some View {
        HStack(spacing: 6) {
            Text("版本")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("", selection: $selectedVersionId) {
                ForEach(sortedVersions) { version in
                    Text("V\(version.versionNumber)")
                        .tag(version.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(width: 80)
            .controlSize(.small)
        }
    }

    private var sortedVersions: [SummaryVersion] {
        versions.sorted { $0.versionNumber > $1.versionNumber }
    }
}

// MARK: - Preview

#Preview("Transcript Version Picker") {
    PreviewTranscriptVersionPicker()
}

@available(macOS 13.0, *)
private struct PreviewTranscriptVersionPicker: View {
    @State var selectedId: UUID? = nil

    let versions = [
        TranscriptVersion(
            versionNumber: 2,
            modelInfo: ModelVersionInfo(modelId: "1", displayName: "Qwen3-ASR", provider: "Aliyun"),
            promptInfo: PromptVersionInfo(promptId: "1", promptName: "标准转录", contentPreview: "", category: .asr),
            filePath: "test.json",
            statistics: TranscriptStatistics(audioDuration: 120, processingTime: 48, wordCount: 3500, segmentCount: 45)
        ),
        TranscriptVersion(
            versionNumber: 1,
            modelInfo: ModelVersionInfo(modelId: "2", displayName: "Whisper-1", provider: "OpenAI"),
            promptInfo: PromptVersionInfo(promptId: "2", promptName: "精确转录", contentPreview: "", category: .asr),
            filePath: "test2.json",
            statistics: TranscriptStatistics(audioDuration: 120, processingTime: 60, wordCount: 3200, segmentCount: 42)
        )
    ]

    var body: some View {
        VStack {
            TranscriptVersionPicker(versions: versions, selectedVersionId: $selectedId)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
        }
        .onAppear {
            selectedId = versions.first?.id
        }
    }
}

#Preview("Summary Version Picker") {
    PreviewSummaryVersionPicker()
}

@available(macOS 13.0, *)
private struct PreviewSummaryVersionPicker: View {
    @State var selectedId: UUID? = nil

    let transcriptVersions = [
        TranscriptVersion(
            versionNumber: 2,
            modelInfo: ModelVersionInfo(modelId: "1", displayName: "Qwen3-ASR", provider: "Aliyun"),
            promptInfo: PromptVersionInfo(promptId: "1", promptName: "标准转录", contentPreview: "", category: .asr),
            filePath: "test.json"
        )
    ]

    let summaryVersions = [
        SummaryVersion(
            versionNumber: 1,
            modelInfo: ModelVersionInfo(modelId: "3", displayName: "Qwen-Max", provider: "Aliyun"),
            promptInfo: PromptVersionInfo(promptId: "3", promptName: "标准纪要", contentPreview: "", category: .llm),
            filePath: "summary.md",
            sourceTranscriptId: UUID(),
            sourceTranscriptVersionNumber: 2,
            statistics: SummaryStatistics(processingTime: 15, inputTokens: 3500, outputTokens: 800, wordCount: 1200)
        )
    ]

    var body: some View {
        VStack {
            SummaryVersionPicker(
                versions: summaryVersions,
                transcriptVersions: transcriptVersions,
                selectedVersionId: $selectedId
            )
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .onAppear {
            selectedId = summaryVersions.first?.id
        }
    }
}
