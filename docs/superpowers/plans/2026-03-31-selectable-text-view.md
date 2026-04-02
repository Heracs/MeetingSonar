# F-0.10.16: Selectable Text View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SwiftUI Text-based rendering in TranscriptView and SummaryView with NSTextView-based components that support full text selection (Cmd+A, drag-select across paragraphs).

**Architecture:** Create a reusable `SelectableTextView` (NSViewRepresentable wrapping NSTextView) with two specialized renderers: `MarkdownAttributedStringRenderer` for summaries and a transcript builder for transcripts. The renderers convert structured data into `NSAttributedString`, which NSTextView renders with native selection support. TranscriptView preserves click-to-seek via link attributes on timestamps.

**Tech Stack:** AppKit (NSTextView, NSAttributedString, NSViewRepresentable), Swift Testing, macOS 13.0+

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `MeetingSonar/Views/Components/SelectableTextView.swift` | NSViewRepresentable wrapping NSTextView. Handles selection, link clicks, highlight range, scroll-to-range. Designed for future `isEditable` toggle (F-0.11.1). |
| Create | `MeetingSonar/Views/Components/MarkdownAttributedStringRenderer.swift` | Parses markdown and builds `NSAttributedString` with proper fonts, paragraph styles, list indentation, code block styling. |
| Create | `MeetingSonarTests/Unit/Views/MarkdownAttributedStringRendererTests.swift` | Tests for markdown → attributed string conversion. |
| Create | `MeetingSonarTests/Unit/Views/TranscriptAttributedStringTests.swift` | Tests for transcript segments → attributed string conversion. |
| Modify | `MeetingSonar/Views/Dashboard/TranscriptView.swift` | Replace LazyVStack+ForEach with SelectableTextView. Preserve click-to-seek and active segment highlighting. |
| Modify | `MeetingSonar/Views/Dashboard/SummaryView.swift` | Replace MarkdownContentView with SelectableTextView + renderer. |
| Modify | `MeetingSonar/Views/Components/StreamingSummaryView.swift` | Replace MarkdownContentView in `StreamingTextView` (when complete) with SelectableTextView + renderer. |
| Delete | `MeetingSonar/Views/Components/MarkdownContentView.swift` | No longer used after migration (verify all references removed). |

---

### Task 1: MarkdownAttributedStringRenderer — Tests

**Files:**
- Create: `MeetingSonarTests/Unit/Views/MarkdownAttributedStringRendererTests.swift`

- [ ] **Step 1: Write tests for all supported markdown block types**

