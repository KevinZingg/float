import AppKit

/// One ordinary, transparent window covering the screen. Normal level so Stage Manager
/// treats all cards as a single app window.
@MainActor
final class CanvasWindow: NSWindow {
    /// Called with the hit view before a left click is dispatched.
    var onMouseDown: ((NSView?) -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.visibleFrame,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        title = "Float"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        // Nearly invisible but non-zero, so clicks on empty canvas stay ours instead of passing through
        // to the wallpaper (where Stage Manager's "click wallpaper to reveal desktop" would hide every card).
        backgroundColor = NSColor(white: 0, alpha: Settings.canvasBackgroundAlpha)
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        isRestorable = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        setFrame(screen.visibleFrame, display: false)
        NotificationCenter.default.addObserver(self, selector: #selector(pin), name: NSWindow.didMoveNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(pin), name: NSWindow.didResizeNotification, object: self)
        NotificationCenter.default.addObserver(
            self, selector: #selector(pin), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// The full visible area of the main screen, including the strip Stage Manager reserves.
    var pinnedFrame: CGRect { (NSScreen.main ?? screen ?? NSScreen.screens[0]).visibleFrame }

    /// Stage Manager shifts the window right to make room for its strip; put it back so cards get the full width.
    @objc func pin() {
        // A web card's element fullscreen changes the screen's visible area; leave the canvas alone meanwhile.
        guard frame != pinnedFrame, !NSApp.currentSystemPresentationOptions.contains(.fullScreen) else { return }
        NSLog("Float: re-pinning window from %@", "\(frame)")
        setFrame(pinnedFrame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            onMouseDown?(contentView?.hitTest(event.locationInWindow))
        }
        super.sendEvent(event)
    }
}
