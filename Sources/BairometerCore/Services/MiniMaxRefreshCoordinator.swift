import Foundation

public struct MiniMaxRefreshPolicy: Equatable, Sendable {
    public let initialBackoff: TimeInterval
    public let maximumBackoff: TimeInterval

    public init(
        initialBackoff: TimeInterval = 30,
        maximumBackoff: TimeInterval = 900
    ) {
        let clampedInitialBackoff = max(0, initialBackoff)
        self.initialBackoff = clampedInitialBackoff
        self.maximumBackoff = max(clampedInitialBackoff, maximumBackoff)
    }

    func retryDate(
        after failureCount: Int,
        retryAfter: MiniMaxRetryAfter?,
        now: Date
    ) -> Date {
        if let retryAfter {
            switch retryAfter {
            case let .date(date):
                return max(now, date)
            case let .seconds(seconds):
                let delay = TimeInterval(seconds)
                let maximumSafeDelay = Date.distantFuture.timeIntervalSince(now)
                guard delay.isFinite, delay < maximumSafeDelay else {
                    return .distantFuture
                }
                return now.addingTimeInterval(delay)
            }
        }

        let exponent = min(max(0, failureCount), 20)
        let delay = min(
            maximumBackoff,
            initialBackoff * pow(2, Double(exponent))
        )
        return now.addingTimeInterval(delay)
    }
}

public struct MiniMaxAccountRefreshResult: Equatable, Sendable {
    public let snapshot: CapacitySnapshot?
    public let completedAt: Date
    public let successfulSourceCount: Int
    public let failedSourceCount: Int
    public let deferredSourceCount: Int
    public let suppressedSourceCount: Int
    public let configuredSourceCount: Int
    public let hasMappingDiagnostics: Bool
    public let failureDiagnosticCode: CredentialContextDiagnosticCode?

    public init(
        snapshot: CapacitySnapshot?,
        completedAt: Date,
        successfulSourceCount: Int,
        failedSourceCount: Int,
        deferredSourceCount: Int,
        suppressedSourceCount: Int,
        configuredSourceCount: Int,
        hasMappingDiagnostics: Bool,
        failureDiagnosticCode: CredentialContextDiagnosticCode? = nil
    ) {
        self.snapshot = snapshot
        self.completedAt = completedAt
        self.successfulSourceCount = successfulSourceCount
        self.failedSourceCount = failedSourceCount
        self.deferredSourceCount = deferredSourceCount
        self.suppressedSourceCount = suppressedSourceCount
        self.configuredSourceCount = configuredSourceCount
        self.hasMappingDiagnostics = hasMappingDiagnostics
        self.failureDiagnosticCode = failureDiagnosticCode
    }
}

public protocol MiniMaxAccountRefreshing: Sendable {
    func refresh(account: ProviderAccount) async throws -> MiniMaxAccountRefreshResult
    func invalidateAccount(providerID: String, accountID: String)
}

