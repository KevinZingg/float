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
        registerHotkeys()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowGeometryChanged), name: name, object: window)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        newTerminal()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func windowGeometryChanged() { manager.clampAll() }

    @objc private func screenChanged() {
        if let screen = NSScreen.main { window.setFrame(screen.visibleFrame, display: true) }
    }

    // MARK: - Actions

    private func bringToFront() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    @objc func newTerminal() {
        bringToFront()
        let directory = (manager.focused?.content as? TerminalCard)?.currentDirectory ?? TerminalCard.lastDirectory
        manager.add(TerminalCard(directory: directory), size: Settings.terminalSize)
    }

    @objc func focusNext() { bringToFront(); manager.cycleFocus(by: 1) }
    @objc func focusPrevious() { bringToFront(); manager.cycleFocus(by: -1) }
    @objc func closeCard() { manager.closeFocused() }
    @objc func zoomIn() { manager.focused?.content.zoom(by: 1) }
    @objc func zoomOut() { manager.focused?.content.zoom(by: -1) }
    @objc func reloadCard() { manager.focused?.content.reload() }

    private func registerHotkeys() {
        let bindings: [(Hotkey, () -> Void)] = [
            (Settings.hotkeyNewTerminal, { [weak self] in self?.newTerminal() }),
            (Settings.hotkeyNext, { [weak self] in self?.focusNext() }),
            (Settings.hotkeyPrevious, { [weak self] in self?.focusPrevious() }),
        ]
        for (key, action) in bindings where !Hotkeys.register(key, action: action) {
            NSLog("Float: hotkey \(key) is taken by another app")
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Float", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Float", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Float")

        let file = NSMenu()
        file.addItem(item("New Terminal", #selector(newTerminal), "t", [.command, .option]))
        file.addItem(.separator())
        file.addItem(item("Close Card", #selector(closeCard), "w"))
        main.addItem(submenu: file, title: "File")

        let edit = NSMenu()
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: "Edit")

        let view = NSMenu()
        view.addItem(item("Bigger", #selector(zoomIn), "+"))
        view.addItem(item("Bigger", #selector(zoomIn), "=", isAlternate: true))
        view.addItem(item("Smaller", #selector(zoomOut), "-"))
        view.addItem(item("Reload", #selector(reloadCard), "r"))
        main.addItem(submenu: view, title: "View")

        let win = NSMenu()
        win.addItem(item("Next Card", #selector(focusNext), String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command, .option]))
        win.addItem(item("Previous Card", #selector(focusPrevious), String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command, .option]))
        main.addItem(submenu: win, title: "Window")
        NSApp.windowsMenu = win

        return main
    }

    private func item(
        _ title: String, _ action: Selector, _ key: String,
        _ modifiers: NSEvent.ModifierFlags = .command, isAlternate: Bool = false
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        if isAlternate { item.isHidden = true; item.allowsKeyEquivalentWhenHidden = true }
        return item
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
