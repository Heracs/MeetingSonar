# Status Pill Overlay Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the recording status overlay as a hover-expandable semi-transparent pill, and fix the menu positioning bug.

**Architecture:** Replace SwiftUI `Menu` with a two-state (collapsed/expanded) hover-based design using `onHover` and SwiftUI animation. Create `KeyablePanel` subclass to fix `canBecomeKey`. Panel resizes dynamically via `onHoverChanged` callback from view to controller.

**Tech Stack:** SwiftUI, AppKit (NSPanel subclass), macOS 13.0+

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `MeetingSonar/Views/Overlay/OverlayWindowController.swift` | Replace `NSPanel` with `KeyablePanel`, handle dynamic panel resizing on hover, remove dead menu code |
| Rewrite | `MeetingSonar/Views/Overlay/StatusPillView.swift` | Two-state collapsed/expanded pill with hover trigger, direct controls instead of Menu |

---

### Task 1: KeyablePanel + Clean Dead Code

**Files:**
- Modify: `MeetingSonar/Views/Overlay/OverlayWindowController.swift`

- [ ] **Step 1: Add KeyablePanel subclass and update createBasePanel**

At the top of `OverlayWindowController.swift` (after the imports), add:

```swift
/// NSPanel subclass that can become key window.
/// Required for SwiftUI controls inside borderless floating panels to
/// receive proper mouse events and coordinate conversions.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
```

In `createBasePanel()`, change `NSPanel(` to `KeyablePanel(`:

```swift
private func createBasePanel() -> NSPanel {
    let panel = KeyablePanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.level = .floating
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true
    return panel
}
```

- [ ] **Step 2: Remove dead menu code from handlePillClick and related methods**

Delete these four methods entirely:
- `handlePillClick()` (lines 363-382)
- `menuStopAction()` (lines 384-386)
- `menuPauseAction()` (lines 388-390)
- `menuResumeAction()` (lines 392-394)

- [ ] **Step 3: Add onHoverChanged callback to ensureStatusPanelCreated**

Replace `ensureStatusPanelCreated()` with:

```swift
private func ensureStatusPanelCreated() {
    if statusPanel != nil { return }

    let panel = createBasePanel()

    let wrappedView = StatusPillWrapper(state: overlayState, onClose: {
        self.requestStopRecording()
    }, onHoverChanged: { [weak self] isExpanded in
        self?.updateStatusPanelLayout()
    })

    panel.contentViewController = NSHostingController(rootView: wrappedView)
    if let viewSize = panel.contentViewController?.view.fittingSize {
        panel.setContentSize(viewSize)
    }

    statusPanel = panel
}
```

Note: `onTap` is removed — no longer needed since we don't use a popup menu.

- [ ] **Step 4: Update StatusPillWrapper to match new interface**

Replace `StatusPillWrapper` with:

```swift
struct StatusPillWrapper: View {
    @ObservedObject var state: OverlayState
    var onClose: () -> Void
    var onHoverChanged: (Bool) -> Void

    var body: some View {
        StatusPillView(
            duration: state.duration,
            isPaused: state.isPaused,
            includeSystemAudio: state.includeSystemAudio,
            includeMicrophone: state.includeMicrophone,
            onClose: onClose,
            onToggleSystemAudio: { enabled in
                Task { await RecordingService.shared.toggleSystemAudio(enabled) }
            },
            onToggleMicrophone: { enabled in
                Task { await RecordingService.shared.toggleMicrophone(enabled) }
            },
            onPause: { RecordingService.shared.pauseRecording() },
            onResume: { RecordingService.shared.resumeRecording() },
            onHoverChanged: onHoverChanged
        )
    }
}
```

- [ ] **Step 5: Build to verify compilation**

Run: `xcodebuild -project MeetingSonar.xcodeproj -scheme MeetingSonar -configuration Debug build 2>&1 | tail -5`

This will fail because StatusPillView hasn't been updated yet. That's expected — proceed to Task 2.

- [ ] **Step 6: Commit controller changes**

```bash
git add MeetingSonar/Views/Overlay/OverlayWindowController.swift
git commit -m "refactor: KeyablePanel, remove dead menu code, add hover callback"
```

---

### Task 2: Rewrite StatusPillView

**Files:**
- Rewrite: `MeetingSonar/Views/Overlay/StatusPillView.swift`

- [ ] **Step 1: Rewrite StatusPillView with two-state hover design**

Replace the entire file with:

