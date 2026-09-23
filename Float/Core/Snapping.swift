import Foundation

/// Pure geometry: keep cards inside the padded canvas and find docking spots.
enum Snapping {
    /// The usable area: the canvas inset by the padding.
    static func area(_ bounds: CGRect, padding: CGFloat = Config.padding) -> CGRect {
        bounds.insetBy(dx: padding, dy: padding)
    }

    /// Moves (and if needed shrinks) a rect so it sits fully inside the padded area.
    static func clamp(_ rect: CGRect, in bounds: CGRect, padding: CGFloat = Config.padding) -> CGRect {
        let a = area(bounds, padding: padding)
        var r = rect
        r.size.width = min(r.width, a.width)
        r.size.height = min(r.height, a.height)
        r.origin.x = min(max(r.minX, a.minX), a.maxX - r.width)
        r.origin.y = min(max(r.minY, a.minY), a.maxY - r.height)
        return r
    }

    /// The 8 docking frames for a card of `size`: 4 corners + 4 edge midpoints of the padded area.
    static func anchors(for size: CGSize, in bounds: CGRect, padding: CGFloat = Config.padding) -> [CGRect] {
        let a = area(bounds, padding: padding)
        let w = min(size.width, a.width), h = min(size.height, a.height)
        let xs = [a.minX, a.midX - w / 2, a.maxX - w]
        let ys = [a.minY, a.midY - h / 2, a.maxY - h]
        var result: [CGRect] = []
        for (i, x) in xs.enumerated() {
            for (j, y) in ys.enumerated() where !(i == 1 && j == 1) {
                result.append(CGRect(x: x, y: y, width: w, height: h))
            }
        }
        return result
    }

    /// The anchor whose center is closest to `point`.
    static func nearestAnchor(to point: CGPoint, size: CGSize, in bounds: CGRect) -> CGRect {
        anchors(for: size, in: bounds).min { distance($0.center, point) < distance($1.center, point) }!
    }

    /// First docking anchor not overlapping any occupied frame; otherwise the center.
    static func freeSpot(for size: CGSize, avoiding occupied: [CGRect], in bounds: CGRect) -> CGRect {
        let spot = anchors(for: size, in: bounds).first { a in
            !occupied.contains { $0.insetBy(dx: -Config.gap / 2, dy: -Config.gap / 2).intersects(a) }
        }
        return spot ?? clamp(CGRect(origin: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), size: size), in: bounds)
    }

    /// Spot for a card opened from `source`: to its right if it fits, else left, else below, preferring
    /// spots no other card covers; if all are taken, cascade from the first one. Clamped to the canvas.
    static func besideSpot(for size: CGSize, next source: CGRect, avoiding occupied: [CGRect], in bounds: CGRect) -> CGRect {
        let a = area(bounds), g = Config.gap
        let candidates = [
            CGRect(x: source.maxX + g, y: source.minY, width: size.width, height: size.height),
            CGRect(x: source.minX - g - size.width, y: source.minY, width: size.width, height: size.height),
            CGRect(x: source.minX, y: source.maxY + g, width: size.width, height: size.height),
        ].filter { a.contains($0) }
        func free(_ r: CGRect) -> Bool { !occupied.contains { $0.intersects(r) } }
        if let spot = candidates.first(where: free) { return spot }
        var spot = clamp(candidates.first ?? CGRect(origin: CGPoint(x: source.maxX + g, y: source.minY), size: size), in: bounds)
        for _ in 0..<8 where !free(spot) {
            spot = clamp(spot.offsetBy(dx: Config.cascadeOffset, dy: Config.cascadeOffset), in: bounds)
        }
        return spot
    }

    /// Midpoint of the side of `source` that faces `target`, where a spawned card grows from.
    static func edgePoint(of source: CGRect, toward target: CGRect) -> CGPoint {
        if target.minX >= source.maxX { return CGPoint(x: source.maxX, y: source.midY) }
        if target.maxX <= source.minX { return CGPoint(x: source.minX, y: source.midY) }
        return CGPoint(x: source.midX, y: target.minY >= source.midY ? source.maxY : source.minY)
    }

    /// While dragging past the edge, the overshoot is damped to sign(d)·|d|^exponent.
    static func rubberBand(_ rect: CGRect, in bounds: CGRect, exponent: CGFloat = Config.rubberBandExponent) -> CGRect {
        let clamped = clamp(rect, in: bounds)
        func band(_ d: CGFloat) -> CGFloat { d == 0 ? 0 : (d < 0 ? -1 : 1) * pow(abs(d), exponent) }
        return clamped.offsetBy(dx: band(rect.minX - clamped.minX), dy: band(rect.minY - clamped.minY))
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

// MARK: - Arrange All

extension Snapping {
    /// Terminals in a grid on the left, previews stacked on the right; everything fits in `bounds`.
    /// `previewAspects` holds each preview's locked content aspect (nil = default preview shape).
    static func arrange(
        terminals: Int, previewAspects: [CGFloat?], in bounds: CGRect,
        gap: CGFloat = Config.gap, chrome: CGFloat = Theme.chromeHeight
    ) -> (terminals: [CGRect], previews: [CGRect]) {
        let a = area(bounds)
        let previewColumn: CGFloat
        if previewAspects.isEmpty {
            previewColumn = 0
        } else if terminals == 0 {
            previewColumn = min(a.width, Config.previewSize.width * 1.5)
        } else {
            previewColumn = min(max(Config.previewSize.width, a.width * 0.3), a.width * 0.45)
        }

        // Previews: right-aligned column, each at most an equal share of the height.
        var previews: [CGRect] = []
        if !previewAspects.isEmpty {
            let n = CGFloat(previewAspects.count)
            let maxH = (a.height - gap * (n - 1)) / n
            let defaultAspect = Config.previewSize.width / (Config.previewSize.height - chrome)
            var y = a.minY
            for aspect in previewAspects {
                let ratio = aspect ?? defaultAspect
                var w = previewColumn
                var h = w / ratio + chrome
                if h > maxH { h = maxH; w = (h - chrome) * ratio }
                previews.append(CGRect(x: a.maxX - w, y: y, width: w, height: h))
                y += h + gap
            }
        }

        // Terminals: grid in what's left, cells shaped like the default terminal but never larger than 1.4x it.
        var result: [CGRect] = []
        if terminals > 0 {
            let rect = CGRect(x: a.minX, y: a.minY, width: a.width - (previewColumn > 0 ? previewColumn + gap : 0), height: a.height)
            let target = Config.terminalSize.width / Config.terminalSize.height
            let cols = (1...terminals).min { c1, c2 in
                abs(log(cellAspect(terminals, c1, rect, gap) / target)) < abs(log(cellAspect(terminals, c2, rect, gap) / target))
            }!
            let rows = (terminals + cols - 1) / cols
            let cellW = min((rect.width - gap * CGFloat(cols - 1)) / CGFloat(cols), Config.terminalSize.width * 1.4)
            let cellH = min((rect.height - gap * CGFloat(rows - 1)) / CGFloat(rows), Config.terminalSize.height * 1.4)
            for i in 0..<terminals {
                let col = CGFloat(i % cols), row = CGFloat(i / cols)
                result.append(CGRect(x: rect.minX + col * (cellW + gap), y: rect.minY + row * (cellH + gap), width: cellW, height: cellH))
            }
        }
        return (result, previews)
    }

    private static func cellAspect(_ n: Int, _ cols: Int, _ rect: CGRect, _ gap: CGFloat) -> CGFloat {
        let rows = (n + cols - 1) / cols
        let w = (rect.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let h = (rect.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return max(w, 1) / max(h, 1)
    }
}
