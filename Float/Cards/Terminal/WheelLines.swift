import Foundation

/// Turns scroll deltas into whole lines, carrying the remainder so slow trackpad drags still add up.
struct WheelLines {
    var pointsPerLine: CGFloat
    var maxLinesPerEvent: Int
    private var remainder: CGFloat = 0

    init(pointsPerLine: CGFloat, maxLinesPerEvent: Int) {
        self.pointsPerLine = pointsPerLine
        self.maxLinesPerEvent = maxLinesPerEvent
    }

    mutating func reset() { remainder = 0 }

    /// Positive = up (towards older content), matching NSEvent's scrollingDeltaY.
    /// Precise deltas are points; a mouse wheel's are already lines.
    mutating func lines(delta: CGFloat, precise: Bool) -> Int {
        guard precise else {
            let n = Int(delta.rounded(.awayFromZero))
            return max(-maxLinesPerEvent, min(maxLinesPerEvent, n))
        }
        remainder += delta
        let n = Int((remainder / pointsPerLine).rounded(.towardZero))
        remainder -= CGFloat(n) * pointsPerLine
        return max(-maxLinesPerEvent, min(maxLinesPerEvent, n))
    }

    /// Arrow key presses for `lines`, the way terminals translate the wheel on the alternate screen (DECSET 1007).
    static func arrowKeys(lines: Int, applicationCursor: Bool) -> [UInt8] {
        guard lines != 0 else { return [] }
        let key = Array((applicationCursor ? "\u{1b}O" : "\u{1b}[").utf8) + [UInt8(ascii: lines > 0 ? "A" : "B")]
        return Array(repeating: key, count: abs(lines)).flatMap { $0 }
    }
}
