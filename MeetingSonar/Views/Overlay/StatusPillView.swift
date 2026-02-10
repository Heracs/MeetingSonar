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

    @State private var isBlinking = false
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
        HStack(spacing: 6) {
            // Status indicator area
            HStack(spacing: 4) {
                // Recording status dot (red blinking / orange paused)
                Circle()
                    .fill(isPaused ? Color.orange : Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(isPaused ? 1.0 : (isBlinking ? 1.0 : 0.4))
                    .animation(isPaused ? nil : Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                               value: isBlinking)

                // MARK: - Audio Source Indicators (v1.0)
                //
                // Purpose: Visually display which audio sources are currently being recorded
                //
                // Why needed:
                // 1. Users can see at a glance which audio sources are being recorded
                // 2. Provides visual feedback confirming settings have taken effect
                HStack(spacing: 2) {
                    if includeSystemAudio {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    if includeMicrophone {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Duration display
            Text(isPaused ? "Paused: \(timeString)" : "Recording: \(timeString)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))

            // Dropdown indicator arrow
            Image(systemName: "chevron.down")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 160)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .onAppear {
            isBlinking = true
        }
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