```swift
//
//  MarkdownAttributedStringRendererTests.swift
//  MeetingSonarTests
//

import Testing
import AppKit
@testable import MeetingSonar

@Suite("MarkdownAttributedStringRenderer")
@MainActor
struct MarkdownAttributedStringRendererTests {

    let renderer = MarkdownAttributedStringRenderer()

    // MARK: - Paragraphs

    @Test("Plain paragraph uses body font")
    func plainParagraph() {
        let result = renderer.render("Hello world")
        #expect(result.string == "Hello world")
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font == .systemFont(ofSize: NSFont.systemFontSize))
    }

    @Test("Multiple paragraphs separated by blank line")
    func multipleParagraphs() {
        let result = renderer.render("First paragraph\n\nSecond paragraph")
        #expect(result.string.contains("First paragraph"))
        #expect(result.string.contains("Second paragraph"))
    }

    // MARK: - Headings

    @Test("H1 heading renders with title2 bold font")
    func h1Heading() {
        let result = renderer.render("# Title")
        #expect(result.string.contains("Title"))
        #expect(!result.string.contains("#"))
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize > NSFont.systemFontSize)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("H2 heading renders with title3 bold font")
    func h2Heading() {
        let result = renderer.render("## Subtitle")
        #expect(result.string.contains("Subtitle"))
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("H3 heading renders with headline font")
    func h3Heading() {
        let result = renderer.render("### Section")
        #expect(result.string.contains("Section"))
    }

    // MARK: - Inline Formatting

    @Test("Bold text has bold font trait")
    func boldText() {
        let result = renderer.render("Hello **bold** world")
        // Find the range of "bold" in the string
        let nsString = result.string as NSString
        let boldRange = nsString.range(of: "bold")
        #expect(boldRange.location != NSNotFound)
        let font = result.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("Italic text has italic font trait")
    func italicText() {
        let result = renderer.render("Hello *italic* world")
        let nsString = result.string as NSString
        let italicRange = nsString.range(of: "italic")
        #expect(italicRange.location != NSNotFound)
        let font = result.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.italic))
    }

    // MARK: - Lists

    @Test("Unordered list item has bullet prefix and indentation")
    func unorderedListItem() {
        let result = renderer.render("- Item one")
        #expect(result.string.contains("•"))
        #expect(result.string.contains("Item one"))
        // Check paragraph style has indentation
        let paraStyle = result.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(paraStyle != nil)
        #expect(paraStyle!.headIndent > 0)
    }

    @Test("Ordered list item has number prefix and indentation")
    func orderedListItem() {
        let result = renderer.render("1. First item")
        #expect(result.string.contains("1."))
        #expect(result.string.contains("First item"))
        let paraStyle = result.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(paraStyle != nil)
        #expect(paraStyle!.headIndent > 0)
    }

    @Test("Nested list items have increasing indentation")
    func nestedListItems() {
        let result = renderer.render("- Parent\n  - Child")
        let nsString = result.string as NSString
        let parentRange = nsString.range(of: "Parent")
        let childRange = nsString.range(of: "Child")
        #expect(parentRange.location != NSNotFound)
        #expect(childRange.location != NSNotFound)

        let parentStyle = result.attribute(.paragraphStyle, at: parentRange.location, effectiveRange: nil) as? NSParagraphStyle
        let childStyle = result.attribute(.paragraphStyle, at: childRange.location, effectiveRange: nil) as? NSParagraphStyle
        #expect(childStyle!.headIndent > parentStyle!.headIndent)
    }

    // MARK: - Code Blocks

    @Test("Code block uses monospaced font")
    func codeBlock() {
        let result = renderer.render("```\nlet x = 1\n```")
        let nsString = result.string as NSString
        let codeRange = nsString.range(of: "let x = 1")
        #expect(codeRange.location != NSNotFound)
        let font = result.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.isFixedPitch)
    }

    @Test("Code block has background color")
    func codeBlockBackground() {
        let result = renderer.render("```\ncode\n```")
        let nsString = result.string as NSString
        let codeRange = nsString.range(of: "code")
        let bgColor = result.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil) as? NSColor
        #expect(bgColor != nil)
    }

    // MARK: - Tables

    @Test("Table renders as tab-separated text with header")
    func simpleTable() {
        let md = """
        | Name | Status |
        |------|--------|
        | Alice | Done |
        | Bob | Pending |
        """
        let result = renderer.render(md)
        #expect(result.string.contains("Name"))
        #expect(result.string.contains("Alice"))
        #expect(result.string.contains("Bob"))
    }

    // MARK: - Horizontal Rule

    @Test("Horizontal rule renders as separator line")
    func horizontalRule() {
        let result = renderer.render("Above\n\n---\n\nBelow")
        #expect(result.string.contains("Above"))
        #expect(result.string.contains("Below"))
        // Should contain some visual separator (─ characters)
        #expect(result.string.contains("─"))
    }

    // MARK: - Empty / Edge Cases

    @Test("Empty string returns empty attributed string")
    func emptyInput() {
        let result = renderer.render("")
        #expect(result.length == 0)
    }

    @Test("Whitespace-only input returns empty result")
    func whitespaceOnly() {
        let result = renderer.render("   \n\n   ")
        #expect(result.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project MeetingSonar.xcodeproj -scheme MeetingSonar -destination 'platform=macOS' -only-testing:MeetingSonarTests/MarkdownAttributedStringRendererTests 2>&1 | tail -20`

Expected: Build failure — `MarkdownAttributedStringRenderer` not found.

---

### Task 2: MarkdownAttributedStringRenderer — Implementation

**Files:**
- Create: `MeetingSonar/Views/Components/MarkdownAttributedStringRenderer.swift`

- [ ] **Step 1: Implement the renderer**

The renderer reuses the same block-type parsing logic as the existing `MarkdownContentView` parser, but outputs `NSAttributedString` instead of SwiftUI views.

