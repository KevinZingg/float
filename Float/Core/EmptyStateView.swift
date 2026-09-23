import AppKit

/// Shown when the canvas has no cards: the Helvetia character halftone (mogen identity § 07), very faint,
/// with the launcher shortcut beneath. Click-inert; everything around it stays transparent.
@MainActor
final class EmptyStateView: NSView {
    private static let lines: [String] = {
        guard let url = Bundle.main.url(forResource: "helvetia", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.hasPrefix("#") }
    }()

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let rows = Self.lines.filter { !$0.isEmpty }
        guard !rows.isEmpty else { return }
        // The ink follows the system appearance, as a guess at the wallpaper: Night on light, ink on dark.
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let inkColor = dark ? Theme.ink : Theme.night

        // Plex Mono advances 0.6 em, the grid's aspect, so one line per point size keeps the cells square to the source.
        let size = min(Settings.emptyStateMaxGlyph, bounds.height * 0.6 / CGFloat(rows.count))
        let font = Theme.mono(size)
        let width = CGFloat(rows[0].count) * size * 0.6
        let label = Theme.label("⌥ space", color: inkColor.withAlphaComponent(Settings.emptyStateLabelAlpha), size: 11)
        let labelSize = label.size()
        let total = CGFloat(rows.count) * size + 28 + labelSize.height
        var y = (bounds.height - total) / 2
        let x = (bounds.width - width) / 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: inkColor.withAlphaComponent(Settings.emptyStateAlpha),
        ]
        for row in rows {
            (row as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            y += size
        }
        label.draw(at: CGPoint(x: (bounds.width - labelSize.width) / 2, y: y + 28))
    }
}
