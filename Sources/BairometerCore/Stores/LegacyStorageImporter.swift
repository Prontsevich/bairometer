import Foundation
import GRDB

public struct LegacyStorageImporter: Sendable {
    private let directory: URL
    private let database: AppDatabase
    private let knownProviderIDs: Set<String>
    private let beforeCommit: @Sendable () throws -> Void

    public init(directory: URL, database: AppDatabase, knownProviderIDs: Set<String>) {
        self.init(
            directory: directory,
            database: database,
            knownProviderIDs: knownProviderIDs,
            beforeCommit: {}
        )
    }

    init(
        directory: URL,
        database: AppDatabase,
        knownProviderIDs: Set<String>,
        beforeCommit: @escaping @Sendable () throws -> Void
    ) {
        self.directory = directory
        self.database = database
        self.knownProviderIDs = knownProviderIDs
        self.beforeCommit = beforeCommit
    }

    public func runIfNeeded() throws {
        let alreadyImported = try database.pool.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM legacy_import_state WHERE id = 1)") ?? false
        }
        guard !alreadyImported else { return }

        let plan = scanLegacyFiles()
        try database.pool.write { db in
            let importedByAnotherConnection = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM legacy_import_state WHERE id = 1)"
            ) ?? false
            guard !importedByAnotherConnection else { return }

            try DatabaseProviderConfigurationStore.write(plan.accounts, in: db)
            try beforeCommit()
            for snapshot in plan.snapshots {
                try DatabaseSnapshotStore.upsert(snapshot, in: db)
            }
            if let settings = plan.refreshSettings {
                try db.execute(
                    sql: "INSERT INTO refresh_settings (id, interval) VALUES (1, ?)",
                    arguments: [settings.interval.rawValue]
                )
            }
            for diagnostic in plan.diagnostics {
                try db.execute(
                    sql: """
                        INSERT INTO source_diagnostics (provider_id, account_id, code, message, occurred_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        diagnostic.providerID,
                        diagnostic.accountID,
                        diagnostic.code,
                        diagnostic.message,
                        diagnostic.occurredAt.timeIntervalSince1970
                    ]
                )
            }
            try db.execute(
                sql: "INSERT INTO legacy_import_state (id, version, completed_at) VALUES (1, 1, ?)",
                arguments: [Date().timeIntervalSince1970]
            )
        }
    }

    private func scanLegacyFiles() -> LegacyImportPlan {
        let now = Date()
        var diagnostics: [SourceDiagnostic] = []
        var accounts = loadAccounts(diagnostics: &diagnostics, now: now)
        accounts = resolveDisplayNameCollisions(accounts, diagnostics: &diagnostics, now: now)
        let accountsByKey = Dictionary(uniqueKeysWithValues: accounts.map { ($0.accountKey, $0) })

        var candidateSnapshots = loadSnapshotDocument(diagnostics: &diagnostics, now: now)
        for account in accounts where account.providerID == "claude-code" && account.sourceMode == .claudeStatusLine {
            guard let path = account.localSnapshotPath, !path.isEmpty else { continue }
            do {
                let payload = try decodeClaudeSnapshot(at: path)
                let snapshot = try ClaudeCodeSnapshotFactory.makeUsageSnapshot(from: payload, account: account)
                candidateSnapshots.append(snapshot)
                let managedPath = try? ClaudeCodeStatusLinePaths.legacySnapshotURL().standardizedFileURL.path
                let configuredPath = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    .standardizedFileURL.path
                if configuredPath != managedPath {
                    diagnostics.append(SourceDiagnostic(
                        providerID: account.providerID,
                        accountID: account.accountID,
                        code: "legacy-custom-statusline",
                        message: "The last valid Claude Code custom snapshot was imported once. Install the bundled statusLine helper for future updates.",
                        occurredAt: now
                    ))
                }
            } catch {
                diagnostics.append(SourceDiagnostic(
                    providerID: account.providerID,
                    accountID: account.accountID,
                    code: "legacy-statusline-unavailable",
                    message: "Claude Code local snapshot could not be imported. Install the bundled statusLine helper for future updates.",
                    occurredAt: now
                ))
            }
        }

        let snapshots = newestValidSnapshots(
            candidateSnapshots,
            accountsByKey: accountsByKey
        )
        let refreshSettings = loadRefreshSettings(diagnostics: &diagnostics, now: now)
        return LegacyImportPlan(
            accounts: accounts.map { account in
                var imported = account
                imported.localSnapshotPath = nil
                return imported
            },
            snapshots: snapshots,
            refreshSettings: refreshSettings,
            diagnostics: diagnostics
        )
    }

    private func loadAccounts(diagnostics: inout [SourceDiagnostic], now: Date) -> [ProviderAccount] {
        let url = directory.appendingPathComponent("providers.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([ProviderAccount].self, from: Data(contentsOf: url))
            var seen = Set<String>()
            var accounts: [ProviderAccount] = []
            for account in decoded where knownProviderIDs.contains(account.providerID) {
                guard seen.insert(account.accountKey).inserted else {
                    diagnostics.append(SourceDiagnostic(
                        providerID: account.providerID,
                        accountID: account.accountID,
                        code: "legacy-duplicate-account",
                        message: "A duplicate legacy account was skipped during database migration.",
                        occurredAt: now
                    ))
                    continue
                }
                accounts.append(account)
            }
            return accounts
        } catch {
            diagnostics.append(SourceDiagnostic(
                providerID: nil,
                accountID: nil,
                code: "legacy-providers-unavailable",
                message: "Legacy provider accounts could not be imported. The original file was left unchanged.",
                occurredAt: now
            ))
            return []
        }
    }

    private func resolveDisplayNameCollisions(
        _ accounts: [ProviderAccount],
        diagnostics: inout [SourceDiagnostic],
        now: Date
    ) -> [ProviderAccount] {
        var usedNames = Set<String>()
        return accounts.map { account in
            var resolved = account
            let baseName = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let preferredName = baseName.isEmpty ? ProviderAccount.defaultDisplayName : baseName
            var candidate = preferredName
            var suffix = 2
            while !usedNames.insert(DatabaseProviderConfigurationStore.displayNameKey(for: candidate)).inserted {
                candidate = "\(preferredName) (\(suffix))"
                suffix += 1
            }
            if candidate != account.displayName {
                diagnostics.append(SourceDiagnostic(
                    providerID: account.providerID,
                    accountID: account.accountID,
                    code: "legacy-display-name-adjusted",
                    message: "An account name was adjusted during database migration to keep all account names unique.",
                    occurredAt: now
                ))
            }
            resolved.displayName = candidate
            return resolved
        }
    }

    private func loadSnapshotDocument(diagnostics: inout [SourceDiagnostic], now: Date) -> [UsageSnapshot] {
        let url = directory.appendingPathComponent("snapshots.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(UsageSnapshotDocument.self, from: Data(contentsOf: url))
            guard document.formatVersion == UsageSnapshotDocument.currentFormatVersion else {
                diagnostics.append(SourceDiagnostic(
                    providerID: nil,
                    accountID: nil,
                    code: "legacy-snapshots-unsupported",
                    message: "Legacy snapshots use an unsupported format and were not imported. The original file was left unchanged.",
                    occurredAt: now
                ))
                return []
            }
            return document.snapshots
        } catch {
            diagnostics.append(SourceDiagnostic(
                providerID: nil,
                accountID: nil,
                code: "legacy-snapshots-unavailable",
                message: "Legacy snapshots could not be imported. The original file was left unchanged.",
                occurredAt: now
            ))
            return []
        }
    }

    private func decodeClaudeSnapshot(at path: String) throws -> ClaudeCodeLocalSnapshot {
        let expandedPath = (path as NSString).expandingTildeInPath
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClaudeCodeLocalSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: expandedPath)))
    }

    private func newestValidSnapshots(
        _ candidates: [UsageSnapshot],
        accountsByKey: [String: ProviderAccount]
    ) -> [UsageSnapshot] {
        var snapshots: [String: UsageSnapshot] = [:]
        for snapshot in candidates {
            guard let account = accountsByKey[snapshot.id] else { continue }
            let normalized = UsageSnapshot(
                providerID: snapshot.providerID,
                accountID: snapshot.accountID,
                accountDisplayName: account.displayName,
                displayName: snapshot.displayName,
                status: snapshot.status,
                planName: snapshot.planName,
                periodLabel: snapshot.periodLabel,
                usedPercent: snapshot.usedPercent,
                remainingLabel: snapshot.remainingLabel,
                resetAt: snapshot.resetAt,
                limitWindows: snapshot.limitWindows,
                lastUpdatedAt: snapshot.lastUpdatedAt,
                confidence: snapshot.confidence,
                source: snapshot.source,
                warnings: snapshot.warnings
            )
            if let current = snapshots[snapshot.id], current.lastUpdatedAt > normalized.lastUpdatedAt {
                continue
            }
            snapshots[snapshot.id] = normalized
        }
        return snapshots.values.sorted { $0.id < $1.id }
    }

    private func loadRefreshSettings(diagnostics: inout [SourceDiagnostic], now: Date) -> RefreshSettings? {
        let url = directory.appendingPathComponent("refresh-settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(RefreshSettings.self, from: Data(contentsOf: url))
        } catch {
            diagnostics.append(SourceDiagnostic(
                providerID: nil,
                accountID: nil,
                code: "legacy-refresh-settings-unavailable",
                message: "Legacy refresh settings could not be imported. Default refresh settings are active.",
                occurredAt: now
            ))
            return nil
        }
    }
}

private struct LegacyImportPlan: Sendable {
    let accounts: [ProviderAccount]
    let snapshots: [UsageSnapshot]
    let refreshSettings: RefreshSettings?
    let diagnostics: [SourceDiagnostic]
}
