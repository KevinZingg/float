import AppKit
import Carbon.HIToolbox

/// Physics, layout and behaviour constants. Colours, type and shape live in Theme.
enum Settings {
    // MARK: User settings (Settings window, persisted in UserDefaults, read live)

    enum Keys {
        static let theme = "theme"
        static let terminalFontSize = "terminalFontSize"
        static let defaultViewport = "defaultViewport"
        static let springDampingRatio = "springDampingRatio"
        static let padding = "cardPadding"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.theme: Theme.Name.ink.rawValue,
            Keys.terminalFontSize: 12.0,
            Keys.defaultViewport: Viewport.desktop.rawValue,
            Keys.springDampingRatio: 0.82,
            Keys.padding: 16.0,
        ])
    }

    static var padding: CGFloat { CGFloat(UserDefaults.standard.double(forKey: Keys.padding)) }
    static var terminalFontSize: CGFloat { CGFloat(UserDefaults.standard.double(forKey: Keys.terminalFontSize)) }
    static var springDampingRatio: CGFloat { CGFloat(UserDefaults.standard.double(forKey: Keys.springDampingRatio)) }
    static var defaultViewport: Viewport {
        Viewport(rawValue: UserDefaults.standard.string(forKey: Keys.defaultViewport) ?? "") ?? .desktop
    }

    static let paddingRange: ClosedRange<CGFloat> = 8...48
    static let dampingRange: ClosedRange<CGFloat> = 0.5...1

    // MARK: Layout

    static let gap: CGFloat = 16
    static let canvasBackgroundAlpha: CGFloat = 0.01
    static let cascadeOffset: CGFloat = 28
    static let resizeZone: CGFloat = 6
    static let minCardSize = NSSize(width: 220, height: 140)

    // Drag lift
    static let liftScale: CGFloat = 1.02

    // Fling + spring (WWDC18 session 803)
    static let velocityWindow: TimeInterval = 0.08
    static let flingDecelerationRate: CGFloat = 0.998
    static let flingMinSpeed: CGFloat = 150
    static let springResponse: CGFloat = 0.4
    static let springRestDistance: CGFloat = 0.5
    static let springRestSpeed: CGFloat = 20
    static let rubberBandExponent: CGFloat = 0.7
    static let rubberBandDampingRatio: CGFloat = 0.6
    static let rubberBandResponse: CGFloat = 0.3
    static let reducedMotionDuration: TimeInterval = 0.15

    static let terminalSize = NSSize(width: 560, height: 360)
    static let previewSize = NSSize(width: 480, height: 300)

    static let terminalInset: CGFloat = 10
    static let terminalFontRange: ClosedRange<CGFloat> = 8...32

    static let defaultURL = "localhost:3000"
    static let localRetryInterval: TimeInterval = 2
    /// Schemes a web card loads itself; anything else (mailto:, zoommtg:, …) goes to its own app.
    static let webSchemes: Set<String> = ["http", "https", "about", "data", "blob", "javascript"]
    static let popupWidthRange: ClosedRange<CGFloat> = 400...800
    static let popupHeightRange: ClosedRange<CGFloat> = 250...800
    static let toastHeight: CGFloat = 28
    static let toastDuration: TimeInterval = 4
    static let promptMaxWidth: CGFloat = 460
    static let emptyStateMaxGlyph: CGFloat = 9
    static let emptyStateAlpha: CGFloat = 0.07
    static let emptyStateLabelAlpha: CGFloat = 0.4
    static let cardEntranceScale: CGFloat = 0.92
    static let cardExitDuration: TimeInterval = 0.2

    // Global hotkeys (⌥⌘)
    private static let optCmd = UInt32(optionKey | cmdKey)
    static let hotkeyNewTerminal = Hotkey(keyCode: UInt32(kVK_ANSI_T), modifiers: optCmd)
    static let hotkeyNewPreview = Hotkey(keyCode: UInt32(kVK_ANSI_P), modifiers: optCmd)
    static let hotkeyArrange = Hotkey(keyCode: UInt32(kVK_ANSI_A), modifiers: optCmd)
    static let hotkeyNext = Hotkey(keyCode: UInt32(kVK_RightArrow), modifiers: optCmd)
    static let hotkeyPrevious = Hotkey(keyCode: UInt32(kVK_LeftArrow), modifiers: optCmd)

    // ⌥Space launcher; falls back to ⌥⌘Space if another app owns ⌥Space.
    static let hotkeyLauncher = Hotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    static let hotkeyLauncherFallback = Hotkey(keyCode: UInt32(kVK_Space), modifiers: optCmd)
    static let launcherWidth: CGFloat = 520
}
