import AppKit

/// Shown when the canvas has no cards: the Helvetia character halftone (mogen identity § 07) and the launcher
/// shortcut. Eight treatments to choose from (`--empty-variant 1…8`, remembered). Click-inert.
@MainActor
final class EmptyStateView: NSView {
    enum Variant: Int, CaseIterable {
        case plain = 1, plate, dim, corner, frost, pixel, ascii, dither
    }

    static var variant: Variant {
        Variant(rawValue: UserDefaults.standard.integer(forKey: Config.Keys.emptyVariant)) ?? .plain
    }

    private static let helvetia: [String] = {
        guard let url = Bundle.main.url(forResource: "helvetia", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") }
    }()

    /// Variant 5 only: a uniform behind-window blur, like the lock screen.
    private let frost = NSVisualEffectView()
    private var art: WallpaperArt.Result?
    /// Everything else is drawn here, above the frost (a view's own drawing would sit under its subviews).
    private let drawing = DrawingView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        frost.material = .hudWindow
        frost.blendingMode = .behindWindow
        frost.state = .active
        frost.appearance = NSAppearance(named: .darkAqua)
        frost.autoresizingMask = [.width, .height]
        addSubview(frost)
        drawing.autoresizingMask = [.width, .height]
        drawing.onDraw = { [weak self] in self?.drawContent() }
        addSubview(drawing)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { refresh() }
    override func layout() { super.layout(); refresh() }

    /// Re-reads the variant and, for the wallpaper treatments, the (cached) processed desktop picture.
    @objc func refresh() {
        var variant = Self.variant
        art = nil
        let style: WallpaperArt.Style? = switch variant {
        case .pixel: .pixel
        case .ascii: .ascii
        case .dither: .dither
        default: nil
        }
        if let style, let window, let screen = window.screen ?? NSScreen.main {
            art = WallpaperArt.render(style, canvas: window.convertToScreen(convert(bounds, to: nil)), screen: screen)
            if art == nil { variant = .dim }
        }
        resolved = variant
        // Variants drawn straight on the wallpaper need an ink that reads on it: sage on dark, deep sage on light.
        if let screen = window?.screen ?? NSScreen.main, let b = WallpaperArt.brightness(screen: screen) {
            ink = b > 0.55 ? Theme.sageInkOnPaper : Theme.sageInk
        } else {
            ink = Theme.sageInk
        }
        frost.frame = bounds
        drawing.frame = bounds
        frost.isHidden = variant != .frost
        drawing.needsDisplay = true
    }

    private var resolved = Variant.plain
    /// Ink for the variants without their own ground (1, 4).
    private var ink = Theme.sageInk

    private func drawContent() {
        switch resolved {
        case .plain:
            drawFigure(center: bounds.center, glyph: 7, alpha: 0.55, color: ink)
        case .plate:
            drawPlate(size: CGSize(width: 360, height: 440))
        case .dim:
            fill(Theme.night.withAlphaComponent(0.62))
            drawFigure(center: bounds.center, glyph: 7, alpha: 0.8)
        case .corner:
            // Anchored bottom-left at the card padding, as the figure rises out of the corner on the website.
            let glyph: CGFloat = 3
            let size = figureSize(glyph: glyph)
            let origin = CGPoint(x: Config.padding + 8, y: bounds.height - Config.padding - 8 - size.height)
            drawFigure(origin: origin, glyph: glyph, alpha: 0.8, color: ink)
            let caption = Theme.label("⌥ space", color: ink.withAlphaComponent(0.9), size: 11)
            caption.draw(at: CGPoint(x: origin.x + size.width + 16, y: origin.y + size.height - caption.size().height))
        case .frost:
            fill(Theme.night.withAlphaComponent(0.55))
            drawFigure(center: bounds.center, glyph: 7, alpha: 0.9)
        case .pixel:
            drawArt()
            fill(Theme.night.withAlphaComponent(0.55))
            drawBlockGrid()
            drawFigure(center: bounds.center, glyph: 7, alpha: 0.9)
        case .ascii:
            drawArt()
            drawFigure(center: bounds.center, glyph: 7, alpha: 1)
        case .dither:
            drawArt()
            drawPlate(size: CGSize(width: 360, height: 440))
        }
    }

    // MARK: - Pieces

    private func fill(_ color: NSColor) {
        color.setFill()
        bounds.fill()
    }

    private func drawArt() {
        guard let art, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.interpolationQuality = art.nearest ? .none : .high
        // The view is flipped; CG images draw bottom-up.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(art.image, in: bounds)
        ctx.restoreGState()
    }

    /// A 1 px darker line between mosaic blocks, aligned to the screen like the blocks themselves.
    private func drawBlockGrid() {
        guard let window, let screen = window.screen else { return }
        let block = Config.pixelBlock
        let canvas = window.convertToScreen(convert(bounds, to: nil))
        let ox = (canvas.minX - screen.frame.minX).truncatingRemainder(dividingBy: block)
        let oy = (screen.frame.maxY - canvas.maxY).truncatingRemainder(dividingBy: block)
        let path = NSBezierPath()
        var x = -ox
        while x < bounds.width { path.move(to: CGPoint(x: x, y: 0)); path.line(to: CGPoint(x: x, y: bounds.height)); x += block }
        var y = -oy
        while y < bounds.height { path.move(to: CGPoint(x: 0, y: y)); path.line(to: CGPoint(x: bounds.width, y: y)); y += block }
        path.lineWidth = 1 / (window.backingScaleFactor)
        Theme.night.withAlphaComponent(0.35).setStroke()
        path.stroke()
    }

    /// A specimen card: Night plate, 2 pt corners, hairline, the figure in sage and the caption inside.
    private func drawPlate(size: CGSize) {
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        Theme.night.setFill()
        path.fill()
        NSColor(white: 1, alpha: 0.1).setStroke()
        path.lineWidth = 1
        path.stroke()
        let caption = Theme.label("⌥ space", color: Theme.sageInk.withAlphaComponent(0.85), size: 11)
        let capSize = caption.size()
        caption.draw(at: CGPoint(x: rect.midX - capSize.width / 2, y: rect.maxY - 24 - capSize.height))
        let glyph = min(6, (size.height - 48 - 24 - capSize.height - 16) / CGFloat(Self.helvetia.count))
        let fig = figureSize(glyph: glyph)
        drawFigure(origin: CGPoint(x: rect.midX - fig.width / 2, y: rect.minY + 40), glyph: glyph, alpha: 0.95)
    }

    private func figureSize(glyph: CGFloat) -> CGSize {
        // Plex Mono advances 0.6 em, the grid's aspect, so one line per point size keeps the source proportions.
        CGSize(width: CGFloat(Self.helvetia.first?.count ?? 0) * glyph * 0.6, height: CGFloat(Self.helvetia.count) * glyph)
    }

    /// The figure centred on `center`, with the caption 24 pt beneath.
    private func drawFigure(center: CGPoint, glyph: CGFloat, alpha: CGFloat, color: NSColor = Theme.sageInk) {
        let size = figureSize(glyph: glyph)
        let caption = Theme.label("⌥ space", color: color.withAlphaComponent(min(1, alpha + 0.3)), size: 12)
        let total = size.height + 24 + caption.size().height
        let origin = CGPoint(x: center.x - size.width / 2, y: center.y - total / 2)
        drawFigure(origin: origin, glyph: glyph, alpha: alpha, color: color)
        caption.draw(at: CGPoint(x: center.x - caption.size().width / 2, y: origin.y + size.height + 24))
    }

    private func drawFigure(origin: CGPoint, glyph: CGFloat, alpha: CGFloat, color: NSColor = Theme.sageInk) {
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.mono(glyph), .foregroundColor: color.withAlphaComponent(alpha)]
        for (i, row) in Self.helvetia.enumerated() {
            (row as NSString).draw(at: CGPoint(x: origin.x, y: origin.y + CGFloat(i) * glyph), withAttributes: attrs)
        }
    }

    // MARK: - Fade

    /// Fades in or out on the card spring; hidden once invisible so nothing behind the cards costs a frame.
    func setVisible(_ visible: Bool, animated: Bool) {
        guard let layer else { return }
        let target: Float = visible ? 1 : 0
        if visible { isHidden = false; refresh() }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            layer.opacity = target
            isHidden = !visible
            return
        }
        let spring = Spring.standard
        let anim = CASpringAnimation(keyPath: "opacity")
        anim.mass = 1
        anim.stiffness = spring.stiffness
        anim.damping = spring.damping
        anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
        anim.toValue = target
        anim.duration = anim.settlingDuration
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated { if self?.layer?.opacity == 0 { self?.isHidden = true } }
        }
        layer.add(anim, forKey: "opacity")
        layer.opacity = target
        CATransaction.commit()
    }
}

private final class DrawingView: NSView {
    var onDraw: (() -> Void)?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { onDraw?() }
}
