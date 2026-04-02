//
//  TranscriptAttributedStringBuilder.swift
//  MeetingSonar
//
//  Converts transcript segments to NSAttributedString for NSTextView rendering.
//  Timestamps are rendered as clickable links for seek functionality.
//

import AppKit

/// Builds NSAttributedString from transcript segments with clickable timestamps.
///
/// Each segment is rendered as: `MM:SS  Segment text\n`
/// Timestamps are link-attributed for click-to-seek in SelectableTextView.
/// Use `buildWithRanges` to get per-segment ranges for highlight tracking.
struct TranscriptAttributedStringBuilder {

    /// URL scheme used for seek links on timestamps.
    static let seekScheme = "meetingsonar-seek"

    struct Style {
        var bodyFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
        var timestampFont: NSFont = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        var textColor: NSColor = .labelColor
        var timestampColor: NSColor = .secondaryLabelColor
        var lineSpacing: CGFloat = 6
    }

    let style: Style

    init(style: Style = Style()) {
        self.style = style
    }

    // MARK: - Public API

    /// Builds attributed string from segments. For display-only (no highlight tracking).
    func build(from segments: [TranscriptSegment]) -> NSAttributedString {
        buildWithRanges(from: segments).0
    }

    /// Builds attributed string and returns per-segment ranges for highlight tracking.
    /// Returns: (attributedString, [NSRange]) where ranges[i] covers the full line of segments[i].
    func buildWithRanges(from segments: [TranscriptSegment]) -> (NSAttributedString, [NSRange]) {
        let result = NSMutableAttributedString()
        var ranges: [NSRange] = []

        for (index, segment) in segments.enumerated() {
            let lineStart = result.length

            // Timestamp with link for click-to-seek
            let timestamp = formatTime(segment.start)
            let seekURL = URL(string: "\(Self.seekScheme)://seek?time=\(segment.start)")!
            let timestampAttrs: [NSAttributedString.Key: Any] = [
                .font: style.timestampFont,
                .foregroundColor: style.timestampColor,
                .link: seekURL
            ]
            result.append(NSAttributedString(string: timestamp, attributes: timestampAttrs))

            // Separator between timestamp and text
            result.append(NSAttributedString(string: "  ", attributes: [
                .font: style.bodyFont
            ]))

            // Segment text
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.lineSpacing = style.lineSpacing
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: style.bodyFont,
                .foregroundColor: style.textColor,
                .paragraphStyle: paraStyle
            ]
            result.append(NSAttributedString(string: segment.text, attributes: textAttrs))

            let lineEnd = result.length
            ranges.append(NSRange(location: lineStart, length: lineEnd - lineStart))

            // Newline between segments
            if index < segments.count - 1 {
                result.append(NSAttributedString(string: "\n\n"))
            }
        }

        return (result, ranges)
    }

    /// Parses seek time from a timestamp link URL.
    static func seekTime(from url: URL) -> TimeInterval? {
        guard url.scheme == seekScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let timeString = components.queryItems?.first(where: { $0.name == "time" })?.value,
              let time = TimeInterval(timeString) else {
            return nil
        }
        return time
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mm = Int(seconds) / 60
        let ss = Int(seconds) % 60
        return String(format: "%02d:%02d", mm, ss)
    }
}
