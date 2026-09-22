import Foundation

public struct OpenRouterRefreshPolicy: Equatable, Sendable {
    public let maximumConcurrentSources: Int
    public let initialBackoff: TimeInterval
    public let maximumBackoff: TimeInterval

    public init(
        maximumConcurrentSources: Int = 4,
        initialBackoff: TimeInterval = 30,
        maximumBackoff: TimeInterval = 900
    ) {
        self.maximumConcurrentSources = max(1, maximumConcurrentSources)
        self.initialBackoff = max(0, initialBackoff)
        self.maximumBackoff = max(initialBackoff, maximumBackoff)
    }

    func retryDate(
        after failureCount: Int,
        retryAfter: OpenRouterRetryAfter?,
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

public struct OpenRouterAccountRefreshResult: Equatable, Sendable {
    public let snapshot: CapacitySnapshot?
    public let completedAt: Date
    public let successfulSourceCount: Int
    public let failedSourceCount: Int
    public let deferredSourceCount: Int
    public let suppressedSourceCount: Int
    public let configuredSourceCount: Int
    public let lastUsableObservationAt: Date?

    public init(
        snapshot: CapacitySnapshot?,
        completedAt: Date,
        successfulSourceCount: Int,
        failedSourceCount: Int,
        deferredSourceCount: Int,
        suppressedSourceCount: Int,
        configuredSourceCount: Int,
        lastUsableObservationAt: Date? = nil
    ) {
        self.snapshot = snapshot
        self.completedAt = completedAt
        self.successfulSourceCount = successfulSourceCount
        self.failedSourceCount = failedSourceCount
        self.deferredSourceCount = deferredSourceCount
        self.suppressedSourceCount = suppressedSourceCount
        self.configuredSourceCount = configuredSourceCount
        self.lastUsableObservationAt = lastUsableObservationAt
    }
}

public protocol OpenRouterAccountRefreshing: Sendable {
    func refresh(account: ProviderAccount) async throws -> OpenRouterAccountRefreshResult
    func invalidateAccount(providerID: String, accountID: String)
}

public actor OpenRouterRefreshCoordinator: OpenRouterAccountRefreshing {
    private let credentialStore: AccountCredentialStore
    private let capacityStore: any NativeCapacitySnapshotStore
    private let client: any OpenRouterAPIClient
    private let policy: OpenRouterRefreshPolicy
    private let now: @Sendable () -> Date
    private nonisolated let generations = OpenRouterRefreshGenerationStore()

    public init(
        credentialStore: AccountCredentialStore,
        capacityStore: any NativeCapacitySnapshotStore,
        client: any OpenRouterAPIClient = URLSessionOpenRouterAPIClient(),
        policy: OpenRouterRefreshPolicy = OpenRouterRefreshPolicy(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentialStore = credentialStore
        self.capacityStore = capacityStore
        self.client = client
        self.policy = policy
        self.now = now
    }

    public nonisolated func invalidateAccount(
        providerID: String,
        accountID: String
    ) {
        let key = Self.accountKey(providerID: providerID, accountID: accountID)
        generations.invalidate(key)
    }

    public func refresh(
        account: ProviderAccount
    ) async throws -> OpenRouterAccountRefreshResult {
        guard account.providerID == OpenRouterProviderContract.providerID,
              account.isEnabled else {
            throw ProviderAdapterError(
                providerID: account.providerID,
                message: "OpenRouter account is unavailable."
            )
        }
        let accountKey = Self.accountKey(
            providerID: account.providerID,
            accountID: account.accountID
        )
        let generationStore = generations
        let (generation, limiter) = generationStore.prepare(
            accountKey,
            maximumPermits: policy.maximumConcurrentSources
        )
        let task = Task {
            try await self.performRefresh(
                account: account,
                accountKey: accountKey,
                generation: generation,
                limiter: limiter
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
        generation: UInt64,
        limiter: OpenRouterAccountRequestLimiter
    ) async throws -> OpenRouterAccountRefreshResult {
        let generationStore = generations
        let contexts = try credentialStore.loadContexts(
            providerID: account.providerID,
            accountID: account.accountID
        )
        let contractContexts = contexts.map(\.contractContext)
        guard let rootContext = contractContexts.first(where: {
            $0.parentContextID == nil
        }), contractContexts.filter({ $0.parentContextID == nil }).count == 1 else {
            throw ProviderAdapterError(
                providerID: account.providerID,
                message: "OpenRouter account contexts are invalid."
            )
        }

        let credentialContexts = try credentialStore.loadCredentialContexts(
            providerID: account.providerID,
            accountID: account.accountID
        )
        let activeSources = credentialContexts
            .map(\.slot)
            .filter { $0.isEnabled && $0.lifecycleState == .active }
            .map { SourceWorkItem(slot: $0) }
        let refreshStates = Dictionary(
            uniqueKeysWithValues: try credentialStore.loadRefreshStates(
                providerID: account.providerID,
                accountID: account.accountID
            ).map { ($0.slotID, $0) }
        )
        let workItems = activeSources.map {
            $0.withRefreshState(refreshStates[$0.slot.slotID])
        }

        let outcomes = await Self.fetch(
            workItems,
            maximumConcurrency: policy.maximumConcurrentSources,
            credentialStore: credentialStore,
            client: client,
            limiter: limiter,
            now: now
        )
        try Task.checkCancellation()

        var successfulSourceCount = 0
        var failedSourceCount = 0
        var deferredSourceCount = 0
        var suppressedSourceCount = 0

        for outcome in outcomes {
            guard generationStore.isCurrent(generation, for: accountKey) else {
                suppressedSourceCount += 1
                continue
            }

            switch outcome {
            case let .success(item, metrics, attemptedAt, completedAt):
                do {
                    let performed = try generationStore.performIfCurrent(
                        generation,
                        for: accountKey
                    ) {
                        _ = try capacityStore.recordSourceSuccess(
                            CapacitySourceMutation(
                                providerID: account.providerID,
                                accountID: account.accountID,
                                contextID: item.slot.contextID,
                                sourceID: item.sourceID,
                                accountContexts: contractContexts,
                                metrics: metrics,
                                completedAt: completedAt,
                                identityExpectation: .slot(item.slot),
                                generationValidator: {
                                    generationStore.isCurrent(
                                        generation,
                                        for: accountKey
                                    )
                                }
                            ),
                            control: NativeCapacityOutcomeControl(
                                attemptedAt: attemptedAt,
                                completedAt: completedAt,
                                generationValidator: {
                                    generationStore.isCurrent(
                                        generation,
                                        for: accountKey
                                    )
                                }
                            ),
                            surface: OpenRouterProviderContract.surface,
                            sources: OpenRouterProviderContract.sources
                        )
                    }
                    guard performed else {
                        suppressedSourceCount += 1
                        continue
                    }
                    successfulSourceCount += 1
                } catch NativeCapacityStoreError.accountUnavailable,
                        NativeCapacityStoreError.sourceIdentityChanged {
                    suppressedSourceCount += 1
                } catch {
                    failedSourceCount += 1
                }

            case let .failure(item, error, attemptedAt, completedAt):
                do {
                    let recorded = try generationStore.performIfCurrent(
                        generation,
                        for: accountKey
                    ) {
                        let failure = Self.failureProjection(
                            error,
                            previousFailureCount:
                                item.refreshState?.consecutiveFailureCount ?? 0,
                            completedAt: completedAt,
                            policy: policy
                        )
                        try capacityStore.recordSourceFailure(
                            slot: item.slot,
                            code: failure.code,
                            retryNotBefore: failure.retryNotBefore,
                            control: NativeCapacityOutcomeControl(
                                attemptedAt: attemptedAt,
                                completedAt: completedAt,
                                generationValidator: {
                                    generationStore.isCurrent(
                                        generation,
                                        for: accountKey
                                    )
                                }
                            )
                        )
                    }
                    guard recorded else {
                        suppressedSourceCount += 1
                        continue
                    }
                    failedSourceCount += 1
                } catch NativeCapacityStoreError.accountUnavailable,
                        NativeCapacityStoreError.sourceIdentityChanged {
                    suppressedSourceCount += 1
                }

            case let .deferred(item):
                do {
                    try capacityStore.validateDeferredSource(
                        slot: item.slot,
                        generationValidator: {
                            generationStore.isCurrent(
                                generation,
                                for: accountKey
                            )
                        }
                    )
                    deferredSourceCount += 1
                } catch NativeCapacityStoreError.accountUnavailable,
                        NativeCapacityStoreError.sourceIdentityChanged {
                    suppressedSourceCount += 1
                }

            case .cancelled:
                throw CancellationError()
            }
        }

        let managementAbsenceCompletedAt = now()
        do {
            let performed = try generationStore.performIfCurrent(
                generation,
                for: accountKey
            ) {
                _ = try capacityStore
                    .replaceManagementMetricsWithUnavailableIfAbsent(
                        CapacitySourceMutation(
                            providerID: account.providerID,
                            accountID: account.accountID,
                            contextID: rootContext.contextID,
                            sourceID: OpenRouterProviderContract.managementSourceID,
                            accountContexts: contractContexts,
                            metrics: [
                                Self.unavailableManagementMetric(
                                    rootContextID: rootContext.contextID,
                                    observedAt: managementAbsenceCompletedAt
                                )
                            ],
                            completedAt: managementAbsenceCompletedAt,
                            identityExpectation: .noEnabledManagementSlot,
                            generationValidator: {
                                generationStore.isCurrent(
                                    generation,
                                    for: accountKey
                                )
                            }
                        ),
                        surface: OpenRouterProviderContract.surface,
                        sources: OpenRouterProviderContract.sources
                    )
            }
            if !performed {
                suppressedSourceCount += 1
            }
        } catch NativeCapacityStoreError.accountUnavailable,
                NativeCapacityStoreError.sourceIdentityChanged {
            suppressedSourceCount += 1
        }

        try Task.checkCancellation()
        let completedAt = now()
        let snapshot = try capacityStore.load(
            providerID: account.providerID,
            accountID: account.accountID,
            surface: OpenRouterProviderContract.surface,
            sources: OpenRouterProviderContract.sources
        )
        let lastUsableObservationAt = snapshot?.metrics
            .filter { $0.availability != .unavailable }
            .map(\.freshness.observedAt)
            .max()
        return OpenRouterAccountRefreshResult(
            snapshot: snapshot,
            completedAt: completedAt,
            successfulSourceCount: successfulSourceCount,
            failedSourceCount: failedSourceCount,
            deferredSourceCount: deferredSourceCount,
            suppressedSourceCount: suppressedSourceCount,
            configuredSourceCount: activeSources.count,
            lastUsableObservationAt: lastUsableObservationAt
        )
    }

    private static func fetch(
        _ workItems: [SourceWorkItem],
        maximumConcurrency: Int,
        credentialStore: AccountCredentialStore,
        client: any OpenRouterAPIClient,
        limiter: OpenRouterAccountRequestLimiter,
        now: @escaping @Sendable () -> Date
    ) async -> [SourceOutcome] {
        guard !workItems.isEmpty else {
            return []
        }

        return await withTaskGroup(of: SourceOutcome.self) { group in
            var iterator = workItems.makeIterator()
            var outcomes: [SourceOutcome] = []

            for _ in 0..<min(maximumConcurrency, workItems.count) {
                if let item = iterator.next() {
                    group.addTask {
                        await fetch(
                            item,
                            credentialStore: credentialStore,
                            client: client,
                            limiter: limiter,
                            now: now
                        )
                    }
                }
            }

            while let outcome = await group.next() {
                outcomes.append(outcome)
                if let item = iterator.next() {
                    group.addTask {
                        await fetch(
                            item,
                            credentialStore: credentialStore,
                            client: client,
                            limiter: limiter,
                            now: now
                        )
                    }
                }
            }
            return outcomes
        }
    }

    private static func fetch(
        _ item: SourceWorkItem,
        credentialStore: AccountCredentialStore,
        client: any OpenRouterAPIClient,
        limiter: OpenRouterAccountRequestLimiter,
        now: @escaping @Sendable () -> Date
    ) async -> SourceOutcome {
        if let retryNotBefore = item.refreshState?.retryNotBefore,
           retryNotBefore > now() {
            return .deferred(item)
        }

        let attemptedAt = now()
        do {
            return try await limiter.withPermit {
                try Task.checkCancellation()
                let secret = try credentialStore.readCredential(
                    providerID: item.slot.providerID,
                    accountID: item.slot.accountID,
                    slotID: item.slot.slotID
                )
                let metrics: [CapacityMetric]
                switch item.slot.role {
                case .ordinary:
                    let credential = try OpenRouterOrdinaryCredential(
                        slot: item.slot,
                        secret: secret
                    )
                    metrics = try await client.fetchCurrentKeyCapacity(
                        credential: credential
                    ).metrics
                case .management:
                    let credential = try OpenRouterManagementCredential(
                        slot: item.slot,
                        secret: secret
                    )
                    metrics = [
                        try await client.fetchManagementCredits(
                            credential: credential
                        ).metric
                    ]
                }
                try Task.checkCancellation()
                return .success(
                    item,
                    metrics,
                    attemptedAt: attemptedAt,
                    completedAt: now()
                )
            }
        } catch is CancellationError {
            return .cancelled(item)
        } catch {
            if Task.isCancelled
                || (error as? OpenRouterAPIClientError) == .cancelled {
                return .cancelled(item)
            }
            return .failure(
                item,
                error,
                attemptedAt: attemptedAt,
                completedAt: now()
            )
        }
    }

    private static func failureProjection(
        _ error: Error,
        previousFailureCount: Int,
        completedAt: Date,
        policy: OpenRouterRefreshPolicy
    ) -> FailureProjection {
        switch error {
        case OpenRouterAPIClientError.authenticationFailure:
            return FailureProjection(code: .authentication)
        case OpenRouterAPIClientError.insufficientPrivilege:
            return FailureProjection(code: .insufficientPrivilege)
        case let OpenRouterAPIClientError.throttled(retryAfter):
            return FailureProjection(
                code: .throttled,
                retryNotBefore: policy.retryDate(
                    after: previousFailureCount,
                    retryAfter: retryAfter,
                    now: completedAt
                )
            )
        case let OpenRouterAPIClientError.serviceUnavailable(retryAfter):
            return FailureProjection(
                code: .transientFailure,
                retryNotBefore: policy.retryDate(
                    after: previousFailureCount,
                    retryAfter: retryAfter,
                    now: completedAt
                )
            )
        case OpenRouterAPIClientError.timedOut,
             OpenRouterAPIClientError.transportFailure,
             OpenRouterAPIClientError.serverFailure:
            return FailureProjection(
                code: .transientFailure,
                retryNotBefore: policy.retryDate(
                    after: previousFailureCount,
                    retryAfter: nil,
                    now: completedAt
                )
            )
        case CredentialStoreError.credentialDisabled:
            return FailureProjection(code: .credentialDisabled)
        case CredentialStoreError.credentialMissing,
             CredentialStoreError.slotNotFound,
             CredentialStoreError.contextNotFound:
            return FailureProjection(code: .credentialMissing)
        default:
            return FailureProjection(code: .transientFailure)
        }
    }

    private static func unavailableManagementMetric(
        rootContextID: String,
        observedAt: Date
    ) -> CapacityMetric {
        CapacityMetric(
            metricID: "account-credits",
            accountContextID: rootContextID,
            sourceID: OpenRouterProviderContract.managementSourceID,
            capability: "credits",
            displayName: "Account credits",
            availability: .unavailable,
            unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
            window: CapacityWindow(kind: .none),
            freshness: ObservationFreshness(observedAt: observedAt),
            confidence: .unknown
        )
    }

    private static func accountKey(providerID: String, accountID: String) -> String {
        "\(providerID):\(accountID)"
    }
}

private final class OpenRouterRefreshGenerationStore: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var generations: [String: UInt64] = [:]
    private var activeTasks: [
        String: (UInt64, Task<OpenRouterAccountRefreshResult, Error>)
    ] = [:]
    private var limiters: [String: OpenRouterAccountRequestLimiter] = [:]

    func prepare(
        _ accountKey: String,
        maximumPermits: Int
    ) -> (UInt64, OpenRouterAccountRequestLimiter) {
        lock.lock()
        defer { lock.unlock() }
        activeTasks.removeValue(forKey: accountKey)?.1.cancel()
        let generation = generations[accountKey, default: 0] &+ 1
        generations[accountKey] = generation
        let limiter = limiters[accountKey]
            ?? OpenRouterAccountRequestLimiter(maximumPermits: maximumPermits)
        limiters[accountKey] = limiter
        return (generation, limiter)
    }

    func install(
        _ task: Task<OpenRouterAccountRefreshResult, Error>,
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

private actor OpenRouterAccountRequestLimiter {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let maximumPermits: Int
    private var availablePermits: Int
    private var waiters: [Waiter] = []

    init(maximumPermits: Int) {
        self.maximumPermits = max(1, maximumPermits)
        availablePermits = max(1, maximumPermits)
    }

    func withPermit<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func release() {
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume()
            return
        }
        availablePermits = min(maximumPermits, availablePermits + 1)
    }
}

private struct SourceWorkItem: Sendable {
    let slot: ProviderCredentialSlot
    let refreshState: CredentialContextRefreshState?

    init(slot: ProviderCredentialSlot, refreshState: CredentialContextRefreshState? = nil) {
        self.slot = slot
        self.refreshState = refreshState
    }

    var sourceID: String {
        switch slot.role {
        case .ordinary:
            OpenRouterProviderContract.currentKeySourceID
        case .management:
            OpenRouterProviderContract.managementSourceID
        }
    }

    func withRefreshState(
        _ refreshState: CredentialContextRefreshState?
    ) -> SourceWorkItem {
        SourceWorkItem(slot: slot, refreshState: refreshState)
    }
}

private enum SourceOutcome: @unchecked Sendable {
    case success(
        SourceWorkItem,
        [CapacityMetric],
        attemptedAt: Date,
        completedAt: Date
    )
    case failure(
        SourceWorkItem,
        Error,
        attemptedAt: Date,
        completedAt: Date
    )
    case deferred(SourceWorkItem)
    case cancelled(SourceWorkItem)
}

private struct FailureProjection: Sendable {
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

public struct UnavailableOpenRouterRefreshCoordinator: OpenRouterAccountRefreshing {
    public init() {}

    public func refresh(
        account: ProviderAccount
    ) async throws -> OpenRouterAccountRefreshResult {
        throw ProviderAdapterError(
            providerID: account.providerID,
            message: "OpenRouter credential refresh is unavailable."
        )
    }

    public func invalidateAccount(providerID: String, accountID: String) {}
}

#if DEBUG
public struct SyntheticOpenRouterVerificationClient: OpenRouterAPIClient {
    private let failingOrdinarySlotID: String
    private let observedAt: Date

    public init(
        failingOrdinarySlotID: String,
        observedAt: Date = Date()
    ) {
        self.failingOrdinarySlotID = failingOrdinarySlotID
        self.observedAt = observedAt
    }

    public func fetchCurrentKeyCapacity(
        credential: OpenRouterOrdinaryCredential
    ) async throws -> OpenRouterCurrentKeyCapacity {
        if credential.credentialSlotID == failingOrdinarySlotID {
            throw OpenRouterAPIClientError.transportFailure
        }
        let freshness = ObservationFreshness(observedAt: observedAt)
        return OpenRouterCurrentKeyCapacity(
            metrics: [
                CapacityMetric(
                    metricID: "key-total-usage",
                    accountContextID: credential.accountContextID,
                    sourceID: OpenRouterProviderContract.currentKeySourceID,
                    capability: "spend",
                    displayName: "API key total usage",
                    availability: .known,
                    unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
                    values: CapacityValues(
                        consumed: CapacityValue(
                            value: Decimal(string: "1.25")!,
                            origin: .reported
                        )
                    ),
                    window: CapacityWindow(kind: .lifetime),
                    freshness: freshness,
                    confidence: .live
                ),
                CapacityMetric(
                    metricID: "key-total-byok-usage",
                    accountContextID: credential.accountContextID,
                    sourceID: OpenRouterProviderContract.currentKeySourceID,
                    capability: "spend",
                    displayName: "API key total BYOK usage",
                    availability: .known,
                    unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
                    values: CapacityValues(
                        consumed: CapacityValue(
                            value: Decimal(string: "0.5")!,
                            origin: .reported
                        )
                    ),
                    window: CapacityWindow(kind: .lifetime),
                    freshness: freshness,
                    confidence: .live
                ),
                CapacityMetric(
                    metricID: "key-credit-limit",
                    accountContextID: credential.accountContextID,
                    sourceID: OpenRouterProviderContract.currentKeySourceID,
                    capability: "credits",
                    displayName: "API key credit limit",
                    availability: .known,
                    unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
                    values: CapacityValues(
                        remaining: CapacityValue(
                            value: Decimal(string: "8.75")!,
                            origin: .reported
                        ),
                        limit: CapacityValue(value: 10, origin: .reported)
                    ),
                    window: CapacityWindow(
                        kind: .fixed,
                        durationSeconds: 2_592_000,
                        nextTransition: CapacityTransition(
                            kind: .reset,
                            at: observedAt.addingTimeInterval(2_592_000)
                        )
                    ),
                    freshness: freshness,
                    confidence: .live
                )
            ],
            includesBYOKInLimit: true,
            tier: .paid,
            expiresAt: nil
        )
    }

    public func fetchManagementCredits(
        credential: OpenRouterManagementCredential
    ) async throws -> OpenRouterManagementCreditsCapacity {
        OpenRouterManagementCreditsCapacity(
            metric: CapacityMetric(
                metricID: "account-credits",
                accountContextID: credential.accountContextID,
                sourceID: OpenRouterProviderContract.managementSourceID,
                capability: "credits",
                displayName: "Account credits",
                availability: .known,
                unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
                values: CapacityValues(
                    consumed: CapacityValue(value: 12, origin: .reported),
                    remaining: CapacityValue(value: 88, origin: .derived),
                    limit: CapacityValue(value: 100, origin: .reported)
                ),
                window: CapacityWindow(kind: .none),
                freshness: ObservationFreshness(observedAt: observedAt),
                confidence: .live,
                derivations: [
                    Derivation(
                        kind: .remainingFromLimitMinusConsumed,
                        target: .remaining,
                        inputs: [.limit, .consumed]
                    )
                ]
            )
        )
    }
}
#endif
