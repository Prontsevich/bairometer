import Foundation

public struct ProviderAdapterError: Error, LocalizedError, Equatable, Sendable {
    public let providerID: String
    public let message: String
    public let recoverySuggestion: String?
    public let isTransient: Bool

    public var errorDescription: String? { message }

    public init(
        providerID: String,
        message: String,
        recoverySuggestion: String? = nil,
        isTransient: Bool = false
    ) {
        self.providerID = providerID
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.isTransient = isTransient
    }
}

public protocol ProviderAdapter: Sendable {
    var id: String { get }
    var displayName: String { get }
    var usageURL: URL? { get }
    var capabilities: ProviderCapabilities { get }

    func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot
}

public extension ProviderAdapter {
    var capabilities: ProviderCapabilities { .manualOnly }
}
