import Foundation

public enum ClaudeCodeSnapshotSource {
    public static let managedStatusLine = "Claude Code managed statusLine"
    public static let usageCLI = "Claude Code /usage (Experimental)"
    public static let usageCLICompatibilityNotice =
        "Experimental /usage source; Claude Code text compatibility may change between versions."
}

public struct ClaudeCodeProviderAdapter: ProviderAdapter {
    public let id = "claude-code"
    public let displayName = "Claude Code"
    public let usageURL: URL? = URL(string: "https://claude.ai/settings/usage")
    public let capabilities = ProviderCapabilities(sources: [
        ProviderSourceCapability(
            mode: .manual,
            kind: .manual,
            summary: "Open Claude Code usage and maintain the snapshot manually."
        ),
        ProviderSourceCapability(
            mode: .claudeStatusLine,
            kind: .localSnapshot,
            summary: "Read the normalized snapshot written by the managed statusLine helper."
        ),
        ProviderSourceCapability(
            mode: .claudeUsageCLI,
            kind: .live,
            summary: "Read current plan limits through the authenticated local Claude CLI."
        )
    ])

    private let snapshotStore: (any CurrentSnapshotStore)?
    private let usageCLIClient: any ClaudeUsageCLIClient
    private let manualAdapter: ManualProviderAdapter

    public init(
        snapshotStore: (any CurrentSnapshotStore)? = nil,
        usageCLIClient: any ClaudeUsageCLIClient = ProcessClaudeUsageCLIClient()
    ) {
        self.snapshotStore = snapshotStore
        self.usageCLIClient = usageCLIClient
        self.manualAdapter = ManualProviderAdapter(
            id: id,
            displayName: displayName,
            usageURL: usageURL,
            sourceDescription: "Claude Code manual usage"
        )
    }

    public func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot {
        switch account.sourceMode {
        case .manual:
            return try await manualAdapter.fetchSnapshot(account: account)
        case .claudeStatusLine:
            return try managedStatusLineSnapshot(account: account)
        case .claudeUsageCLI:
            return try await usageCLISnapshot(account: account)
        case .ollamaWebPage, .appServer, .openRouterAPI, .miniMaxTokenPlan:
            throw ProviderAdapterError(
                providerID: id,
                message: "Claude Code account has an unsupported source configuration.",
                recoverySuggestion: "Open this account in Settings and save it again."
            )
        }
    }

    private func managedStatusLineSnapshot(account: ProviderAccount) throws -> UsageSnapshot {
        guard let snapshotStore else {
            throw ProviderAdapterError(
                providerID: id,
                message: "Claude Code managed statusLine storage is unavailable.",
                recoverySuggestion: "Open Bairometer and install the bundled statusLine helper from this account's settings."
            )
        }
        guard let snapshot = try snapshotStore.snapshot(providerID: id, accountID: account.accountID) else {
            throw ProviderAdapterError(
                providerID: id,
                message: "Claude Code has not written a managed statusLine snapshot yet.",
                recoverySuggestion: "Install the bundled statusLine helper and use Claude Code once."
            )
        }
        guard snapshot.source == ClaudeCodeSnapshotSource.managedStatusLine else {
            throw ProviderAdapterError(
                providerID: id,
                message: "Claude Code has not written a managed statusLine snapshot for this source yet.",
                recoverySuggestion: "Install the bundled statusLine helper and use Claude Code once."
            )
        }
        return snapshot
    }

    private func usageCLISnapshot(account: ProviderAccount) async throws -> UsageSnapshot {
        do {
            let envelope = try await usageCLIClient.fetchUsage(executablePath: account.executablePath)
            let windows = try ClaudeUsageCLIParser.parse(envelope.result)
            let highestUsage = windows.compactMap(\.usedPercent).max() ?? 0

            return UsageSnapshot(
                providerID: id,
                accountID: account.accountID,
                accountDisplayName: account.displayName,
                displayName: displayName,
                status: highestUsage >= 85 ? .warning : .ok,
                limitWindows: windows,
                lastUpdatedAt: Date(),
                confidence: .live,
                source: ClaudeCodeSnapshotSource.usageCLI,
                warnings: [ClaudeCodeSnapshotSource.usageCLICompatibilityNotice]
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ProviderAdapterError {
            throw error
        } catch let error as ClaudeUsageCLIClientError {
            throw ProviderAdapterError(
                providerID: id,
                message: error.localizedDescription,
                recoverySuggestion: error.recoverySuggestion,
                isTransient: error.isTransient
            )
        } catch let error as ClaudeUsageCLIParserError {
            throw ProviderAdapterError(
                providerID: id,
                message: error.localizedDescription,
                recoverySuggestion: error.recoverySuggestion
            )
        } catch {
            throw ProviderAdapterError(
                providerID: id,
                message: "Claude Code usage limits could not be read.",
                recoverySuggestion: "Try refreshing again or switch this account to Manual or managed statusLine.",
                isTransient: true
            )
        }
    }
}

public struct ClaudeCodeLocalSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let planName: String?
    public let periodLabel: String?
    public let usedPercent: Double?
    public let remainingLabel: String?
    public let resetAt: Date?
    public let limitWindows: [UsageLimitWindow]
    public let lastUpdatedAt: Date

    public init(
        schemaVersion: Int,
        planName: String? = nil,
        periodLabel: String? = nil,
        usedPercent: Double? = nil,
        remainingLabel: String? = nil,
        resetAt: Date? = nil,
        limitWindows: [UsageLimitWindow] = [],
        lastUpdatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.planName = planName
        self.periodLabel = periodLabel
        self.usedPercent = usedPercent
        self.remainingLabel = remainingLabel
        self.resetAt = resetAt
        self.limitWindows = limitWindows
        self.lastUpdatedAt = lastUpdatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
        periodLabel = try container.decodeIfPresent(String.self, forKey: .periodLabel)
        usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
        remainingLabel = try container.decodeIfPresent(String.self, forKey: .remainingLabel)
        resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
        limitWindows = try container.decodeIfPresent([UsageLimitWindow].self, forKey: .limitWindows) ?? []
        lastUpdatedAt = try container.decode(Date.self, forKey: .lastUpdatedAt)
    }
}