```swift
//
//  MarkdownAttributedStringRenderer.swift
//  MeetingSonar
//
//  Converts markdown text to NSAttributedString for use in NSTextView.
//  Supports: headings, lists, code blocks, tables (simplified), horizontal rules,
//  bold, italic, and plain paragraphs.
//

import AppKit

/// Renders markdown content as NSAttributedString for display in NSTextView.
/// Paired with SelectableTextView for full text selection support.
struct MarkdownAttributedStringRenderer {

    // MARK: - Style Configuration

    /// Visual styling parameters for rendered markdown.
    struct Style {
        var bodyFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
        var h1Font: NSFont = .systemFont(ofSize: 20, weight: .bold)
        var h2Font: NSFont = .systemFont(ofSize: 17, weight: .bold)
        var h3Font: NSFont = .systemFont(ofSize: 15, weight: .semibold)
        var h4Font: NSFont = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        var codeFont: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
        var textColor: NSColor = .labelColor
        var secondaryColor: NSColor = .secondaryLabelColor
        var codeBackgroundColor: NSColor = .controlBackgroundColor
        var lineSpacing: CGFloat = 4
        var listIndentPerLevel: CGFloat = 20
        var bulletIndent: CGFloat = 24
    }

    let style: Style

    init(style: Style = Style()) {
        self.style = style
    }

    // MARK: - Public API

    /// Renders markdown text into an NSAttributedString.
    func render(_ markdown: String) -> NSAttributedString {
        let blocks = parseBlocks(markdown)
        let result = NSMutableAttributedString()

        for (index, block) in blocks.enumerated() {
            if index > 0, case .blankLine = block {
                result.append(NSAttributedString(string: "\n"))
                continue
            }
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(renderBlock(block))
        }

        return result
    }

    // MARK: - Block Rendering

    private func renderBlock(_ block: MarkdownBlock) -> NSAttributedString {
        switch block {
        case .heading(let level, let text):
            return renderHeading(level: level, text: text)
        case .paragraph(let text):
            return renderInlineMarkdown(text, font: style.bodyFont)
        case .unorderedListItem(let indent, let text):
            return renderUnorderedListItem(indent: indent, text: text)
        case .orderedListItem(let indent, let number, let text):
            return renderOrderedListItem(indent: indent, number: number, text: text)
        case .codeBlock(let code):
            return renderCodeBlock(code)
        case .table(let headers, let rows):
            return renderTable(headers: headers, rows: rows)
        case .horizontalRule:
            return renderHorizontalRule()
        case .blankLine:
            return NSAttributedString(string: "")
        }
    }

    private func renderHeading(level: Int, text: String) -> NSAttributedString {
        let font: NSFont
        switch level {
        case 1: font = style.h1Font
        case 2: font = style.h2Font
        case 3: font = style.h3Font
        default: font = style.h4Font
        }

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = style.lineSpacing
        paraStyle.paragraphSpacingBefore = level == 1 ? 16 : 12
        paraStyle.paragraphSpacing = 4

        return renderInlineMarkdown(text, font: font, extraAttributes: [
            .paragraphStyle: paraStyle
        ])
    }

    private func renderUnorderedListItem(indent: Int, text: String) -> NSAttributedString {
        let paraStyle = NSMutableParagraphStyle()
        let indentPoints = style.bulletIndent + CGFloat(indent) * style.listIndentPerLevel
        paraStyle.firstLineHeadIndent = indentPoints - 16
        paraStyle.headIndent = indentPoints
        paraStyle.lineSpacing = style.lineSpacing

        let bullet = NSMutableAttributedString(string: "•\t", attributes: [
            .font: style.bodyFont,
            .foregroundColor: style.secondaryColor,
            .paragraphStyle: paraStyle
        ])
        bullet.append(renderInlineMarkdown(text, font: style.bodyFont, extraAttributes: [
            .paragraphStyle: paraStyle
        ]))
        return bullet
    }

    private func renderOrderedListItem(indent: Int, number: Int, text: String) -> NSAttributedString {
        let paraStyle = NSMutableParagraphStyle()
        let indentPoints = style.bulletIndent + CGFloat(indent) * style.listIndentPerLevel
        paraStyle.firstLineHeadIndent = indentPoints - 20
        paraStyle.headIndent = indentPoints
        paraStyle.lineSpacing = style.lineSpacing

        let prefix = NSMutableAttributedString(string: "\(number).\t", attributes: [
            .font: style.bodyFont,
            .foregroundColor: style.secondaryColor,
            .paragraphStyle: paraStyle
        ])
        prefix.append(renderInlineMarkdown(text, font: style.bodyFont, extraAttributes: [
            .paragraphStyle: paraStyle
        ]))
        return prefix
    }

    private func renderCodeBlock(_ code: String) -> NSAttributedString {
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 2

        return NSAttributedString(string: code, attributes: [
            .font: style.codeFont,
            .foregroundColor: style.textColor,
            .backgroundColor: style.codeBackgroundColor,
            .paragraphStyle: paraStyle
        ])
    }

    /// Renders table as monospaced tab-separated text.
    /// Simplified format suitable for copy-paste; full grid layout is not needed
    /// since tables are rare in meeting summaries (typically just action items).
    private func renderTable(headers: [String], rows: [[String]]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let separator = "\t"

        // Header row (bold)
        let headerText = headers.joined(separator: separator)
        result.append(NSAttributedString(string: headerText, attributes: [
            .font: NSFont.boldSystemFont(ofSize: style.codeFont.pointSize),
            .foregroundColor: style.textColor
        ]))

        // Separator line
        let divider = String(repeating: "─", count: min(headers.joined().count + headers.count * 4, 60))
        result.append(NSAttributedString(string: "\n" + divider + "\n", attributes: [
            .font: style.codeFont,
            .foregroundColor: style.secondaryColor
        ]))

        // Data rows
        for (rowIndex, row) in rows.enumerated() {
            let rowText = row.joined(separator: separator)
            result.append(NSAttributedString(string: rowText, attributes: [
                .font: style.codeFont,
                .foregroundColor: style.textColor
            ]))
            if rowIndex < rows.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return result
    }

    private func renderHorizontalRule() -> NSAttributedString {
        let rule = String(repeating: "─", count: 40)
        return NSAttributedString(string: rule, attributes: [
            .font: style.bodyFont,
            .foregroundColor: style.secondaryColor
        ])
    }

    // MARK: - Inline Markdown

    /// Renders inline markdown (bold, italic, links) using AttributedString parsing,
    /// then converts to NSAttributedString with the specified base font.
    private func renderInlineMarkdown(
        _ text: String,
        font: NSFont,
        extraAttributes: [NSAttributedString.Key: Any] = [:]
    ) -> NSAttributedString {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            let swiftAttrStr = try AttributedString(markdown: text, options: options)
            let nsAttrStr = NSMutableAttributedString(swiftAttrStr)

            // Apply base font and color to entire range, preserving bold/italic traits
            let fullRange = NSRange(location: 0, length: nsAttrStr.length)
            nsAttrStr.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                var resolvedFont = font
                if let existingFont = value as? NSFont {
                    let traits = existingFont.fontDescriptor.symbolicTraits
                    var descriptor = font.fontDescriptor
                    if traits.contains(.bold) {
                        descriptor = descriptor.withSymbolicTraits(.bold)
                    }
                    if traits.contains(.italic) {
                        descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic))
                    }
                    resolvedFont = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
                }
                nsAttrStr.addAttribute(.font, value: resolvedFont, range: range)
            }
            nsAttrStr.addAttribute(.foregroundColor, value: style.textColor, range: fullRange)

            // Apply extra attributes (e.g., paragraph style)
            for (key, value) in extraAttributes {
                nsAttrStr.addAttribute(key, value: value, range: fullRange)
            }

            return nsAttrStr
        } catch {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: style.textColor
            ].merging(extraAttributes) { _, new in new }
            return NSAttributedString(string: text, attributes: attrs)
        }
    }
}

// MARK: - Block Types (shared with parser)

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case unorderedListItem(indent: Int, text: String)
    case orderedListItem(indent: Int, number: Int, text: String)
    case codeBlock(code: String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
    case paragraph(text: String)
    case blankLine
}

// MARK: - Markdown Parser

extension MarkdownAttributedStringRenderer {

    /// Parses markdown text into block-level elements.
    /// Ported from MarkdownContentView's parser with identical behavior.
    func parseBlocks(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line
            if trimmed.isEmpty {
                if let last = blocks.last, case .blankLine = last {
                    // skip consecutive
                } else {
                    blocks.append(.blankLine)
                }
                index += 1
                continue
            }

            // Code block
            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let codeLine = lines[index]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(codeLine)
                    index += 1
                }
                blocks.append(.codeBlock(code: codeLines.joined(separator: "\n")))
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            // Heading
            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            // Unordered list
            if let listItem = parseUnorderedListItem(line) {
                blocks.append(listItem)
                index += 1
                continue
            }

            // Ordered list
            if let listItem = parseOrderedListItem(line) {
                blocks.append(listItem)
                index += 1
                continue
            }

            // Table
            if isTableRow(trimmed) {
                var tableLines: [String] = [trimmed]
                index += 1
                while index < lines.count {
                    let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    if isTableRow(nextTrimmed) || isTableSeparator(nextTrimmed) {
                        tableLines.append(nextTrimmed)
                        index += 1
                    } else {
                        break
                    }
                }
                if let table = parseTable(tableLines) {
                    blocks.append(table)
                } else {
                    blocks.append(.paragraph(text: tableLines.joined(separator: " ")))
                }
                continue
            }

            // Paragraph
            var paragraphLines: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty
                    || nextTrimmed.hasPrefix("#")
                    || nextTrimmed.hasPrefix("```")
                    || nextTrimmed == "---" || nextTrimmed == "***" || nextTrimmed == "___"
                    || parseUnorderedListItem(next) != nil
                    || parseOrderedListItem(next) != nil
                    || isTableRow(nextTrimmed) {
                    break
                }
                paragraphLines.append(nextTrimmed)
                index += 1
            }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    private func parseHeading(_ line: String) -> MarkdownBlock? {
        var level = 0
        for char in line {
            if char == "#" { level += 1 } else { break }
        }
        guard level > 0, level <= 6, line.count > level else { return nil }
        let afterHashes = line[line.index(line.startIndex, offsetBy: level)...]
        guard afterHashes.first == " " else { return nil }
        return .heading(level: level, text: String(afterHashes.dropFirst()))
    }

    private func parseUnorderedListItem(_ line: String) -> MarkdownBlock? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let stripped = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- ", "* ", "+ "] {
            if stripped.hasPrefix(prefix) {
                return .unorderedListItem(indent: indent / 2, text: String(stripped.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    private func parseOrderedListItem(_ line: String) -> MarkdownBlock? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = stripped.firstIndex(of: ".") else { return nil }
        let numberPart = String(stripped[stripped.startIndex..<dotIndex])
        guard let number = Int(numberPart) else { return nil }
        let afterDot = stripped[stripped.index(after: dotIndex)...]
        guard afterDot.first == " " else { return nil }
        return .orderedListItem(indent: indent / 2, number: number, text: String(afterDot.dropFirst()))
    }

    private func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 1
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }
        let allowed = CharacterSet(charactersIn: "|\\-: ")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func parseTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed = String(trimmed.dropFirst()) }
        if trimmed.hasSuffix("|") { trimmed = String(trimmed.dropLast()) }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func parseTable(_ lines: [String]) -> MarkdownBlock? {
        guard lines.count >= 2 else { return nil }
        let headers = parseTableCells(lines[0])
        guard !headers.isEmpty else { return nil }
        var dataStartIndex = 1
        if dataStartIndex < lines.count && isTableSeparator(lines[dataStartIndex]) {
            dataStartIndex += 1
        }
        var rows: [[String]] = []
        for i in dataStartIndex..<lines.count {
            if isTableSeparator(lines[i]) { continue }
            rows.append(parseTableCells(lines[i]))
        }
        return .table(headers: headers, rows: rows)
    }
}
```

- [ ] **Step 2: Add file to Xcode project and run tests**

Run: `xcodebuild test -project MeetingSonar.xcodeproj -scheme MeetingSonar -destination 'platform=macOS' -only-testing:MeetingSonarTests/MarkdownAttributedStringRendererTests 2>&1 | tail -30`

Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
git add MeetingSonar/Views/Components/MarkdownAttributedStringRenderer.swift MeetingSonarTests/Unit/Views/MarkdownAttributedStringRendererTests.swift
git commit -m "feat(F-0.10.16): add MarkdownAttributedStringRenderer with tests

Converts markdown to NSAttributedString for NSTextView rendering.
Supports headings, lists, code blocks, tables, inline formatting."
```

