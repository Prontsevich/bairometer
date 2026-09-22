import Foundation

public struct MockProviderAdapter: ProviderAdapter {
    public let id = "mock"
    public let displayName = "Mock Provider"
    public let usageURL: URL? = nil
    public let capabilities = ProviderCapabilities(sources: [
        ProviderSourceCapability(
            mode: .manual,
            kind: .manual,
            summary: "Built-in generated data for development and UI checks."
        )
    ])

    public init() {}

    public func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot {
        let now = Date()
        let minute = Calendar.current.component(.minute, from: now)
        let second = Calendar.current.component(.second, from: now)
        let usedPercent = Double((minute * 60 + second) % 100)
        let rollingUsedPercent = Double((minute * 45 + second) % 100)
        let remainingPercent = max(0, 100 - Int(usedPercent.rounded()))
        let rollingRemainingPercent = max(0, 100 - Int(rollingUsedPercent.rounded()))

        return UsageSnapshot(
            providerID: id,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: displayName,
            status: max(usedPercent, rollingUsedPercent) >= 85 ? .warning : .ok,
            planName: "Development",
            periodLabel: "Weekly mock limit",
            usedPercent: usedPercent,
            remainingLabel: "Approx. \(remainingPercent)% remaining",
            resetAt: Calendar.current.date(byAdding: .day, value: 3, to: now),
            limitWindows: [
                UsageLimitWindow(
                    id: "weekly",
                    displayName: "Weekly",
                    usedPercent: usedPercent,
                    remainingLabel: "Approx. \(remainingPercent)% remaining",
                    resetAt: Calendar.current.date(byAdding: .day, value: 3, to: now)
                ),
                UsageLimitWindow(
                    id: "rolling-5-hour",
                    displayName: "5-hour",
                    usedPercent: rollingUsedPercent,
                    remainingLabel: "Approx. \(rollingRemainingPercent)% remaining",
                    resetAt: Calendar.current.date(byAdding: .hour, value: 5, to: now)
                )
            ],
            lastUpdatedAt: now,
            confidence: .localEstimate,
            source: "Generated mock data",
            warnings: max(usedPercent, rollingUsedPercent) >= 85 ? ["Mock usage is close to the limit."] : []
        )
    }
}
