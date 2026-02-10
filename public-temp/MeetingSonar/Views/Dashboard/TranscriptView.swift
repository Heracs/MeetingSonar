//
//  TranscriptView.swift
//  MeetingSonar
//
//  Created by MeetingSonar Team.
//  Copyright © 2024 MeetingSonar. All rights reserved.
//

import SwiftUI

/// View for displaying transcript lines with click-to-seek functionality.
/// Implements F-7.1.
struct TranscriptView: View {
    let segments: [TranscriptSegment]
    let currentTime: TimeInterval
    let onSeek: (TimeInterval) -> Void
    
    // Auto-scroll state
    @State private var autoScroll: Bool = true
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(segments) { segment in
                        TranscriptRow(
                            segment: segment,
                            isActive: isSegmentActive(segment, currentTime: currentTime)
                        )
                        .id(segment.id) // Use stable ID for scrolling
                        .onTapGesture {
                            onSeek(segment.start)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: currentTime) { time in
                if autoScroll {
                    if let activeSegment = segments.first(where: { time >= $0.start && time < $0.end }) {
                        withAnimation {
                            proxy.scrollTo(activeSegment.id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    private func isSegmentActive(_ segment: TranscriptSegment, currentTime: TimeInterval) -> Bool {
        return currentTime >= segment.start && currentTime < segment.end
    }
}

struct TranscriptRow: View {
    let segment: TranscriptSegment
    let isActive: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(formatTime(segment.start))
                .font(.monospacedDigit(.caption)())
                .foregroundColor(.secondary)
                .frame(width: 45, alignment: .leading)
            
            Text(segment.text)
                .font(.body)
                .foregroundColor(isActive ? .accentColor : .primary)
                .fontWeight(isActive ? .medium : .regular)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mm = Int(seconds) / 60
        let ss = Int(seconds) % 60
        return String(format: "%02d:%02d", mm, ss)
    }
}
