import AppKit

/// Shown when the canvas has no cards: the Helvetia character halftone (mogen identity § 07) in sage ink over a
/// soft frosted halo, with the launcher shortcut beneath. The halo keeps any wallpaper from clashing and feathers
/// out into the transparent canvas. Click-inert.
@MainActor
final class EmptyStateView: NSView {
    private let halo = NSVisualEffectView()
    private let tint = RadialTintView()
    private let figure = HelvetiaView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        halo.material = .hudWindow
        halo.blendingMode = .behindWindow
        halo.state = .active
        halo.appearance = NSAppearance(named: .darkAqua)
        for v in [halo, tint, figure] as [NSView] { addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let d = min(max(bounds.width * Config.haloWidthFraction, Config.haloWidthRange.lowerBound), Config.haloWidthRange.upperBound)
        let rect = CGRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
        // A layer mask switches the behind-window blur off; maskImage keeps it, weighted by the image's alpha.
        if halo.frame.size != rect.size { halo.maskImage = Self.radialMask(size: rect.size) }
        halo.frame = rect
        tint.frame = rect
        figure.frame = rect
        figure.coreDiameter = d * Self.coreFraction
    }

    /// Fades in or out on the card spring; hidden once invisible so the blur costs nothing under cards.
    func setVisible(_ visible: Bool, animated: Bool) {
        guard let layer else { return }
        let target: Float = visible ? 1 : 0
        if visible { isHidden = false }
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

    /// NSGradient's radial fill reaches the rect's corners, so locations are fractions of half the diagonal.
    private static let radiusScale: CGFloat = 1 / 2.squareRoot()
    static var coreFraction: CGFloat { Config.haloFigureFraction }

    static func radialMask(size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            radialGradient(color: .black)?.draw(in: rect, relativeCenterPosition: .zero)
            return true
        }
    }

    /// Fully opaque in the core (the blur has to be near total where the figure stands, or the wallpaper shows
    /// through at partial alpha), then a Gaussian tail to nothing by `haloFadeEnd` of the radius. No ring, no edge.
    static func radialGradient(color: NSColor, peak: CGFloat = 1) -> NSGradient? {
        let core = Config.haloCoreEnd, end = Config.haloFadeEnd
        var stops: [(CGFloat, CGFloat)] = [(0, 1)]
        // A Gaussian tail reads as a glow rather than a disc; the last few percent are ramped to exactly zero.
        let floor = exp(-pow((end - core) / Config.haloSigma, 2))
        for i in 0...20 {
            let r = core + (end - core) * CGFloat(i) / 20
            let g = exp(-pow((r - core) / Config.haloSigma, 2))
            stops.append((r, max(0, (g - floor) / (1 - floor))))
        }
        stops.append((1, 0))
        return NSGradient(
            colors: stops.map { color.withAlphaComponent($0.1 * peak) },
            atLocations: stops.map { $0.0 * radiusScale },
            colorSpace: .sRGB)
    }
}

/// A Night tint over the blur, with the same radial falloff.
private final class RadialTintView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        EmptyStateView.radialGradient(color: Theme.night, peak: Config.haloTint)?.draw(in: bounds, relativeCenterPosition: .zero)
    }
}

/// The halftone figure and the "⌥ space" label, sized to sit inside the visible part of the halo.
private final class HelvetiaView: NSView {
    private static let lines: [String] = {
        guard let url = Bundle.main.url(forResource: "helvetia", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") }
    }()

    var coreDiameter: CGFloat = 500 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rows = Self.lines
        guard !rows.isEmpty else { return }
        let ink = Theme.current.accent
        let label = Theme.label("⌥ space", color: ink.withAlphaComponent(Config.emptyStateLabelAlpha), size: 12)
        let labelSize = label.size()
        let gap: CGFloat = 24
        // Plex Mono advances 0.6 em, the grid's aspect, so one line per point size keeps the source proportions.
        let size = min(Config.emptyStateMaxGlyph, (coreDiameter - gap - labelSize.height) / CGFloat(rows.count))
        let width = CGFloat(rows[0].count) * size * 0.6
        let total = CGFloat(rows.count) * size + gap + labelSize.height
        var y = (bounds.height - total) / 2
        let x = (bounds.width - width) / 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.mono(size), .foregroundColor: ink.withAlphaComponent(Config.emptyStateAlpha),
        ]
        for row in rows {
            (row as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            y += size
        }
        label.draw(at: CGPoint(x: (bounds.width - labelSize.width) / 2, y: y + gap))
    }
}
