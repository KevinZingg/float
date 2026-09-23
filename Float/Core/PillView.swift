import AppKit

/// The one style for floating pills: toast, prompt/dialog and launcher.
/// Theme A: a solid Night fill with a hairline. Theme B: vibrancy material. Subclasses add content on top.
@MainActor
class PillView: NSView {
    private let material = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        material.material = .hudWindow
        material.blendingMode = .withinWindow
        material.state = .active
        material.autoresizingMask = [.width, .height]
        material.wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        material.frame = bounds
        addSubview(material, positioned: .below, relativeTo: nil)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme() {
        let t = Theme.current
        material.isHidden = !t.usesVibrancy
        // Pills float over cards, so they sit a step above the Night ground and keep a soft shadow.
        layer?.backgroundColor = t.usesVibrancy ? NSColor.clear.cgColor : t.pillBackground.cgColor
        layer?.borderColor = t.pillBorder.cgColor
        layer?.borderWidth = t.borderWidth
        layer?.cornerRadius = t.pillRadius
        layer?.cornerCurve = .continuous
        layer?.shadowOpacity = t.pillShadowOpacity
        layer?.shadowRadius = t.pillShadowRadius
        // The shadow needs an unclipped layer; the material clips itself instead.
        layer?.masksToBounds = false
        material.layer?.cornerRadius = t.pillRadius
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
    }

    /// A borderless text button in the pill style: mono, uppercase, tracked; the default one in the accent.
    static func button(_ title: String, isDefault: Bool, target: AnyObject, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.isBordered = false
        b.attributedTitle = Theme.label(title, color: isDefault ? Theme.current.accent : Theme.current.secondaryText)
        return b
    }
}