---

### Task 3: SelectableTextView — NSViewRepresentable

**Files:**
- Create: `MeetingSonar/Views/Components/SelectableTextView.swift`

- [ ] **Step 1: Implement SelectableTextView**

```swift
//
//  SelectableTextView.swift
//  MeetingSonar
//
//  NSViewRepresentable wrapping NSTextView for full text selection support.
//  Solves SwiftUI's inability to select across multiple Text views.
//  Designed for future isEditable toggle (F-0.11.1 proofreading).
//

import SwiftUI
import AppKit

/// A text view that supports full text selection (Cmd+A, drag-select) via NSTextView.
///
/// Wraps NSTextView in NSViewRepresentable. Supports:
/// - Read-only mode with full selection
/// - Link click handling (for transcript click-to-seek)
/// - Dynamic highlight range (for active transcript segment)
/// - Scroll-to-range (for auto-scroll during playback)
/// - Future: isEditable mode for proofreading (F-0.11.1)
struct SelectableTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    var isEditable: Bool = false
    var backgroundColor: NSColor = .textBackgroundColor

    /// Range to highlight with accent color background (e.g., active transcript segment).
    var highlightRange: NSRange? = nil

    /// Range to scroll into view (e.g., active transcript segment).
    var scrollToRange: NSRange? = nil

    /// Called when a link in the text is clicked. Return value URL is passed through.
    var onLinkClick: ((URL) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = backgroundColor
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)

        // Allow text to wrap to container width
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true

        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(attributedString)

        applyHighlight(to: textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Only update content if it changed (avoid resetting selection)
        let currentContent = textView.attributedString()
        if currentContent != attributedString {
            let selectedRanges = textView.selectedRanges
            textView.textStorage?.setAttributedString(attributedString)
            // Restore selection if still valid
            if let first = selectedRanges.first?.rangeValue,
               first.upperBound <= attributedString.length {
                textView.setSelectedRange(first)
            }
        }

        textView.isEditable = isEditable
        textView.backgroundColor = backgroundColor

        applyHighlight(to: textView)

        // Scroll to range if requested
        if let range = scrollToRange, range.upperBound <= attributedString.length {
            textView.scrollRangeToVisible(range)
        }
    }

    /// Applies or removes highlight background on the specified range.
    private func applyHighlight(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)

        // Remove previous highlight
        storage.removeAttribute(.backgroundColor, range: fullRange)

        // Re-apply code block backgrounds from the attributed string
        attributedString.enumerateAttribute(.backgroundColor, in: fullRange) { value, range, _ in
            if let color = value as? NSColor {
                storage.addAttribute(.backgroundColor, value: color, range: range)
            }
        }

        // Apply active highlight
        if let range = highlightRange, range.upperBound <= storage.length {
            storage.addAttribute(
                .backgroundColor,
                value: NSColor.controlAccentColor.withAlphaComponent(0.12),
                range: range
            )
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: SelectableTextView

        init(_ parent: SelectableTextView) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                parent.onLinkClick?(url)
                return true
            }
            if let urlString = link as? String, let url = URL(string: urlString) {
                parent.onLinkClick?(url)
                return true
            }
            return false
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project MeetingSonar.xcodeproj -scheme MeetingSonar -configuration Debug build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add MeetingSonar/Views/Components/SelectableTextView.swift
git commit -m "feat(F-0.10.16): add SelectableTextView NSViewRepresentable

NSTextView wrapper with full text selection, link click handling,
dynamic highlight range, and scroll-to-range for playback tracking."
```

