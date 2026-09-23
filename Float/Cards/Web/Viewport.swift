import Foundation

/// Virtual viewport a preview lays out at. The page renders at this CSS width and is then
/// zoomed to fit the card, like a scaled-down screenshot rather than a narrow browser.
enum Viewport: String, CaseIterable {
    case desktop = "Desktop"
    case laptop = "Laptop"
    case tablet = "Tablet"
    case mobile = "Mobile"

    var width: CGFloat {
        switch self {
        case .desktop: 1440
        case .laptop: 1280
        case .tablet: 834
        case .mobile: 390
        }
    }

    /// Content aspect (width / height) a card should take for this viewport, if it has a natural one.
    var suggestedAspect: CGFloat? {
        self == .mobile ? 9.0 / 16.0 : nil
    }

    func pageZoom(forCardWidth cardWidth: CGFloat) -> CGFloat {
        max(cardWidth, 1) / width
    }
}
