import Foundation

public struct ProviderRefreshRequest: Sendable {
    public let adapter: any ProviderAdapter
    public let account: ProviderAccount

    public init(adapter: any ProviderAdapter, account: ProviderAccount) {
        self.adapter = adapter
        self.account = account
    }
}

public struct ProviderRetryPolicy: Equatable, Sendable {
    public let maxAttempts: Int
    public let initialDelay: TimeInterval
    public let backoffMultiplier: Double

    public init(maxAttempts: Int = 2, initialDelay: TimeInterval = 2, backoffMultiplier: Double = 2) {
        self.maxAttempts = max(1, maxAttempts)
        self.initialDelay = max(0, initialDelay)
        self.backoffMultiplier = max(1, backoffMultiplier)
    }
}

public struct ProviderRefreshCoordinator: Sendable {
    private let retryPolicy: ProviderRetryPolicy

    public init(retryPolicy: ProviderRetryPolicy = ProviderRetryPolicy()) {
        self.retryPolicy = retryPolicy
    }

    public func refresh(_ requests: [ProviderRefreshRequest]) async -> [UsageSnapshot] {
        var snapshots: [UsageSnapshot] = []

        for request in requests {
            guard !Task.isCancelled else { break }
            let snapshot = await refresh(request)
            snapshots.append(snapshot)
        }

        return snapshots
    }

    public func refresh(_ request: ProviderRefreshRequest) async -> UsageSnapshot {
        var attempt = 1
        var delay = retryPolicy.initialDelay

        while true {
            do {
                try Task.checkCancellation()
                let snapshot = try await request.adapter.fetchSnapshot(account: request.account)
                return try validated(snapshot, for: request)
            } catch is CancellationError {
                return errorSnapshot(
                    account: request.account,
                    providerDisplayName: request.adapter.displayName,
                    error: ProviderAdapterError(
                        providerID: request.account.providerID,
                        message: "Refresh was cancelled."
                    )
                )
            } catch {
                guard shouldRetry(error, attempt: attempt) else {
                    return errorSnapshot(
                        account: request.account,
                        providerDisplayName: request.adapter.displayName,
                        error: error
                    )
                }

                do {
                    try await sleep(for: delay)
                } catch {
                    return errorSnapshot(
                        account: request.account,
                        providerDisplayName: request.adapter.displayName,
                        error: ProviderAdapterError(
                            providerID: request.account.providerID,
                            message: "Refresh was cancelled."
                        )
                    )
                }
                attempt += 1
                delay *= retryPolicy.backoffMultiplier
            }
        }
    }

    private func shouldRetry(_ error: Error, attempt: Int) -> Bool {
        guard attempt < retryPolicy.maxAttempts else { return false }
        return (error as? ProviderAdapterError)?.isTransient == true
    }

    private func sleep(for delay: TimeInterval) async throws {
        guard delay > 0 else { return }
        let nanoseconds = UInt64(delay * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private func validated(
        _ snapshot: UsageSnapshot,
        for request: ProviderRefreshRequest
    ) throws -> UsageSnapshot {
        guard snapshot.providerID == request.account.providerID,
              snapshot.accountID == request.account.accountID else {
            throw ProviderAdapterError(
                providerID: request.account.providerID,
                message: "Provider adapter returned usage for a different account.",
                recoverySuggestion: "Verify the provider adapter preserves the requested provider and account identity."
            )
        }
        return snapshot
    }

    public func errorSnapshot(
        account: ProviderAccount,
        providerDisplayName: String,
        error: Error
    ) -> UsageSnapshot {
        var warnings = [error.localizedDescription]
        if let recoverySuggestion = (error as? LocalizedError)?.recoverySuggestion {
            warnings.append(recoverySuggestion)
        }

        if (error as? ProviderAdapterError)?.isTransient == true {
            warnings.append(
                "Transient failure persisted after \(retryPolicy.maxAttempts) refresh attempts."
            )
        }

        return UsageSnapshot(
            providerID: account.providerID,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: providerDisplayName,
            status: .error,
            remainingLabel: "Refresh failed",
            lastUpdatedAt: Date(),
            confidence: .unknown,
            source: "Provider adapter error",
            warnings: warnings
        )
    }
}