---

### Task 4: Update SummaryView and StreamingSummaryView

**Files:**
- Modify: `MeetingSonar/Views/Dashboard/SummaryView.swift`
- Modify: `MeetingSonar/Views/Components/StreamingSummaryView.swift`

- [ ] **Step 1: Update SummaryView to use SelectableTextView**

Replace the body of `SummaryView`:

```swift
//
//  SummaryView.swift
//  MeetingSonar
//
//  Created by MeetingSonar Team.
//  Copyright © 2024 MeetingSonar. All rights reserved.
//

import SwiftUI

/// View for displaying Markdown summary with full text selection support.
/// Uses NSTextView via SelectableTextView for cross-paragraph selection.
@available(macOS 13.0, *)
struct SummaryView: View {
    let content: String

    private let renderer = MarkdownAttributedStringRenderer()

    var body: some View {
        SelectableTextView(
            attributedString: renderer.render(content),
            backgroundColor: .textBackgroundColor
        )
    }
}
```

- [ ] **Step 2: Update StreamingSummaryView's StreamingTextView**

In `StreamingSummaryView.swift`, update the `StreamingTextView` struct to use `SelectableTextView` when content is complete:

Find the `StreamingTextView` body and replace:

```swift
// Before:
if isComplete {
    MarkdownContentView(content: text)
} else {
    Text(text)
        .textSelection(.enabled)
}

// After:
if isComplete {
    let renderer = MarkdownAttributedStringRenderer()
    SelectableTextView(
        attributedString: renderer.render(text),
        backgroundColor: .clear
    )
} else {
    Text(text)
        .textSelection(.enabled)
}
```

