import AppKit

@main
@MainActor
final class FloatApp: NSObject, NSApplicationDelegate {
    private static let delegate = FloatApp()

    private var window: CanvasWindow!
    private var manager: CardManager!

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        window = CanvasWindow(screen: screen)
        let canvas = CanvasView(frame: window.contentLayoutRect)
        window.contentView = canvas
        manager = CardManager(canvas: canvas)
        window.onMouseDown = { [weak self] hit in self?.manager.focus(containing: hit) }

        NSApp.mainMenu = buildMenu()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowGeometryChanged), name: name, object: window)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        manager.add(PlaceholderCard(), size: Settings.terminalSize)
        manager.add(PlaceholderCard(), size: Settings.previewSize)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    @objc private func windowGeometryChanged() { manager.clampAll() }

    @objc private func screenChanged() {
        if let screen = NSScreen.main { window.setFrame(screen.visibleFrame, display: true) }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Float", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Float", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Float")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: "Edit")

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        submenu.title = title
        item.submenu = submenu
        addItem(item)
    }
}

/// Temporary content to exercise drag/snap before real card types exist.
@MainActor
private final class PlaceholderCard: CardContent {
    let kind = CardKind.terminal
    let view = NSView()
    let title = "Placeholder"
    var onTitleChange: ((String) -> Void)?
    var onRequestClose: (() -> Void)?
    func close() {}
}
