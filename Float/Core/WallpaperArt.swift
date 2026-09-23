import AppKit
import CoreImage

/// Processed copies of the desktop picture for the empty state (pixel mosaic, character halftone, dither),
/// cropped to the canvas exactly as macOS aspect-fills the wallpaper. Reading the picture file needs no
/// screen-recording permission. Rendered once and cached until the wallpaper, its file or the canvas changes.
@MainActor
enum WallpaperArt {
    enum Style { case pixel, ascii, dither }

    struct Result {
        let image: CGImage
        /// Draw without smoothing (the dither is stored at one pixel per dot).
        let nearest: Bool
    }

    private struct Key: Equatable {
        let url: URL, modified: Date?, canvas: CGRect, scale: CGFloat, style: Style
    }

    private static var cache: (key: Key, result: Result?)?
    private static let context = CIContext()

    /// nil when there is no readable picture or it is a flat colour; callers fall back to the plain dim.
    static func render(_ style: Style, canvas: CGRect, screen: NSScreen) -> Result? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = Key(url: url, modified: modified, canvas: canvas, scale: screen.backingScaleFactor, style: style)
        if let cache, cache.key == key { return cache.result }
        let result = make(style, url: url, canvas: canvas, screen: screen)
        cache = (key, result)
        return result
    }

    private static func make(_ style: Style, url: URL, canvas: CGRect, screen: NSScreen) -> Result? {
        guard let source = CIImage(contentsOf: url) else { return nil }
        let s = screen.backingScaleFactor
        let screenPx = CGSize(width: screen.frame.width * s, height: screen.frame.height * s)
        // Aspect-fill onto the whole screen, then take the part under the canvas (both bottom-left origin).
        let k = max(screenPx.width / source.extent.width, screenPx.height / source.extent.height)
        var image = source.transformed(by: CGAffineTransform(scaleX: k, y: k))
        image = image.transformed(by: CGAffineTransform(
            translationX: (screenPx.width - image.extent.width) / 2 - image.extent.minX,
            y: (screenPx.height - image.extent.height) / 2 - image.extent.minY))
        let crop = CGRect(x: (canvas.minX - screen.frame.minX) * s, y: (canvas.minY - screen.frame.minY) * s,
                          width: canvas.width * s, height: canvas.height * s)
        if style == .pixel {
            // Blocks anchored to the screen origin, so the mosaic stays put as the canvas moves.
            image = image.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: Config.pixelBlock * s, kCIInputCenterKey: CIVector(x: 0, y: 0),
            ])
        }
        image = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        guard let full = context.createCGImage(image, from: image.extent), !isFlat(full) else { return nil }

        switch style {
        case .pixel:
            return Result(image: full, nearest: false)
        case .ascii:
            return asciiHalftone(full, canvas: canvas.size, scale: s).map { Result(image: $0, nearest: false) }
        case .dither:
            return bayerDither(full, canvas: canvas.size).map { Result(image: $0, nearest: true) }
        }
    }

    // MARK: - Styles

    /// The identity's character halftone (" .:+x#@", lightest first): as in the Helvetia source, darker areas of
    /// the picture take denser glyphs, so a light wallpaper leaves the Night ground mostly empty.
    private static func asciiHalftone(_ image: CGImage, canvas: CGSize, scale: CGFloat) -> CGImage? {
        let cell = Config.asciiCell
        let cols = Int(canvas.width / (cell * 0.6)), rows = Int(canvas.height / cell)
        let lum = luminance(image, cols: cols, rows: rows)
        let ramp = Array(" .:+x#@")
        let w = Int(canvas.width * scale), h = Int(canvas.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(Theme.night.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.mono(cell), .foregroundColor: Theme.sageInk.withAlphaComponent(Config.asciiAlpha),
        ]
        // One string per row keeps it to a few dozen draw calls.
        for r in 0..<rows {
            let line = String((0..<cols).map { c in ramp[min(ramp.count - 1, (255 - Int(lum[r * cols + c])) * ramp.count / 256)] })
            (line as NSString).draw(at: CGPoint(x: 0, y: canvas.height - CGFloat(r + 1) * cell), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// 1-bit ordered (Bayer 8x8) dither as a Night / sage duotone, one image pixel per dot; darker picture, more ink.
    private static func bayerDither(_ image: CGImage, canvas: CGSize) -> CGImage? {
        let cols = Int(canvas.width / Config.ditherDot), rows = Int(canvas.height / Config.ditherDot)
        let lum = luminance(image, cols: cols, rows: rows)
        let bayer: [Int] = [0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, 12, 44, 4, 36, 14, 46, 6, 38,
                            60, 28, 52, 20, 62, 30, 54, 22, 3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25,
                            15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29, 53, 21]
        let on = Theme.night.blended(withFraction: Config.ditherInk, of: Theme.sageInk)!.usingColorSpace(.sRGB)!
        let off = Theme.night.usingColorSpace(.sRGB)!
        func rgba(_ c: NSColor) -> [UInt8] {
            [UInt8(c.redComponent * 255), UInt8(c.greenComponent * 255), UInt8(c.blueComponent * 255), 255]
        }
        let onPx = rgba(on), offPx = rgba(off)
        var pixels = [UInt8](repeating: 0, count: cols * rows * 4)
        for r in 0..<rows {
            for c in 0..<cols {
                let threshold = (bayer[(r % 8) * 8 + c % 8] * 4 + 2)
                let px = 255 - Int(lum[r * cols + c]) > threshold ? onPx : offPx
                pixels.replaceSubrange((r * cols + c) * 4..<(r * cols + c) * 4 + 4, with: px)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: cols, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: cols * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: - Helpers

    /// Average luminance per cell, row 0 at the top.
    private static func luminance(_ image: CGImage, cols: Int, rows: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: cols * rows)
        out.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: cols,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        }
        return out
    }

    /// Mean luminance of the desktop picture (0…1), for choosing an ink that reads on it. Cached per file.
    static func brightness(screen: NSScreen) -> CGFloat? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let b = brightnessCache, b.url == url, b.modified == modified { return b.value }
        guard let ci = CIImage(contentsOf: url), let cg = context.createCGImage(ci, from: ci.extent) else { return nil }
        let lum = luminance(cg, cols: 32, rows: 20)
        let value = CGFloat(lum.map(Int.init).reduce(0, +)) / CGFloat(lum.count * 255)
        brightnessCache = (url, modified, value)
        return value
    }

    private static var brightnessCache: (url: URL, modified: Date?, value: CGFloat)?

    /// A solid-colour desktop has nothing to render.
    private static func isFlat(_ image: CGImage) -> Bool {
        let lum = luminance(image, cols: 32, rows: 20).map(Double.init)
        let mean = lum.reduce(0, +) / Double(lum.count)
        let variance = lum.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lum.count)
        return variance < 9
    }
}
