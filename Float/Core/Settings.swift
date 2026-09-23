import AppKit

/// Single source of truth for layout and appearance constants.
enum Settings {
    static let padding: CGFloat = 16
    static let gap: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let cascadeOffset: CGFloat = 28

    static let chromeHeight: CGFloat = 28
    static let resizeZone: CGFloat = 6
    static let minCardSize = NSSize(width: 220, height: 140)

    static let shadowRadius: CGFloat = 14
    static let shadowOpacity: Float = 0.35
    static let shadowOffset = CGSize(width: 0, height: -4)

    // Drag lift
    static let liftScale: CGFloat = 1.02
    static let liftShadowRadius: CGFloat = 28
    static let liftShadowOpacity: Float = 0.5
    static let liftShadowOffset = CGSize(width: 0, height: -12)

    // Fling + spring (WWDC18 session 803)
    static let velocityWindow: TimeInterval = 0.08
    static let flingDecelerationRate: CGFloat = 0.998
    static let flingMinSpeed: CGFloat = 150
    static let springDampingRatio: CGFloat = 0.82
    static let springResponse: CGFloat = 0.4
    static let springRestDistance: CGFloat = 0.5
    static let springRestSpeed: CGFloat = 20
    static let rubberBandExponent: CGFloat = 0.7
    static let rubberBandDampingRatio: CGFloat = 0.6
    static let rubberBandResponse: CGFloat = 0.3
    static let reducedMotionDuration: TimeInterval = 0.15

    static let terminalSize = NSSize(width: 560, height: 360)
    static let previewSize = NSSize(width: 480, height: 300)

    static let terminalFontSize: CGFloat = 12
    static let terminalFontRange: ClosedRange<CGFloat> = 8...32

    static let defaultURL = "localhost:3000"
}
