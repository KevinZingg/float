import AppKit

/// Safari-style inline prompt at the top of a card: a message, optional text field and a few buttons.
/// Used for site permissions and JS alert/confirm/prompt. Requests queue up and show one at a time.
@MainActor
final class PromptView: PillView {
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
        isHidden = true

        label.maximumNumberOfLines = 6
        field.font = Theme.mono(12)
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.target = self
        field.action = #selector(returnPressed)
        buttonStack.spacing = 16

        let stack = NSStackView(views: [label, field, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 10, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            label.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -32),
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
            widthAnchor.constraint(lessThanOrEqualToConstant: Config.promptMaxWidth),
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
        let t = Theme.current
        applyTheme()
        label.attributedStringValue = NSAttributedString(string: r.message, attributes: [
            .font: Theme.mono(11.5), .foregroundColor: t.text,
        ])
        field.isHidden = r.textDefault == nil
        field.stringValue = r.textDefault ?? ""
        field.textColor = t.text
        field.backgroundColor = t.fieldBackground
        buttonStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, title) in r.buttons.enumerated() {
            let b = PillView.button(title, isDefault: i == r.defaultIndex, target: self, action: #selector(buttonClicked(_:)))
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
