import Foundation

public enum ProviderRefreshStatus: Equatable, Sendable {
    case idle
    case refreshing
    case succeeded(Date)
    case failed(Date)

    public var displayName: String {
        switch self {
        case .idle: "Idle"
        case .refreshing: "Refreshing"
        case .succeeded: "Updated"
        case .failed: "Failed"
        }
    }
}
