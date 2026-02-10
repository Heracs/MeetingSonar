//
//  PlayerControlsView.swift
//  MeetingSonar
//
//  Created by MeetingSonar Team.
//  Copyright © 2024 MeetingSonar. All rights reserved.
//

import SwiftUI

/// Reusable player controls view.
/// Implements F-7.0 Audio Player UI: Play/Pause, Slider, Time Labels.
@available(macOS 13.0, *)
struct PlayerControlsView: View {
    @ObservedObject var playerManager: AudioPlayerManager
    @State private var isDragging: Bool = false
    @State private var dragTime: Double = 0
    
    var body: some View {
        VStack(spacing: 8) {
            // Error overlay
            if let error = playerManager.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // Time Labels
            HStack {
                Text(formatTime(isDragging ? dragTime : playerManager.currentTime))
                    .font(.monospacedDigit(.caption)())
                Spacer()
                Text(formatTime(playerManager.duration))
                    .font(.monospacedDigit(.caption)())
            }
            .foregroundColor(.secondary)
            
            // Slider (Scrubber)
            Slider(
                value: Binding(
                    get: { isDragging ? dragTime : playerManager.currentTime },
                    set: { newValue in
                        dragTime = newValue
                        // We strictly only seek on commit (drag end) to avoid stuttering, but updating dragTime updates UI
                    }
                ),
                in: 0...max(0.1, playerManager.duration),
                onEditingChanged: { editing in
                    isDragging = editing
                    if editing {
                         // Started dragging
                         dragTime = playerManager.currentTime
                    } else {
                         // Ended dragging, commit seek
                         playerManager.seek(to: dragTime)
                    }
                }
            )
            .disabled(playerManager.duration == 0)
            
            // Buttons
            HStack(spacing: 20) {
                Button(action: { playerManager.skip(seconds: -15) }) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(playerManager.duration == 0)
                
                Button(action: { playerManager.togglePlayPause() }) {
                    Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                }
                .buttonStyle(.plain)
                .disabled(playerManager.duration == 0)
                
                Button(action: { playerManager.skip(seconds: 15) }) {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(playerManager.duration == 0)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
        let totalSeconds = Int(seconds)
        let mm = totalSeconds / 60
        let ss = totalSeconds % 60
        // Extend to HH:MM:SS if needed, v0.7.0 specific MM:SS for simplicity as meetings > 1h
        if totalSeconds >= 3600 {
            let hh = totalSeconds / 3600
            let mmLeft = (totalSeconds % 3600) / 60
            return String(format: "%02d:%02d:%02d", hh, mmLeft, ss)
        }
        return String(format: "%02d:%02d", mm, ss)
    }
}
