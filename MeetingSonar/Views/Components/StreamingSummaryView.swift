//
//  StreamingSummaryView.swift
//  MeetingSonar
//
//  Phase 3: Streaming summary display component
//  v1.1.0: Real-time streaming text display for AI summary generation
//

import SwiftUI

/// View for displaying streaming summary generation
@available(macOS 13.0, *)
struct StreamingSummaryView: View {
    let transcript: String
    let meetingID: UUID
    let config: CloudAIModelConfig
    let provider: any CloudServiceProvider

    @State private var viewModel = StreamingSummaryViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Control Bar
            StreamingControlBar(
                state: viewModel.state,
                wordCount: viewModel.wordCount,
                onStart: { startStreaming() },
                onStop: { viewModel.stopStreaming() },
                onRetry: { retryStreaming() }
            )

            Divider()

            // Content Area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        StreamingTextView(
                            text: viewModel.streamingText,
                            isComplete: viewModel.isComplete,
                            isStreaming: viewModel.isStreaming
                        )

                        // Animated cursor when streaming
                        if viewModel.isStreaming {
                            StreamingCursor()
                                .id("cursor")
                        }

                        Spacer(minLength: 20)
                    }
                    .padding()
                    .id("content-bottom")
                }
                .onChange(of: viewModel.streamingText) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .alert("生成失败", isPresented: .constant(!viewModel.errorMessage.isEmpty)) {
            Button("重试") { retryStreaming() }
            Button("取消", role: .cancel) { viewModel.stopStreaming() }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private func startStreaming() {
        viewModel.startStreaming(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: provider
        )
    }

    private func retryStreaming() {
        viewModel.retry(
            transcript: transcript,
            meetingID: meetingID,
            config: config,
            provider: provider
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo("content-bottom", anchor: .bottom)
        }
    }
}

// MARK: - Streaming Control Bar

@available(macOS 13.0, *)
struct StreamingControlBar: View {
    let state: StreamingState
    let wordCount: Int
    let onStart: () -> Void
    let onStop: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Leading: Status
            HStack(spacing: 8) {
                StreamingStatusIndicator(state: state)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Center: Word count (when streaming or completed)
            if state.isStreaming || state.isComplete {
                Text("\(wordCount) 字")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            // Trailing: Actions
            HStack(spacing: 8) {
                switch state {
                case .idle, .cancelled:
                    Button(action: onStart) {
                        Label("生成", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                case .streaming:
                    Button(action: onStop) {
                        Label("停止", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                case .completed:
                    Button(action: onStart) {
                        Label("重新生成", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                case .failed:
                    Button(action: onRetry) {
                        Label("重试", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                default:
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusText: String {
        switch state {
        case .idle: return "准备就绪"
        case .connecting: return "连接中..."
        case .streaming: return "生成中..."
        case .completed: return "已完成"
        case .failed: return "生成失败"
        case .cancelled: return "已取消"
        }
    }
}

// MARK: - Streaming Status Indicator

@available(macOS 13.0, *)
struct StreamingStatusIndicator: View {
    let state: StreamingState

    var body: some View {
        Group {
            switch state {
            case .idle:
                Image(systemName: "circle")
                    .foregroundColor(.secondary)

            case .connecting:
                ThreeDotIndicator()
                    .foregroundColor(.blue)

            case .streaming:
                PulsingDot()
                    .foregroundColor(.accentColor)

            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)

            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)

            case .cancelled:
                Image(systemName: "stop.circle.fill")
                    .foregroundColor(.orange)
            }
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Pulsing Dot Animation

@available(macOS 13.0, *)
private struct PulsingDot: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 8, height: 8)
            .opacity(isAnimating ? 1.0 : 0.3)
            .scaleEffect(isAnimating ? 1.0 : 0.8)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

// MARK: - Three Dot Indicator

@available(macOS 13.0, *)
private struct ThreeDotIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 4, height: 4)
                    .opacity(phase == index ? 1.0 : 0.3)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: - Streaming Text View

@available(macOS 13.0, *)
struct StreamingTextView: View {
    let text: String
    let isComplete: Bool
    let isStreaming: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isComplete {
                // Full markdown rendering when complete
                Text(parseMarkdown(text))
                    .textSelection(.enabled)
            } else {
                // Plain text during streaming for better performance
                Text(text)
                    .textSelection(.enabled)
            }
        }
        .font(.body)
        .lineSpacing(4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parseMarkdown(_ text: String) -> AttributedString {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            return try AttributedString(markdown: text, options: options)
        } catch {
            return AttributedString(stringLiteral: text)
        }
    }
}

// MARK: - Streaming Cursor

@available(macOS 13.0, *)
private struct StreamingCursor: View {
    @State private var isVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: 16)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                value: isVisible
            )
            .onAppear { isVisible.toggle() }
    }
}

// MARK: - Preview

@available(macOS 13.0, *)
struct StreamingSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("Streaming Control Bar States:")
                .font(.headline)
                .padding()

            StreamingControlBar(
                state: .idle,
                wordCount: 0,
                onStart: {},
                onStop: {},
                onRetry: {}
            )

            StreamingControlBar(
                state: .streaming(progress: 0.5),
                wordCount: 1234,
                onStart: {},
                onStop: {},
                onRetry: {}
            )

            StreamingControlBar(
                state: .completed(text: "Done"),
                wordCount: 5678,
                onStart: {},
                onStop: {},
                onRetry: {}
            )
        }
        .padding()
        .frame(width: 600)
    }
}
