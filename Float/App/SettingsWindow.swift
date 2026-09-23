import SwiftUI

/// ⌘, : a small native form. Everything persists in UserDefaults and FloatApp applies it live.
struct SettingsView: View {
    @AppStorage(Settings.Keys.theme) private var theme = Theme.Name.ink.rawValue
    @AppStorage(Settings.Keys.terminalFontSize) private var fontSize = 12.0
    @AppStorage(Settings.Keys.defaultViewport) private var viewport = Viewport.desktop.rawValue
    @AppStorage(Settings.Keys.springDampingRatio) private var damping = 0.82
    @AppStorage(Settings.Keys.padding) private var padding = 16.0
    let launcherHotkey: String

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(Theme.Name.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                Stepper("Terminal font size  \(Int(fontSize)) pt", value: $fontSize,
                        in: Double(Settings.terminalFontRange.lowerBound)...Double(Settings.terminalFontRange.upperBound))
                Picker("Default viewport", selection: $viewport) {
                    ForEach(Viewport.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
            }
            Section {
                LabeledContent("Spring bounce") {
                    Slider(value: $damping, in: Double(Settings.dampingRange.lowerBound)...Double(Settings.dampingRange.upperBound)) {
                        EmptyView()
                    } minimumValueLabel: { Text("more") } maximumValueLabel: { Text("none") }
                }
                LabeledContent("Card padding  \(Int(padding)) pt") {
                    Slider(value: $padding, in: Double(Settings.paddingRange.lowerBound)...Double(Settings.paddingRange.upperBound), step: 4)
                }
            }
            Section {
                LabeledContent("Quick launch", value: launcherHotkey)
                LabeledContent("Site permissions") {
                    Button("Reset") { SitePermissions.resetAll() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(launcherHotkey: String) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(launcherHotkey: launcherHotkey)))
            w.title = "Float Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    static func orderFrontIfOpen() {
        if let window, window.isVisible { window.makeKeyAndOrderFront(nil) }
    }
}
