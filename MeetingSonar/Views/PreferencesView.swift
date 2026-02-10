//
//  PreferencesView.swift
//  MeetingSonar
//
//  Settings window for configuring application preferences.
//  v1.0: Replaced tabbed interface with unified settings view.
//

import SwiftUI
import AppKit

/// Main preferences window view - now using unified settings interface
@available(macOS 13.0, *)
struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Unified Settings View
            UnifiedSettingsView()

            // Version footer
            HStack {
                Spacer()
                Text(AppVersion.fullVersion)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("Text_Version")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(width: 750, height: 700)
    }
}

#if DEBUG
@available(macOS 13.0, *)
struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
#endif
