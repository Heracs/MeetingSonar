//
//  TranscriptAttributedStringTests.swift
//  MeetingSonarTests
//
//  Tests for TranscriptAttributedStringBuilder — segments to NSAttributedString conversion.
//

import Testing
import AppKit
@testable import MeetingSonar

@Suite("TranscriptAttributedStringBuilder")
@MainActor
struct TranscriptAttributedStringTests {

    let builder = TranscriptAttributedStringBuilder()

    // MARK: - Basic Rendering

    @Test("Single segment renders with timestamp and text")
    func singleSegment() {
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "Hello world")
        ]
        let result = builder.build(from: segments)
        #expect(result.string.contains("00:00"))
        #expect(result.string.contains("Hello world"))
    }

    @Test("Multiple segments each on separate lines")
    func multipleSegments() {
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "First"),
            TranscriptSegment(start: 5, end: 10, text: "Second")
        ]
        let result = builder.build(from: segments)
        #expect(result.string.contains("First"))
        #expect(result.string.contains("Second"))
        #expect(result.string.contains("00:00"))
        #expect(result.string.contains("00:05"))
    }

    @Test("Timestamp formats correctly for minutes and seconds")
    func timestampFormat() {
        let segments = [
            TranscriptSegment(start: 125, end: 130, text: "At two minutes")
        ]
        let result = builder.build(from: segments)
        #expect(result.string.contains("02:05"))
    }

    @Test("Hour-long timestamp formats correctly")
    func hourTimestamp() {
        let segments = [
            TranscriptSegment(start: 3661, end: 3665, text: "Over an hour")
        ]
        let result = builder.build(from: segments)
        // 3661 seconds = 61 minutes 1 second
        #expect(result.string.contains("61:01"))
    }

    // MARK: - Timestamp Links

    @Test("Timestamp has link attribute for click-to-seek")
    func timestampHasLink() {
        let segments = [
            TranscriptSegment(start: 30.5, end: 35, text: "Some text")
        ]
        let result = builder.build(from: segments)
        let nsString = result.string as NSString
        let timestampRange = nsString.range(of: "00:30")
        #expect(timestampRange.location != NSNotFound)
        let link = result.attribute(.link, at: timestampRange.location, effectiveRange: nil)
        #expect(link != nil)
        if let url = link as? URL {
            #expect(url.absoluteString.contains("30.5"))
        }
    }

    @Test("seekTime parses time from URL correctly")
    func seekTimeParsing() {
        let url = URL(string: "meetingsonar-seek://seek?time=125.5")!
        let time = TranscriptAttributedStringBuilder.seekTime(from: url)
        #expect(time == 125.5)
    }

    @Test("seekTime returns nil for non-seek URL")
    func seekTimeRejectsInvalidURL() {
        let url = URL(string: "https://example.com")!
        let time = TranscriptAttributedStringBuilder.seekTime(from: url)
        #expect(time == nil)
    }

    // MARK: - Styling

    @Test("Timestamp uses monospaced font")
    func timestampFont() {
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "Text")
        ]
        let result = builder.build(from: segments)
        let nsString = result.string as NSString
        let timestampRange = nsString.range(of: "00:00")
        let font = result.attribute(.font, at: timestampRange.location, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.isFixedPitch)
    }

    @Test("Segment text uses body font")
    func bodyFont() {
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "Body text here")
        ]
        let result = builder.build(from: segments)
        let nsString = result.string as NSString
        let textRange = nsString.range(of: "Body text here")
        let font = result.attribute(.font, at: textRange.location, effectiveRange: nil) as? NSFont
        #expect(font == .systemFont(ofSize: NSFont.systemFontSize))
    }

    // MARK: - Segment Ranges

    @Test("buildWithRanges returns correct ranges for each segment")
    func segmentRanges() {
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "First"),
            TranscriptSegment(start: 5, end: 10, text: "Second")
        ]
        let (_, ranges) = builder.buildWithRanges(from: segments)
        #expect(ranges.count == 2)
        #expect(ranges[0].length > 0)
        #expect(ranges[1].length > 0)
        #expect(ranges[1].location > ranges[0].location)
    }

    // MARK: - Edge Cases

    @Test("Empty segments returns empty attributed string")
    func emptySegments() {
        let result = builder.build(from: [])
        #expect(result.length == 0)
    }

    @Test("Segment with empty text still renders timestamp")
    func emptyText() {
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "")
        ]
        let result = builder.build(from: segments)
        #expect(result.string.contains("00:00"))
    }
}
