import SwiftUI

struct RemindOverlayView: View {
    var appName: String
    var mode: String = "remind"  // "remind" | "maxDuration"
    var durationMinutes: Int = 180
    var onStart: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        if mode == "maxDuration" {
            maxDurationBody
        } else {
            remindBody
        }
    }

    /// Existing remind mode — compact horizontal pill prompting user to start recording.
    private var remindBody: some View {
        HStack(spacing: 12) {
            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 24, height: 24)

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text("overlay.remind.title")
                    .font(.system(size: 13, weight: .bold))
                Text("overlay.remind.description.\(appName)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Start Recording Button
            Button(action: onStart) {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                    Text("overlay.remind.start")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.9))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            // Dismiss Button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 360, height: 48)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
    }

    /// maxDuration mode — vertical layout informing user the recording limit has been reached.
    private var maxDurationBody: some View {
        VStack(spacing: 12) {
            Text("Recording limit reached")
                .font(.headline)
            Text("The recording has reached the \(durationMinutes)-minute limit. Meeting may still be active. Start a new recording?")
                .font(.subheadline)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .frame(minWidth: 60)
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(action: onStart) {
                    Text("Start New Recording")
                        .frame(minWidth: 60)
                }
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding()
        .frame(width: 340)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
    }
}

struct RemindOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        RemindOverlayView(appName: "Zoom", onStart: {}, onDismiss: {})
            .padding()
            .background(Color.blue)
    }
}
