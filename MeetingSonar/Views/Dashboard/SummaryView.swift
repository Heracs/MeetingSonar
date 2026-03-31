//
//  SummaryView.swift
//  MeetingSonar
//
//  Created by MeetingSonar Team.
//  Copyright © 2024 MeetingSonar. All rights reserved.
//

import SwiftUI

/// View for displaying Markdown summary with full block-level rendering.
@available(macOS 13.0, *)
struct SummaryView: View {
    let content: String

    var body: some View {
        ScrollView {
            MarkdownContentView(content: content)
                .font(.body)
                .lineSpacing(4)
                .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }
}