public actor MiniMaxRefreshCoordinator: MiniMaxAccountRefreshing {
    private let credentialStore: AccountCredentialStore
    private let capacityStore: any NativeCapacitySnapshotStore
    private let diagnosticStore: any SourceDiagnosticStore
    private let client: any MiniMaxAPIClient
    private let policy: MiniMaxRefreshPolicy
    private let now: @Sendable () -> Date
    private let postFetchCheckpoint: @Sendable () async -> Void
    private nonisolated let generations = MiniMaxRefreshGenerationStore()

    public init(
        credentialStore: AccountCredentialStore,
        capacityStore: any NativeCapacitySnapshotStore,
        diagnosticStore: any SourceDiagnosticStore,
        client: any MiniMaxAPIClient,
        policy: MiniMaxRefreshPolicy = MiniMaxRefreshPolicy(),
        now: @escaping @Sendable () -> Date = Date.init,
        postFetchCheckpoint: @escaping @Sendable () async -> Void = {}
    ) {
        self.credentialStore = credentialStore
        self.capacityStore = capacityStore
        self.diagnosticStore = diagnosticStore
        self.client = client
        self.policy = policy
        self.now = now
        self.postFetchCheckpoint = postFetchCheckpoint
    }

    public nonisolated func invalidateAccount(
        providerID: String,
        accountID: String
    ) {
        generations.invalidate(
            Self.accountKey(providerID: providerID, accountID: accountID)
        )
    }

    public func refresh(
        account: ProviderAccount
    ) async throws -> MiniMaxAccountRefreshResult {
        guard account.providerID == MiniMaxProviderContract.providerID,
              account.sourceMode == .miniMaxTokenPlan,
              account.isEnabled else {
            throw ProviderAdapterError(
                providerID: account.providerID,
                message: "MiniMax account is unavailable."
            )
        }

        let accountKey = Self.accountKey(
            providerID: account.providerID,
            accountID: account.accountID
        )
        let generationStore = generations
        let generation = generationStore.prepare(accountKey)
        let task = Task {
            try await self.performRefresh(
                account: account,
                accountKey: accountKey,
                generation: generation
            )
        }
        generationStore.install(task, for: accountKey, generation: generation)
        defer {
            generationStore.finish(accountKey, generation: generation)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performRefresh(
        account: ProviderAccount,
        accountKey: String,
        generation: UInt64
    ) async throws -> MiniMaxAccountRefreshResult {
        let generationStore = generations
        let configuration = try loadConfiguration(account: account)
        guard try capacityStore.isCurrentSource(configuration.slot) else {
            return try result(
                account: account,
                completedAt: now(),
                suppressedSourceCount: 1
            )
        }
        let refreshState = try credentialStore.loadRefreshStates(
            providerID: account.providerID,
            accountID: account.accountID
        ).first { $0.slotID == configuration.slot.slotID }

        if let retryNotBefore = refreshState?.retryNotBefore,
           retryNotBefore > now() {
            do {
                try capacityStore.validateDeferredSource(
                    slot: configuration.slot,
                    generationValidator: {
                        generationStore.isCurrent(generation, for: accountKey)
                    }
                )
                return try result(
                    account: account,
                    completedAt: now(),
                    deferredSourceCount: 1
                )
            } catch NativeCapacityStoreError.accountUnavailable,
                    NativeCapacityStoreError.sourceIdentityChanged {
                return try result(
                    account: account,
                    completedAt: now(),
                    suppressedSourceCount: 1
                )
            }
        }

        let attemptedAt = now()
        let capacityResult: MiniMaxCapacityResult
        do {
            try Task.checkCancellation()
            let secret = try credentialStore.readCredential(
                providerID: configuration.slot.providerID,
                accountID: configuration.slot.accountID,
                slotID: configuration.slot.slotID
            )
            let credential = try MiniMaxSubscriptionKey(
                slot: configuration.slot,
                secret: secret
            )
            capacityResult = try await client.fetchTokenPlanCapacity(
                credential: credential
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled
                || (error as? MiniMaxAPIClientError) == .cancelled {
                throw CancellationError()
            }
            return try recordFailure(
                error,
                account: account,
                slot: configuration.slot,
                previousFailureCount: refreshState?.consecutiveFailureCount ?? 0,
                attemptedAt: attemptedAt,
                accountKey: accountKey,
                generation: generation
            )
        }

        let completedAt = now()
        await postFetchCheckpoint()
        try Task.checkCancellation()
        if Self.isUnknownQuotaCategoryOnly(capacityResult) {
            return try recordUnknownQuotaCategoryOnlyResult(
                account: account,
                configuration: configuration,
                completedAt: completedAt,
                accountKey: accountKey,
                generation: generation
            )
        }

        let metrics: [CapacityMetric]
        do {
            metrics = try Self.metricsBoundToTeam(
                capacityResult,
                slot: configuration.slot,
                teamContextID: configuration.teamContext.contextID
            )
        } catch {
            return try recordFailure(
                error,
                account: account,
                slot: configuration.slot,
                previousFailureCount: refreshState?.consecutiveFailureCount ?? 0,
                attemptedAt: attemptedAt,
                completedAt: completedAt,
                accountKey: accountKey,
                generation: generation
            )
        }

        do {
            let performed = try generationStore.performIfCurrent(
                generation,
                for: accountKey
            ) {
                _ = try capacityStore.recordSourceSuccess(
                    CapacitySourceMutation(
                        providerID: account.providerID,
                        accountID: account.accountID,
                        contextID: configuration.teamContext.contextID,
                        sourceID: MiniMaxProviderContract.sourceID,
                        accountContexts: configuration.contractContexts,
                        metrics: metrics,
                        completedAt: completedAt,
                        identityExpectation: .slotWithDirectTeamParent(
                            slot: configuration.slot,
                            teamContextID: configuration.teamContext.contextID
                        ),
                        generationValidator: {
                            generationStore.isCurrent(generation, for: accountKey)
                        }
                    ),
                    control: NativeCapacityOutcomeControl(
                        attemptedAt: attemptedAt,
                        completedAt: completedAt,
                        generationValidator: {
                            generationStore.isCurrent(generation, for: accountKey)
                        }
                    ),
                    surface: MiniMaxProviderContract.surface,
                    sources: MiniMaxProviderContract.sources
                )
                try diagnosticStore.replaceRefreshDiagnostics(
                    providerID: account.providerID,
                    accountID: account.accountID,
                    occurredAt: completedAt,
                    messages: capacityResult.diagnostics.isEmpty
                        ? []
                        : ["MiniMax ignored an unrecognized quota category."]
                )
            }
            guard performed else {
                return try result(
                    account: account,
                    completedAt: completedAt,
                    suppressedSourceCount: 1
                )
            }
        } catch NativeCapacityStoreError.accountUnavailable,
                NativeCapacityStoreError.sourceIdentityChanged {
            return try result(
                account: account,
                completedAt: completedAt,
                suppressedSourceCount: 1
            )
        }

        return try result(
            account: account,
            completedAt: completedAt,
            successfulSourceCount: 1,
            hasMappingDiagnostics: !capacityResult.diagnostics.isEmpty
        )
    }

    private func recordUnknownQuotaCategoryOnlyResult(
        account: ProviderAccount,
        configuration: MiniMaxRefreshConfiguration,
        completedAt: Date,
        accountKey: String,
        generation: UInt64
    ) throws -> MiniMaxAccountRefreshResult {
        let generationStore = generations
        do {
            let recorded = try generationStore.performIfCurrent(
                generation,
                for: accountKey
            ) {
                try capacityStore.validateDeferredSource(
                    slot: configuration.slot,
                    generationValidator: {
                        generationStore.isCurrent(generation, for: accountKey)
                    }
                )
                let currentConfiguration: MiniMaxRefreshConfiguration
                do {
                    currentConfiguration = try loadConfiguration(account: account)
                } catch {
                    throw NativeCapacityStoreError.sourceIdentityChanged
                }
                guard currentConfiguration.slot == configuration.slot,
                      currentConfiguration.teamContext.contextID
                        == configuration.teamContext.contextID else {
                    throw NativeCapacityStoreError.sourceIdentityChanged
                }
                try diagnosticStore.replaceRefreshDiagnostics(
                    providerID: account.providerID,
                    accountID: account.accountID,
                    occurredAt: completedAt,
                    messages: [
                        "MiniMax ignored an unrecognized quota category."
                    ]
                )
            }
            guard recorded else {
                return try result(
                    account: account,
                    completedAt: completedAt,
                    suppressedSourceCount: 1
                )
            }
            return try result(
                account: account,
                completedAt: completedAt,
                hasMappingDiagnostics: true
            )
        } catch NativeCapacityStoreError.accountUnavailable,
                NativeCapacityStoreError.sourceIdentityChanged {
            return try result(
                account: account,
                completedAt: completedAt,
                suppressedSourceCount: 1
            )
        }
    }

    private func loadConfiguration(
        account: ProviderAccount
    ) throws -> MiniMaxRefreshConfiguration {
        let contexts = try credentialStore.loadContexts(
            providerID: account.providerID,
            accountID: account.accountID
        )
        let roots = contexts.filter { $0.parentContextID == nil }
        guard roots.count == 1,
              let teamContext = roots.first,
              teamContext.providerID == account.providerID,
              teamContext.accountID == account.accountID,
              teamContext.kind == .team,
              teamContext.regionID == "global"
        else {
            throw ProviderAdapterError(
                providerID: account.providerID,
                message: "MiniMax account contexts are invalid."
            )
        }

        let credentialContexts = try credentialStore.loadCredentialContexts(
            providerID: account.providerID,
            accountID: account.accountID
        )
        let activeContexts = credentialContexts.filter {
            $0.slot.isEnabled && $0.slot.lifecycleState == .active
        }
        guard activeContexts.count == 1,
              let source = activeContexts.first,
              source.slot.providerID == account.providerID,
              source.slot.accountID == account.accountID,
              source.slot.role == .ordinary,
              source.context.kind == .credential,
              source.context.parentContextID == teamContext.contextID,
              source.context.regionID == teamContext.regionID
        else {
            throw ProviderAdapterError(
                providerID: account.providerID,
                message: "MiniMax requires exactly one enabled Subscription Key."
            )
        }

        return MiniMaxRefreshConfiguration(
            teamContext: teamContext,
            slot: source.slot,
            contractContexts: contexts.map(\.contractContext)
        )
    }

    private func recordFailure(
        _ error: Error,
        account: ProviderAccount,
        slot: ProviderCredentialSlot,
        previousFailureCount: Int,
        attemptedAt: Date,
        completedAt: Date? = nil,
        accountKey: String,
        generation: UInt64
    ) throws -> MiniMaxAccountRefreshResult {
        let generationStore = generations
        let failureCompletedAt = completedAt ?? now()
        let failure = Self.failureProjection(
            error,
            previousFailureCount: previousFailureCount,
            completedAt: failureCompletedAt,
            policy: policy
        )
        do {
            let recorded = try generationStore.performIfCurrent(
                generation,
                for: accountKey
            ) {
                try capacityStore.recordSourceFailure(
                    slot: slot,
                    code: failure.code,
                    retryNotBefore: failure.retryNotBefore,
                    control: NativeCapacityOutcomeControl(
                        attemptedAt: attemptedAt,
                        completedAt: failureCompletedAt,
                        generationValidator: {
                            generationStore.isCurrent(generation, for: accountKey)
                        }
                    )
                )
            }
            guard recorded else {
                return try result(
                    account: account,
                    completedAt: failureCompletedAt,
                    suppressedSourceCount: 1
                )
            }
            return try result(
                account: account,
                completedAt: failureCompletedAt,
                failedSourceCount: 1,
                failureDiagnosticCode: failure.code
            )
        } catch NativeCapacityStoreError.accountUnavailable,
                NativeCapacityStoreError.sourceIdentityChanged {
            return try result(
                account: account,
                completedAt: failureCompletedAt,
                suppressedSourceCount: 1
            )
        }
    }

    private func result(
        account: ProviderAccount,
        completedAt: Date,
        successfulSourceCount: Int = 0,
        failedSourceCount: Int = 0,
        deferredSourceCount: Int = 0,
        suppressedSourceCount: Int = 0,
        hasMappingDiagnostics: Bool = false,
        failureDiagnosticCode: CredentialContextDiagnosticCode? = nil
    ) throws -> MiniMaxAccountRefreshResult {
        try Task.checkCancellation()
        return MiniMaxAccountRefreshResult(
            snapshot: try capacityStore.load(
                providerID: account.providerID,
                accountID: account.accountID,
                surface: MiniMaxProviderContract.surface,
                sources: MiniMaxProviderContract.sources
            ),
            completedAt: completedAt,
            successfulSourceCount: successfulSourceCount,
            failedSourceCount: failedSourceCount,
            deferredSourceCount: deferredSourceCount,
            suppressedSourceCount: suppressedSourceCount,
            configuredSourceCount: 1,
            hasMappingDiagnostics: hasMappingDiagnostics,
            failureDiagnosticCode: failureDiagnosticCode
        )
    }

    private static func metricsBoundToTeam(
        _ result: MiniMaxCapacityResult,
        slot: ProviderCredentialSlot,
        teamContextID: String
    ) throws -> [CapacityMetric] {
        let metricIDs = Set(result.metrics.map(\.metricID))
        guard !result.metrics.isEmpty,
              metricIDs.count == result.metrics.count,
              result.metrics.allSatisfy({
                  $0.accountContextID == slot.contextID
                      && $0.sourceID == MiniMaxProviderContract.sourceID
                      && $0.capability == "quota-windows"
                      && $0.unit == CapacityUnit(kind: .percent)
                      && $0.freshness.observedAt == result.observedAt
                      && $0.confidence == .live
              })
        else {
            throw MiniMaxRefreshCoordinatorError.invalidCapacity
        }

        return try result.metrics.map {
            let displayName: String
            switch $0.window.kind {
            case .rolling:
                displayName = "Included usage — current rolling window"
            case .fixed:
                displayName = "Included usage — weekly window"
            default:
                throw MiniMaxRefreshCoordinatorError.invalidCapacity
            }
            return CapacityMetric(
                metricID: $0.metricID,
                accountContextID: teamContextID,
                sourceID: $0.sourceID,
                capability: $0.capability,
                displayName: displayName,
                availability: $0.availability,
                conditions: $0.conditions,
                unit: $0.unit,
                values: $0.values,
                window: $0.window,
                freshness: $0.freshness,
                confidence: $0.confidence,
                derivations: $0.derivations
            )
        }
    }

    private static func isUnknownQuotaCategoryOnly(
        _ result: MiniMaxCapacityResult
    ) -> Bool {
        result.metrics.isEmpty
            && !result.diagnostics.isEmpty
            && result.diagnostics.allSatisfy {
                $0.code == .unknownQuotaCategory
            }
    }

    private static func failureProjection(
        _ error: Error,
        previousFailureCount: Int,
        completedAt: Date,
        policy: MiniMaxRefreshPolicy
    ) -> MiniMaxFailureProjection {
        switch error {
        case MiniMaxAPIClientError.authenticationFailure:
            MiniMaxFailureProjection(code: .authentication)
        case MiniMaxAPIClientError.unavailableSubscription:
            MiniMaxFailureProjection(code: .insufficientPrivilege)
        case let MiniMaxAPIClientError.throttled(retryAfter):
            MiniMaxFailureProjection(
                code: .throttled,
                retryNotBefore: policy.retryDate(
                    after: previousFailureCount,
                    retryAfter: retryAfter,
                    now: completedAt
                )
            )
        case let MiniMaxAPIClientError.serviceUnavailable(retryAfter):
            MiniMaxFailureProjection(
                code: .transientFailure,
                retryNotBefore: policy.retryDate(
                    after: previousFailureCount,
                    retryAfter: retryAfter,
                    now: completedAt
                )
            )
        case MiniMaxAPIClientError.timedOut,
             MiniMaxAPIClientError.transportFailure,
             MiniMaxAPIClientError.serverFailure:
            MiniMaxFailureProjection(
                code: .transientFailure,
                retryNotBefore: policy.retryDate(
                    after: previousFailureCount,
                    retryAfter: nil,
                    now: completedAt
                )
            )
        case CredentialStoreError.credentialDisabled:
            MiniMaxFailureProjection(code: .credentialDisabled)
        case CredentialStoreError.credentialMissing,
             CredentialStoreError.slotNotFound,
             CredentialStoreError.contextNotFound:
            MiniMaxFailureProjection(code: .credentialMissing)
        default:
            MiniMaxFailureProjection(code: .transientFailure)
        }
    }

    private static func accountKey(providerID: String, accountID: String) -> String {
        "\(providerID):\(accountID)"
    }
}

public struct UnavailableMiniMaxRefreshCoordinator: MiniMaxAccountRefreshing {
    public init() {}

    public func refresh(
        account: ProviderAccount
    ) async throws -> MiniMaxAccountRefreshResult {
        throw ProviderAdapterError(
            providerID: account.providerID,
            message: "MiniMax credential refresh is unavailable."
        )
    }

    public func invalidateAccount(providerID: String, accountID: String) {}
}

private struct MiniMaxRefreshConfiguration: Sendable {
    let teamContext: ProviderAccountContextConfiguration
    let slot: ProviderCredentialSlot
    let contractContexts: [AccountContext]
}

private enum MiniMaxRefreshCoordinatorError: Error {
    case invalidCapacity
}

private struct MiniMaxFailureProjection: Sendable {
    let code: CredentialContextDiagnosticCode
    let retryNotBefore: Date?

    init(
        code: CredentialContextDiagnosticCode,
        retryNotBefore: Date? = nil
    ) {
        self.code = code
        self.retryNotBefore = retryNotBefore
    }
}

private final class MiniMaxRefreshGenerationStore: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var generations: [String: UInt64] = [:]
    private var activeTasks: [
        String: (UInt64, Task<MiniMaxAccountRefreshResult, Error>)
    ] = [:]

    func prepare(_ accountKey: String) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        activeTasks.removeValue(forKey: accountKey)?.1.cancel()
        let generation = generations[accountKey, default: 0] &+ 1
        generations[accountKey] = generation
        return generation
    }

    func install(
        _ task: Task<MiniMaxAccountRefreshResult, Error>,
        for accountKey: String,
        generation: UInt64
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard generations[accountKey] == generation else {
            task.cancel()
            return
        }
        activeTasks[accountKey] = (generation, task)
    }

    func finish(_ accountKey: String, generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if activeTasks[accountKey]?.0 == generation {
            activeTasks.removeValue(forKey: accountKey)
        }
    }

    func invalidate(_ accountKey: String) {
        lock.lock()
        defer { lock.unlock() }
        generations[accountKey, default: 0] &+= 1
        activeTasks.removeValue(forKey: accountKey)?.1.cancel()
    }

    func isCurrent(_ generation: UInt64, for accountKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generations[accountKey] == generation
    }

    func performIfCurrent(
        _ generation: UInt64,
        for accountKey: String,
        _ body: () throws -> Void
    ) rethrows -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generations[accountKey] == generation else {
            return false
        }
        try body()
        return true
    }
}
