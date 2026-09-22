import XCTest
@testable import BairometerCore

final class DatabaseSnapshotStoreTests: XCTestCase {
    func testDatabaseSnapshotStoreRoundTripsWindowsWarningsAndAccountName() throws {
        let database = try database()
        let account = ProviderAccount(providerID: "mock", accountID: "work", displayName: "Work", isEnabled: true)
        try DatabaseProviderConfigurationStore(database: database).save([account])
        let snapshot = UsageSnapshot(
            providerID: account.providerID,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: "Mock",
            status: .warning,
            usedPercent: 74,
            limitWindows: [
                UsageLimitWindow(id: "session", displayName: "Session", usedPercent: 74),
                UsageLimitWindow(id: "weekly", displayName: "Weekly", usedPercent: 35)
            ],
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
            confidence: .live,
            source: "Test",
            warnings: ["First", "Second"]
        )
        let store = DatabaseSnapshotStore(database: database)

        try store.save([snapshot])
        let loaded = try XCTUnwrap(store.load().snapshots.first)

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.limitWindows.map(\.id), ["session", "weekly"])
        XCTAssertEqual(loaded.warnings, ["First", "Second"])
    }

    func testNewerSnapshotDoesNotGetOverwrittenByOlderWriter() throws {
        let database = try database()
        let account = ProviderAccount(providerID: "mock", accountID: "work", displayName: "Work", isEnabled: true)
        try DatabaseProviderConfigurationStore(database: database).save([account])
        let store = DatabaseSnapshotStore(database: database)
        let newer = snapshot(account: account, usedPercent: 80, updatedAt: 100)
        let older = snapshot(account: account, usedPercent: 20, updatedAt: 10)

        try store.save([newer])
        try store.save([older])

        XCTAssertEqual(try store.snapshot(providerID: account.providerID, accountID: account.accountID), newer)
    }

    func testUsageDisplayOverridesRoundTripAndCascadeWithAccountDeletion() throws {
        let database = try database()
        let account = ProviderAccount(providerID: "mock", accountID: "work", displayName: "Work", isEnabled: true)
        let accountStore = DatabaseProviderConfigurationStore(database: database)
        try accountStore.save([account])
        let store = DatabaseUsageDisplayOverrideStore(database: database)
        let key = UsageDisplayOverrideKey(
            providerID: account.providerID,
            accountID: account.accountID,
            windowID: "weekly"
        )

        try store.set(.left, for: key)
        XCTAssertEqual(store.load().overrides, [UsageDisplayOverride(key: key, mode: .left)])

        try accountStore.save([])
        XCTAssertTrue(store.load().overrides.isEmpty)
    }

    private func database() throws -> AppDatabase {
        try AppDatabase(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func snapshot(account: ProviderAccount, usedPercent: Double, updatedAt: TimeInterval) -> UsageSnapshot {
        UsageSnapshot(
            providerID: account.providerID,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: "Mock",
            status: .ok,
            usedPercent: usedPercent,
            lastUpdatedAt: Date(timeIntervalSince1970: updatedAt),
            confidence: .live,
            source: "Test"
        )
    }
}
