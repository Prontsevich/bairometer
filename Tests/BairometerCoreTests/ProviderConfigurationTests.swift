import XCTest
@testable import BairometerCore

final class ProviderConfigurationTests: XCTestCase {
    func testProviderDefaultsUseTheConfiguredSourceForRealProviders() {
        XCTAssertEqual(ProviderSourceMode.defaultMode(for: "claude-code"), .claudeStatusLine)
        XCTAssertEqual(ProviderSourceMode.defaultMode(for: "ollama-cloud"), .ollamaWebPage)
        XCTAssertEqual(ProviderSourceMode.defaultMode(for: "openai-codex"), .appServer)
        XCTAssertEqual(ProviderSourceMode.defaultMode(for: "minimax"), .miniMaxTokenPlan)
        XCTAssertEqual(ProviderSourceMode.defaultMode(for: "mock"), .manual)
    }

    func testProviderAdaptersExposeSourceCapabilities() {
        let adapters = ProviderRegistry.defaultAdapters
        let claude = adapters.first { $0.id == "claude-code" }
        let codex = adapters.first { $0.id == "openai-codex" }
        let ollama = adapters.first { $0.id == "ollama-cloud" }
        let miniMax = adapters.first { $0.id == "minimax" }

        XCTAssertEqual(
            claude?.capabilities.capability(for: .claudeStatusLine)?.kind,
            .localSnapshot
        )
        XCTAssertEqual(
            claude?.capabilities.capability(for: .claudeUsageCLI)?.kind,
            .live
        )
        XCTAssertEqual(
            codex?.capabilities.capability(for: .appServer)?.kind,
            .live
        )
        XCTAssertEqual(
            ollama?.capabilities.capability(for: .ollamaWebPage)?.kind,
            .live
        )
        XCTAssertEqual(
            miniMax?.capabilities.capability(for: .miniMaxTokenPlan)?.kind,
            .live
        )
    }

    func testProviderAccountWithoutSourceUsesProviderDefault() {
        XCTAssertEqual(
            ProviderAccount(providerID: "openai-codex", isEnabled: true).sourceMode,
            .appServer
        )
    }

    func testProviderAccountRejectsManualSourceForRealProviders() {
        XCTAssertEqual(
            ProviderAccount(
                providerID: "ollama-cloud",
                isEnabled: true,
                sourceMode: .manual
            ).sourceMode,
            .ollamaWebPage
        )
        XCTAssertEqual(
            ProviderAccount(
                providerID: "minimax",
                isEnabled: true,
                sourceMode: .manual
            ).sourceMode,
            .miniMaxTokenPlan
        )
    }

    func testMiniMaxTokenPlanSourceModeRoundTripsExplicitly() throws {
        let account = ProviderAccount(
            providerID: "minimax",
            accountID: "team",
            displayName: "Team",
            isEnabled: true
        )

        let encoded = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(ProviderAccount.self, from: encoded)

        XCTAssertEqual(decoded.sourceMode, .miniMaxTokenPlan)
        XCTAssertTrue(
            String(decoding: encoded, as: UTF8.self)
                .contains(#""sourceMode":"minimax-token-plan""#)
        )
        XCTAssertTrue(decoded.sourceMode.isExperimental)
    }

    func testClaudeCodeAllowsExplicitSourceSelectionWithoutChangingDefault() {
        XCTAssertEqual(
            ProviderAccount(providerID: "claude-code", isEnabled: true).sourceMode,
            .claudeStatusLine
        )
        XCTAssertEqual(
            ProviderAccount(
                providerID: "claude-code",
                isEnabled: true,
                sourceMode: .manual
            ).sourceMode,
            .manual
        )
        XCTAssertEqual(
            ProviderAccount(
                providerID: "claude-code",
                isEnabled: true,
                sourceMode: .claudeUsageCLI
            ).sourceMode,
            .claudeUsageCLI
        )
    }

    func testProviderAccountDecodesLegacyLocalSnapshotAsManagedStatusLine() throws {
        let account = try JSONDecoder().decode(
            ProviderAccount.self,
            from: Data(
                """
                {
                  "providerID": "claude-code",
                  "accountID": "work",
                  "displayName": "Work",
                  "isEnabled": true,
                  "sourceMode": "local-snapshot",
                  "localSnapshotPath": "/tmp/legacy.json"
                }
                """.utf8
            )
        )

        XCTAssertEqual(account.sourceMode, .claudeStatusLine)
        XCTAssertEqual(account.localSnapshotPath, "/tmp/legacy.json")
    }

    func testProviderAccountDecodesLegacyCodexExecutablePathAndEncodesNeutralKey() throws {
        let account = try JSONDecoder().decode(
            ProviderAccount.self,
            from: Data(
                """
                {
                  "providerID": "openai-codex",
                  "accountID": "work",
                  "displayName": "Work",
                  "isEnabled": true,
                  "sourceMode": "app-server",
                  "codexExecutablePath": "~/.local/bin/codex"
                }
                """.utf8
            )
        )

        XCTAssertEqual(account.executablePath, "~/.local/bin/codex")
        let encoded = try JSONEncoder().encode(account)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["executablePath"] as? String, "~/.local/bin/codex")
        XCTAssertNil(object["codexExecutablePath"])
    }

