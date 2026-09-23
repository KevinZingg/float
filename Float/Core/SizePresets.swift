import Foundation

/// Content aspect ratios offered in the card menu. Picking one locks drag-resizing to it.
enum AspectPreset: String, CaseIterable {
    case free = "Free"
    case wide = "16:9"
    case tall = "9:16"
    case square = "1:1"
    case classic = "4:3"

    var ratio: CGFloat? {
        switch self {
        case .free: nil
        case .wide: 16.0 / 9.0
        case .tall: 9.0 / 16.0
        case .square: 1
        case .classic: 4.0 / 3.0
        }
    }
}

/// Card widths offered in the card menu.
enum SizePreset: String, CaseIterable {
    case small = "S"
    case medium = "M"
    case large = "L"

    var width: CGFloat {
        switch self {
        case .small: 400
        case .medium: 560
        case .large: 800
        }
    }
}
