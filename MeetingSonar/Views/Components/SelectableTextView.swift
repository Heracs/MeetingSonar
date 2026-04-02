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

    /// Called when a link in the text is clicked.
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

        // Link appearance: use cursor hand but keep default link color
        textView.linkTextAttributes = [
            .cursor: NSCursor.pointingHand,
            .foregroundColor: NSColor.secondaryLabelColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        textView.delegate = context.coordinator
        context.coordinator.lastBaseContent = attributedString
        textView.textStorage?.setAttributedString(attributedString)

        applyHighlight(to: textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Compare against coordinator's cached base content (not textView's current
        // content which includes highlight modifications from applyHighlight).
        // This prevents resetting textStorage on every currentTime change.
        if !attributedString.isEqual(to: context.coordinator.lastBaseContent) {
            context.coordinator.lastBaseContent = attributedString
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
    /// Preserves existing background colors (e.g., code blocks) while
    /// adding the active segment highlight on top.
    private func applyHighlight(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }

        // Remove previous highlight by restoring original backgrounds
        storage.removeAttribute(.backgroundColor, range: fullRange)

        // Re-apply code block backgrounds from the source attributed string
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
        var parent: SelectableTextView
        /// Tracks the last base content set on textStorage, so updateNSView
        /// can distinguish "content changed" from "highlight changed".
        var lastBaseContent: NSAttributedString = NSAttributedString()

        init(_ parent: SelectableTextView) {
            self.parent = parent
        }

        /// Intercepts link clicks to route through onLinkClick callback
        /// instead of opening in browser.
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
