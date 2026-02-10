import Cocoa
import SwiftUI
import Combine

class OverlayState: ObservableObject {
    @Published var duration: TimeInterval = 0
    @Published var isPaused: Bool = false
    @Published var isDismissed: Bool = false  // F-9.2: User dismissed the pill
    @Published var includeSystemAudio: Bool = true   // v1.0: Current audio source state
    @Published var includeMicrophone: Bool = true    // v1.0: Current audio source state
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
        
        statusPanel?.alphaValue = 0
        statusPanel?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            statusPanel?.animator().alphaValue = 1
        }
    }
    
    func hideStatusPill() {
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
                    self.showStartOverlay()
                    self.showStatusPill()
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .recordingDidStop)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.hideStartOverlay()
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
                    self?.updateStatusPanelLayout() // Resize and reposition
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .recordingDidResume)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.overlayState.isPaused = false
                    self?.updateStatusPanelLayout() // Resize and reposition
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
        // Set initial frame size based on view fitting size
        if let viewSize = panel.contentViewController?.view.fittingSize {
            panel.setContentSize(viewSize)
        }
        
        startPanel = panel
    }
    
    private func ensureStatusPanelCreated() {
        if statusPanel != nil { return }

        let panel = createBasePanel()

        // F-9.2: Inject state with close callback
        let wrappedView = StatusPillWrapper(state: overlayState, onTap: {
            self.handlePillClick()
        }, onClose: {
            self.dismissStatusPill()
        })

        panel.contentViewController = NSHostingController(rootView: wrappedView)
        if let viewSize = panel.contentViewController?.view.fittingSize {
            panel.setContentSize(viewSize)
        }

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
            panel.setContentSize(viewSize)
        }

        remindPanel = panel
    }

    /// F-9.2: User-initiated dismiss (won't show again this session)
    private func dismissStatusPill() {
        overlayState.isDismissed = true
        hideStatusPill()
    }
    
    private func createBasePanel() -> NSPanel {
        let panel = NSPanel(
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
    
    private func positionStartPanel() {
        guard let panel = startPanel, let screen = NSScreen.main else { return }

        let screenRect = screen.visibleFrame
        let panelSize = panel.frame.size

        // Center Top: X = (ScreenWidth - PanelWidth) / 2, Y = ScreenHeight - TopPadding
        let x = screenRect.minX + (screenRect.width - panelSize.width) / 2
        let y = screenRect.maxY - 60 // 100px from top might be too low, let's try 60 (below menu bar)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionRemindPanel() {
        guard let panel = remindPanel, let screen = NSScreen.main else { return }

        let screenRect = screen.visibleFrame
        let panelSize = panel.frame.size

        // Center Top: Same position as start panel
        let x = screenRect.minX + (screenRect.width - panelSize.width) / 2
        let y = screenRect.maxY - 60

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionStatusPanel() {
        guard let panel = statusPanel, let screen = NSScreen.main else { return }
        
        let screenRect = screen.visibleFrame
        let panelSize = panel.frame.size
        
        // Bottom Right: X = ScreenMaxX - Width - Padding, Y = ScreenMinY + Padding
        let x = screenRect.maxX - panelSize.width - 20
        let y = screenRect.minY + 20
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func updateStatusPanelLayout() {
        guard let panel = statusPanel, let view = panel.contentViewController?.view else { return }
        
        // Force layout update to get new fitting size
        let newSize = view.fittingSize
        if newSize != .zero && newSize != panel.frame.size {
            panel.setContentSize(newSize)
            positionStatusPanel() // Re-calculate X based on new width
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
    
    private func handlePillClick() {
        let menu = NSMenu()
        
        // Stop
        let stopItem = menu.addItem(withTitle: "Stop Recording", action: #selector(menuStopAction), keyEquivalent: "")
        stopItem.target = self
        
        // Pause/Resume
        let isPaused = overlayState.isPaused
        let pauseTitle = isPaused ? "Resume Recording" : "Pause Recording"
        let pauseAction = isPaused ? #selector(menuResumeAction) : #selector(menuPauseAction)
        
        let pauseItem = menu.addItem(withTitle: pauseTitle, action: pauseAction, keyEquivalent: "")
        pauseItem.target = self
        
        // Show menu
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: statusPanel?.contentView ?? NSView())
        }
    }
    
    @objc private func menuStopAction() {
        requestStopRecording()
    }
    
    @objc private func menuPauseAction() {
        RecordingService.shared.pauseRecording()
    }
    
    @objc private func menuResumeAction() {
        RecordingService.shared.resumeRecording()
    }
}

// Wrapper to bridge ObservableObject to View
// v1.0 - Recording Scenario Optimization: Added audio source state and toggle callbacks
struct StatusPillWrapper: View {
    @ObservedObject var state: OverlayState
    var onTap: () -> Void
    var onClose: () -> Void  // F-9.2: Close callback

    var body: some View {
        StatusPillView(
            duration: state.duration,
            isPaused: state.isPaused,
            includeSystemAudio: state.includeSystemAudio,
            includeMicrophone: state.includeMicrophone,
            onTap: onTap,
            onClose: onClose,
            onToggleSystemAudio: { enabled in
                Task {
                    await RecordingService.shared.toggleSystemAudio(enabled)
                }
            },
            onToggleMicrophone: { enabled in
                Task {
                    await RecordingService.shared.toggleMicrophone(enabled)
                }
            }
        )
    }
}

// Define Notification Names extension here if not visible
// Notification Names are defined in RecordingService.swift
