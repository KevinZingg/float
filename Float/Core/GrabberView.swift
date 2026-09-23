import AppKit

/// iOS-style grabber pill hinting that the top strip moves the card. Purely visual: clicks
/// fall through to the strip, and the two-finger move is handled by `TrackpadMover`.
@MainActor
final class GrabberView: NSView {
    enum Emphasis { case hidden, idle, active }

    var emphasis = Emphasis.hidden {
        didSet {
            guard emphasis != oldValue else { return }
            let alpha: CGFloat = switch emphasis {
            case .hidden: 0
            case .idle: Theme.current.grabberIdleAlpha
            case .active: Theme.current.grabberActiveAlpha
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                animator().alphaValue = alpha
            }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        applyTheme()
    }

    func applyTheme() {
        layer?.backgroundColor = Theme.current.accent.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
