import Cocoa
import SwiftUI
import Combine

/// NSPanel subclass that can become key window and guards against
/// NSHostingView's auto-resize (`updateAnimatedWindowSize`) which can
/// cause Auto Layout constraint cycles in borderless panels.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Only allows frame/size changes when set to `true`.
    /// Blocks unsolicited resizes from NSHostingView during layout.
    var allowResize = false

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard allowResize else { return }
        super.setFrame(frameRect, display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        guard allowResize else { return }
        super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
    }

    override func setContentSize(_ size: NSSize) {
        guard allowResize else { return }
        super.setContentSize(size)
    }
}

class OverlayState: ObservableObject {
    @Published var duration: TimeInterval = 0
    @Published var isPaused: Bool = false
    @Published var isDismissed: Bool = false  // F-9.2: User dismissed the pill
    @Published var includeSystemAudio: Bool = true   // v1.0: Current audio source state
    @Published var includeMicrophone: Bool = true    // v1.0: Current audio source state
    /// Drives expand/collapse from the controller (e.g. auto-expand on recording start).
    @Published var isExpandedByController: Bool = false
}

@MainActor
class OverlayWindowController: NSObject {
    static let shared = OverlayWindowController()
    
    // MARK: - Windows
    private var startPanel: NSPanel?
    private var statusPanel: NSPanel?
    private var remindPanel: NSPanel?
    
    // MARK: - State
    private var overlayState = OverlayState()
    private var dismissTimer: Timer?
    /// Collapsed-state opacity. Semi-transparent to stay unobtrusive.
    private static let collapsedAlpha: CGFloat = 0.4
    /// Timer for auto-collapsing the pill after initial expanded display.
    private var autoCollapseTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    private override init() {
        super.init()
        setupNotificationObservers()
        // Initialize windows lazily or upfront? Upfront is safer for main thread.
    }
    
    // MARK: - Public API
    
    func showStartOverlay(appName: String = "Meeting") {
        ensureStartPanelCreated()
        
        // Configuration
        // In a real app we might pass appName to the view, currently view uses static text
        // or we could add appName to OverlayState if needed.
        
        positionStartPanel()
        
        // Animate In
        startPanel?.alphaValue = 0
        startPanel?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            startPanel?.animator().alphaValue = 1
        }
        
