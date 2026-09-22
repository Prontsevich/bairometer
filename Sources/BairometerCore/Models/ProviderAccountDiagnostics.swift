import Foundation

public struct SourceRefreshState: Equatable, Sendable {
    public let providerID: String
    public let accountID: String
    public let lastAttemptAt: Date?
    public let lastSuccessfulRefreshAt: Date?
    public let lastFailedRefreshAt: Date?

    public init(
        providerID: String,
        accountID: String,
        lastAttemptAt: Date? = nil,
        lastSuccessfulRefreshAt: Date? = nil,
        lastFailedRefreshAt: Date? = nil
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.lastFailedRefreshAt = lastFailedRefreshAt
    }
}

public enum ProviderSourceAvailability: String, Equatable, Sendable {
    case supported
    case needsConnection = "needs-connection"
    case noData = "no-data"
    case failed
    case unsupported
}

public struct ProviderAccountDiagnostics: Equatable, Sendable {
    public let providerID: String
    public let accountID: String
    public let sourceMode: ProviderSourceMode
    public let sourceKind: ProviderSourceKind?
    public let availability: ProviderSourceAvailability
    public let message: String
    public let lastAttemptAt: Date?
    public let lastSuccessfulRefreshAt: Date?
    public let lastFailedRefreshAt: Date?
    public let messages: [String]

    public init(
        providerID: String,
        accountID: String,
        sourceMode: ProviderSourceMode,
        sourceKind: ProviderSourceKind?,
        availability: ProviderSourceAvailability,
        message: String,
        lastAttemptAt: Date? = nil,
        lastSuccessfulRefreshAt: Date? = nil,
        lastFailedRefreshAt: Date? = nil,
        messages: [String] = []
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.sourceMode = sourceMode
        self.sourceKind = sourceKind
        self.availability = availability
        self.message = message
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.lastFailedRefreshAt = lastFailedRefreshAt
        self.messages = messages
    }
}
