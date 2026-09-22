import Foundation

public enum MiniMaxProviderContract {
    public static let providerID = "minimax"
    public static let surfaceID = "token-plan"
    public static let sourceID = "token-plan-remains-api"
    public static let providerUnitID = "minimax.included-usage"
    public static let unavailableSubscriptionWarning =
        "MiniMax Token Plan subscription is unavailable or expired."

    public static let surface = ProviderSurface(
        providerID: providerID,
        surfaceID: surfaceID,
        displayName: "MiniMax Global Token Plan",
        interactionModel: .subscription,
        regions: [
            RegionDescriptor(regionID: "global", displayName: "Global")
        ],
        accountContextKinds: [.team, .credential],
        capabilities: ["quota-windows", "reset-schedule"]
    )

    public static let source = SourceDescriptor(
        providerID: providerID,
        surfaceID: surfaceID,
        sourceID: sourceID,
        displayName: "MiniMax Token Plan remains API",
        kind: .documentedRemoteAPI,
        authority: .providerReported,
        maturity: .experimental,
        defaultConfidence: .live,
        freshnessPolicy: FreshnessPolicy(kind: .unknown),
        capabilities: ["quota-windows", "reset-schedule"],
        authRequirement: AuthRequirement(
            category: .subscriptionKey,
            privilege: .leastPrivilege,
            storageBoundary: .keychain
        )
    )

    public static let sources = [source]

    public static let reviewedQuotaCategories = try! MiniMaxQuotaCategoryMapping(
        categories: [
            try! MiniMaxReviewedQuotaCategory(
                providerIdentifier: "general",
                stableID: "quota-category-a",
                displayName: "Token Plan capacity A"
            ),
            try! MiniMaxReviewedQuotaCategory(
                providerIdentifier: "video",
                stableID: "quota-category-b",
                displayName: "Token Plan capacity B"
            )
        ]
    )
}

public enum MiniMaxQuotaCategoryMappingError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case invalidEntry
    case duplicateProviderIdentifier
    case duplicateStableID

    public var errorDescription: String? {
        switch self {
        case .invalidEntry:
            "The MiniMax quota category mapping is invalid."
        case .duplicateProviderIdentifier:
            "The MiniMax quota category mapping contains a duplicate provider identifier."
        case .duplicateStableID:
            "The MiniMax quota category mapping contains a duplicate stable identifier."
        }
    }
}

public struct MiniMaxReviewedQuotaCategory:
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    fileprivate let providerIdentifier: String
    public let stableID: String
    public let displayName: String

    public init(
        providerIdentifier: String,
        stableID: String,
        displayName: String
    ) throws {
        guard !providerIdentifier.isEmpty,
              !providerIdentifier.contains("*"),
              Self.isStableID(stableID),
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw MiniMaxQuotaCategoryMappingError.invalidEntry
        }
        self.providerIdentifier = providerIdentifier
        self.stableID = stableID
        self.displayName = displayName
    }

    public var description: String {
        "<redacted MiniMax reviewed quota category: \(stableID)>"
    }

    public var debugDescription: String { description }

    private static func isStableID(_ value: String) -> Bool {
        value.range(
            of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#,
            options: .regularExpression
        ) != nil
    }
}

public struct MiniMaxQuotaCategoryMapping: Sendable {
    private let categoriesByProviderIdentifier: [
        String: MiniMaxReviewedQuotaCategory
    ]

    public init(categories: [MiniMaxReviewedQuotaCategory]) throws {
        var providerIdentifiers = Set<String>()
        var stableIDs = Set<String>()
        var mappedCategories: [String: MiniMaxReviewedQuotaCategory] = [:]

        for category in categories {
            guard providerIdentifiers.insert(category.providerIdentifier).inserted else {
                throw MiniMaxQuotaCategoryMappingError.duplicateProviderIdentifier
            }
            guard stableIDs.insert(category.stableID).inserted else {
                throw MiniMaxQuotaCategoryMappingError.duplicateStableID
            }
            mappedCategories[category.providerIdentifier] = category
        }
        categoriesByProviderIdentifier = mappedCategories
    }

    func reviewedCategory(
        forProviderIdentifier providerIdentifier: String
    ) -> MiniMaxReviewedQuotaCategory? {
        categoriesByProviderIdentifier[providerIdentifier]
    }
}

public struct MiniMaxProviderAdapter: ProviderAdapter {
    public let id = MiniMaxProviderContract.providerID
    public let displayName = "MiniMax"
    public let usageURL = URL(
        string: "https://platform.minimax.io/docs/token-plan/intro"
    )
    public let capabilities = ProviderCapabilities(sources: [
        ProviderSourceCapability(
            mode: .miniMaxTokenPlan,
            kind: .live,
            summary: "Independent Global Token Plan capacity."
        )
    ])

    private let refreshCoordinator: any MiniMaxAccountRefreshing

    public init(
        refreshCoordinator: any MiniMaxAccountRefreshing =
            UnavailableMiniMaxRefreshCoordinator()
    ) {
        self.refreshCoordinator = refreshCoordinator
    }

    public func fetchSnapshot(
        account: ProviderAccount
    ) async throws -> UsageSnapshot {
        guard account.providerID == id,
              account.sourceMode == .miniMaxTokenPlan else {
            throw ProviderAdapterError(
                providerID: id,
                message: "MiniMax source configuration is invalid."
            )
        }

        let result = try await refreshCoordinator.refresh(account: account)
        let status: UsageStatus
        if result.successfulSourceCount == 0 {
            status = .error
        } else if result.failedSourceCount > 0
            || result.deferredSourceCount > 0
            || result.suppressedSourceCount > 0
            || result.hasMappingDiagnostics {
            status = .warning
        } else {
            status = .ok
        }

        var warnings: [String] = []
        if result.failedSourceCount > 0 {
            warnings.append(
                result.failureDiagnosticCode == .insufficientPrivilege
                    ? MiniMaxProviderContract.unavailableSubscriptionWarning
                    : "MiniMax refresh failed; the last valid native observation was preserved."
            )
        }
        if result.deferredSourceCount > 0 {
            warnings.append(
                "MiniMax is waiting for the next eligible refresh."
            )
        }
        if result.suppressedSourceCount > 0 {
            warnings.append(
                "A late MiniMax result was discarded after configuration changed."
            )
        }
        if result.hasMappingDiagnostics {
            warnings.append(
                "MiniMax returned an unrecognized quota category that was ignored."
            )
        }

        return UsageSnapshot(
            providerID: id,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: displayName,
            status: status,
            remainingLabel: result.successfulSourceCount > 0
                ? "Native MiniMax Token Plan capacity stored"
                : "MiniMax Token Plan capacity unavailable",
            lastUpdatedAt: result.completedAt,
            confidence: result.successfulSourceCount > 0 ? .live : .unknown,
            source: "MiniMax documented Global Token Plan API",
            warnings: warnings
        )
    }

    public func invalidateAccount(accountID: String) {
        refreshCoordinator.invalidateAccount(
            providerID: id,
            accountID: accountID
        )
    }
}
