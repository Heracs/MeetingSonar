//
//  QualityPresetPicker.swift
//  MeetingSonar
//
//  Quality preset picker for LLM configuration
//  v1.1.0: Simplified parameter configuration using presets
//

import SwiftUI

/// Quality preset picker for LLM configuration
/// Allows users to select quality presets (fast/balanced/quality)
struct QualityPresetPicker: View {
    @Binding var selection: LLMQualityPreset
    @Binding var showAdvancedSettings: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("摘要质量")
                .font(.headline)

            Text("如需自定义参数，可进入高级设置")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(LLMQualityPreset.allCases) { preset in
                    PresetRow(
                        preset: preset,
                        isSelected: selection == preset,
                        onSelect: { selection = preset }
                    )
                }
            }

            // Advanced settings button
            Button {
                showAdvancedSettings = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text("高级设置...")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }
}

// MARK: - Preset Row

private struct PresetRow: View {
    let preset: LLMQualityPreset
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: preset.icon)
                    .font(.title3)
                    .foregroundColor(preset.swiftUIColor)
                    .frame(width: 24)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(preset.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if preset == .balanced {
                            Text("(推荐)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(preset.descriptionWithRecommendation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(backgroundColor)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.1)
        }
        return Color(nsColor: .controlBackgroundColor)
    }
}

// MARK: - LLMQualityPreset Extensions

extension LLMQualityPreset {
    var swiftUIColor: Color {
        switch self {
        case .fast: return .blue
        case .balanced: return .green
        case .quality: return .purple
        }
    }

    var descriptionWithRecommendation: String {
        let params = recommendedParameters
        switch self {
        case .fast:
            return "响应快，摘要简洁（推荐 16K tokens，temperature: \(String(format: "%.1f", params.temperature))）"
        case .balanced:
            return "速度与质量兼顾（推荐 32K tokens，temperature: \(String(format: "%.1f", params.temperature))）"
        case .quality:
            return "详细摘要，响应较慢（推荐 64K tokens，temperature: \(String(format: "%.1f", params.temperature))）"
        }
    }
}

// MARK: - Preview

#Preview("Quality Preset Picker") {
    struct PreviewWrapper: View {
        @State private var selection: LLMQualityPreset = .balanced
        @State private var showAdvanced = false

        var body: some View {
            QualityPresetPicker(
                selection: $selection,
                showAdvancedSettings: $showAdvanced
            )
            .padding()
            .frame(width: 400)
        }
    }

    return PreviewWrapper()
}
