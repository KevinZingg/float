import AppKit

/// Small pill at the bottom of a card for transient status ("Downloaded x · Show in Finder").
@MainActor
final class ToastView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    private var onClick: (() -> Void)?
    private var hideTimer: Timer?

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.masksToBounds = true
        alphaValue = 0
        isHidden = true

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Settings.toastHeight),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Pins the pill to the bottom center of `host`.
    func install(in host: NSView) {
        translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: host.centerXAnchor),
            bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -12),
            widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, constant: -24),
        ])
    }

    /// `sticky` keeps it up (e.g. while a download is running); otherwise it hides after a few seconds.
    func show(_ text: String, sticky: Bool = false, onClick: (() -> Void)? = nil) {
        label.stringValue = text
        self.onClick = onClick
        layer?.cornerRadius = Settings.toastHeight / 2
        isHidden = false
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; animator().alphaValue = 1 }
        hideTimer?.invalidate()
        guard !sticky else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: Settings.toastDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; animator().alphaValue = 0 }) { [weak self] in
            MainActor.assumeIsolated { self?.isHidden = true }
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
        hide()
    }

    override func resetCursorRects() {
        if onClick != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }
}
