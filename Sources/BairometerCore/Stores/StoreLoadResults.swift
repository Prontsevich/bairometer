import Foundation

public struct SnapshotLoadResult: Sendable {
    public let snapshots: [UsageSnapshot]
    public let warning: String?

    public init(snapshots: [UsageSnapshot], warning: String? = nil) {
        self.snapshots = snapshots
        self.warning = warning
    }
}

public struct ProviderAccountLoadResult: Sendable {
    public let accounts: [ProviderAccount]
    public let warning: String?

    public init(accounts: [ProviderAccount], warning: String? = nil) {
        self.accounts = accounts
        self.warning = warning
    }
}

public struct RefreshSettingsLoadResult: Sendable {
    public let settings: RefreshSettings
    public let warning: String?

    public init(settings: RefreshSettings, warning: String? = nil) {
        self.settings = settings
        self.warning = warning
    }
}