```swift
import SwiftUI

/// Two-state recording status overlay.
/// Collapsed: minimal pill showing recording dot + duration.
/// Expanded (on hover): full control panel with audio toggles and action buttons.
struct StatusPillView: View {
    let duration: TimeInterval
    let isPaused: Bool
    let includeSystemAudio: Bool
    let includeMicrophone: Bool

    // MARK: - Callbacks
    var onClose: () -> Void
    var onToggleSystemAudio: (Bool) -> Void
    var onToggleMicrophone: (Bool) -> Void
    var onPause: () -> Void
    var onResume: () -> Void
    var onHoverChanged: (Bool) -> Void

    @State private var isExpanded = false
    /// Tracks whether mouse is inside the view, used with delayed collapse.
    @State private var isMouseInside = false
    @State private var collapseTask: Task<Void, Never>?

    private var timeString: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// Dot color: red for recording, orange for paused.
    private var indicatorColor: Color {
        isPaused ? .orange : .red
    }

    var body: some View {
        VStack(spacing: 0) {
            // Always visible: status row
            statusRow

            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 8)

                audioToggles
                    .padding(.vertical, 6)

                Divider()
                    .padding(.horizontal, 8)

                actionButtons
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isExpanded ? 10 : 8)
        .background(.ultraThinMaterial)
        .cornerRadius(isExpanded ? 12 : 20)
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 12 : 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
        .fixedSize()
        .onHover { hovering in
            isMouseInside = hovering
            if hovering {
                // Cancel pending collapse
                collapseTask?.cancel()
                collapseTask = nil
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded = true
                }
                onHoverChanged(true)
            } else {
                // Delay collapse to prevent accidental close
                collapseTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled, !isMouseInside else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded = false
                    }
                    onHoverChanged(false)
                }
            }
        }
    }

    // MARK: - Status Row (always visible)

    private var statusRow: some View {
        HStack(spacing: 8) {
            // Pulsing indicator dot
            Circle()
                .fill(indicatorColor)
                .frame(width: 10, height: 10)
                .shadow(color: indicatorColor.opacity(0.6), radius: 4)

            Text(isPaused ? "Paused" : "Rec")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Text(timeString)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Audio Source Toggles (expanded only)

    private var audioToggles: some View {
        VStack(spacing: 4) {
            Toggle(isOn: Binding(
                get: { includeSystemAudio },
                set: { onToggleSystemAudio($0) }
            )) {
                Label("settings.audio.systemAudio", systemImage: "speaker.wave.2")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: Binding(
                get: { includeMicrophone },
                set: { onToggleMicrophone($0) }
            )) {
                Label("settings.audio.microphone", systemImage: "mic")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Action Buttons (expanded only)

    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Pause / Resume
            Button(action: { isPaused ? onResume() : onPause() }) {
                Label(
                    isPaused ? "recording.resume" : "recording.pause",
                    systemImage: isPaused ? "play.fill" : "pause.fill"
                )
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Stop
            Button(role: .destructive, action: onClose) {
                Label("recording.stop", systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Preview

struct StatusPillView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            StatusPillView(
                duration: 125,
                isPaused: false,
                includeSystemAudio: true,
                includeMicrophone: true,
                onClose: {},
                onToggleSystemAudio: { _ in },
                onToggleMicrophone: { _ in },
                onPause: {},
                onResume: {},
                onHoverChanged: { _ in }
            )

            StatusPillView(
                duration: 3605,
                isPaused: true,
                includeSystemAudio: true,
                includeMicrophone: false,
                onClose: {},
                onToggleSystemAudio: { _ in },
                onToggleMicrophone: { _ in },
                onPause: {},
                onResume: {},
                onHoverChanged: { _ in }
            )
        }
        .padding(40)
        .background(Color.gray.opacity(0.3))
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project MeetingSonar.xcodeproj -scheme MeetingSonar -configuration Debug build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add MeetingSonar/Views/Overlay/StatusPillView.swift
git commit -m "feat: redesign StatusPillView with hover-expandable two-state overlay"
```

---

### Task 3: Verify with Computer Use

- [ ] **Step 1: Build Release and run**

```bash
xcodebuild -project MeetingSonar.xcodeproj -scheme MeetingSonar -configuration Debug build
open /path/to/DerivedData/.../Debug/MeetingSonar.app
```

- [ ] **Step 2: Use computer-use tools to verify**

1. Start a recording (click menu bar icon → start)
2. Screenshot to confirm the collapsed pill appears at bottom-right
3. Move mouse over the pill to trigger expand
4. Screenshot to confirm expanded state shows toggles and buttons
5. Click Stop button to verify it works
6. Verify pill disappears after recording stops

- [ ] **Step 3: Final commit if any adjustments needed**

```bash
git add -A
git commit -m "fix: adjust overlay layout after manual verification"
```

---

## Risk Notes

1. **Panel resizing during animation**: `updateStatusPanelLayout()` calls `view.fittingSize` which may return the target size before animation completes. The panel will jump to final size immediately while content animates — this is acceptable and avoids complexity of animating the panel frame.

2. **`isMovableByWindowBackground` vs hover**: Dragging starts on mouseDown, hover triggers on mouseEnter. These don't conflict — dragging requires holding the mouse button, hover just requires cursor presence.

3. **Localization keys**: Reuses existing keys (`settings.audio.systemAudio`, `settings.audio.microphone`, `recording.stop`, `recording.pause`, `recording.resume`). If any key is missing, add it to `Localizable.xcstrings`.
