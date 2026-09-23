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
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        isRestorable = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        setFrame(screen.visibleFrame, display: false)
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
