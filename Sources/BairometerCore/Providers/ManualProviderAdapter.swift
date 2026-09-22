import Foundation

public struct ManualProviderAdapter: ProviderAdapter {
    public let id: String
    public let displayName: String
    public let usageURL: URL?
    private let sourceDescription: String

    public init(
        id: String,
        displayName: String,
        usageURL: URL?,
        sourceDescription: String
    ) {
        self.id = id
        self.displayName = displayName
        self.usageURL = usageURL
        self.sourceDescription = sourceDescription
    }

    public func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot {
        UsageSnapshot(
            providerID: id,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: displayName,
            status: .unavailable,
            remainingLabel: "Open provider usage page",
            lastUpdatedAt: Date(),
            confidence: .manual,
            source: sourceDescription,
            warnings: ["No verified machine-readable usage source is configured yet."]
        )
    }
}
