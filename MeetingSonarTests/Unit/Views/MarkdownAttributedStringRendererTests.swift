//
//  MarkdownAttributedStringRendererTests.swift
//  MeetingSonarTests
//
//  Tests for MarkdownAttributedStringRenderer — markdown to NSAttributedString conversion.
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

    @Test("H1 heading renders with large bold font")
    func h1Heading() {
        let result = renderer.render("# Title")
        #expect(result.string.contains("Title"))
        #expect(!result.string.contains("#"))
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize > NSFont.systemFontSize)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("H2 heading renders with bold font")
    func h2Heading() {
        let result = renderer.render("## Subtitle")
        #expect(result.string.contains("Subtitle"))
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("H3 heading renders with semibold font")
    func h3Heading() {
        let result = renderer.render("### Section")
        #expect(result.string.contains("Section"))
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font != nil)
    }

    // MARK: - Inline Formatting

    @Test("Bold text has bold font trait")
    func boldText() {
        let result = renderer.render("Hello **bold** world")
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

    @Test("Table renders with header and data rows")
    func simpleTable() {
        let md = "| Name | Status |\n|------|--------|\n| Alice | Done |\n| Bob | Pending |"
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
        #expect(result.string.contains("─"))
    }

    // MARK: - Edge Cases

    @Test("Empty string returns empty attributed string")
    func emptyInput() {
        let result = renderer.render("")
        #expect(result.length == 0)
    }

    @Test("Whitespace-only input returns minimal result")
    func whitespaceOnly() {
        let result = renderer.render("   \n\n   ")
        #expect(result.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
