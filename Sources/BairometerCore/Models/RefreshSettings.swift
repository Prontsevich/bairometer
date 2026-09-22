import Foundation

public enum RefreshInterval: String, Codable, CaseIterable, Identifiable, Sendable {
    case manualOnly = "manual-only"
    case oneMinute = "1-minute"
    case fiveMinutes = "5-minutes"
    case tenMinutes = "10-minutes"
    case fifteenMinutes = "15-minutes"
    case thirtyMinutes = "30-minutes"
    case oneHour = "1-hour"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .manualOnly: "Manual"
        case .oneMinute: "1 min"
        case .fiveMinutes: "5 min"
        case .tenMinutes: "10 min"
        case .fifteenMinutes: "15 min"
        case .thirtyMinutes: "30 min"
        case .oneHour: "1 hr"
        }
    }

    public var timeInterval: TimeInterval? {
        switch self {
        case .manualOnly: nil
        case .oneMinute: 1 * 60
        case .fiveMinutes: 5 * 60
        case .tenMinutes: 10 * 60
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        }
    }

    public var staleAfter: TimeInterval {
        switch self {
        case .manualOnly: 24 * 60 * 60
        case .oneMinute, .fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour:
            (timeInterval ?? 0) * 2
        }
    }
}

public struct RefreshSettings: Codable, Equatable, Sendable {
    public var interval: RefreshInterval

    public init(interval: RefreshInterval = .manualOnly) {
        self.interval = interval
    }
}
