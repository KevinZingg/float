import AppKit

/// A view that wants first say over scroll events AppKit would deliver to it (for views whose scrollWheel isn't open).
@MainActor
protocol ScrollInterceptor: NSView {
    /// Returns true when the event was consumed.
    func interceptScroll(_ event: NSEvent) -> Bool
}

/// Moves cards with a two-finger trackpad swipe, over the top strip or anywhere with ⌘ held.
/// An app-level monitor, because SwiftTerm and WKWebView consume scroll events before the card sees them.
@MainActor
final class TrackpadMover {
    private var monitor: Any?
    private weak var active: CardView?
    /// Card whose gesture we handled; its trailing momentum events are swallowed.
    private weak var momentumOwner: CardView?
    private var offset = CGVector.zero

    init(canvas: CanvasView, onBegin: @escaping (CardView) -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak canvas] event in
            guard let self, let canvas, event.window === canvas.window else { return event }
            return self.handle(event, canvas: canvas, onBegin: onBegin)
        }
    }

    private func handle(_ event: NSEvent, canvas: CanvasView, onBegin: (CardView) -> Void) -> NSEvent? {
        if !event.momentumPhase.isEmpty {
            if momentumOwner != nil {
                if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { momentumOwner = nil }
                return nil
            }
            return intercept(event)
        }

        if event.phase.contains(.began) {
            momentumOwner = nil
            // A gesture whose .ended went to another window would otherwise keep capturing every later scroll.
            if let stale = active {
                active = nil
                stale.endMove(at: event.timestamp, cancelled: true)
            }
            guard event.hasPreciseScrollingDeltas, let card = card(at: event, in: canvas) else { return intercept(event) }
            let local = card.convert(event.locationInWindow, from: nil)
            guard event.modifierFlags.contains(.command) || card.isInStrip(local) else { return intercept(event) }
            NSLog("Float: trackpad move started (%@)", event.modifierFlags.contains(.command) ? "⌘" : "strip")
            active = card
            offset = .zero
            onBegin(card)
            card.beginMove(at: event.timestamp)
        }

        guard let card = active else { return intercept(event) }
        if event.phase.contains(.changed) || event.phase.contains(.began) {
            // Follow the fingers: natural scrolling already reports deltas in finger direction.
            let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            offset.dx += sign * event.scrollingDeltaX
            offset.dy += sign * event.scrollingDeltaY // canvas is flipped, so +y is down like the fingers
            card.updateMove(offset: offset, at: event.timestamp)
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            active = nil
            momentumOwner = card
            card.endMove(at: event.timestamp, cancelled: event.phase.contains(.cancelled))
        }
        return nil
    }

    /// Offers a pass-through event to the view under the pointer; nil if it consumed it.
    private func intercept(_ event: NSEvent) -> NSEvent? {
        guard let content = event.window?.contentView,
              let target = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
        else { return event }
        var view: NSView? = target
        while let v = view, !(v is ScrollInterceptor) { view = v.superview }
        guard let interceptor = view as? ScrollInterceptor else { return event }
        return interceptor.interceptScroll(event) ? nil : event
    }

    /// Topmost card under the pointer.
    private func card(at event: NSEvent, in canvas: CanvasView) -> CardView? {
        let p = canvas.convert(event.locationInWindow, from: nil)
        return canvas.subviews.reversed().lazy.compactMap { $0 as? CardView }.first { $0.frame.contains(p) }
    }
}
