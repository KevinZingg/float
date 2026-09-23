import AppKit

/// The one style for floating pills: toast, prompt/dialog and launcher. A raised Night fill with a hairline.
@MainActor
class PillView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme() {
        let t = Theme.current
        // Pills float over cards, so they sit a step above the Night ground and keep a soft shadow.
        layer?.backgroundColor = t.pillBackground.cgColor
        layer?.borderColor = t.pillBorder.cgColor
        layer?.borderWidth = t.borderWidth
        layer?.cornerRadius = t.pillRadius
        layer?.cornerCurve = .continuous
        layer?.shadowOpacity = t.pillShadowOpacity
        layer?.shadowRadius = t.pillShadowRadius
        layer?.masksToBounds = false
    }

    /// A borderless text button in the pill style: mono, uppercase, tracked; the default one in the accent.
    static func button(_ title: String, isDefault: Bool, target: AnyObject, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.isBordered = false
        b.attributedTitle = Theme.label(title, color: isDefault ? Theme.current.accent : Theme.current.secondaryText)
        return b
    }
}
