import AppKit

@main
@MainActor
final class FloatApp: NSObject, NSApplicationDelegate {
    private static let delegate = FloatApp()

    private var window: CanvasWindow!
    private var manager: CardManager!
    private let launcher = LauncherView()

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
        window.onMouseDown = { [weak self] hit in self?.mouseDown(on: hit) }
        launcher.onLaunch = { [weak self] in self?.launch($0) }
        launcher.onDismiss = { [weak self] in
            if let card = self?.manager.focused { self?.manager.focus(card) }
        }

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
        if CommandLine.arguments.contains("--demo") { runDemo() } else { newTerminal() }
    }

    /// Dev flag: a typical layout to eyeball rendering and spacing.
    private func runDemo() {
        for _ in 0..<3 { newTerminal() }
        newPreview(url: "https://example.com")
        newPreview()
        // Give Stage Manager a moment to place the window so the layout uses the final bounds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.arrangeAll() }
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

    private func mouseDown(on hit: NSView?) {
        if launcher.superview != nil, hit?.isDescendant(of: launcher) != true { launcher.dismiss() }
        manager.focus(containing: hit)
    }

    @objc func newTerminal() { newTerminal(directory: nil) }

    /// nil directory = where the focused terminal is, else the last directory used.
    func newTerminal(directory: String?, command: String? = nil, spawnFrom: CGRect? = nil) {
        bringToFront()
        let dir = directory ?? (manager.focused?.content as? TerminalCard)?.currentDirectory ?? TerminalCard.lastDirectory
        manager.add(TerminalCard(directory: dir, command: command), size: Settings.terminalSize, spawnFrom: spawnFrom)
    }

    @objc func newPreview() { newPreview(url: Settings.defaultURL) }

    func newPreview(url: String, spawnFrom: CGRect? = nil) {
        bringToFront()
        let web = WebCard(url: url)
        let card = manager.add(web, size: Settings.previewSize, spawnFrom: spawnFrom)
        web.onSuggestAspect = { [weak self, weak card] aspect in
            guard let self, let card else { return }
            self.manager.setAspect(aspect, for: card)
        }
    }

    @objc func showLauncher() {
        bringToFront()
        guard let canvas = window.contentView else { return }
        launcher.show(in: canvas, bounds: manager.canvas.layoutBounds)
    }

    private func launch(_ action: LaunchAction) {
        let from = launcher.frame
        switch action {
        case .terminal(let directory, let command):
            if let directory, !FileManager.default.fileExists(atPath: directory) { NSSound.beep(); return }
            newTerminal(directory: directory, command: command, spawnFrom: from)
        case .preview(let url):
            newPreview(url: url, spawnFrom: from)
        }
    }

    @objc func arrangeAll() { bringToFront(); manager.arrangeAll() }
    @objc func focusNext() { bringToFront(); manager.cycleFocus(by: 1) }
    @objc func focusPrevious() { bringToFront(); manager.cycleFocus(by: -1) }
    @objc func closeCard() { manager.closeFocused() }
    @objc func zoomIn() { manager.focused?.content.zoom(by: 1) }
    @objc func zoomOut() { manager.focused?.content.zoom(by: -1) }
    @objc func reloadCard() { manager.focused?.content.reload() }

    private func registerHotkeys() {
        let bindings: [(Hotkey, () -> Void)] = [
            (Settings.hotkeyNewTerminal, { [weak self] in self?.newTerminal() }),
            (Settings.hotkeyNewPreview, { [weak self] in self?.newPreview() }),
            (Settings.hotkeyArrange, { [weak self] in self?.arrangeAll() }),
            (Settings.hotkeyNext, { [weak self] in self?.focusNext() }),
            (Settings.hotkeyPrevious, { [weak self] in self?.focusPrevious() }),
        ]
        for (key, action) in bindings where !Hotkeys.register(key, action: action) {
            NSLog("Float: hotkey \(key) is taken by another app")
        }
        let showLauncher: () -> Void = { [weak self] in self?.showLauncher() }
        if !Hotkeys.register(Settings.hotkeyLauncher, action: showLauncher) {
            NSLog("Float: ⌥Space is taken by another app, using ⌥⌘Space for the launcher")
            Hotkeys.register(Settings.hotkeyLauncherFallback, action: showLauncher)
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
        file.addItem(item("New Terminal", #selector(newTerminal as () -> Void), "t", [.command, .option]))
        file.addItem(item("New Preview", #selector(newPreview as () -> Void), "p", [.command, .option]))
        file.addItem(item("Quick Launch…", #selector(showLauncher), " ", [.option]))
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
        win.addItem(item("Arrange All", #selector(arrangeAll), "a", [.command, .option]))
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
