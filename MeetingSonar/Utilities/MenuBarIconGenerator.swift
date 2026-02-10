//
//  MenuBarIconGenerator.swift
//  MeetingSonar
//
//  Unused in v0.1-rebuild. Reference kept for project file compatibility.
//

import AppKit

// Placeholder
final class MenuBarIconGenerator {
    static let shared = MenuBarIconGenerator()
    private init() {}
    
    func generateIcon(for state: Any) -> NSImage {
        return NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) ?? NSImage()
    }
}

extension NSImage {
    static func menuBarIcon(for state: Any) -> NSImage {
        return NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) ?? NSImage()
    }
}
