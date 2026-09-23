import AppKit

/// Owns the cards: add/remove, focus, z-order and snapping.
@MainActor
final class CardManager {
    let canvas: CanvasView
    /// Creation order, used for focus cycling. Z-order lives in `canvas.subviews`.
    private(set) var cards: [CardView] = []
    private(set) var focused: CardView?

    init(canvas: CanvasView) {
        self.canvas = canvas
    }

    @discardableResult
    func add(_ content: CardContent, size: NSSize, aspect: CGFloat? = nil) -> CardView {
        let step = CGFloat(cards.count % 8) * Settings.cascadeOffset
        let proposed = CGRect(
            x: canvas.layoutBounds.minX + Settings.padding + step,
            y: canvas.layoutBounds.minY + Settings.padding + step,
            width: size.width, height: size.height)
        let card = CardView(content: content, frame: Snapping.clamp(proposed, in: canvas.layoutBounds))
        card.aspect = aspect
        card.onFocus = { [weak self] in self?.focus($0) }
        card.onMoveEnded = { [weak self] in self?.settle($0, velocity: $1) }
        card.onResizeEnded = { [weak self] in self?.settle($0, velocity: .zero) }
        card.onCloseRequested = { [weak self] in self?.close($0) }
        content.onRequestClose = { [weak self, weak card] in
            guard let card else { return }
            self?.remove(card)
        }
        canvas.addSubview(card)
        cards.append(card)
        focus(card)
        return card
    }

    func focus(_ card: CardView) {
        if canvas.subviews.last !== card {
            canvas.subviews = canvas.subviews.filter { $0 !== card } + [card]
        }
        if focused !== card {
            focused?.isFocused = false
            focused = card
            card.isFocused = true
        }
        card.content.focus()
    }

    /// Finds the card owning a hit view and focuses it.
    func focus(containing view: NSView?) {
        var v = view
        while let current = v {
            if let card = current as? CardView {
                focus(card)
                return
            }
            v = current.superview
        }
    }

    func cycleFocus(by delta: Int) {
        guard !cards.isEmpty else { return }
        let index = focused.flatMap { f in cards.firstIndex { $0 === f } } ?? 0
        let next = (index + delta + cards.count) % cards.count
        focus(cards[next])
    }

    func close(_ card: CardView) {
        guard card.content.confirmClose() else { return }
        remove(card)
    }

    func closeFocused() {
        if let focused { close(focused) }
    }

    private func remove(_ card: CardView) {
        card.content.close()
        card.removeFromSuperview()
        cards.removeAll { $0 === card }
        if focused === card {
            focused = nil
            if let top = canvas.subviews.last as? CardView { focus(top) }
        }
    }

    /// PiP-style release: a fling docks at the anchor nearest the projected point; a slow drop stays, clamped.
    func settle(_ card: CardView, velocity: CGVector) {
        let target = Fling.target(for: card.frame, velocity: velocity, in: canvas.layoutBounds)
        guard target != card.frame else { return }
        let spring: Spring = Fling.isFling(velocity) ? .standard : .rubberBand
        card.mover.animate(to: target, velocity: velocity, spring: spring)
    }

    /// Locks (or frees) a card's content aspect and resizes it to match, keeping its width.
    func setAspect(_ aspect: CGFloat?, for card: CardView) {
        card.aspect = aspect
        guard let aspect else { return }
        var f = card.frame
        f.size.height = f.width / aspect + Settings.chromeHeight
        setFrame(Snapping.clamp(f, in: canvas.layoutBounds), for: card)
    }

    /// Pulls every card back on screen, e.g. after Stage Manager shifts the window.
    func clampAll() {
        for card in cards where !card.mover.isRunning {
            card.frame = Snapping.clamp(card.frame, in: canvas.layoutBounds)
        }
    }

    func setFrame(_ frame: CGRect, for card: CardView, animated: Bool = true) {
        guard animated else { card.mover.stop(); card.frame = frame; return }
        card.mover.animate(to: frame)
    }
}
