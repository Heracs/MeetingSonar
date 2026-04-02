# Status Pill Overlay Redesign

## Problem

1. **Bug**: StatusPillView uses SwiftUI `Menu` inside a borderless `NSPanel` with `nonactivatingPanel` style. The panel's `canBecomeKey` defaults to `false`, causing the menu to appear at incorrect screen coordinates. Users cannot select menu items.

2. **UX**: Current pill is a flat text bar that doesn't feel like an overlay. Needs a semi-transparent, non-intrusive design that informs without distracting.

## Design

### Two-State Overlay

The overlay has two visual states: **collapsed** (default) and **expanded** (on hover).

#### Collapsed State

- Content: pulsing red dot + recording duration (`● 03:25`)
- When paused: orange dot + duration (`● Paused 03:25`)
- Style: capsule shape, `ultraThinMaterial` background, ~100px wide
- Position: bottom-right corner, 20px padding from screen edges
- Draggable via `isMovableByWindowBackground`

#### Expanded State (on hover)

Triggered by mouse enter, smooth animation (0.3s ease-in-out) expanding the capsule.

Layout (top to bottom):
1. **Status row**: recording indicator dot + "Recording" / "Paused" + duration
2. **Divider**
3. **Audio source toggles**: system audio toggle, microphone toggle
4. **Divider**
5. **Action buttons** (horizontal): Pause/Resume button + Stop button (red, destructive)

Collapse trigger: mouse exit with 0.3s delay (prevents accidental collapse).

Same `ultraThinMaterial` background, same capsule corner radius, shadow for depth.

### Panel Size Management

- Collapsed and expanded states have different content sizes
- On state change: compute new `fittingSize`, call `panel.setContentSize()`, reposition to keep bottom-right anchor stable
- Animate frame change alongside content transition

### Paused State

- Collapsed: orange dot instead of red, text shows "Paused"
- Expanded: Pause button becomes Resume button, indicator color changes to orange

## Bug Fix

### Root Cause

`NSPanel` created with `[.borderless, .nonactivatingPanel]` has `canBecomeKey` returning `false`. SwiftUI `Menu` requires key window status for correct coordinate conversion.

### Fix

1. **Create `KeyablePanel` subclass**: Override `canBecomeKey` to return `true`. This allows the panel to become key when interacted with, without stealing app activation (`.nonactivatingPanel` still prevents that).

2. **Replace SwiftUI `Menu` with custom expand/collapse view**: The hover-based expand design eliminates the need for SwiftUI `Menu` entirely. All controls are directly visible in the expanded state — no popup menu needed. This bypasses the menu positioning bug at the architecture level.

3. **Clean up dead code**: Remove `handlePillClick()`, `menuStopAction()`, `menuPauseAction()`, `menuResumeAction()` from `OverlayWindowController` — these are unused since `StatusPillView` switched to SwiftUI `Menu`, and now we're removing the Menu too.

## Files

| Action | File | Change |
|--------|------|--------|
| Modify | `OverlayWindowController.swift` | Use `KeyablePanel`, remove dead menu code, update panel sizing for hover states |
| Rewrite | `StatusPillView.swift` | Two-state design with hover expand/collapse, replace `Menu` with direct controls |

## Out of Scope

- StartOverlayView and RemindOverlayView are not changed
- No changes to recording service or audio source logic
- No new localization keys (reuse existing ones where possible)
