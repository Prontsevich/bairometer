import Foundation

enum DashboardHeightPreset: String, CaseIterable, Identifiable {
    case compact
    case standard
    case tall

    static let storageKey = "dashboard-height-preset"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .tall: "Tall"
        }
    }

    var viewportHeight: CGFloat {
        switch self {
        case .compact: 320
        case .standard: 460
        case .tall: 640
        }
    }
}
