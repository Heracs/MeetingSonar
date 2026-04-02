//
//  SummaryView.swift
//  MeetingSonar
//
//  Created by MeetingSonar Team.
//  Copyright © 2024 MeetingSonar. All rights reserved.
//

import SwiftUI

/// Displays meeting summary markdown with full text selection support.
/// Uses NSTextView (via SelectableTextView) to enable Cmd+A and cross-paragraph selection.
@available(macOS 13.0, *)
struct SummaryView: View {
    let content: String

    private let renderer = MarkdownAttributedStringRenderer()

    var body: some View {
        SelectableTextView(
            attributedString: renderer.render(content),
            backgroundColor: .textBackgroundColor
        )
        .cornerRadius(8)
    }
}
