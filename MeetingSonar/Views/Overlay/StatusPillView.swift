import SwiftUI

/// Two-state recording status overlay using fixed-panel approach.
/// The NSPanel size is fixed at the maximum (expanded) dimensions.
/// SwiftUI handles all visual transitions internally — the pill content
/// with its background/shadow is positioned at `.bottomLeading` within
/// the transparent panel, growing from bottom-left toward upper-right.
struct StatusPillView: View {
    let duration: TimeInterval
    let isPaused: Bool
    let includeSystemAudio: Bool
    let includeMicrophone: Bool

    /// External expand request from the controller (e.g. auto-expand on recording start).
    let isExpandedByController: Bool

    // MARK: - Callbacks
    var onClose: () -> Void
    var onToggleSystemAudio: (Bool) -> Void
    var onToggleMicrophone: (Bool) -> Void
    var onPause: () -> Void
    var onResume: () -> Void
    var onHoverChanged: (Bool) -> Void

    /// Tracks whether mouse is inside the visible content area.
    @State private var isMouseInside = false
    @State private var collapseTask: Task<Void, Never>?

    /// Merged expand state: expanded if controller says so OR mouse is hovering.
    private var isExpanded: Bool {
        isExpandedByController || isMouseInside
    }

    // MARK: - Layout Constants

    /// Fixed panel size (always the expanded maximum). The NSPanel
    /// is created at this size and never changes.
    static let panelWidth: CGFloat = 230
    static let panelHeight: CGFloat = 200

    private var timeString: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private var indicatorColor: Color {
        isPaused ? .orange : .red
    }

    var body: some View {
        // The pill content — sized naturally by its content,
        // with background and shape applied directly.
        pillContent
            // Position at bottom-left of the fixed-size panel.
            .frame(
                width: Self.panelWidth,
                height: Self.panelHeight,
                alignment: .bottomLeading
            )
    }

    /// The visible pill: a VStack with background, corners, and shadow.
    /// Its size changes naturally based on `isExpanded`.
    private var pillContent: some View {
        VStack(spacing: 0) {
            if isExpanded {
                actionButtons
                    .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 8)

                audioToggles
                    .padding(.vertical, 6)

                Divider()
                    .padding(.horizontal, 8)
            }

            statusRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isExpanded ? 10 : 8)
        .background(.ultraThinMaterial)
        .cornerRadius(isExpanded ? 12 : 20)
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 12 : 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
        .fixedSize()
        .onHover { hovering in
            if hovering {
                collapseTask?.cancel()
                collapseTask = nil
                isMouseInside = true
                onHoverChanged(true)
            } else {
                collapseTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    isMouseInside = false
                    onHoverChanged(false)
                }
            }
        }
        // Animate expand/collapse driven by the merged isExpanded computed property.
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
    }

    // MARK: - Status Row (always visible)

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 10, height: 10)
                .shadow(color: indicatorColor.opacity(0.6), radius: 4)

            Text(isPaused ? "Paused" : "Rec")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Text(timeString)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Audio Source Toggles

    private var audioToggles: some View {
        VStack(spacing: 4) {
            Toggle(isOn: Binding(
                get: { includeSystemAudio },
                set: { onToggleSystemAudio($0) }
            )) {
                Label("settings.audio.systemAudio", systemImage: "speaker.wave.2")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: Binding(
                get: { includeMicrophone },
                set: { onToggleMicrophone($0) }
            )) {
                Label("settings.audio.microphone", systemImage: "mic")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: { isPaused ? onResume() : onPause() }) {
                Label(
                    isPaused ? "recording.resume" : "recording.pause",
                    systemImage: isPaused ? "play.fill" : "pause.fill"
                )
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive, action: onClose) {
                Label("recording.stop", systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Preview

struct StatusPillView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            StatusPillView(
                duration: 125,
                isPaused: false,
                includeSystemAudio: true,
                includeMicrophone: true,
                isExpandedByController: false,
                onClose: {},
                onToggleSystemAudio: { _ in },
                onToggleMicrophone: { _ in },
                onPause: {},
                onResume: {},
                onHoverChanged: { _ in }
            )

            StatusPillView(
                duration: 3605,
                isPaused: true,
                includeSystemAudio: true,
                includeMicrophone: false,
                isExpandedByController: true,
                onClose: {},
                onToggleSystemAudio: { _ in },
                onToggleMicrophone: { _ in },
                onPause: {},
                onResume: {},
                onHoverChanged: { _ in }
            )
        }
        .padding(40)
        .background(Color.gray.opacity(0.3))
    }
}
