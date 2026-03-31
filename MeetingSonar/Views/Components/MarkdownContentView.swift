//
//  MarkdownContentView.swift
//  MeetingSonar
//
//  Renders markdown content with proper block-level formatting.
//  Supports: headers, unordered/ordered lists, code blocks, horizontal rules,
//  bold, italic, and plain paragraphs.
//

import SwiftUI

@available(macOS 13.0, *)
struct MarkdownContentView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parseBlocks(content).enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
                .padding(.top, level == 1 ? 16 : 12)
                .padding(.bottom, 4)

        case .unorderedListItem(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .foregroundColor(.secondary)
                inlineMarkdown(text)
            }
            .padding(.leading, CGFloat(indent) * 16 + 8)
            .padding(.vertical, 2)

        case .orderedListItem(let indent, let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(number).")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 20, alignment: .trailing)
                inlineMarkdown(text)
            }
            .padding(.leading, CGFloat(indent) * 16 + 8)
            .padding(.vertical, 2)

        case .codeBlock(let code):
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .padding(.vertical, 4)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
                .padding(.vertical, 4)

        case .horizontalRule:
            Divider()
                .padding(.vertical, 8)

        case .paragraph(let text):
            inlineMarkdown(text)
                .padding(.vertical, 4)

        case .blankLine:
            Spacer()
                .frame(height: 4)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        switch level {
        case 1:
            inlineMarkdown(text)
                .font(.title2.bold())
        case 2:
            inlineMarkdown(text)
                .font(.title3.bold())
        case 3:
            inlineMarkdown(text)
                .font(.headline)
        default:
            inlineMarkdown(text)
                .font(.subheadline.bold())
        }
    }

    // MARK: - Table Rendering

    @ViewBuilder
    private func tableView(headers: [String], rows: [[String]]) -> some View {
        let columnCount = headers.count

        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            // Header row
            GridRow {
                ForEach(0..<columnCount, id: \.self) { col in
                    inlineMarkdown(headers[col])
                        .font(.body.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gridColumnAlignment(.leading)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Data rows
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { col in
                        let cellText = col < rows[rowIndex].count ? rows[rowIndex][col] : ""
                        inlineMarkdown(cellText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if rowIndex < rows.count - 1 {
                    Divider()
                        .opacity(0.5)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .cornerRadius(4)
    }

    // MARK: - Inline Markdown

    private func inlineMarkdown(_ text: String) -> Text {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            let attrStr = try AttributedString(markdown: text, options: options)
            return Text(attrStr)
        } catch {
            return Text(text)
        }
    }
}

// MARK: - Block Types

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case unorderedListItem(indent: Int, text: String)
    case orderedListItem(indent: Int, number: Int, text: String)
    case codeBlock(code: String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
    case paragraph(text: String)
    case blankLine
}

// MARK: - Parser

extension MarkdownContentView {

    private func parseBlocks(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line
            if trimmed.isEmpty {
                // Avoid consecutive blank lines
                if let last = blocks.last, case .blankLine = last {
                    // skip
                } else {
                    blocks.append(.blankLine)
                }
                index += 1
                continue
            }

            // Code block (```)
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

            // Unordered list item (-, *, +)
            if let listItem = parseUnorderedListItem(line) {
                blocks.append(listItem)
                index += 1
                continue
            }

            // Ordered list item
            if let listItem = parseOrderedListItem(line) {
                blocks.append(listItem)
                index += 1
                continue
            }

            // Table (lines starting and ending with |)
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
                    // Not a valid table, treat lines as paragraphs
                    blocks.append(.paragraph(text: tableLines.joined(separator: " ")))
                }
                continue
            }

            // Paragraph — accumulate consecutive non-empty, non-special lines
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
            if char == "#" {
                level += 1
            } else {
                break
            }
        }
        guard level > 0, level <= 6, line.count > level else { return nil }
        let afterHashes = line[line.index(line.startIndex, offsetBy: level)...]
        guard afterHashes.first == " " else { return nil }
        let text = String(afterHashes.dropFirst())
        return .heading(level: level, text: text)
    }

    private func parseUnorderedListItem(_ line: String) -> MarkdownBlock? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indentLevel = indent / 2
        let stripped = line.trimmingCharacters(in: .whitespaces)

        for prefix in ["- ", "* ", "+ "] {
            if stripped.hasPrefix(prefix) {
                let text = String(stripped.dropFirst(prefix.count))
                return .unorderedListItem(indent: indentLevel, text: text)
            }
        }
        return nil
    }

    private func parseOrderedListItem(_ line: String) -> MarkdownBlock? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indentLevel = indent / 2
        let stripped = line.trimmingCharacters(in: .whitespaces)

        // Match "1. ", "2. ", etc.
        guard let dotIndex = stripped.firstIndex(of: ".") else { return nil }
        let numberPart = String(stripped[stripped.startIndex..<dotIndex])
        guard let number = Int(numberPart) else { return nil }

        let afterDot = stripped[stripped.index(after: dotIndex)...]
        guard afterDot.first == " " else { return nil }
        let text = String(afterDot.dropFirst())
        return .orderedListItem(indent: indentLevel, number: number, text: text)
    }

    // MARK: - Table Parsing

    private func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 1
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }
        // Separator rows contain only |, -, :, and spaces
        let allowed = CharacterSet(charactersIn: "|\\-: ")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func parseTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        // Remove leading and trailing pipes
        if trimmed.hasPrefix("|") { trimmed = String(trimmed.dropFirst()) }
        if trimmed.hasSuffix("|") { trimmed = String(trimmed.dropLast()) }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func parseTable(_ lines: [String]) -> MarkdownBlock? {
        guard lines.count >= 2 else { return nil }

        let headers = parseTableCells(lines[0])
        guard !headers.isEmpty else { return nil }

        var dataStartIndex = 1
        // Skip separator row if present
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