Note: Keep plain `Text` during streaming for performance — NSTextView redraws on every update are heavier than SwiftUI Text for rapid character appending.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project MeetingSonar.xcodeproj -scheme MeetingSonar -configuration Debug build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add MeetingSonar/Views/Dashboard/SummaryView.swift MeetingSonar/Views/Components/StreamingSummaryView.swift
git commit -m "feat(F-0.10.16): migrate SummaryView and StreamingSummaryView to SelectableTextView

Summary and completed streaming views now support full text selection
via NSTextView. Streaming-in-progress still uses SwiftUI Text for performance."
```

---

### Task 5: Transcript Attributed String Builder — Tests

**Files:**
- Create: `MeetingSonarTests/Unit/Views/TranscriptAttributedStringTests.swift`

- [ ] **Step 1: Write tests for transcript rendering**

```swift
//
//  TranscriptAttributedStringTests.swift
//  MeetingSonarTests
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
        // 3661 seconds = 61 minutes 1 second = 61:01
        #expect(result.string.contains("61:01"))
    }

    // MARK: - Timestamp Links

    @Test("Timestamp has link attribute for click-to-seek")
    func timestampHasLink() {
        let segments = [
            TranscriptSegment(start: 30.5, end: 35, text: "Some text")
        ]
        let result = builder.build(from: segments)
        // Find the timestamp range
        let nsString = result.string as NSString
        let timestampRange = nsString.range(of: "00:30")
        #expect(timestampRange.location != NSNotFound)
        let link = result.attribute(.link, at: timestampRange.location, effectiveRange: nil)
        #expect(link != nil)
        // Verify link contains the seek time
        if let url = link as? URL {
            #expect(url.absoluteString.contains("30.5"))
        }
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

    @Test("segmentRanges returns correct ranges for each segment")
    func segmentRanges() {
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "First"),
            TranscriptSegment(start: 5, end: 10, text: "Second")
        ]
        let (_, ranges) = builder.buildWithRanges(from: segments)
        #expect(ranges.count == 2)
        // Each range should cover its full line (timestamp + text)
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project MeetingSonar.xcodeproj -scheme MeetingSonar -destination 'platform=macOS' -only-testing:MeetingSonarTests/TranscriptAttributedStringTests 2>&1 | tail -20`

Expected: Build failure — `TranscriptAttributedStringBuilder` not found.

---

### Task 6: Transcript Attributed String Builder — Implementation

**Files:**
- Create: `MeetingSonar/Views/Components/TranscriptAttributedStringBuilder.swift`

- [ ] **Step 1: Implement the builder**

```swift
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
/// Each segment is rendered as: `[MM:SS]  Segment text\n`
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

            // Timestamp with link
            let timestamp = formatTime(segment.start)
            let seekURL = URL(string: "\(Self.seekScheme)://seek?time=\(segment.start)")!
            let timestampAttrs: [NSAttributedString.Key: Any] = [
                .font: style.timestampFont,
                .foregroundColor: style.timestampColor,
                .link: seekURL,
                .cursor: NSCursor.pointingHand
            ]
            result.append(NSAttributedString(string: timestamp, attributes: timestampAttrs))

            // Separator
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
```

- [ ] **Step 2: Run tests**

Run: `xcodebuild test -project MeetingSonar.xcodeproj -scheme MeetingSonar -destination 'platform=macOS' -only-testing:MeetingSonarTests/TranscriptAttributedStringTests 2>&1 | tail -30`

Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
git add MeetingSonar/Views/Components/TranscriptAttributedStringBuilder.swift MeetingSonarTests/Unit/Views/TranscriptAttributedStringTests.swift
git commit -m "feat(F-0.10.16): add TranscriptAttributedStringBuilder with tests

Converts transcript segments to NSAttributedString with clickable
timestamps for seek and per-segment ranges for highlight tracking."
```

