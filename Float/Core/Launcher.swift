import AppKit

/// What Enter does in the launcher.
enum LaunchAction: Equatable {
    /// nil directory = the last directory.
    case terminal(directory: String?, command: String?)
    case preview(url: String)

    enum Mode { case terminal, preview }

    /// Pure parser: input (plus an optional forced mode from Tab / ⌘1 / ⌘2) → action.
    static func parse(_ input: String, mode: Mode? = nil) -> LaunchAction {
        let s = input.trimmingCharacters(in: .whitespaces)
        let isPath = s.hasPrefix("~") || s.hasPrefix("/")
        switch mode {
        case .preview:
            return .preview(url: s.isEmpty ? Settings.defaultURL : s)
        case .terminal:
            break
        case nil:
            if !isPath && URLInput.looksLikeURL(s) { return .preview(url: s) }
        }
        if s.isEmpty { return .terminal(directory: nil, command: nil) }
        if isPath { return .terminal(directory: (s as NSString).expandingTildeInPath, command: nil) }
        return .terminal(directory: nil, command: s)
    }

    var hint: String {
        switch self {
        case .terminal(nil, nil): "↩ New terminal in the last directory"
        case .terminal(let dir?, _): "↩ New terminal in \((dir as NSString).abbreviatingWithTildeInPath)"
        case .terminal(_, let cmd?): "↩ Run “\(cmd)” in a new terminal"
        case .preview(let url): "↩ Preview \(URLInput.url(from: url)?.absoluteString ?? url)"
        }
    }
}

/// Recently opened terminal directories, newest first.
enum RecentDirectories {
    private static let key = "recentDirectories"

    static var all: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func add(_ path: String) {
        let list = [path] + all.filter { $0 != path }
        UserDefaults.standard.set(Array(list.prefix(20)), forKey: key)
    }

    static func matching(_ input: String) -> [String] {
        let typed = (input as NSString).expandingTildeInPath
        return Array(all.filter { $0.hasPrefix(typed) }.prefix(5))
    }
}

/// ⌥Space quick launcher: a centered pill overlay inside the canvas.
@MainActor
final class LauncherView: PillView, NSTextFieldDelegate {
    var onLaunch: ((LaunchAction) -> Void)?
    var onDismiss: (() -> Void)?

    private let field = NSTextField()
    private let hintLabel = NSTextField(labelWithString: "")
    private let suggestionStack = NSStackView()
    private var mode: LaunchAction.Mode?
    private var suggestions: [String] = []
    private var selected: Int?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Settings.launcherWidth, height: 90))

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self

        suggestionStack.orientation = .vertical
        suggestionStack.alignment = .leading
        suggestionStack.spacing = 4

        let stack = NSStackView(views: [field, hintLabel, suggestionStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 14, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        applyTheme()
    }

    override func applyTheme() {
        super.applyTheme()
        // The launcher holds focus, so it wears the focus hairline, like a focused card.
        layer?.borderColor = Theme.current.focusHairline.cgColor
        field.font = Theme.mono(18)
        field.textColor = Theme.current.text
        field.placeholderAttributedString = NSAttributedString(string: "command, ~/path or localhost:3000", attributes: [
            .font: Theme.mono(18), .foregroundColor: Theme.faint,
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Shows the pill centered horizontally in the upper third of `bounds`.
    func show(in canvas: NSView, bounds: CGRect) {
        field.stringValue = ""
        mode = nil
        applyTheme()
        refresh()
        let origin = CGPoint(x: bounds.midX - frame.width / 2, y: bounds.minY + bounds.height * 0.28)
        setFrameOrigin(origin)
        canvas.addSubview(self)
        window?.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertionPointColor = Theme.current.accent
    }

    func dismiss() {
        guard superview != nil else { return }
        removeFromSuperview()
        onDismiss?()
    }

    private var action: LaunchAction {
        if let selected, suggestions.indices.contains(selected) {
            return .terminal(directory: suggestions[selected], command: nil)
        }
        return LaunchAction.parse(field.stringValue, mode: mode)
    }

    private func refresh() {
        let text = field.stringValue
        suggestions = (text.hasPrefix("~") || text.hasPrefix("/")) && mode != .preview ? RecentDirectories.matching(text) : []
        if let s = selected, !suggestions.indices.contains(s) { selected = nil }
        let t = Theme.current
        let other = if case .preview = action { "terminal" } else { "preview" }
        let hint = NSMutableAttributedString(string: action.hint, attributes: [.font: Theme.mono(11), .foregroundColor: t.accent])
        hint.append(NSAttributedString(string: "     "))
        hint.append(Theme.label("⇥ \(other)", color: Theme.faint))
        hintLabel.attributedStringValue = hint

        suggestionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, path) in suggestions.enumerated() {
            let label = NSTextField(labelWithString: (path as NSString).abbreviatingWithTildeInPath)
            label.font = Theme.mono(12, weight: i == selected ? .medium : .regular)
            label.textColor = i == selected ? t.accent : t.secondaryText
            suggestionStack.addArrangedSubview(label)
        }
        layoutSubtreeIfNeeded()
        let height = 16 + field.intrinsicContentSize.height + 8 + hintLabel.intrinsicContentSize.height + 14
            + (suggestions.isEmpty ? 0 : 8 + CGFloat(suggestions.count) * 20)
        setFrameSize(CGSize(width: Settings.launcherWidth, height: height))
    }

    // MARK: - Keys

    func controlTextDidChange(_ obj: Notification) { selected = nil; refresh() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            if case .preview = action { mode = .terminal } else { mode = .preview }
        case #selector(NSResponder.moveDown(_:)) where !suggestions.isEmpty:
            selected = min((selected ?? -1) + 1, suggestions.count - 1)
        case #selector(NSResponder.moveUp(_:)) where !suggestions.isEmpty:
            selected = (selected ?? 0) > 0 ? selected! - 1 : nil
        case #selector(NSResponder.insertNewline(_:)):
            let action = action
            dismiss()
            onLaunch?(action)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            return true
        default:
            return false
        }
        refresh()
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard superview != nil, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "1": mode = .terminal
        case "2": mode = .preview
        default: return super.performKeyEquivalent(with: event)
        }
        refresh()
        return true
    }
}
