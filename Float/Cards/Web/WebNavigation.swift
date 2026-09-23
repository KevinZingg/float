import AppKit

/// Pure policy decisions for links in a web card.
enum WebNavigation {
    enum Action: Equatable {
        case allow
        case download
        /// Open in a new Float card (⌘-click).
        case newCard
        /// Open in the system default browser (⌘⇧-click).
        case defaultBrowser
        /// Hand a non-web scheme (mailto:, zoommtg:, …) to the app that owns it.
        case external
    }

    static func action(
        for url: URL?, modifiers: NSEvent.ModifierFlags, isLinkClick: Bool, shouldDownload: Bool
    ) -> Action {
        if let scheme = url?.scheme?.lowercased(), !Config.webSchemes.contains(scheme) { return .external }
        if shouldDownload { return .download }
        guard isLinkClick, modifiers.contains(.command) else { return .allow }
        return modifiers.contains(.shift) ? .defaultBrowser : .newCard
    }

    /// Responses the web view can't render, or that ask to be saved, become downloads.
    static func shouldDownload(canShowMIMEType: Bool, contentDisposition: String?) -> Bool {
        let attachment = contentDisposition?.lowercased().trimmingCharacters(in: .whitespaces).hasPrefix("attachment") ?? false
        return !canShowMIMEType || attachment
    }

    /// Card size for a popup's requested width/height (content size), clamped to S–L. nil = no hint.
    static func popupSize(width: CGFloat?, height: CGFloat?) -> CGSize? {
        guard let width, let height else { return nil }
        let w = min(max(width, Config.popupWidthRange.lowerBound), Config.popupWidthRange.upperBound)
        let h = min(max(height, Config.popupHeightRange.lowerBound), Config.popupHeightRange.upperBound)
        return CGSize(width: w, height: h + Theme.chromeHeight)
    }
}
