import Foundation

public enum OpenRouterProviderContract {
    public static let providerID = "openrouter"
    public static let surfaceID = "api-account"
    public static let currentKeySourceID = "current-key-api"
    public static let managementSourceID = "management-api"
    public static let maximumAgeSeconds: UInt = 600

    public static let surface = ProviderSurface(
        providerID: providerID,
        surfaceID: surfaceID,
        displayName: "OpenRouter API account",
        interactionModel: .api,
        regions: [
            RegionDescriptor(regionID: "global", displayName: "Global")
        ],
        accountContextKinds: [.personal, .organization, .credential],
        capabilities: ["credits", "spend"]
    )

    public static let currentKeySource = SourceDescriptor(
        providerID: providerID,
        surfaceID: surfaceID,
        sourceID: currentKeySourceID,
        displayName: "OpenRouter current API key",
        kind: .documentedRemoteAPI,
        authority: .providerReported,
        maturity: .stable,
        defaultConfidence: .live,
        freshnessPolicy: FreshnessPolicy(
            kind: .maximumAge,
            maxAgeSeconds: maximumAgeSeconds
        ),
        capabilities: ["credits", "spend"],
        authRequirement: AuthRequirement(
            category: .apiKey,
            privilege: .leastPrivilege,
            storageBoundary: .keychain
        )
    )

    public static let managementSource = SourceDescriptor(
        providerID: providerID,
        surfaceID: surfaceID,
        sourceID: managementSourceID,
        displayName: "OpenRouter account credits",
        kind: .documentedRemoteAPI,
        authority: .providerReported,
        maturity: .stable,
        defaultConfidence: .live,
        freshnessPolicy: FreshnessPolicy(
            kind: .maximumAge,
            maxAgeSeconds: maximumAgeSeconds
        ),
        capabilities: ["credits"],
        authRequirement: AuthRequirement(
            category: .apiKey,
            privilege: .elevated,
            storageBoundary: .keychain
        )
    )

    public static let sources = [currentKeySource, managementSource]
}

public struct OpenRouterProviderAdapter: ProviderAdapter {
    public let id = OpenRouterProviderContract.providerID
    public let displayName = "OpenRouter"
    public let usageURL = URL(string: "https://openrouter.ai/settings/credits")
    public let capabilities = ProviderCapabilities(sources: [
        ProviderSourceCapability(
            mode: .openRouterAPI,
            kind: .live,
            summary: "Independent API-key capacity and optional account credits."
        )
    ])

    private let refreshCoordinator: any OpenRouterAccountRefreshing

    public init(
        refreshCoordinator: any OpenRouterAccountRefreshing =
            UnavailableOpenRouterRefreshCoordinator()
    ) {
        self.refreshCoordinator = refreshCoordinator
    }

    public func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot {
        guard account.providerID == id,
              account.sourceMode == .openRouterAPI else {
            throw ProviderAdapterError(
                providerID: id,
                message: "OpenRouter source configuration is invalid."
            )
        }

        let result = try await refreshCoordinator.refresh(account: account)
        let status: UsageStatus
        if result.successfulSourceCount == 0 {
            status = .error
        } else if result.failedSourceCount > 0
            || result.deferredSourceCount > 0
            || result.suppressedSourceCount > 0 {
            status = .warning
        } else {
            status = .ok
        }

        var warnings: [String] = []
        if result.failedSourceCount > 0 {
            warnings.append(
                "One or more OpenRouter credential sources failed; last valid native observations were preserved."
            )
        }
        if result.deferredSourceCount > 0 {
            warnings.append(
                "One or more OpenRouter credential sources are waiting for their next eligible refresh."
            )
        }
        if result.suppressedSourceCount > 0 {
            warnings.append(
                "A late OpenRouter credential result was discarded after configuration changed."
            )
        }
        if result.configuredSourceCount == 0 {
            warnings.append("No enabled OpenRouter credential source is configured.")
        }

        return UsageSnapshot(
            providerID: id,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: displayName,
            status: status,
            remainingLabel: result.configuredSourceCount == 0
                ? "No enabled OpenRouter credentials"
                : "Native OpenRouter capacity stored",
            lastUpdatedAt: result.completedAt,
            confidence: result.successfulSourceCount > 0 ? .live : .unknown,
            source: "OpenRouter documented APIs",
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
