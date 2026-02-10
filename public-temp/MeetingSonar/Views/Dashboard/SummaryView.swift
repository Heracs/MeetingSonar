//
//  SummaryView.swift
//  MeetingSonar
//
//  Created by MeetingSonar Team.
//  Copyright © 2024 MeetingSonar. All rights reserved.
//

import SwiftUI

/// View for displaying Markdown summary.
/// Implements F-7.2 Summary Viewer.
@available(macOS 13.0, *)
struct SummaryView: View {
    let content: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Initial v0.7.0 implementation:
                // Use SwiftUI's native Markdown support via LocalizedStringKey or AttributedString
                Text(parseMarkdown(content))
                    .font(.body)
                    .lineSpacing(4)
                    .padding()
                    .textSelection(.enabled) // Allow copying
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }
    
    private func parseMarkdown(_ text: String) -> AttributedString {
        do {
            // Basic Markdown parsing supporting Bold, Italic, etc.
            // F-7.2 Fix: Use .inlineOnlyPreservingWhitespace to ensure line breaks are respected.
            // .full parsing often collapses single newlines in Text view, making lists unreadable.
            // Trade-off: Headers (#) will show as plain text, but content structure is preserved.
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            let attrStr = try AttributedString(markdown: text, options: options)
            return attrStr
        } catch {
            return AttributedString(stringLiteral: text)
        }
    }
}
