import SwiftUI

struct RemindOverlayView: View {
    var appName: String
    var onStart: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 24, height: 24)

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text("Meeting Detected")
                    .font(.system(size: 13, weight: .bold))
                Text("Detected \(appName) meeting. Start recording?")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Start Recording Button
            Button(action: onStart) {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                    Text("Start")
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
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

struct RemindOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        RemindOverlayView(appName: "Zoom", onStart: {}, onDismiss: {})
            .padding()
            .background(Color.blue)
    }
}
