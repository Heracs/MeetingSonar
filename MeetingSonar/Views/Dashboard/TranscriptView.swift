//
//  TranscriptView.swift
//  MeetingSonar
//
//  Created by MeetingSonar Team.
//  Copyright © 2024 MeetingSonar. All rights reserved.
//

import SwiftUI

/// Displays transcript segments with full text selection, click-to-seek timestamps,
/// and active segment highlighting during audio playback.
///
/// Uses NSTextView (via SelectableTextView) to solve SwiftUI's cross-view
/// text selection limitation. Timestamps are rendered as clickable links
/// that trigger seek via the onSeek callback.
struct TranscriptView: View {
    let segments: [TranscriptSegment]
    let currentTime: TimeInterval
    let onSeek: (TimeInterval) -> Void

    private let builder = TranscriptAttributedStringBuilder()

    /// Cached attributed string and per-segment ranges.
    /// Rebuilt only when segments change, not on every currentTime update.
    @State private var cachedContent: NSAttributedString = NSAttributedString()
    @State private var cachedRanges: [NSRange] = []

    var body: some View {
        let activeIndex = findActiveSegmentIndex()

        SelectableTextView(
            attributedString: cachedContent,
            backgroundColor: .textBackgroundColor,
            highlightRange: activeIndex.flatMap { cachedRanges.indices.contains($0) ? cachedRanges[$0] : nil },
            scrollToRange: activeIndex.flatMap { cachedRanges.indices.contains($0) ? cachedRanges[$0] : nil },
            onLinkClick: { url in
                if let time = TranscriptAttributedStringBuilder.seekTime(from: url) {
                    onSeek(time)
                }
            }
        )
        .onChange(of: segments) { newSegments in
            rebuildContent(from: newSegments)
        }
        .onAppear {
            rebuildContent(from: segments)
        }
    }

    /// Finds the active segment index for the current playback time.
    /// Handles ASR data where segments may have zero duration (start == end)
    /// by using the next segment's start time as the effective end boundary.
    private func findActiveSegmentIndex() -> Int? {
        for i in segments.indices {
            let start = segments[i].start
            let end: TimeInterval
            if segments[i].end > segments[i].start {
                // Normal segment with duration
                end = segments[i].end
            } else if i + 1 < segments.count {
                // Zero-duration segment: use next segment's start as boundary
                end = segments[i + 1].start
            } else {
                // Last segment with zero duration: match anything >= start
                return currentTime >= start ? i : nil
            }
            if currentTime >= start && currentTime < end {
                return i
            }
        }
        return nil
    }

    /// Rebuilds the cached attributed string and ranges when segments change.
    private func rebuildContent(from segments: [TranscriptSegment]) {
        let (content, ranges) = builder.buildWithRanges(from: segments)
        cachedContent = content
        cachedRanges = ranges
    }
}
