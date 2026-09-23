import Foundation

/// Release velocity from recent drag samples (points per second).
struct VelocityTracker {
    private var samples: [(time: TimeInterval, point: CGPoint)] = []

    mutating func reset() { samples.removeAll() }

    mutating func add(_ point: CGPoint, at time: TimeInterval) {
        samples.append((time, point))
        samples.removeAll { time - $0.time > Settings.velocityWindow }
    }

    /// Velocity over the samples still inside the window at `now`. Zero if the pointer paused before release.
    func velocity(at now: TimeInterval) -> CGVector {
        let recent = samples.filter { now - $0.time <= Settings.velocityWindow }
        guard let first = recent.first, let last = recent.last, last.time > first.time else { return .zero }
        let dt = last.time - first.time
        return CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
    }
}

/// PiP-style momentum targeting (WWDC18 "Designing Fluid Interfaces").
enum Fling {
    /// Distance a decelerating scroll-view-like body travels from velocity `v` (pt/s).
    static func project(_ v: CGFloat, decelerationRate r: CGFloat = Settings.flingDecelerationRate) -> CGFloat {
        (v / 1000) * r / (1 - r)
    }

    static func speed(_ v: CGVector) -> CGFloat { hypot(v.dx, v.dy) }

    static func isFling(_ v: CGVector) -> Bool { speed(v) >= Settings.flingMinSpeed }

    /// Where a card released at `frame` with `velocity` should come to rest.
    static func target(for frame: CGRect, velocity: CGVector, in bounds: CGRect) -> CGRect {
        guard isFling(velocity) else { return Snapping.clamp(frame, in: bounds) }
        let projected = CGPoint(x: frame.midX + project(velocity.dx), y: frame.midY + project(velocity.dy))
        return Snapping.nearestAnchor(to: projected, size: frame.size, in: bounds)
    }
}
