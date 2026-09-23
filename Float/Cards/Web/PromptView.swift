import AppKit

/// Safari-style inline prompt at the top of a card: a message, optional text field and a few buttons.
/// Used for site permissions and JS alert/confirm/prompt. Requests queue up and show one at a time.
@MainActor
final class PromptView: NSVisualEffectView {
    struct Request {
        let message: String
        let buttons: [String]
        /// Button triggered by Return.
        let defaultIndex: Int
        /// Button reported if the card goes away before an answer (WebKit requires every handler to be called).
        let cancelIndex: Int
        var textDefault: String?
        /// Chosen button index, plus the text field's value when there is one.
        let completion: @MainActor (Int, String?) -> Void
    }

    private var queue: [Request] = []
    private let label = NSTextField(wrappingLabelWithString: "")
    private let field = NSTextField()
    private let buttonStack = NSStackView()

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = Settings.promptCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        isHidden = true

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.maximumNumberOfLines = 4
        field.font = .systemFont(ofSize: 12)
        field.controlSize = .small
        field.target = self
        field.action = #selector(returnPressed)
        buttonStack.spacing = 6

        let stack = NSStackView(views: [label, field, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
            label.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Pins the prompt to the top center of `host`.
    func install(in host: NSView) {
        translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: host.centerXAnchor),
            topAnchor.constraint(equalTo: host.topAnchor, constant: 12),
            widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, constant: -24),
            widthAnchor.constraint(lessThanOrEqualToConstant: Settings.promptMaxWidth),
        ])
    }

    func enqueue(_ request: Request) {
        queue.append(request)
        if queue.count == 1 { present(request) }
    }

    /// Answers everything still pending with its cancel button (used when the card closes).
    func cancelAll() {
        let pending = queue
        queue.removeAll()
        isHidden = true
        for r in pending { r.completion(r.cancelIndex, nil) }
    }

    private func present(_ r: Request) {
        label.stringValue = r.message
        field.isHidden = r.textDefault == nil
        field.stringValue = r.textDefault ?? ""
        buttonStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, title) in r.buttons.enumerated() {
            let b = NSButton(title: title, target: self, action: #selector(buttonClicked(_:)))
            b.controlSize = .small
            b.bezelStyle = .push
            b.tag = i
            if i == r.defaultIndex { b.keyEquivalent = "\r" }
            buttonStack.addArrangedSubview(b)
        }
        isHidden = false
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; animator().alphaValue = 1 }
        if !field.isHidden { window?.makeFirstResponder(field) }
    }

    /// Answers the visible request with button `index`.
    private func answer(_ index: Int) {
        guard let r = queue.first else { return }
        queue.removeFirst()
        let text = r.textDefault == nil ? nil : field.stringValue
        if let next = queue.first { present(next) } else { isHidden = true }
        r.completion(index, text)
    }

    @objc private func buttonClicked(_ sender: NSButton) { answer(sender.tag) }
    @objc private func returnPressed() { if let r = queue.first { answer(r.defaultIndex) } }

}