        // Auto Dismiss
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.hideStartOverlay()
        }
    }
    
    func hideStartOverlay() {
        guard let panel = startPanel else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
    
    func showStatusPill() {
        // F-9.2: Don't show if user dismissed
        guard !overlayState.isDismissed else { return }

        ensureStatusPanelCreated()
        positionStatusPanel()

        // Show in expanded state (replaces the old StartOverlayView).
        overlayState.isExpandedByController = true
        statusPanel?.alphaValue = 0
        statusPanel?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            statusPanel?.animator().alphaValue = 1
        }

        // Auto-collapse after 5 seconds if user doesn't interact.
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.overlayState.isExpandedByController = false
            // Fade to semi-transparent
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                self.statusPanel?.animator().alphaValue = Self.collapsedAlpha
            }
        }
    }
    
    func hideStatusPill() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
        overlayState.isExpandedByController = false
        guard let panel = statusPanel else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
    
    func updateDuration(_ duration: TimeInterval) {
        overlayState.duration = duration
    }

    // MARK: - Remind Overlay

    func showRemindOverlay(appName: String) {
        ensureRemindPanelCreated(appName: appName)

        guard let panel = remindPanel else { return }

        positionRemindPanel()

        // Animate In
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 1
        }

        // Auto Dismiss after 10 seconds (longer than start overlay for user to decide)
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.hideRemindOverlay()
        }
    }

    func hideRemindOverlay() {
        guard let panel = remindPanel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: - Private Helpers
    
    private func setupNotificationObservers() {
        // Listen for RecordingService notifications
        // Note: These need to be defined in NotificationManager or RecordingService
        // Assuming .recordingDidStart, .recordingDidStop, .recordingTimerUpdate exist or will be added.

        // Listen for remind overlay request from DetectionService
        NotificationCenter.default.publisher(for: .showRemindOverlay)
            .compactMap { $0.userInfo?["appName"] as? String }
            .sink { [weak self] appName in
                DispatchQueue.main.async {
                    self?.showRemindOverlay(appName: appName)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .recordingDidStart)
            .sink { [weak self] notification in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    // v1.0: Initialize audio source state from current recording config
                    let config = RecordingService.shared.currentAudioSourceState
                    self.overlayState.includeSystemAudio = config.includeSystemAudio
                    self.overlayState.includeMicrophone = config.includeMicrophone
                    self.overlayState.isPaused = false
                    self.overlayState.isDismissed = false  // F-9.2: Reset dismiss state on new recording
                    // Pill shows in expanded state (replaces StartOverlayView)
                    self.showStatusPill()
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .recordingDidStop)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.hideStatusPill()
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .recordingTimerUpdate)
            .compactMap { $0.userInfo?["duration"] as? TimeInterval }
            .sink { [weak self] duration in
                DispatchQueue.main.async {
                    self?.updateDuration(duration)
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .recordingDidPause)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.overlayState.isPaused = true
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .recordingDidResume)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.overlayState.isPaused = false
                }
            }
            .store(in: &cancellables)

        // v1.0 - Recording Scenario Optimization: Listen for audio source changes
        NotificationCenter.default.publisher(for: .recordingAudioSourceChanged)
            .sink { [weak self] notification in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let systemAudio = notification.userInfo?["systemAudio"] as? Bool {
                        self.overlayState.includeSystemAudio = systemAudio
                    }
                    if let microphone = notification.userInfo?["microphone"] as? Bool {
                        self.overlayState.includeMicrophone = microphone
                    }
                }
            }
            .store(in: &cancellables)
    }

    
    private func ensureStartPanelCreated() {
        if startPanel != nil { return }
        
        let panel = createBasePanel()
        let view = StartOverlayView(onStop: {
            self.requestStopRecording()
        }, onClose: {
            self.hideStartOverlay()
        })
        
        panel.contentViewController = NSHostingController(rootView: view)
        if let viewSize = panel.contentViewController?.view.fittingSize {
            withResize(of: panel) { $0.setContentSize(viewSize) }
        }

        startPanel = panel
    }
    
    private func ensureStatusPanelCreated() {
        if statusPanel != nil { return }

        let panel = createBasePanel()

        let wrappedView = StatusPillWrapper(state: overlayState, onClose: {
            self.requestStopRecording()
            self.dismissStatusPill()
        }, onHoverChanged: { [weak self] isHovering in
            guard let self = self else { return }
            if isHovering {
                // Cancel auto-collapse if user interacts during initial display
                self.autoCollapseTimer?.invalidate()
                self.autoCollapseTimer = nil
                // Restore full opacity when user interacts
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    self.statusPanel?.animator().alphaValue = 1.0
                }
            } else {
                // Fade to semi-transparent after hover ends
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.5
                    self.statusPanel?.animator().alphaValue = Self.collapsedAlpha
                }
            }
        })

        panel.contentViewController = NSHostingController(rootView: wrappedView)
        // Fixed panel size: always the expanded maximum.
        // SwiftUI handles visual expand/collapse internally via clipping.
        let fixedSize = NSSize(width: StatusPillView.panelWidth, height: StatusPillView.panelHeight)
        // Panel is transparent — only the SwiftUI pill content is visible.
        withResize(of: panel) { $0.setContentSize(fixedSize) }

        statusPanel = panel
    }

    private func ensureRemindPanelCreated(appName: String) {
        if remindPanel != nil { return }

        let panel = createBasePanel()
        let view = RemindOverlayView(appName: appName, onStart: {
            self.handleRemindStartRecording()
        }, onDismiss: {
            self.hideRemindOverlay()
        })

        panel.contentViewController = NSHostingController(rootView: view)
        if let viewSize = panel.contentViewController?.view.fittingSize {
            withResize(of: panel) { $0.setContentSize(viewSize) }
        }

        remindPanel = panel
    }

    /// F-9.2: User-initiated dismiss (won't show again this session)
    private func dismissStatusPill() {
        overlayState.isDismissed = true
        hideStatusPill()
    }
    
    private func createBasePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], // Important: nonactivatingPanel prevents focus stealing
            backing: .buffered,
            defer: false
        )
        panel.level = .floating // Above normal windows
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // View has shadow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] // Show on all spaces and on top of fullscreen apps
        panel.isMovableByWindowBackground = true  // F-9.2: Enable dragging
        return panel
    }
    
    /// Performs a panel resize/reposition within the `allowResize` guard.
    private func withResize(of panel: NSPanel?, _ body: (KeyablePanel) -> Void) {
        guard let keyable = panel as? KeyablePanel else { return }
        keyable.allowResize = true
        body(keyable)
        keyable.allowResize = false
    }

    private func positionStartPanel() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        withResize(of: startPanel) { panel in
            let panelSize = panel.frame.size
            let x = screenRect.minX + (screenRect.width - panelSize.width) / 2
            let y = screenRect.maxY - 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func positionRemindPanel() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        withResize(of: remindPanel) { panel in
            let panelSize = panel.frame.size
            let x = screenRect.minX + (screenRect.width - panelSize.width) / 2
            let y = screenRect.maxY - 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func positionStatusPanel() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        // Bottom-left corner with padding.
        let origin = NSPoint(x: screenRect.minX + 20, y: screenRect.minY + 20)
        withResize(of: statusPanel) { panel in
            panel.setFrameOrigin(origin)
        }
    }

    /// Resizes panel to match current SwiftUI content size.
    /// Preserves frame origin (bottom-left corner) so the pill
    /// expands rightward and upward from its anchored position.
    private func updateStatusPanelLayout() {
        guard let view = statusPanel?.contentViewController?.view else { return }
        let newSize = view.fittingSize
        guard newSize != .zero else { return }
        withResize(of: statusPanel) { panel in
            let newFrame = NSRect(origin: panel.frame.origin, size: newSize)
            panel.setFrame(newFrame, display: true)
        }
    }
    
    private func requestStopRecording() {
        // Direct call for reliability
        RecordingService.shared.stopRecording()
    }

    private func handleRemindStartRecording() {
        hideRemindOverlay()
        // Post notification that user accepted the reminder
        NotificationCenter.default.post(name: .startRecordingRequested, object: nil)
    }
}

/// Bridges OverlayState (ObservableObject) to StatusPillView.
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
            isExpandedByController: state.isExpandedByController,
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

// Define Notification Names extension here if not visible
// Notification Names are defined in RecordingService.swift
