import SwiftUI

/// Status pill view for recording overlay with audio source control
/// v1.0 - Recording Scenario Optimization: Added dropdown menu for real-time audio source toggling
struct StatusPillView: View {
    let duration: TimeInterval
    let isPaused: Bool

    // MARK: - Audio Source State (v1.0)
    //
    // Purpose: Receive current audio source state for display and menu state
    //
    // Why needed:
    // 1. Need to display which audio sources are currently recording (via icons)
    // 2. Menu toggles need to bind to actual state
    let includeSystemAudio: Bool
    let includeMicrophone: Bool

    // MARK: - Callbacks
    //
    // onToggleSystemAudio and onToggleMicrophone are new callbacks
    // Called when user toggles audio sources in the menu, passed to RecordingService
    var onTap: () -> Void
    var onClose: () -> Void
    var onToggleSystemAudio: (Bool) -> Void  // v1.0: Toggle system audio callback
    var onToggleMicrophone: (Bool) -> Void   // v1.0: Toggle microphone callback

    @State private var isHovering = false

    private var timeString: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%02i:%02i:%02i", hours, minutes, seconds)
        } else {
            return String(format: "%02i:%02i", minutes, seconds)
        }
    }

    var body: some View {
        // Use Menu to implement dropdown functionality
        // MenuStyle set to borderlessButton so overall appearance is like a normal button
        Menu {
            // MARK: - Audio Source Control Section
            Section("settings.recording.audioSources") {
                // System Audio Toggle
                // Use Binding to associate Toggle state with passed properties and callbacks
                Toggle("settings.audio.systemAudio",
                       isOn: Binding(
                           get: { includeSystemAudio },
                           set: { onToggleSystemAudio($0) }
                       ))

                // Microphone Toggle
                Toggle("settings.audio.microphone",
                       isOn: Binding(
                           get: { includeMicrophone },
                           set: { onToggleMicrophone($0) }
                       ))
            }

            Divider()

            // Stop Recording button
            // Use destructive role to show in red, indicating this is a terminating action
            Button(role: .destructive) {
                onClose()
            } label: {
                Label("recording.stop", systemImage: "stop.fill")
            }
        } label: {
            // Menu button appearance (pillContent)
            pillContent
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden) // Hide default dropdown arrow, custom appearance
    }

    /// Pill appearance content
    /// Contains: Status indicator dot, audio source icons, duration, dropdown arrow
    private var pillContent: some View {
        HStack(spacing: 8) {
            // Recording indicator: red/orange dot with microphone icon
            HStack(spacing: 5) {
                // Recording status indicator using SF Symbol for reliable color rendering in Menu labels
                Image(systemName: isPaused ? "pause.circle.fill" : "record.circle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isPaused ? Color.orange : Color.red)
                    .symbolRenderingMode(.hierarchical)

                // Microphone icon as universal recording indicator
                Image(systemName: "mic.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isPaused ? .orange : .red)
            }

            // Duration display
            Text(isPaused ? "Paused: \(timeString)" : "Recording: \(timeString)")
                .font(.system(size: 14, weight: .medium, design: .monospaced))

            // Dropdown indicator arrow
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: 200)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Preview

struct StatusPillView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Preview with both sources
            StatusPillView(
                duration: 125,
                isPaused: false,
                includeSystemAudio: true,
                includeMicrophone: true,
                onTap: {},
                onClose: {},
                onToggleSystemAudio: { _ in },
                onToggleMicrophone: { _ in }
            )

            // Preview with system audio only
            StatusPillView(
                duration: 3605,
                isPaused: false,
                includeSystemAudio: true,
                includeMicrophone: false,
                onTap: {},
                onClose: {},
                onToggleSystemAudio: { _ in },
                onToggleMicrophone: { _ in }
            )

            // Preview paused
            StatusPillView(
                duration: 60,
                isPaused: true,
                includeSystemAudio: true,
                includeMicrophone: true,
                onTap: {},
                onClose: {},
                onToggleSystemAudio: { _ in },
                onToggleMicrophone: { _ in }
            )
        }
        .padding()
        .background(Color.gray)
    }
}
