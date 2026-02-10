import SwiftUI

struct StartOverlayView: View {
    // Callback to stop recording
    var onStop: () -> Void
    var onClose: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 24, height: 24)
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text("MeetingSonar")
                    .font(.system(size: 13, weight: .bold))
                Text("Recording started")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Stop Button
            Button(action: onStop) {
                HStack(spacing: 4) {
                    Image(systemName: "square.fill")
                        .font(.system(size: 8))
                    Text("Stop")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.9))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            // Close Button (X)
            Button(action: onClose) {
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
        .frame(width: 300, height: 48)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

struct StartOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        StartOverlayView(onStop: {}, onClose: {})
            .padding()
            .background(Color.blue) // To see transparency
    }
}
