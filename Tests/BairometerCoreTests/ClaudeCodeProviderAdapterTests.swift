import XCTest
@testable import BairometerCore

final class ClaudeCodeProviderAdapterTests: XCTestCase {
    func testStatusLineWriterBuildsRateLimitWindows() throws {
        let writer = ClaudeCodeStatusLineSnapshotWriter()
        let now = Date(timeIntervalSince1970: 1_751_880_000)

        let snapshot = try writer.makeSnapshot(
            from: Data(
                """
                {
                  "rate_limits": {
                    "five_hour": { "used_percentage": 23.5, "resets_at": 1751883600 },
                    "seven_day": { "used_percentage": 41.2, "resets_at": 1752320000 }
                  }
                }
                """.utf8
            ),
            now: now
        )

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.usedPercent, 41.2)
        XCTAssertEqual(snapshot.lastUpdatedAt, now)
        XCTAssertEqual(snapshot.limitWindows.map(\.id), ["rolling-5-hour", "seven-day"])
    }

    func testStatusLineWriterRejectsInvalidInputBeforeDatabaseWrite() throws {
        let directory = try temporaryDirectory()
        let database = try AppDatabase(directory: directory)
        let account = claudeAccount()
        try DatabaseProviderConfigurationStore(database: database).save([account])
        let writer = ClaudeCodeStatusLineDatabaseWriter(directory: directory)

        XCTAssertThrowsError(
            try writer.writeSnapshot(from: Data("{}".utf8), accountID: account.accountID)
        ) { error in
            XCTAssertEqual(error as? ClaudeCodeStatusLineError, .noRateLimitData)
        }
        XCTAssertTrue(DatabaseSnapshotStore(database: database).load().snapshots.isEmpty)
    }

    func testManagedStatusLineWriterPersistsNormalizedSnapshot() throws {
        let directory = try temporaryDirectory()
        let database = try AppDatabase(directory: directory)
        let account = claudeAccount()
        try DatabaseProviderConfigurationStore(database: database).save([account])

        let snapshot = try ClaudeCodeStatusLineDatabaseWriter(directory: directory).writeSnapshot(
            from: Data(
                """
                { "rate_limits": { "five_hour": { "used_percentage": 64 } } }
                """.utf8
            ),
            accountID: account.accountID,
            now: Date(timeIntervalSince1970: 1_751_880_000)
        )

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.confidence, .localEstimate)
        XCTAssertEqual(snapshot.source, "Claude Code managed statusLine")
        XCTAssertEqual(snapshot.limitWindows.map(\.id), ["rolling-5-hour"])
        XCTAssertEqual(
            try DatabaseSnapshotStore(database: database).snapshot(
                providerID: account.providerID,
                accountID: account.accountID
            ),
            snapshot
        )
    }

    func testManagedStatusLineWriterRejectsWrongAccountWithoutReplacingLastSnapshot() throws {
        let directory = try temporaryDirectory()
        let database = try AppDatabase(directory: directory)
        let account = claudeAccount()
        try DatabaseProviderConfigurationStore(database: database).save([account])
        let writer = ClaudeCodeStatusLineDatabaseWriter(directory: directory)
        let first = try writer.writeSnapshot(
            from: Data("{\"rate_limits\":{\"five_hour\":{\"used_percentage\":24}}}".utf8),
            accountID: account.accountID,
            now: Date(timeIntervalSince1970: 1)
        )

        XCTAssertThrowsError(
            try writer.writeSnapshot(
                from: Data("{\"rate_limits\":{\"five_hour\":{\"used_percentage\":80}}}".utf8),
                accountID: "missing"
            )
        ) { error in
            XCTAssertEqual(error as? AppDatabaseError, .missingClaudeCodeAccount)
        }
        XCTAssertEqual(
            try DatabaseSnapshotStore(database: database).snapshot(
                providerID: account.providerID,
                accountID: account.accountID
            ),
            first
        )
    }

    func testManagedStatusLineAdapterReadsDatabaseSnapshot() async throws {
        let directory = try temporaryDirectory()
        let database = try AppDatabase(directory: directory)
        let account = claudeAccount()
        try DatabaseProviderConfigurationStore(database: database).save([account])
        _ = try ClaudeCodeStatusLineDatabaseWriter(directory: directory).writeSnapshot(
            from: Data("{\"rate_limits\":{\"seven_day\":{\"used_percentage\":41}}}".utf8),
            accountID: account.accountID
        )

        let adapter = ClaudeCodeProviderAdapter(snapshotStore: DatabaseSnapshotStore(database: database))
        let snapshot = try await adapter.fetchSnapshot(account: account)

        XCTAssertEqual(snapshot.accountDisplayName, "Work")
        XCTAssertEqual(snapshot.limitWindows.map(\.id), ["seven-day"])
    }

    func testManagedStatusLineAdapterReportsMissingSnapshot() async throws {
        let directory = try temporaryDirectory()
        let database = try AppDatabase(directory: directory)
        let account = claudeAccount()
        try DatabaseProviderConfigurationStore(database: database).save([account])
        let adapter = ClaudeCodeProviderAdapter(snapshotStore: DatabaseSnapshotStore(database: database))

        do {
            _ = try await adapter.fetchSnapshot(account: account)
            XCTFail("Expected managed statusLine setup error.")
        } catch let error as ProviderAdapterError {
            XCTAssertEqual(error.message, "Claude Code has not written a managed statusLine snapshot yet.")
        }
    }

    func testUsageCLIAdapterBuildsLiveExperimentalSnapshot() async throws {
        let adapter = ClaudeCodeProviderAdapter(
            usageCLIClient: FixtureClaudeUsageClient(result: .success(
                ClaudeUsageCLIEnvelope(result: """
                Current session: 24% used
                Current week (all models): 48% used · resets Jul 20 at 4pm (UTC)
                Current week (Fable): 12% used · resets Jul 21 at 4pm (UTC)
                """)
            ))
        )
        let account = ProviderAccount(
            providerID: "claude-code",
            accountID: "work",
            displayName: "Work",
            isEnabled: true,
            sourceMode: .claudeUsageCLI,
            executablePath: "~/.local/bin/claude"
        )

        let snapshot = try await adapter.fetchSnapshot(account: account)

        XCTAssertEqual(snapshot.confidence, .live)
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.source, ClaudeCodeSnapshotSource.usageCLI)
        XCTAssertEqual(snapshot.limitWindows.map(\.id), ["session", "weekly-all", "weekly-fable"])
        XCTAssertEqual(snapshot.warnings, [ClaudeCodeSnapshotSource.usageCLICompatibilityNotice])
    }

    func testUsageCLIAdapterUsesExistingWarningThreshold() async throws {
        let adapter = ClaudeCodeProviderAdapter(
            usageCLIClient: FixtureClaudeUsageClient(result: .success(
                ClaudeUsageCLIEnvelope(result: """
                Current session: 12% used
                Current week (all models): 85% used · resets Jul 20 at 4pm (UTC)
                """)
            ))
        )
        let account = ProviderAccount(
            providerID: "claude-code",
            isEnabled: true,
            sourceMode: .claudeUsageCLI
        )

        let snapshot = try await adapter.fetchSnapshot(account: account)

        XCTAssertEqual(snapshot.status, .warning)
    }

    func testManualClaudeSourceUsesManualSnapshotSemantics() async throws {
        let adapter = ClaudeCodeProviderAdapter()
        let account = ProviderAccount(
            providerID: "claude-code",
            isEnabled: true,
            sourceMode: .manual
        )

        let snapshot = try await adapter.fetchSnapshot(account: account)

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertEqual(snapshot.confidence, .manual)
    }

    func testManagedStatusLineRejectsSnapshotFromUsageCLISource() async throws {
        let directory = try temporaryDirectory()
        let database = try AppDatabase(directory: directory)
        let account = claudeAccount()
        try DatabaseProviderConfigurationStore(database: database).save([account])
        try DatabaseSnapshotStore(database: database).save([
            UsageSnapshot(
                providerID: account.providerID,
                accountID: account.accountID,
                accountDisplayName: account.displayName,
                displayName: "Claude Code",
                status: .ok,
                limitWindows: [],
                lastUpdatedAt: Date(),
                confidence: .live,
                source: ClaudeCodeSnapshotSource.usageCLI
            )
        ])
        let adapter = ClaudeCodeProviderAdapter(snapshotStore: DatabaseSnapshotStore(database: database))

        do {
            _ = try await adapter.fetchSnapshot(account: account)
            XCTFail("Expected source mismatch failure.")
        } catch let error as ProviderAdapterError {
            XCTAssertEqual(
                error.message,
                "Claude Code has not written a managed statusLine snapshot for this source yet."
            )
        }
    }

    func testUsageCLITimeoutMapsToSanitizedTransientAdapterError() async throws {
        let adapter = ClaudeCodeProviderAdapter(
            usageCLIClient: FixtureClaudeUsageClient(result: .failure(.timedOut))
        )
        let account = ProviderAccount(
            providerID: "claude-code",
            isEnabled: true,
            sourceMode: .claudeUsageCLI
        )

        do {
            _ = try await adapter.fetchSnapshot(account: account)
            XCTFail("Expected timeout failure.")
        } catch let error as ProviderAdapterError {
            XCTAssertEqual(error.message, "Claude Code CLI timed out while reading usage limits.")
            XCTAssertTrue(error.isTransient)
        }
    }

    private func claudeAccount() -> ProviderAccount {
        ProviderAccount(
            providerID: "claude-code",
            accountID: "work",
            displayName: "Work",
            isEnabled: true,
            sourceMode: .claudeStatusLine
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct FixtureClaudeUsageClient: ClaudeUsageCLIClient {
    let result: Result<ClaudeUsageCLIEnvelope, ClaudeUsageCLIClientError>

    func fetchUsage(executablePath: String?) async throws -> ClaudeUsageCLIEnvelope {
        try result.get()
    }
}
