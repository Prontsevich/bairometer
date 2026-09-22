import Foundation

/// Deterministically projects the current percentage-oriented snapshot into contract v1.
///
/// The bridge is intentionally one-way. Native non-percentage metrics must not be
/// fabricated into the legacy dashboard projection.
public struct LegacyUsageSnapshotBridge: Sendable {
    public let surface: ProviderSurface
    public let source: SourceDescriptor
    public let accountContext: AccountContext

    public init(
        surface: ProviderSurface,
        source: SourceDescriptor,
        accountContext: AccountContext
    ) {
        self.surface = surface
        self.source = source
        self.accountContext = accountContext
    }

    public func makeCapacitySnapshot(from snapshot: UsageSnapshot) throws -> CapacitySnapshot {
        let legacyWindows = snapshot.displayLimitWindows
        let windows = legacyWindows.isEmpty
            ? [
                UsageLimitWindow(
                    id: "primary",
                    displayName: snapshot.periodLabel ?? "Usage",
                    usedPercent: snapshot.usedPercent,
                    resetAt: snapshot.resetAt
                )
            ]
            : legacyWindows

        let metrics = windows.map { window in
            makeMetric(from: window, snapshot: snapshot)
        }
        let capacitySnapshot = CapacitySnapshot(
            providerID: snapshot.providerID,
            surfaceID: surface.surfaceID,
            savedAccountID: snapshot.accountID,
            accountContexts: [accountContext],
            observedAt: snapshot.lastUpdatedAt,
            metrics: metrics
        )

        try ProviderContractValidator.validate(
            snapshot: capacitySnapshot,
            surface: surface,
            sources: [source]
        )
        return capacitySnapshot
    }

    private func makeMetric(
        from window: UsageLimitWindow,
        snapshot: UsageSnapshot
    ) -> CapacityMetric {
        let availability: CapacityAvailability
        let values: CapacityValues?
        let derivations: [Derivation]

        if let usedPercent = window.usedPercent,
           let consumed = Decimal(
               string: String(usedPercent),
               locale: Locale(identifier: "en_US_POSIX")
           ) {
            availability = .known
            values = CapacityValues(
                consumed: CapacityValue(value: consumed, origin: .reported),
                remaining: CapacityValue(value: 100 - consumed, origin: .derived)
            )
            derivations = [
                Derivation(
                    kind: .percentComplement,
                    target: .remaining,
                    inputs: [.consumed]
                )
            ]
        } else {
            availability = legacyAvailability(for: snapshot)
            values = nil
            derivations = []
        }

        return CapacityMetric(
            metricID: window.id,
            accountContextID: accountContext.contextID,
            sourceID: source.sourceID,
            capability: "quota-windows",
            displayName: window.displayName,
            availability: availability,
            unit: CapacityUnit(kind: .percent),
            values: values,
            window: CapacityWindow(
                kind: .unknown,
                nextTransition: window.resetAt.map {
                    CapacityTransition(kind: .reset, at: $0)
                }
            ),
            freshness: ObservationFreshness(observedAt: snapshot.lastUpdatedAt),
            confidence: snapshot.confidence,
            derivations: derivations
        )
    }

    private func legacyAvailability(for snapshot: UsageSnapshot) -> CapacityAvailability {
        if snapshot.confidence == .manual {
            return .manual
        }
        if snapshot.status == .unavailable {
            return .unavailable
        }
        return .unknown
    }
}
