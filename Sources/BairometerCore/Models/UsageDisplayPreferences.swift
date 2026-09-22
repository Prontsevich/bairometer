import Foundation

public enum UsageDisplayMode: String, CaseIterable, Codable, Equatable, Sendable {
    case used
    case left

    public static let storageKey = "usage-display-mode"
}

public struct UsageDisplayOverrideKey: Hashable, Codable, Sendable {
    public let providerID: String
    public let accountID: String
    public let windowID: String

    public init(providerID: String, accountID: String, windowID: String) {
        self.providerID = providerID
        self.accountID = accountID
        self.windowID = windowID
    }
}

public struct UsageDisplayOverride: Equatable, Sendable {
    public let key: UsageDisplayOverrideKey
    public let mode: UsageDisplayMode

    public init(key: UsageDisplayOverrideKey, mode: UsageDisplayMode) {
        self.key = key
        self.mode = mode
    }
}

public struct UsageDisplayOverrideLoadResult: Sendable {
    public let overrides: [UsageDisplayOverride]
    public let warning: String?

    public init(overrides: [UsageDisplayOverride], warning: String? = nil) {
        self.overrides = overrides
        self.warning = warning
    }
}

public protocol UsageDisplayOverrideStore: Sendable {
    func load() -> UsageDisplayOverrideLoadResult
    func set(_ mode: UsageDisplayMode?, for key: UsageDisplayOverrideKey) throws
}
