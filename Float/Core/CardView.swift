import AppKit

/// Rounded, shadowed container for one card: chrome strip, drag to move, edges to resize.
@MainActor
final class CardView: NSView {
    let content: CardContent
    /// Locked content aspect ratio (width / height of the area below the chrome).
    var aspect: CGFloat?
    var isFocused = false { didSet { updateBorder() } }

    var onFocus: ((CardView) -> Void)?
    /// Drag released, with the release velocity in canvas points per second.
    var onMoveEnded: ((CardView, CGVector) -> Void)?
    var onResizeEnded: ((CardView) -> Void)?
    var onAspectPicked: ((CardView, CGFloat?) -> Void)?
    var onSizePicked: ((CardView, SizePreset) -> Void)?
    var onCloseRequested: ((CardView) -> Void)?

    private let container = FlippedView()
    private let chrome = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let presetButton = NSButton()

    private enum Gesture { case move, resize(Edges) }
    private var gesture: Gesture?
    private var startFrame = CGRect.zero
    private var startMouse = CGPoint.zero
    private var tracker = VelocityTracker()
    private(set) lazy var mover = SpringAnimator(view: self)

    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1)
        static let right = Edges(rawValue: 2)
        static let top = Edges(rawValue: 4)
        static let bottom = Edges(rawValue: 8)
    }

    init(content: CardContent, frame: CGRect) {
        self.content = content
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Settings.shadowOpacity
        layer?.shadowRadius = Settings.shadowRadius
        layer?.shadowOffset = Settings.shadowOffset

        container.wantsLayer = true
        container.layer?.cornerRadius = Settings.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = Settings.cardBackground.cgColor
        container.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        container.layer?.borderWidth = 1
        addSubview(container)

        chrome.wantsLayer = true
        chrome.layer?.backgroundColor = Settings.chromeBackground.cgColor
        container.addSubview(chrome)

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.stringValue = content.title
        chrome.addSubview(titleLabel)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        chrome.addSubview(closeButton)

        presetButton.image = NSImage(systemSymbolName: "aspectratio", accessibilityDescription: "Size")
        presetButton.isBordered = false
        presetButton.contentTintColor = .secondaryLabelColor
        presetButton.target = self
        presetButton.action = #selector(showPresets)
        chrome.addSubview(presetButton)

        if let accessory = content.accessory { chrome.addSubview(accessory) }
        container.addSubview(content.view)

        content.onTitleChange = { [weak self] title in self?.titleLabel.stringValue = title }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        setHovered(false, animated: false)
    }

    // MARK: - Hover

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    /// Chrome buttons stay quiet until the pointer is over the card.
    private func setHovered(_ hovered: Bool, animated: Bool = true) {
        let alpha: CGFloat = hovered ? 1 : Settings.idleChromeAlpha
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.15 : 0
            for button in [closeButton, presetButton] { button.animator().alphaValue = alpha }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        container.frame = bounds
        layer?.shadowPath = CGPath(
            roundedRect: bounds, cornerWidth: Settings.cornerRadius, cornerHeight: Settings.cornerRadius, transform: nil)

        let h = Settings.chromeHeight
        chrome.frame = CGRect(x: 0, y: 0, width: bounds.width, height: h)
        let button: CGFloat = 22
        closeButton.frame = CGRect(x: bounds.width - button - 6, y: (h - button) / 2, width: button, height: button)
        presetButton.frame = closeButton.frame.offsetBy(dx: -button, dy: 0)
        let trailing = presetButton.frame.minX - 4

        if let accessory = content.accessory {
            titleLabel.isHidden = true
            accessory.frame = CGRect(x: 8, y: 0, width: max(0, trailing - 8), height: h)
        } else {
            titleLabel.sizeToFit()
            let labelH = titleLabel.frame.height
            titleLabel.frame = CGRect(x: 12, y: (h - labelH) / 2, width: max(0, trailing - 12), height: labelH)
        }
        content.view.frame = CGRect(x: 0, y: h, width: bounds.width, height: max(0, bounds.height - h))
    }

    private func updateBorder() {
        container.layer?.borderColor = isFocused
            ? NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
            : NSColor(white: 1, alpha: 0.08).cgColor
    }

    @objc private func closeClicked() { onCloseRequested?(self) }

    // MARK: - Presets

    @objc private func showPresets() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Aspect", action: nil, keyEquivalent: "").isEnabled = false
        for preset in AspectPreset.allCases {
            let item = menu.addItem(withTitle: preset.rawValue, action: #selector(aspectPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            item.state = preset.ratio == aspect ? .on : .off
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Size", action: nil, keyEquivalent: "").isEnabled = false
        for preset in SizePreset.allCases {
            let item = menu.addItem(withTitle: preset.rawValue, action: #selector(sizePicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
        }
        menu.popUp(positioning: nil, at: CGPoint(x: presetButton.frame.minX, y: presetButton.frame.maxY), in: chrome)
    }

    @objc private func aspectPicked(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let preset = AspectPreset(rawValue: raw) else { return }
        onAspectPicked?(self, preset.ratio)
    }

    @objc private func sizePicked(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let preset = SizePreset(rawValue: raw) else { return }
        onSizePicked?(self, preset)
    }

    // MARK: - Hit testing

    private func edges(at p: CGPoint) -> Edges {
        let z = Settings.resizeZone
        var e: Edges = []
        if p.x < z { e.insert(.left) }
        if p.x > bounds.width - z { e.insert(.right) }
        if p.y < z { e.insert(.top) }
        if p.y > bounds.height - z { e.insert(.bottom) }
        return e
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        let local = convert(point, from: superview)
        let commandDrag = NSApp.currentEvent?.type == .leftMouseDown
            && NSEvent.modifierFlags.contains(.command)
        let onChrome = hit === chrome || hit === titleLabel || hit === container || hit === content.accessory
        if !edges(at: local).isEmpty || commandDrag || onChrome {
            return self
        }
        return hit
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Move / resize

    override func mouseDown(with event: NSEvent) {
        mover.stop()
        let local = convert(event.locationInWindow, from: nil)
        let e = edges(at: local)
        gesture = e.isEmpty ? .move : .resize(e)
        startFrame = frame
        startMouse = superview?.convert(event.locationInWindow, from: nil) ?? .zero
        tracker.reset()
        tracker.add(startMouse, at: event.timestamp)
        if case .move = gesture { setLifted(true) }
        onFocus?(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let gesture, let superview else { return }
        let p = superview.convert(event.locationInWindow, from: nil)
        let dx = p.x - startMouse.x, dy = p.y - startMouse.y
        switch gesture {
        case .move:
            tracker.add(p, at: event.timestamp)
            let bounds = (superview as? CanvasView)?.layoutBounds ?? superview.bounds
            frame = Snapping.rubberBand(startFrame.offsetBy(dx: dx, dy: dy), in: bounds)
        case .resize(let e):
            frame = resized(edges: e, dx: dx, dy: dy)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let ended = gesture else { return }
        gesture = nil
        switch ended {
        case .move:
            setLifted(false)
            onMoveEnded?(self, tracker.velocity(at: event.timestamp))
        case .resize:
            onResizeEnded?(self)
        }
    }

    // MARK: - Lift

    /// Scales the card up slightly and deepens its shadow while it is being dragged.
    private func setLifted(_ lifted: Bool) {
        guard let layer else { return }
        let scale = lifted ? Settings.liftScale : 1
        // AppKit-backed layers anchor at (0,0), so scale around the center explicitly.
        var t = CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        t = CATransform3DTranslate(t, -bounds.midX, -bounds.midY, 0)
        let values: [(String, Any)] = [
            ("transform", NSValue(caTransform3D: t)),
            ("shadowRadius", lifted ? Settings.liftShadowRadius : Settings.shadowRadius),
            ("shadowOpacity", lifted ? Settings.liftShadowOpacity : Settings.shadowOpacity),
            ("shadowOffset", NSValue(size: lifted ? Settings.liftShadowOffset : Settings.shadowOffset)),
        ]
        for (key, value) in values {
            let anim = CASpringAnimation(perceptualDuration: 0.3, bounce: lifted ? 0 : 0.25)
            anim.keyPath = key
            anim.fromValue = layer.presentation()?.value(forKeyPath: key) ?? layer.value(forKeyPath: key)
            anim.toValue = value
            layer.add(anim, forKey: key)
            layer.setValue(value, forKeyPath: key)
        }
    }

    private func resized(edges e: Edges, dx: CGFloat, dy: CGFloat) -> CGRect {
        let min = Settings.minCardSize
        var w = startFrame.width, h = startFrame.height
        if e.contains(.left) { w -= dx }
        if e.contains(.right) { w += dx }
        if e.contains(.top) { h -= dy }
        if e.contains(.bottom) { h += dy }
        w = max(w, min.width)
        h = max(h, min.height)

        if let aspect {
            let chromeH = Settings.chromeHeight
            if e.isDisjoint(with: [.left, .right]) {
                w = max((h - chromeH) * aspect, min.width)
            }
            h = w / aspect + chromeH
        }

        let x = e.contains(.left) ? startFrame.maxX - w : startFrame.minX
        let y = e.contains(.top) ? startFrame.maxY - h : startFrame.minY
        return CGRect(x: x, y: y, width: w, height: h)
    }

    override func resetCursorRects() {
        let z = Settings.resizeZone
        let b = bounds
        addCursorRect(CGRect(x: 0, y: z, width: z, height: b.height - 2 * z), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: b.width - z, y: z, width: z, height: b.height - 2 * z), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: z, y: 0, width: b.width - 2 * z, height: z), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: z, y: b.height - z, width: b.width - 2 * z, height: z), cursor: .resizeUpDown)
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: b.width - z, y: 0),
                       CGPoint(x: 0, y: b.height - z), CGPoint(x: b.width - z, y: b.height - z)] {
            addCursorRect(CGRect(origin: corner, size: CGSize(width: z, height: z)), cursor: .crosshair)
        }
    }
}

/// Top-left origin, so chrome/content layout matches the card's own coordinates.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
