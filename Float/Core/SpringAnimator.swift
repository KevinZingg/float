import AppKit

/// Damped spring with mass 1, parameterised the SwiftUI/UIKit way.
struct Spring {
    let stiffness: CGFloat
    let damping: CGFloat

    init(dampingRatio: CGFloat = Settings.springDampingRatio, response: CGFloat = Settings.springResponse) {
        stiffness = pow(2 * .pi / response, 2)
        damping = 4 * .pi * dampingRatio / response
    }

    /// Reads the user's damping ratio each time, so the Settings slider applies live.
    static var standard: Spring { Spring() }
    static let rubberBand = Spring(dampingRatio: Settings.rubberBandDampingRatio, response: Settings.rubberBandResponse)

    /// One semi-implicit Euler step toward `target`. Returns the new value and velocity.
    func step(value x: CGFloat, velocity v: CGFloat, target: CGFloat, dt: CGFloat) -> (value: CGFloat, velocity: CGFloat) {
        let a = -stiffness * (x - target) - damping * v
        let nv = v + a * dt
        return (x + nv * dt, nv)
    }

    static func isSettled(value x: CGFloat, velocity v: CGFloat, target: CGFloat) -> Bool {
        abs(x - target) < Settings.springRestDistance && abs(v) < Settings.springRestSpeed
    }
}

/// Drives a view's frame (x, y, width, height) with a spring, one display-link tick at a time.
@MainActor
final class SpringAnimator: NSObject {
    private weak var view: NSView?
    private var link: CADisplayLink?
    private var spring = Spring.standard
    private var value: [CGFloat] = []
    private var velocity: [CGFloat] = []
    private var targetValues: [CGFloat] = []
    private var lastTime: CFTimeInterval = 0

    var isRunning: Bool { link != nil }
    /// Where the running animation is heading.
    var target: CGRect? { isRunning ? CGRect(x: targetValues[0], y: targetValues[1], width: targetValues[2], height: targetValues[3]) : nil }

    init(view: NSView) {
        self.view = view
    }

    /// Starts from the view's current frame, carrying `velocity` (pt/s) so a fling continues without a restart.
    func animate(to frame: CGRect, velocity v: CGVector = .zero, spring: Spring = .standard) {
        guard let view else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            stop()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Settings.reducedMotionDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                view.animator().frame = frame
            }
            return
        }
        let f = view.frame
        value = [f.minX, f.minY, f.width, f.height]
        velocity = [v.dx, v.dy, 0, 0]
        targetValues = [frame.minX, frame.minY, frame.width, frame.height]
        self.spring = spring
        lastTime = CACurrentMediaTime()
        if link == nil {
            let link = view.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        // Clamp long gaps (e.g. app was hidden), and substep for stability with stiff springs.
        var remaining = min(now - lastTime, 1.0 / 30)
        lastTime = now
        while remaining > 0 {
            let dt = min(remaining, 1.0 / 240)
            for i in value.indices {
                (value[i], velocity[i]) = spring.step(value: value[i], velocity: velocity[i], target: targetValues[i], dt: dt)
            }
            remaining -= dt
        }
        let settled = value.indices.allSatisfy {
            Spring.isSettled(value: value[$0], velocity: velocity[$0], target: targetValues[$0])
        }
        let v = settled ? targetValues : value
        view?.frame = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
        if settled { stop() }
    }
}