    func testDatabaseMigrationCopiesLegacyCodexExecutablePath() throws {
        let directory = temporaryDirectory()
        var database: AppDatabase? = try AppDatabase(directory: directory)
        try database?.pool.write { db in
            try db.execute(sql: """
                INSERT INTO provider_accounts (
                    provider_id, account_id, display_name, display_name_key,
                    is_enabled, source_mode, web_data_store_id,
                    codex_executable_path, executable_path, sort_index
                ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, NULL, ?)
                """, arguments: [
                    "openai-codex", "work", "Work", "work", true,
                    "app-server", "~/.local/bin/codex", 0
                ])
            try db.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                arguments: ["v2-provider-neutral-executable-path"]
            )
        }
        database = nil

        let migratedDatabase = try AppDatabase(directory: directory)
        let result = DatabaseProviderConfigurationStore(database: migratedDatabase).load(
            knownProviderIDs: ["openai-codex"]
        )

        XCTAssertEqual(result.accounts.first?.executablePath, "~/.local/bin/codex")
    }

    func testDatabaseMigrationRemovesOrphanedAccountDiagnosticsAndAddsCascade() throws {
        let directory = temporaryDirectory()
        let account = ProviderAccount(
            providerID: "mock",
            accountID: "current",
            displayName: "Current",
            isEnabled: true
        )
        var database: AppDatabase? = try AppDatabase(directory: directory)
        try DatabaseProviderConfigurationStore(database: database).save([account])
        try database?.pool.write { db in
            try db.execute(sql: "DROP INDEX source_diagnostics_account")
            try db.execute(sql: "DROP TABLE source_diagnostics")
            try db.execute(sql: """
                CREATE TABLE source_diagnostics (
                    id INTEGER PRIMARY KEY,
                    provider_id TEXT,
                    account_id TEXT,
                    code TEXT NOT NULL,
                    message TEXT NOT NULL,
                    occurred_at REAL NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE INDEX source_diagnostics_account
                ON source_diagnostics(provider_id, account_id, occurred_at)
                """)
            try db.execute(sql: """
                INSERT INTO source_diagnostics (
                    provider_id, account_id, code, message, occurred_at
                ) VALUES
                    ('mock', 'current', 'refresh-0', 'Current account failed', 1000),
                    ('mock', 'deleted', 'refresh-0', 'Deleted account failed', 1001),
                    (NULL, NULL, 'global-warning', 'Global warning', 1002)
                """)
            try db.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                arguments: ["v3-account-diagnostic-lifecycle"]
            )
        }
        database = nil

        let migratedDatabase = try AppDatabase(directory: directory)
        let diagnostics = DatabaseSourceDiagnosticStore(database: migratedDatabase)
        XCTAssertEqual(
            Set(diagnostics.load().map(\.message)),
            ["Current account failed", "Global warning"]
        )

        try DatabaseProviderConfigurationStore(database: migratedDatabase).save([])

        XCTAssertEqual(diagnostics.load().map(\.message), ["Global warning"])
    }

    func testDatabaseStoreRoundTripsAccountsAndOrdering() throws {
        let database = try AppDatabase(directory: temporaryDirectory())
        let accounts = [
            ProviderAccount(providerID: "claude-code", accountID: "work", displayName: "Work", isEnabled: true),
            ProviderAccount(providerID: "mock", accountID: "demo", displayName: "Demo", isEnabled: true)
        ]
        let store = DatabaseProviderConfigurationStore(database: database)

        try store.save(accounts)
        let result = store.load(knownProviderIDs: ["mock", "claude-code"])

        XCTAssertEqual(result.accounts.map(\.id), accounts.map(\.id))
        XCTAssertNil(result.warning)
    }

    func testDatabaseStoreRejectsGloballyDuplicateNormalizedDisplayNames() throws {
        let database = try AppDatabase(directory: temporaryDirectory())
        let store = DatabaseProviderConfigurationStore(database: database)

        XCTAssertThrowsError(
            try store.save([
                ProviderAccount(providerID: "mock", accountID: "one", displayName: " Work ", isEnabled: true),
                ProviderAccount(providerID: "claude-code", accountID: "two", displayName: "work", isEnabled: false)
            ])
        ) { error in
            XCTAssertEqual(error as? StorageValidationError, .duplicateDisplayName)
        }
    }

    func testDatabaseStoreDeletesSnapshotsWhenAccountIsRemoved() throws {
        let database = try AppDatabase(directory: temporaryDirectory())
        let account = ProviderAccount(providerID: "mock", accountID: "one", displayName: "One", isEnabled: true)
        let accounts = DatabaseProviderConfigurationStore(database: database)
        let snapshots = DatabaseSnapshotStore(database: database)
        try accounts.save([account])
        try snapshots.save([
            UsageSnapshot(
                providerID: account.providerID,
                accountID: account.accountID,
                accountDisplayName: account.displayName,
                displayName: "Mock",
                status: .ok,
                lastUpdatedAt: Date(),
                confidence: .live,
                source: "Test"
            )
        ])

        try accounts.save([])

        XCTAssertTrue(snapshots.load().snapshots.isEmpty)
    }

    func testDatabaseSourceDiagnosticsRoundTripAndClear() throws {
        let database = try AppDatabase(directory: temporaryDirectory())
        let store = DatabaseSourceDiagnosticStore(database: database)
        let occurredAt = Date(timeIntervalSince1970: 1_000)
        try DatabaseProviderConfigurationStore(database: database).save([
            ProviderAccount(
                providerID: "mock",
                accountID: "one",
                displayName: "One",
                isEnabled: true
            )
        ])

        try store.replaceRefreshDiagnostics(
            providerID: "mock",
            accountID: "one",
            occurredAt: occurredAt,
            messages: ["Refresh failed", "Retry later"]
        )
        try store.recordGlobal(code: "legacy-warning", message: "Legacy data needs attention", occurredAt: occurredAt)

        XCTAssertEqual(store.load().filter { $0.providerID == "mock" }.map(\.message), ["Refresh failed", "Retry later"])
        XCTAssertEqual(store.load().first { $0.code == "legacy-warning" }?.message, "Legacy data needs attention")

        try store.clearRefreshDiagnostics(providerID: "mock", accountID: "one")
        XCTAssertFalse(store.load().contains { $0.providerID == "mock" })
    }

    func testDatabaseRefreshStateKeepsSuccessAndFailureTimestampsSeparate() throws {
        let database = try AppDatabase(directory: temporaryDirectory())
        let store = DatabaseSourceDiagnosticStore(database: database)
        try DatabaseProviderConfigurationStore(database: database).save([
            ProviderAccount(providerID: "mock", accountID: "one", displayName: "One", isEnabled: true)
        ])

        try store.recordRefreshSuccess(
            providerID: "mock",
            accountID: "one",
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        try store.recordRefreshFailure(
            providerID: "mock",
            accountID: "one",
            occurredAt: Date(timeIntervalSince1970: 200)
        )
        try store.recordRefreshAttempt(
            providerID: "mock",
            accountID: "one",
            occurredAt: Date(timeIntervalSince1970: 300)
        )

        let state = try XCTUnwrap(store.loadRefreshStates().first)
        XCTAssertEqual(state.lastSuccessfulRefreshAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(state.lastFailedRefreshAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(state.lastAttemptAt, Date(timeIntervalSince1970: 300))

        try DatabaseProviderConfigurationStore(database: database).save([])
        XCTAssertTrue(store.loadRefreshStates().isEmpty)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
