import AppKit

/// Root view holding the cards. Draws nothing, so empty areas stay fully transparent.
final class CanvasView: NSView {
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The part of the canvas actually on screen. Stage Manager may shift the window past the
    /// screen edge to make room for its strip, so layout must not use the full bounds.
    var layoutBounds: CGRect {
        guard let window, let screen = window.screen ?? NSScreen.main else { return bounds }
        let visible = window.convertFromScreen(screen.visibleFrame)
        let rect = convert(visible, from: nil).intersection(bounds)
        return rect.isNull ? bounds : rect
    }
}
