import Foundation

/// Pure geometry: keep cards inside the padded canvas and find docking spots.
enum Snapping {
    /// The usable area: the canvas inset by the padding.
    static func area(_ bounds: CGRect, padding: CGFloat = Settings.padding) -> CGRect {
        bounds.insetBy(dx: padding, dy: padding)
    }

    /// Moves (and if needed shrinks) a rect so it sits fully inside the padded area.
    static func clamp(_ rect: CGRect, in bounds: CGRect, padding: CGFloat = Settings.padding) -> CGRect {
        let a = area(bounds, padding: padding)
        var r = rect
        r.size.width = min(r.width, a.width)
        r.size.height = min(r.height, a.height)
        r.origin.x = min(max(r.minX, a.minX), a.maxX - r.width)
        r.origin.y = min(max(r.minY, a.minY), a.maxY - r.height)
        return r
    }

    /// The 8 docking frames for a card of `size`: 4 corners + 4 edge midpoints of the padded area.
    static func anchors(for size: CGSize, in bounds: CGRect, padding: CGFloat = Settings.padding) -> [CGRect] {
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

    /// While dragging past the edge, the overshoot is damped to sign(d)·|d|^exponent.
    static func rubberBand(_ rect: CGRect, in bounds: CGRect, exponent: CGFloat = Settings.rubberBandExponent) -> CGRect {
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
