import Foundation

public struct CodexAppServerProviderAdapter: ProviderAdapter {
    public let id = "openai-codex"
    public let displayName = "OpenAI Codex"
    public let usageURL: URL? = URL(string: "https://chatgpt.com/codex")
    public let capabilities = ProviderCapabilities(sources: [
        ProviderSourceCapability(
            mode: .appServer,
            kind: .live,
            summary: "Read current rate limits through the local Codex app-server."
        )
    ])

    private let client: any CodexAppServerClient

    public init(client: any CodexAppServerClient = ProcessCodexAppServerClient()) {
        self.client = client
    }

    public func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot {
        guard account.sourceMode == .appServer else {
            throw ProviderAdapterError(
                providerID: id,
                message: "OpenAI Codex account has an unsupported source configuration.",
                recoverySuggestion: "Open this account in Settings and save it again."
            )
        }

        do {
            let payload = try await client.fetchRateLimits(executablePath: account.executablePath)
            return try makeSnapshot(account: account, payload: payload)
        } catch let error as ProviderAdapterError {
            throw error
        } catch let error as CodexAppServerClientError {
            throw ProviderAdapterError(
                providerID: id,
                message: error.localizedDescription,
                recoverySuggestion: error.recoverySuggestion,
                isTransient: error.isTransient
            )
        } catch let error as CodexRateLimitsParserError {
            throw ProviderAdapterError(
                providerID: id,
                message: error.localizedDescription,
                recoverySuggestion: error.recoverySuggestion
            )
        } catch {
            throw ProviderAdapterError(
                providerID: id,
                message: "Codex rate limits could not be read.",
                recoverySuggestion: "Try refreshing again after updating Codex CLI.",
                isTransient: true
            )
        }
    }

    public func makeSnapshot(
        account: ProviderAccount,
        payload: CodexRateLimitsPayload,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        let parsed = try CodexRateLimitsParser.parse(payload, now: now)
        let highestUsage = parsed.windows.compactMap(\.usedPercent).max() ?? 0
        let status: UsageStatus = highestUsage >= 85 || !parsed.warnings.isEmpty ? .warning : .ok

        return UsageSnapshot(
            providerID: id,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: displayName,
            status: status,
            limitWindows: parsed.windows,
            lastUpdatedAt: now,
            confidence: .live,
            source: CodexRateLimitsParser.sourceDescription,
            warnings: [CodexRateLimitsParser.compatibilityWarning] + parsed.warnings
        )
    }

}

public struct CodexParsedRateLimits: Equatable, Sendable {
    public let windows: [UsageLimitWindow]
    public let warnings: [String]
}

public enum CodexRateLimitsParserError: Error, LocalizedError, Equatable, Sendable {
    case codexBucketUnavailable
    case noUsableWindows

    public var errorDescription: String? {
        switch self {
        case .codexBucketUnavailable:
            "Codex app-server did not identify a Codex rate-limit bucket."
        case .noUsableWindows:
            "Codex app-server did not provide a usable rate-limit window."
        }
    }

    public var recoverySuggestion: String? {
        "Update Codex CLI and try refreshing again."
    }
}

public enum CodexRateLimitsParser {
    public static let sourceDescription = "Codex app-server (Experimental)"
    public static let compatibilityWarning = "Experimental app-server source; Codex CLI compatibility and data coverage may change between versions."

    public static func parse(
        _ payload: CodexRateLimitsPayload,
        now: Date = Date()
    ) throws -> CodexParsedRateLimits {
        let bucket = try selectCodexBucket(from: payload)
        var windows: [UsageLimitWindow] = []
        var warnings: [String] = []

        if let primary = bucket.primary {
            appendWindow(
                primary,
                id: "primary",
                fallbackName: "Primary",
                isRequired: true,
                now: now,
                windows: &windows,
                warnings: &warnings
            )
        } else {
            warnings.append("Codex did not provide a primary rate-limit window.")
        }

        if let secondary = bucket.secondary {
            appendWindow(
                secondary,
                id: "secondary",
                fallbackName: "Secondary",
                isRequired: false,
                now: now,
                windows: &windows,
                warnings: &warnings
            )
        }

        guard !windows.isEmpty else {
            throw CodexRateLimitsParserError.noUsableWindows
        }
        return CodexParsedRateLimits(windows: windows, warnings: warnings)
    }

    private static func selectCodexBucket(
        from payload: CodexRateLimitsPayload
    ) throws -> CodexRateLimitBucketPayload {
        if let buckets = payload.rateLimitsByLimitID {
            if let bucket = buckets["codex"], bucket.limitID == nil || bucket.limitID == "codex" {
                return bucket
            }

            let matchingBuckets = buckets.values.filter { $0.limitID == "codex" }
            guard matchingBuckets.count == 1 else {
                throw CodexRateLimitsParserError.codexBucketUnavailable
            }
            return matchingBuckets[0]
        }

        guard payload.rateLimits.limitID == "codex" else {
            throw CodexRateLimitsParserError.codexBucketUnavailable
        }
        return payload.rateLimits
    }

    private static func appendWindow(
        _ payload: CodexRateLimitWindowPayload,
        id: String,
        fallbackName: String,
        isRequired: Bool,
        now: Date,
        windows: inout [UsageLimitWindow],
        warnings: inout [String]
    ) {
        let displayName = displayName(
            durationMinutes: payload.windowDurationMins,
            fallback: fallbackName
        )
        guard let usedPercent = payload.usedPercent, (0...100).contains(usedPercent) else {
            let requirement = isRequired ? "required " : ""
            warnings.append("Codex provided an invalid \(requirement)\(displayName) rate-limit percentage.")
            return
        }

        let resetAt: Date?
        if let resetTimestamp = payload.resetsAt {
            let date = Date(timeIntervalSince1970: TimeInterval(resetTimestamp))
            if resetTimestamp > 0, date > now {
                resetAt = date
            } else {
                resetAt = nil
                warnings.append("Codex provided an invalid \(displayName) reset time.")
            }
        } else {
            resetAt = nil
        }

        windows.append(
            UsageLimitWindow(
                id: id,
                displayName: displayName,
                usedPercent: usedPercent,
                resetAt: resetAt
            )
        )
    }

    private static func displayName(durationMinutes: Int?, fallback: String) -> String {
        guard let durationMinutes, durationMinutes > 0 else { return fallback }
        if durationMinutes.isMultiple(of: 1_440) {
            return "\(durationMinutes / 1_440)-day"
        }
        if durationMinutes.isMultiple(of: 60) {
            return "\(durationMinutes / 60)-hour"
        }
        return "\(durationMinutes)-minute"
    }
}
