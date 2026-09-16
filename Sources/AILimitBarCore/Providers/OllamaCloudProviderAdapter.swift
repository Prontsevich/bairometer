import Foundation

public protocol OllamaWebPageClient: Sendable {
    func fetchUsage(account: ProviderAccount) async throws -> OllamaUsagePagePayload
}

public struct UnavailableOllamaWebPageClient: OllamaWebPageClient {
    public init() {}

    public func fetchUsage(account: ProviderAccount) async throws -> OllamaUsagePagePayload {
        throw ProviderAdapterError(
            providerID: "ollama-cloud",
            message: "Ollama experimental web source is unavailable in this app session.",
            recoverySuggestion: "Open the Settings connection flow and reconnect Ollama through Bairometer."
        )
    }
}

public struct OllamaUsagePageWindowPayload: Codable, Equatable, Sendable {
    public let usedPercent: Double?
    public let resetAt: Date?

    public init(usedPercent: Double?, resetAt: Date? = nil) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
    }
}

public struct OllamaUsagePagePayload: Codable, Equatable, Sendable {
    public let session: OllamaUsagePageWindowPayload?
    public let weekly: OllamaUsagePageWindowPayload?

    public init(
        session: OllamaUsagePageWindowPayload?,
        weekly: OllamaUsagePageWindowPayload?
    ) {
        self.session = session
        self.weekly = weekly
    }
}

public enum OllamaUsagePageParseError: Error, LocalizedError, Equatable, Sendable {
    case missingWindow(String)
    case missingPercentage(String)
    case invalidPercentage(String)
    case invalidReset(String)

    public var errorDescription: String? {
        switch self {
        case let .missingWindow(window): "Ollama usage page is missing the \(window) window."
        case let .missingPercentage(window): "Ollama usage page did not provide a percentage for the \(window) window."
        case let .invalidPercentage(window): "Ollama usage page provided an invalid percentage for the \(window) window."
        case let .invalidReset(window): "Ollama usage page provided an invalid reset time for the \(window) window."
        }
    }
}

public enum OllamaUsagePageParser {
    public static let sourceDescription = "Ollama settings web page (Experimental)"
    public static let compatibilityWarning = "Experimental web page source; Ollama may change its authenticated page structure without notice."

    public static func limitWindows(
        from payload: OllamaUsagePagePayload,
        now: Date = Date()
    ) throws -> [UsageLimitWindow] {
        [
            try makeWindow(
                id: "session",
                displayName: "Session",
                payload: payload.session,
                now: now
            ),
            try makeWindow(
                id: "weekly",
                displayName: "Weekly",
                payload: payload.weekly,
                now: now
            )
        ]
    }

    private static func makeWindow(
        id: String,
        displayName: String,
        payload: OllamaUsagePageWindowPayload?,
        now: Date
    ) throws -> UsageLimitWindow {
        guard let payload else {
            throw OllamaUsagePageParseError.missingWindow(displayName)
        }
        guard let usedPercent = payload.usedPercent else {
            throw OllamaUsagePageParseError.missingPercentage(displayName)
        }
        guard (0...100).contains(usedPercent) else {
            throw OllamaUsagePageParseError.invalidPercentage(displayName)
        }
        if let resetAt = payload.resetAt, resetAt <= now {
            throw OllamaUsagePageParseError.invalidReset(displayName)
        }

        return UsageLimitWindow(
            id: id,
            displayName: displayName,
            usedPercent: usedPercent,
            resetAt: payload.resetAt
        )
    }
}

public struct OllamaCloudProviderAdapter: ProviderAdapter {
    public let id = "ollama-cloud"
    public let displayName = "Ollama Cloud"
    public let usageURL = URL(string: "https://ollama.com/settings")
    public let capabilities = ProviderCapabilities(sources: [
        ProviderSourceCapability(
            mode: .ollamaWebPage,
            kind: .live,
            summary: "Read usage from the authenticated Ollama settings page in Bairometer."
        )
    ])

    private let client: any OllamaWebPageClient

    public init(client: any OllamaWebPageClient = UnavailableOllamaWebPageClient()) {
        self.client = client
    }

    public func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot {
        guard account.sourceMode == .ollamaWebPage else {
            throw ProviderAdapterError(
                providerID: id,
                message: "Ollama Cloud account has an unsupported source configuration.",
                recoverySuggestion: "Open this account in Settings and save it again."
            )
        }
        guard account.webDataStoreID != nil else {
            throw ProviderAdapterError(
                providerID: id,
                message: "Ollama experimental web source is not connected.",
                recoverySuggestion: "Choose Connect Ollama in Settings and sign in through Bairometer."
            )
        }

        do {
            let payload = try await client.fetchUsage(account: account)
            return try makeSnapshot(account: account, payload: payload)
        } catch let error as ProviderAdapterError {
            throw error
        } catch let error as OllamaUsagePageParseError {
            throw ProviderAdapterError(
                providerID: id,
                message: error.localizedDescription,
                recoverySuggestion: "Reconnect Ollama and check whether its settings page structure has changed."
            )
        } catch {
            throw ProviderAdapterError(
                providerID: id,
                message: "Ollama settings page could not be read.",
                recoverySuggestion: "Reconnect Ollama through Bairometer and try again.",
                isTransient: true
            )
        }
    }

    public func makeSnapshot(
        account: ProviderAccount,
        payload: OllamaUsagePagePayload,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        let windows = try OllamaUsagePageParser.limitWindows(from: payload, now: now)
        let highestUsage = windows.compactMap(\.usedPercent).max() ?? 0
        let status: UsageStatus = highestUsage >= 85 ? .warning : .ok

        return UsageSnapshot(
            providerID: id,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: displayName,
            status: status,
            limitWindows: windows,
            lastUpdatedAt: now,
            confidence: .live,
            source: OllamaUsagePageParser.sourceDescription,
            warnings: [OllamaUsagePageParser.compatibilityWarning]
        )
    }

}
