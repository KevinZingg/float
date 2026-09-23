import AppKit

/// Owns the cards: add/remove, focus, z-order and snapping.
@MainActor
final class CardManager {
    let canvas: CanvasView
    /// Creation order, used for focus cycling. Z-order lives in `canvas.subviews`.
    private(set) var cards: [CardView] = []
    private(set) var focused: CardView?

    private var trackpad: TrackpadMover?

    init(canvas: CanvasView) {
        self.canvas = canvas
        trackpad = TrackpadMover(canvas: canvas) { [weak self] in self?.focus($0) }
    }

    @discardableResult
    /// With `spawnFrom`, the card appears centered there and springs into a free spot.
    func add(_ content: CardContent, size: NSSize, aspect: CGFloat? = nil, spawnFrom: CGRect? = nil) -> CardView {
        let bounds = canvas.bounds
        let step = CGFloat(cards.count % 8) * Settings.cascadeOffset
        var start = Snapping.clamp(CGRect(
            x: bounds.minX + Settings.padding + step, y: bounds.minY + Settings.padding + step,
            width: size.width, height: size.height), in: bounds)
        if let spawnFrom {
            start.origin = CGPoint(x: spawnFrom.midX - size.width / 2, y: spawnFrom.midY - size.height / 2)
        }
        let target = spawnFrom.map { _ in Snapping.freeSpot(for: size, avoiding: cards.map(\.frame), in: bounds) }
        return insert(content, frame: start, aspect: aspect, target: target)
    }

    /// Opens a card next to `source` (right, else left, else below), growing out of its edge.
    @discardableResult
    func add(_ content: CardContent, size: NSSize, beside source: CardView) -> CardView {
        let others = cards.filter { $0 !== source }.map { $0.mover.target ?? $0.frame }
        let target = Snapping.besideSpot(for: size, next: source.frame, avoiding: others, in: canvas.bounds)
        let edge = Snapping.edgePoint(of: source.frame, toward: target)
        let start = CGRect(x: edge.x - size.width / 2, y: edge.y - size.height / 2, width: size.width, height: size.height)
        let card = insert(content, frame: start, aspect: nil, target: target)
        card.animateEntrance()
        return card
    }

    private func insert(_ content: CardContent, frame start: CGRect, aspect: CGFloat?, target: CGRect?) -> CardView {
        let card = CardView(content: content, frame: start)
        card.aspect = aspect
        card.onFocus = { [weak self] in self?.focus($0) }
        card.onMoveEnded = { [weak self] in self?.settle($0, velocity: $1) }
        card.onResizeEnded = { [weak self] in self?.settle($0, velocity: .zero) }
        card.onCloseRequested = { [weak self] in self?.close($0) }
        card.onAspectPicked = { [weak self] in self?.setAspect($1, for: $0) }
        card.onSizePicked = { [weak self] in self?.applySize($1, to: $0) }
        content.onRequestClose = { [weak self, weak card] in
            guard let card else { return }
            self?.remove(card)
        }
        canvas.addSubview(card)
        cards.append(card)
        focus(card)
        if let target { card.mover.animate(to: target) }
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
        guard cards.contains(where: { $0 === card }) else { return }
        cards.removeAll { $0 === card }
        card.content.close()
        card.mover.stop()
        card.animateExit { card.removeFromSuperview() }
        if focused === card {
            focused = nil
            if let top = canvas.subviews.last(where: { v in cards.contains { $0 === v } }) as? CardView { focus(top) }
        }
    }

    /// PiP-style release: a fling docks at the anchor nearest the projected point; a slow drop stays, clamped.
    func settle(_ card: CardView, velocity: CGVector) {
        let target = Fling.target(for: card.frame, velocity: velocity, in: canvas.bounds)
        guard target != card.frame else { return }
        let spring: Spring = Fling.isFling(velocity) ? .standard : .rubberBand
        card.mover.animate(to: target, velocity: velocity, spring: spring)
    }

    /// Terminals in a grid on the left, previews stacked on the right, all springing into place.
    func arrangeAll() {
        let terminals = cards.filter { $0.content.kind == .terminal }
        let previews = cards.filter { $0.content.kind == .web }
        let layout = Snapping.arrange(
            terminals: terminals.count, previewAspects: previews.map(\.aspect), in: canvas.bounds)
        for (card, frame) in zip(terminals + previews, layout.terminals + layout.previews) {
            setFrame(frame, for: card)
        }
    }

    /// Applies an S/M/L width, keeping the locked aspect or the current proportions.
    func applySize(_ preset: SizePreset, to card: CardView) {
        var f = card.frame
        let chrome = Settings.chromeHeight
        let ratio = card.aspect ?? f.width / max(f.height - chrome, 1)
        f.size = CGSize(width: preset.width, height: preset.width / ratio + chrome)
        setFrame(Snapping.clamp(f, in: canvas.bounds), for: card)
    }

    /// Locks (or frees) a card's content aspect and resizes it to match, keeping its width.
    func setAspect(_ aspect: CGFloat?, for card: CardView) {
        card.aspect = aspect
        guard let aspect else { return }
        var f = card.frame
        f.size.height = f.width / aspect + Settings.chromeHeight
        setFrame(Snapping.clamp(f, in: canvas.bounds), for: card)
    }

    /// Pulls every card back on screen, e.g. after Stage Manager shifts the window.
    func clampAll() {
        for card in cards where !card.mover.isRunning {
            card.frame = Snapping.clamp(card.frame, in: canvas.bounds)
        }
    }

    func setFrame(_ frame: CGRect, for card: CardView, animated: Bool = true) {
        guard animated else { card.mover.stop(); card.frame = frame; return }
        card.mover.animate(to: frame)
    }
}
