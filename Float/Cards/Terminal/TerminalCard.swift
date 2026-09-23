import AppKit
import SwiftTerm

/// A login shell in a SwiftTerm view.
@MainActor
final class TerminalCard: CardContent {
    let kind = CardKind.terminal
    private let terminal = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    private(set) var title: String
    private var fontSize = Settings.terminalFontSize
    var onTitleChange: ((String) -> Void)?
    var onRequestClose: (() -> Void)?

    /// Wrapper that gives the text a small margin from the card edge.
    let view = NSView()

    /// Remembered so new terminals open where you last were.
    static var lastDirectory: String {
        get { UserDefaults.standard.string(forKey: "lastDirectory") ?? NSHomeDirectory() }
        set { UserDefaults.standard.set(newValue, forKey: "lastDirectory") }
    }

    init(directory: String = TerminalCard.lastDirectory, command: String? = nil) {
        title = (directory as NSString).lastPathComponent
        terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminal.nativeBackgroundColor = Settings.cardBackground
        terminal.nativeForegroundColor = NSColor(white: 0.9, alpha: 1)
        terminal.caretColor = .controlAccentColor
        terminal.optionAsMetaKey = true
        terminal.processDelegate = self
        view.wantsLayer = true
        view.layer?.backgroundColor = Settings.cardBackground.cgColor
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        terminal.frame = view.bounds.insetBy(dx: Settings.terminalInset, dy: Settings.terminalInset)
        terminal.autoresizingMask = [.width, .height]
        view.addSubview(terminal)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminal.startProcess(
            executable: shell, args: ["-l"], environment: Self.environment(),
            execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: directory)
        TerminalCard.lastDirectory = directory
        if let command { send(command + "\n") }
    }

    private static func environment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Float"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }
    }

    func send(_ text: String) {
        terminal.send(data: ArraySlice(Array(text.utf8)))
    }

    /// The shell's working directory, read from the kernel (works without OSC 7 support).
    var currentDirectory: String? {
        let pid = terminal.process.shellPid
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }

    func focus() {
        terminal.window?.makeFirstResponder(terminal)
        if let dir = currentDirectory { TerminalCard.lastDirectory = dir }
    }

    /// True when something other than the shell owns the terminal (vim, claude, a dev server...).
    private var hasForegroundJob: Bool {
        let process = terminal.process!
        guard process.running, process.childfd >= 0 else { return false }
        let group = tcgetpgrp(process.childfd)
        return group > 0 && group != process.shellPid
    }

    func confirmClose() -> Bool {
        guard hasForegroundJob else { return true }
        let alert = NSAlert()
        alert.messageText = "Close “\(title)”?"
        alert.informativeText = "A process is still running in this terminal."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func close() {
        terminal.processDelegate = nil
        if let dir = currentDirectory { TerminalCard.lastDirectory = dir }
        terminal.process.terminate()
    }

    func zoom(by step: Int) {
        fontSize = min(max(fontSize + CGFloat(step), Settings.terminalFontRange.lowerBound), Settings.terminalFontRange.upperBound)
        terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}

extension TerminalCard: @preconcurrency LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        guard !title.isEmpty else { return }
        self.title = title
        onTitleChange?(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let path = URL(string: directory)?.path ?? Optional(directory), !path.isEmpty else { return }
        TerminalCard.lastDirectory = path
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in self?.onRequestClose?() }
    }
}
