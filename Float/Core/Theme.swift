import AppKit
import CoreText

/// Design tokens: colour, type, shape and shadow for everything Float draws. Physics and layout live in Settings.
/// Values follow the mogen identity (website/brand/IDENTITY.md, src/styles/tokens.css, dark ground).
struct Theme {
    enum Name: String, CaseIterable {
        /// A, "Night / Ink": solid Night chrome, 2 pt radius, hairlines, sage ink accents.
        case ink = "a"
        /// B, "Glass + ink": macOS vibrancy chrome with the same type and accent, softer radius.
        case glass = "b"

        var title: String { self == .ink ? "Night / Ink" : "Glass + ink" }
    }

    let name: Name

    // MARK: Palette (mogen dark tokens)

    static let night = NSColor(hex: 0x161615)
    static let paper = NSColor(hex: 0xf6f6f6)
    static let ink = NSColor(hex: 0xebe7e2)
    static let caption = NSColor(hex: 0xa19c96)
    static let faint = NSColor(hex: 0x6f6b67)
    static let hair = NSColor(hex: 0x2e2c2a)
    static let codeBackground = NSColor(hex: 0x1f1e1c)
    static let sageInk = NSColor(hex: 0xc5cc9f)

    /// Solid card and terminal ground.
    var cardBackground: NSColor { Self.night }
    /// Chrome strip fill; nil means vibrancy material instead of a fill.
    var chromeBackground: NSColor? { name == .ink ? Self.night : nil }
    /// On the grey vibrancy of B, caption grey is too faint; ink at 75 % keeps the same quiet weight.
    var chromeText: NSColor { name == .ink ? Self.caption : Self.ink.withAlphaComponent(0.75) }
    var controlTint: NSColor { Self.caption }
    var hairline: NSColor { name == .ink ? Self.hair : NSColor(white: 1, alpha: 0.1) }
    var focusHairline: NSColor { Self.sageInk }
    var accent: NSColor { Self.sageInk }
    var text: NSColor { Self.ink }
    var secondaryText: NSColor { Self.caption }
    var fieldBackground: NSColor { Self.codeBackground }

    // MARK: Shape

    /// Both themes share the chrome height, since card layout maths depends on it.
    static let chromeHeight: CGFloat = 28
    var cardRadius: CGFloat { name == .ink ? 2 : 10 }
    var pillRadius: CGFloat { name == .ink ? 2 : 12 }
    var borderWidth: CGFloat { 1 }
    var usesVibrancy: Bool { name == .glass }
    var grabberSize: CGSize { name == .ink ? CGSize(width: 28, height: 2) : CGSize(width: 36, height: 4) }
    var grabberTopInset: CGFloat { 3 }
    var grabberIdleAlpha: CGFloat { 0.45 }
    var grabberActiveAlpha: CGFloat { 0.9 }
    var idleControlAlpha: CGFloat { 0.35 }
    var pillBackground: NSColor { Self.codeBackground }
    var pillBorder: NSColor { name == .ink ? NSColor(hex: 0x3a3835) : NSColor(white: 1, alpha: 0.12) }
    var pillShadowOpacity: Float { 0.45 }
    var pillShadowRadius: CGFloat { 18 }

    // MARK: Shadow (the identity has none; floating cards on an unknown wallpaper need a trace of one)

    var shadowOpacity: Float { name == .ink ? 0.22 : 0.35 }
    var shadowRadius: CGFloat { name == .ink ? 10 : 14 }
    var shadowOffset: CGSize { CGSize(width: 0, height: -3) }
    var liftShadowOpacity: Float { name == .ink ? 0.32 : 0.5 }
    var liftShadowRadius: CGFloat { name == .ink ? 20 : 28 }
    var liftShadowOffset: CGSize { CGSize(width: 0, height: -10) }

    // MARK: Type

    /// Chrome labels: mono, uppercase, 0.06 em tracking (identity § 03).
    static let labelSize: CGFloat = 10.5
    static let labelTracking: CGFloat = 0.06

    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name = weight == .medium ? "IBMPlexMono-Medm" : "IBMPlexMono"
        return NSFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Uppercase, tracked mono label text.
    static func label(_ string: String, color: NSColor, size: CGFloat = labelSize) -> NSAttributedString {
        NSAttributedString(string: string.uppercased(), attributes: [
            .font: mono(size, weight: .medium),
            .foregroundColor: color,
            .kern: size * labelTracking,
        ])
    }

    // MARK: Terminal

    var terminalForeground: NSColor { Self.ink }
    var terminalBackground: NSColor { Self.night }
    var terminalCaret: NSColor { Self.sageInk }
    /// ANSI 0–15, derived from the mogen inks: rose for red, sage for green, lake for blue.
    var ansi: [NSColor] {
        [0x2e2c2a, 0xe0a7a3, 0xb9c094, 0xd9c79e, 0xa9bfcf, 0xcdb2c7, 0xa3c4bd, 0xa19c96,
         0x6f6b67, 0xe7c7c5, 0xd3d9b3, 0xe8dcbc, 0xc4d3de, 0xdfcbda, 0xc0d9d3, 0xebe7e2].map(NSColor.init(hex:))
    }

    // MARK: Current

    static var current: Theme {
        Theme(name: Name(rawValue: UserDefaults.standard.string(forKey: Config.Keys.theme) ?? "") ?? .ink)
    }

    /// Makes the bundled IBM Plex Mono available to NSFont (OFL, see Resources/Fonts).
    static func registerFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}
