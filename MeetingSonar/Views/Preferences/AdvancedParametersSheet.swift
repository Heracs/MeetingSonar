//
//  AdvancedParametersSheet.swift
//  MeetingSonar
//
//  Advanced parameters configuration sheet for LLM settings
//  v1.1.0: Optional parameter configuration (uses provider defaults if not set)
//

import SwiftUI

/// Advanced parameters configuration sheet
/// Allows users to optionally configure temperature, maxTokens, and topP
/// If parameters are not set, provider defaults are used
struct AdvancedParametersSheet: View {
    @Binding var temperature: Double?
    @Binding var maxTokens: Int?
    @Binding var topP: Double?

    @Environment(\.dismiss) private var dismiss

    // Local state for sliders
    @State private var tempValue: Double = 0.7
    @State private var topPValue: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("高级参数设置")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Form content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Info section
                    InfoSection()

                    Divider()

                    // Temperature
                    TemperatureSection(
                        temperature: $temperature,
                        sliderValue: $tempValue
                    )

                    Divider()

                    // Max Tokens
                    MaxTokensSection(maxTokens: $maxTokens)

                    Divider()

                    // Top P
                    TopPSection(
                        topP: $topP,
                        sliderValue: $topPValue
                    )
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Button("重置为默认") {
                    resetToDefaults()
                }
                .buttonStyle(.link)

                Spacer()

                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding()
        }
        .frame(width: 450, height: 550)
        .onAppear {
            // Initialize slider values from binding values
            tempValue = temperature ?? 0.7
            topPValue = topP ?? 1.0
        }
    }

    private func resetToDefaults() {
        temperature = nil
        maxTokens = nil
        topP = nil
        tempValue = 0.7
        topPValue = 1.0
    }
}

// MARK: - Info Section

private struct InfoSection: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
            Text("如果留空，将使用各厂家的默认值。只有明确设置的参数会被发送到 API。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Temperature Section

private struct TemperatureSection: View {
    @Binding var temperature: Double?
    @Binding var sliderValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Temperature")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let temp = temperature {
                    Text(String(format: "%.1f", temp))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundColor(.primary)

                    Button {
                        temperature = nil
                        sliderValue = 0.7
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("默认")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Slider(
                value: $sliderValue,
                in: 0...2,
                step: 0.1
            )
            .onChange(of: sliderValue) { newValue in
                temperature = newValue
            }

            HStack {
                Text("更确定")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("更随机")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Max Tokens Section

private struct MaxTokensSection: View {
    @Binding var maxTokens: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Max Tokens")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let tokens = maxTokens {
                    Text(formatTokenCount(tokens))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundColor(.primary)

                    Button {
                        maxTokens = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("默认")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Token count selector
            Picker("", selection: Binding(
                get: {
                    MaxTokensOption(maxTokens) ?? .default
                },
                set: { option in
                    maxTokens = option.tokenValue
                }
            )) {
                ForEach(MaxTokensOption.allCases) { option in
                    Text(option.displayName)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return "\(count / 1000)K"
        }
        return "\(count)"
    }
}

// MARK: - Top P Section

private struct TopPSection: View {
    @Binding var topP: Double?
    @Binding var sliderValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top P")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let p = topP {
                    Text(String(format: "%.2f", p))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundColor(.primary)

                    Button {
                        topP = nil
                        sliderValue = 1.0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("默认")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Slider(
                value: $sliderValue,
                in: 0...1,
                step: 0.05
            )
            .onChange(of: sliderValue) { newValue in
                topP = newValue
            }

            HStack {
                Text("0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Max Tokens Option

enum MaxTokensOption: String, CaseIterable, Identifiable {
    case `default` = "default"
    case k16 = "16384"
    case k32 = "32768"
    case k64 = "65536"
    case k128 = "131072"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "默认"
        case .k16: return "16K"
        case .k32: return "32K"
        case .k64: return "64K"
        case .k128: return "128K"
        }
    }

    var tokenValue: Int? {
        switch self {
        case .default: return nil
        case .k16: return 16384
        case .k32: return 32768
        case .k64: return 65536
        case .k128: return 131072
        }
    }

    init?(_ tokenCount: Int?) {
        guard let count = tokenCount else {
            self = .default
            return
        }
        switch count {
        case 16384: self = .k16
        case 32768: self = .k32
        case 65536: self = .k64
        case 131072: self = .k128
        default: self = .default
        }
    }
}

// MARK: - Preview

#Preview("Advanced Parameters Sheet") {
    struct PreviewWrapper: View {
        @State private var temperature: Double? = nil
        @State private var maxTokens: Int? = nil
        @State private var topP: Double? = nil

        var body: some View {
            AdvancedParametersSheet(
                temperature: $temperature,
                maxTokens: $maxTokens,
                topP: $topP
            )
        }
    }

    return PreviewWrapper()
}
