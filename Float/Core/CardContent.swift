import AppKit

enum CardKind { case terminal, web }

/// What a card hosts. Add a new card type by conforming to this.
@MainActor
protocol CardContent: AnyObject {
    var kind: CardKind { get }
    var view: NSView { get }
    var title: String { get }
    /// Optional controls shown in the chrome strip next to the title.
    var accessory: NSView? { get }
    var onTitleChange: ((String) -> Void)? { get set }
    /// Called when the content wants its card removed (e.g. the shell exited).
    var onRequestClose: (() -> Void)? { get set }

    func focus()
    /// Returns false if the user cancelled.
    func confirmClose() -> Bool
    func close()
    func zoom(by step: Int)
    func reload()
}

extension CardContent {
    var accessory: NSView? { nil }
    func focus() { view.window?.makeFirstResponder(view) }
    func confirmClose() -> Bool { true }
    func zoom(by step: Int) {}
    func reload() {}
}
