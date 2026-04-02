//
//  MenuIconGenerator.swift
//  MeetingSonar
//
//  Created for F-2.5 Dynamic Menu Icon.
//

import AppKit

/// Generates dynamic menu bar icons based on recording state
///
/// ## Icon States
/// - **Idle**: Template icon that adapts to system theme (light/dark)
/// - **Recording**: Red indicator with pulsing effect
/// - **Paused**: Orange/yellow indicator showing paused state
///
/// ## Implementation
/// - Loads base icon from Assets catalog
/// - Draws colored indicators using Core Graphics
/// - Caches generated images for performance
class MenuIconGenerator {

    // MARK: - Icon States

    /// Recording state indicators
    enum IconState {
        /// App is idle (not recording)
        case idle
        /// actively recording
        case recording
        /// Recording is paused (sleep/lock)
        case paused
    }

    // MARK: - Properties

    /// Cache for generated images to improve performance
    private var cache: [IconState: NSImage] = [:]

    /// Base icon image name in Assets catalog
    private let baseIconName = "menubar_icon"

    // MARK: - Public API

    /// Get the icon for the specified state
    ///
    /// - Parameter state: The recording state
    /// - Returns: Generated `NSImage` for the state
    ///
    /// ## Process
    /// 1. Check cache and return cached image if available
    /// 2. Generate new icon using Core Graphics
    /// 3. Set template mode for idle state (adapts to theme)
    /// 4. Cache the result
    func icon(for state: IconState) -> NSImage {
        if let cached = cache[state] {
            return cached
        }
        
        let image = generateIcon(for: state)
        // Set template mode for idle to adapt to system theme automatically
        if state == .idle {
            image.isTemplate = true
        } else {
            image.isTemplate = false // Colored states should not be templates
        }
        
        cache[state] = image
        return image
    }
    
    // MARK: - Drawing Logic
    
    private func generateIcon(for state: IconState) -> NSImage {
        // 1. Load Base Image
        // Use a default size if image fails to load, though it shouldn't.
        // Standard macOS menu bar icon size: 18x18 points (reduced from 22 for better visual fit)
        let targetSize = NSSize(width: 18, height: 18)
        
        // Find base image from Resources specifically if needed, or Assets
        // Assuming "menubar_icon" is in Bundle Resources or Assets
        var baseImage: NSImage?
        
        // Try loading from Assets first
        if let assetImage = NSImage(named: baseIconName) {
            baseImage = assetImage
        } else {
            // Try loading from file path if it's a loose resource (fallback)
             if let path = Bundle.main.path(forResource: "menubar_icon", ofType: "png") {
                 baseImage = NSImage(contentsOfFile: path)
             }
        }
        
        guard let base = baseImage else {
            LoggerService.shared.log(category: .general, level: .error, message: "[MenuIconGenerator] Base icon not found")
            return NSImage(systemSymbolName: "mic", accessibilityDescription: "Error") ?? NSImage()
        }
        
        // 2. Create Destination Image
        let finalImage = NSImage(size: targetSize)
        finalImage.lockFocus()
        
        // Context setup
        NSGraphicsContext.current?.imageInterpolation = .high
        
        // 3. Draw Base Icon (White/Template)
        // We force it to be drawn as a white-ish icon for the colored states, 
        // or just draw the template logic.
        // If state is idle, we just use the base image as template (handled in icon(for:)).
        // If state is recording/paused, we likely want a fixed white base so the colors pop.
        
        let drawRect = NSRect(origin: .zero, size: targetSize)
        
        if state == .idle {
             base.draw(in: drawRect)
        } else {
            // For colored states, we want a consistent base color (usually white/labelColor)
            // But since the requirement says "White version", let's fill it with white or use the image as mask.
            // If the PNG is already white with transparency, just drawing it is fine.
            // If it's black (template), we might need to tint it.
            // Let's assume the provided png is suitable or we treat it as a mask.
            
            // Draw as white using masking
            // 1. Fill with white
            NSColor.white.setFill()
            let iconRect = NSRect(origin: .zero, size: targetSize)
            iconRect.fill()
            
            // 2. Mask using the base image (Source) to cut out the shape from the white rect (Destination)
            // operation: .destinationIn => R = D * Sa. (Result = Dest * SourceAlpha)
            // This keeps the White color where the Image has alpha.
            base.draw(in: iconRect, from: .zero, operation: .destinationIn, fraction: 1.0, respectFlipped: true, hints: nil)
        }
        
        // 4. Draw Overlays
        switch state {
        case .idle:
            break // No overlay
            
        case .recording:
            drawRedDot(in: drawRect)
            
        case .paused:
            drawOrangeBars(in: drawRect)
        }
        
        finalImage.unlockFocus()
        return finalImage
    }
    
    private func drawRedDot(in rect: NSRect) {
        let dotSize = rect.width * 0.35 // 35% size
        let dotRect = NSRect(
            x: rect.width - dotSize + 1, // Shift slightly right
            y: 0 - 1,                    // Shift slightly down (CoreGraphics origin is bottom-left usually, but lockFocus translates)
            // Wait, NSImage coordinate system: (0,0) is bottom-left? 
            // Yes. So y=0 is bottom.
            width: dotSize,
            height: dotSize
        )
        
        NSColor.systemRed.setFill()
        let path = NSBezierPath(ovalIn: dotRect)
        path.fill()
        
        // Add a tiny stroke for separation if needed, or just fill.
    }
    
    /// Draws a pause indicator using SF Symbol at the bottom-right corner of the icon.
    private func drawOrangeBars(in rect: NSRect) {
        let symbolSize = rect.width * 0.4
        guard let pauseImage = NSImage(
            systemSymbolName: "pause.circle.fill",
            accessibilityDescription: "Paused"
        ) else { return }

        // Apply orange color via palette configuration (not NSColor.set which doesn't affect NSImage.draw)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .bold)
        let combined = colorConfig.applying(sizeConfig)
        let configured = pauseImage.withSymbolConfiguration(combined) ?? pauseImage
        configured.isTemplate = false

        // Draw at bottom-right corner
        let drawSize = NSSize(width: symbolSize, height: symbolSize)
        let origin = NSPoint(
            x: rect.width - drawSize.width + 1,
            y: -1
        )

        configured.draw(
            in: NSRect(origin: origin, size: drawSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    }
}