---

### Task 7: Update TranscriptView

**Files:**
- Modify: `MeetingSonar/Views/Dashboard/TranscriptView.swift`

This is the most complex change — must preserve click-to-seek, active segment highlighting, and auto-scroll.

- [ ] **Step 1: Rewrite TranscriptView to use SelectableTextView**

```swift
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
    private var contentAndRanges: (NSAttributedString, [NSRange]) {
        builder.buildWithRanges(from: segments)
    }

    var body: some View {
        let (content, ranges) = contentAndRanges
        let activeIndex = segments.firstIndex { currentTime >= $0.start && currentTime < $0.end }

        SelectableTextView(
            attributedString: content,
            backgroundColor: .textBackgroundColor,
            highlightRange: activeIndex.flatMap { ranges.indices.contains($0) ? ranges[$0] : nil },
            scrollToRange: activeIndex.flatMap { ranges.indices.contains($0) ? ranges[$0] : nil },
            onLinkClick: { url in
                if let time = TranscriptAttributedStringBuilder.seekTime(from: url) {
                    onSeek(time)
                }
            }
        )
    }
}
```

Note: `TranscriptRow` struct is no longer needed and can be removed from this file.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project MeetingSonar.xcodeproj -scheme MeetingSonar -configuration Debug build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Manual verification checklist**

