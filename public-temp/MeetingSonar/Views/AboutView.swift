//
//  AboutView.swift
//  MeetingSonar
//
//  About view displaying app information, version, and copyright.
//  v0.1-rebuild
//

import SwiftUI
import AppKit

/// About view for displaying application information
@available(macOS 13.0, *)
struct AboutView: View {

    @Environment(\.dismiss) private var dismiss

    // MARK: - App Info
    
    /// App version from Info.plist (CFBundleShortVersionString)
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    
    /// Build number with Git SHA from BuildInfo
    private var buildString: String {
        BuildInfo.fullBuildString
    }
    
    /// Copyright string
    private var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String 
            ?? "© 2026 MeetingSonar. All rights reserved."
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with Done button
            HStack {
                Text("about.title")
                    .font(.headline)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("general.done")
                        .frame(minWidth: 60)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                // App Icon
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .accessibilityIdentifier("Image_AppIcon")
                }
                
                // App Name
                Text("about.appName")
                    .font(.title)
                    .fontWeight(.bold)
                    .accessibilityIdentifier("Text_AppName")
                
                // Version Info
                VStack(spacing: 2) {
                    Text("Version \(appVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("(Build \(buildString))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .accessibilityIdentifier("Text_VersionInfo")
                
                // App Description
                Text("about.tagline")
                    .font(.body)
                    .foregroundColor(.primary)
                
                Divider()
                    .padding(.horizontal, 40)
                
                // Copyright
                Text(copyright)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Actions
                HStack(spacing: 20) {
                    Button("About.Button.OpenLogs") {
                        LoggerService.shared.openLogDirectory()
                    }
                    .accessibilityIdentifier("Button_OpenLogs")
                    
                    Button(action: openGitHub) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text("about.github")
                        }
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("Button_GitHub")
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
        }
        .padding()
        }
    }
    
    // MARK: - Actions
    
    private func openGitHub() {
        if let url = URL(string: "https://github.com/Heracs/MeetingSonar") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Version Helper

/// Helper struct to get app version info
struct AppVersion {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    
    static var build: String {
        BuildInfo.fullBuildString
    }
    
    static var fullVersion: String {
        "v\(version)"
    }
    
    static var detailedVersion: String {
        "\(version) (Build \(build))"
    }
}

// MARK: - Preview

#if DEBUG
@available(macOS 13.0, *)
struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
            .frame(width: 400, height: 350)
    }
}
#endif

