import XCTest
@testable import BairometerCore

final class ProviderRefreshCoordinatorTests: XCTestCase {
    func testRefreshReturnsSnapshotsInRequestOrder() async {
        let coordinator = ProviderRefreshCoordinator()
        let requests = [
            ProviderRefreshRequest(
                adapter: TestProviderAdapter(id: "first", displayName: "First"),
                account: ProviderAccount(providerID: "first", isEnabled: true)
            ),
            ProviderRefreshRequest(
                adapter: TestProviderAdapter(id: "second", displayName: "Second"),
                account: ProviderAccount(providerID: "second", accountID: "work", displayName: "Work", isEnabled: true)
            )
        ]

        let snapshots = await coordinator.refresh(requests)

        XCTAssertEqual(snapshots.map(\.providerID), ["first", "second"])
        XCTAssertEqual(snapshots.map(\.accountID), ["default", "work"])
        XCTAssertEqual(snapshots.map(\.status), [.ok, .ok])
    }

    func testRefreshConvertsAdapterErrorsToSnapshots() async {
        let coordinator = ProviderRefreshCoordinator()
        let requests = [
            ProviderRefreshRequest(
                adapter: TestProviderAdapter(
                    id: "failing",
                    displayName: "Failing",
                    error: ProviderAdapterError(
                        providerID: "failing",
                        message: "Snapshot file is missing.",
                        recoverySuggestion: "Choose a readable JSON file."
                    )
                ),
                account: ProviderAccount(providerID: "failing", accountID: "work", displayName: "Work", isEnabled: true)
            )
        ]

        let snapshots = await coordinator.refresh(requests)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].providerID, "failing")
        XCTAssertEqual(snapshots[0].accountID, "work")
        XCTAssertEqual(snapshots[0].accountDisplayName, "Work")
        XCTAssertEqual(snapshots[0].status, .error)
        XCTAssertEqual(snapshots[0].remainingLabel, "Refresh failed")
        XCTAssertEqual(snapshots[0].confidence, .unknown)
        XCTAssertEqual(snapshots[0].warnings, ["Snapshot file is missing.", "Choose a readable JSON file."])
    }

    func testRefreshRetriesTransientErrors() async {
        let counter = FetchCounter()
        let coordinator = ProviderRefreshCoordinator(
            retryPolicy: ProviderRetryPolicy(maxAttempts: 2, initialDelay: 0)
        )
        let requests = [
            ProviderRefreshRequest(
                adapter: FlakyProviderAdapter(counter: counter),
                account: ProviderAccount(providerID: "flaky", isEnabled: true)
            )
        ]

        let snapshots = await coordinator.refresh(requests)
        let attempts = await counter.attempts

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].providerID, "flaky")
        XCTAssertEqual(snapshots[0].status, .ok)
    }

    func testRefreshDoesNotRetryPermanentErrors() async {
        let counter = FetchCounter()
        let coordinator = ProviderRefreshCoordinator(
            retryPolicy: ProviderRetryPolicy(maxAttempts: 2, initialDelay: 0)
        )
        let requests = [
            ProviderRefreshRequest(
                adapter: FailingProviderAdapter(counter: counter, isTransient: false),
                account: ProviderAccount(providerID: "permanent", isEnabled: true)
            )
        ]

        let snapshots = await coordinator.refresh(requests)
        let attempts = await counter.attempts

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(snapshots[0].status, .error)
    }

    func testRefreshRejectsMismatchedSnapshotIdentity() async {
        let account = ProviderAccount(
            providerID: "expected",
            accountID: "work",
            displayName: "Work",
            isEnabled: true
        )
        let request = ProviderRefreshRequest(
            adapter: MismatchedIdentityAdapter(),
            account: account
        )

        let snapshot = await ProviderRefreshCoordinator().refresh(request)

        XCTAssertEqual(snapshot.providerID, "expected")
        XCTAssertEqual(snapshot.accountID, "work")
        XCTAssertEqual(snapshot.status, .error)
        XCTAssertEqual(snapshot.warnings.first, "Provider adapter returned usage for a different account.")
    }

    func testCancellationStopsTransientRetry() async {
        let counter = FetchCounter()
        let coordinator = ProviderRefreshCoordinator(
            retryPolicy: ProviderRetryPolicy(maxAttempts: 3, initialDelay: 30)
        )
        let request = ProviderRefreshRequest(
            adapter: FailingProviderAdapter(counter: counter, isTransient: true),
            account: ProviderAccount(providerID: "permanent", isEnabled: true)
        )

        let task = Task {
            await coordinator.refresh(request)
        }
        while await counter.attempts == 0 {
            await Task.yield()
        }
        task.cancel()
        let snapshot = await task.value
        let attempts = await counter.attempts

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(snapshot.status, .error)
        XCTAssertEqual(snapshot.warnings.first, "Refresh was cancelled.")
    }
}

private struct TestProviderAdapter: ProviderAdapter {
    let id: String
    let displayName: String
    let usageURL: URL? = nil
    let error: ProviderAdapterError?

    init(id: String, displayName: String, error: ProviderAdapterError? = nil) {
        self.id = id
        self.displayName = displayName
        self.error = error
    }

    func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot {
        if let error {
            throw error
        }

        return UsageSnapshot(
            providerID: id,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: displayName,
            status: .ok,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_200),
            confidence: .localEstimate,
            source: "Test adapter"
        )
    }
}

private actor FetchCounter {
    private(set) var attempts = 0

    func increment() -> Int {
        attempts += 1
        return attempts
    }
}

private struct FlakyProviderAdapter: ProviderAdapter {
    let id = "flaky"
    let displayName = "Flaky"
    let usageURL: URL? = nil
    let counter: FetchCounter

    func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot {
        let attempt = await counter.increment()
        if attempt == 1 {
            throw ProviderAdapterError(
                providerID: id,
                message: "Network timeout.",
                isTransient: true
            )
        }

        return UsageSnapshot(
            providerID: id,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: displayName,
            status: .ok,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_200),
            confidence: .localEstimate,
            source: "Flaky adapter"
        )
    }
}

private struct FailingProviderAdapter: ProviderAdapter {
    let id = "permanent"
    let displayName = "Permanent"
    let usageURL: URL? = nil
    let counter: FetchCounter
    let isTransient: Bool

    func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot {
        _ = await counter.increment()
        throw ProviderAdapterError(
            providerID: id,
            message: "Configuration is missing.",
            isTransient: isTransient
        )
    }
}

private struct MismatchedIdentityAdapter: ProviderAdapter {
    let id = "expected"
    let displayName = "Expected"
    let usageURL: URL? = nil

    func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot {
        UsageSnapshot(
            providerID: "different",
            accountID: "other",
            accountDisplayName: "Other",
            displayName: displayName,
            status: .ok,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_200),
            confidence: .localEstimate,
            source: "Broken adapter"
        )
    }
}
