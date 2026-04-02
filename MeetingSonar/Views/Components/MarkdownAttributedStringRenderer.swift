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
        // Filter out leading/trailing blank lines to avoid empty output for whitespace-only input
        let contentBlocks = blocks.filter { block in
            if case .blankLine = block { return false }
            return true
        }
        guard !contentBlocks.isEmpty else {
            return NSAttributedString()
        }

        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if case .blankLine = block {
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

    private func renderBlock(_ block: Block) -> NSAttributedString {
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

    /// Renders table as tab-separated text with monospaced font.
    /// Simplified format — tables are rare in meeting summaries.
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

    /// Renders inline markdown (bold, italic) using AttributedString parsing,
    /// then converts to NSAttributedString with the specified base font.
    ///
    /// AttributedString from markdown uses `inlinePresentationIntent` to mark
    /// bold/italic runs rather than font traits. We enumerate these intents
    /// and apply corresponding NSFont trait variants.
    private func renderInlineMarkdown(
        _ text: String,
        font: NSFont,
        extraAttributes: [NSAttributedString.Key: Any] = [:]
    ) -> NSAttributedString {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            let swiftAttrStr = try AttributedString(markdown: text, options: options)

            // Build NSAttributedString by iterating runs with presentation intents
            let result = NSMutableAttributedString()
            for run in swiftAttrStr.runs {
                let runText = String(swiftAttrStr[run.range].characters)
                var runFont = font

                // Check for bold/italic via inlinePresentationIntent
                if let intent = run.inlinePresentationIntent {
                    var descriptor = font.fontDescriptor
                    if intent.contains(.stronglyEmphasized) {
                        descriptor = descriptor.withSymbolicTraits(.bold)
                    }
                    if intent.contains(.emphasized) {
                        descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic))
                    }
                    runFont = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
                }

                var attrs: [NSAttributedString.Key: Any] = [
                    .font: runFont,
                    .foregroundColor: style.textColor
                ]
                for (key, value) in extraAttributes {
                    attrs[key] = value
                }

                result.append(NSAttributedString(string: runText, attributes: attrs))
            }

            return result
        } catch {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: style.textColor
            ].merging(extraAttributes) { _, new in new }
            return NSAttributedString(string: text, attributes: attrs)
        }
    }
    // MARK: - Block Types

    /// Represents a parsed markdown block element.
    enum Block {
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

    /// Parses markdown text into block-level elements.
    /// Ported from MarkdownContentView's parser with identical behavior.
    func parseBlocks(_ text: String) -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [Block] = []
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

    private func parseHeading(_ line: String) -> Block? {
        var level = 0
        for char in line {
            if char == "#" { level += 1 } else { break }
        }
        guard level > 0, level <= 6, line.count > level else { return nil }
        let afterHashes = line[line.index(line.startIndex, offsetBy: level)...]
        guard afterHashes.first == " " else { return nil }
        return .heading(level: level, text: String(afterHashes.dropFirst()))
    }

    private func parseUnorderedListItem(_ line: String) -> Block? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let stripped = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- ", "* ", "+ "] {
            if stripped.hasPrefix(prefix) {
                return .unorderedListItem(indent: indent / 2, text: String(stripped.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    private func parseOrderedListItem(_ line: String) -> Block? {
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

    private func parseTable(_ lines: [String]) -> Block? {
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
