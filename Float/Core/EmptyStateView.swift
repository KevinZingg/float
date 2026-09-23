import AppKit
import CoreImage

/// Shown when the canvas has no cards: the Helvetia character halftone (mogen identity § 07) in Night with a white
/// sticker outline, and "⌥ SPACE" beneath, so it reads on any wallpaper. Click-inert.
@MainActor
final class EmptyStateView: NSView {
    private static let helvetia: [String] = {
        guard let url = Bundle.main.url(forResource: "helvetia", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") }
    }()

    private var sticker: (scale: CGFloat, image: CGImage, size: CGSize)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeBackingProperties() { sticker = nil; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let scale = window?.backingScaleFactor ?? 2
        if sticker?.scale != scale { sticker = Self.makeSticker(scale: scale) }
        guard let sticker, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = CGRect(x: (bounds.width - sticker.size.width) / 2, y: (bounds.height - sticker.size.height) / 2,
                          width: sticker.size.width, height: sticker.size.height).integral
        ctx.saveGState()
        // The view is flipped; CG images draw bottom-up.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(sticker.image, in: CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    /// Figure and caption in Night over their own silhouette, dilated by `emptyOutline` and filled white.
    /// Rendered once per backing scale.
    private static func makeSticker(scale: CGFloat) -> (scale: CGFloat, image: CGImage, size: CGSize)? {
        let glyph = Config.emptyGlyph, pad = Config.emptyOutline * 2
        let cols = CGFloat(helvetia.first?.count ?? 0)
        let figure = CGSize(width: cols * glyph * 0.6, height: CGFloat(helvetia.count) * glyph)
        let caption = Theme.label("⌥ space", color: Theme.night, size: 12)
        let gap: CGFloat = 24
        let size = CGSize(width: figure.width + pad * 2, height: figure.height + gap + caption.size().height + pad * 2)

        // 1. Black glyphs on transparent.
        guard let glyphs = bitmap(size: size, scale: scale, draw: {
            let attrs: [NSAttributedString.Key: Any] = [.font: Theme.mono(glyph), .foregroundColor: Theme.night]
            for (i, row) in helvetia.enumerated() {
                (row as NSString).draw(at: CGPoint(x: pad, y: pad + CGFloat(i) * glyph), withAttributes: attrs)
            }
            caption.draw(at: CGPoint(x: (size.width - caption.size().width) / 2, y: pad + figure.height + gap))
        }) else { return nil }

        // 2. Dilate the silhouette (max filter on alpha) and paint it white.
        let dilated = CIImage(cgImage: glyphs)
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: Config.emptyOutline * scale])
            .cropped(to: CGRect(x: 0, y: 0, width: glyphs.width, height: glyphs.height))
        guard let outline = CIContext().createCGImage(dilated, from: dilated.extent) else { return nil }

        // 3. White outline, black glyphs on top.
        let px = CGRect(x: 0, y: 0, width: glyphs.width, height: glyphs.height)
        guard let ctx = CGContext(data: nil, width: glyphs.width, height: glyphs.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(outline, in: px)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(px)
        ctx.setBlendMode(.normal)
        ctx.draw(glyphs, in: px)
        return ctx.makeImage().map { (scale, $0, size) }
    }

    /// A transparent bitmap at `scale`, drawn into with a flipped AppKit context.
    private static func bitmap(size: CGSize, scale: CGFloat, draw: () -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: size.height * scale)
        ctx.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    // MARK: - Fade

    /// Fades in or out on the card spring; hidden once invisible.
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
}