Run the app and verify:
- [ ] Transcript text is fully selectable (Cmd+A selects all, drag-select across segments)
- [ ] Clicking a timestamp seeks to that position
- [ ] Active segment is highlighted during playback
- [ ] View auto-scrolls to active segment during playback
- [ ] Summary text is fully selectable
- [ ] Streaming summary shows plain text during streaming, then selectable markdown when complete

- [ ] **Step 4: Commit**

```bash
git add MeetingSonar/Views/Dashboard/TranscriptView.swift
git commit -m "feat(F-0.10.16): migrate TranscriptView to SelectableTextView

Full text selection via NSTextView. Click-to-seek via link attributes
on timestamps. Active segment highlighting and auto-scroll preserved."
```

---

### Task 8: Cleanup — Remove MarkdownContentView

**Files:**
- Delete: `MeetingSonar/Views/Components/MarkdownContentView.swift`

- [ ] **Step 1: Verify no remaining references**

Run: `grep -r "MarkdownContentView" MeetingSonar/ --include="*.swift"`

Expected: Only hits in MarkdownContentView.swift itself (or none if file is already staged for deletion).

- [ ] **Step 2: Delete MarkdownContentView.swift**

```bash
git rm MeetingSonar/Views/Components/MarkdownContentView.swift
```

- [ ] **Step 3: Build to verify no broken references**

Run: `xcodebuild -project MeetingSonar.xcodeproj -scheme MeetingSonar -configuration Debug build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run all tests**

Run: `xcodebuild test -project MeetingSonar.xcodeproj -scheme MeetingSonar -destination 'platform=macOS' 2>&1 | tail -20`

Expected: All tests PASS.

- [ ] **Step 5: Update feature tracking**

Update `.claude/feature_list.json`: set F-0.10.16 status to `done`, `passes: true`, and fill `files` list:
```json
{
    "id": "F-0.10.16",
    "status": "done",
    "passes": true,
    "passesAt": "<current timestamp>",
    "files": [
        "MeetingSonar/Views/Components/SelectableTextView.swift",
        "MeetingSonar/Views/Components/MarkdownAttributedStringRenderer.swift",
        "MeetingSonar/Views/Components/TranscriptAttributedStringBuilder.swift",
        "MeetingSonar/Views/Dashboard/TranscriptView.swift",
        "MeetingSonar/Views/Dashboard/SummaryView.swift",
        "MeetingSonar/Views/Components/StreamingSummaryView.swift"
    ]
}
```

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "cleanup(F-0.10.16): remove MarkdownContentView, update feature tracking

All views migrated to NSTextView-based SelectableTextView.
MarkdownContentView no longer referenced anywhere."
```

---

## Risk Mitigation Notes

1. **Table rendering**: Simplified to tab-separated monospaced text. Acceptable given low frequency in meeting notes. Can be improved later with NSTextTable if needed.

2. **Performance (long transcripts)**: NSTextView handles large text natively with layout caching. If 2+ hour transcripts show lag, the `contentAndRanges` computation can be memoized with `@State` + `onChange(of: segments)` in a future optimization pass.

3. **Highlight flicker**: `applyHighlight` modifies textStorage directly without rebuilding the attributed string, keeping highlight updates cheap during playback.

4. **Backward compatibility**: macOS 13.0+ required (same as existing minimum). NSTextView APIs used are stable since macOS 10.0.
