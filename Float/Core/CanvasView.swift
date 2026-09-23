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
}
