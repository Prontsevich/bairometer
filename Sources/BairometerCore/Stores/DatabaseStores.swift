import Foundation
import GRDB

public protocol ProviderAccountStore: Sendable {
    func load(knownProviderIDs: Set<String>) -> ProviderAccountLoadResult
    func save(_ accounts: [ProviderAccount]) throws
}

public protocol CurrentSnapshotStore: Sendable {
    func load() -> SnapshotLoadResult
    func save(_ snapshots: [UsageSnapshot]) throws
    func snapshot(providerID: String, accountID: String) throws -> UsageSnapshot?
}

public protocol RefreshSettingsStoreProtocol: Sendable {
    func load(defaults: RefreshSettings) -> RefreshSettingsLoadResult
    func save(_ settings: RefreshSettings) throws
}

public final class DatabaseUsageDisplayOverrideStore: UsageDisplayOverrideStore, @unchecked Sendable {
    private let database: AppDatabase?

    public init(database: AppDatabase?) {
        self.database = database
    }

    public func load() -> UsageDisplayOverrideLoadResult {
        guard let database else {
            return UsageDisplayOverrideLoadResult(
                overrides: [],
                warning: "Usage display preferences could not be loaded."
            )
        }

        do {
            let overrides = try database.pool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT provider_id, account_id, window_id, mode
                    FROM usage_display_overrides
                    """).compactMap { row -> UsageDisplayOverride? in
                    guard let mode = UsageDisplayMode(rawValue: row["mode"] as String) else {
                        return nil
                    }
                    return UsageDisplayOverride(
                        key: UsageDisplayOverrideKey(
                            providerID: row["provider_id"],
                            accountID: row["account_id"],
                            windowID: row["window_id"]
                        ),
                        mode: mode
                    )
                }
            }
            return UsageDisplayOverrideLoadResult(overrides: overrides)
        } catch {
            return UsageDisplayOverrideLoadResult(
                overrides: [],
                warning: "Usage display preferences could not be loaded."
            )
        }
    }

    public func set(_ mode: UsageDisplayMode?, for key: UsageDisplayOverrideKey) throws {
        guard let database else { throw AppDatabaseError.unavailable }
        try database.pool.write { db in
            if let mode {
                try db.execute(
                    sql: """
                        INSERT INTO usage_display_overrides (provider_id, account_id, window_id, mode)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(provider_id, account_id, window_id) DO UPDATE SET
                            mode = excluded.mode
                        """,
                    arguments: [key.providerID, key.accountID, key.windowID, mode.rawValue]
                )
            } else {
                try db.execute(
                    sql: """
                        DELETE FROM usage_display_overrides
                        WHERE provider_id = ? AND account_id = ? AND window_id = ?
                        """,
                    arguments: [key.providerID, key.accountID, key.windowID]
                )
            }
        }
    }
}

public struct SourceDiagnostic: Identifiable, Equatable, Sendable {
    public let providerID: String?
    public let accountID: String?
    public let code: String
    public let message: String
    public let occurredAt: Date

    public var id: String {
        "\(providerID ?? "global"):\(accountID ?? "global"):\(code):\(occurredAt.timeIntervalSince1970)"
    }
}

public protocol SourceDiagnosticStore: Sendable {
    func load() -> [SourceDiagnostic]
    func loadRefreshStates() -> [SourceRefreshState]
    func recordRefreshAttempt(providerID: String, accountID: String, occurredAt: Date) throws
    func recordRefreshSuccess(providerID: String, accountID: String, occurredAt: Date) throws
    func recordRefreshFailure(providerID: String, accountID: String, occurredAt: Date) throws
    func replaceRefreshDiagnostics(
        providerID: String,
        accountID: String,
        occurredAt: Date,
        messages: [String]
    ) throws
    func clearRefreshDiagnostics(providerID: String, accountID: String) throws
    func recordGlobal(code: String, message: String, occurredAt: Date) throws
}

public final class DatabaseProviderConfigurationStore: ProviderAccountStore, @unchecked Sendable {
    private let database: AppDatabase?

    public init(database: AppDatabase?) {
        self.database = database
    }

    public func load(knownProviderIDs: Set<String>) -> ProviderAccountLoadResult {
        guard let database else {
            return ProviderAccountLoadResult(accounts: [], warning: "Provider account settings could not be loaded.")
        }

        do {
            let accounts = try database.pool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT provider_id, account_id, display_name, is_enabled, source_mode,
                           web_data_store_id, executable_path
                    FROM provider_accounts
                    ORDER BY sort_index ASC
                    """).compactMap { row -> ProviderAccount? in
                    let providerID: String = row["provider_id"]
                    guard knownProviderIDs.contains(providerID),
                          let sourceMode = ProviderSourceMode(rawValue: row["source_mode"] as String)
                    else { return nil }
                    let webDataStoreID = (row["web_data_store_id"] as String?).flatMap(UUID.init(uuidString:))
                    return ProviderAccount(
                        providerID: providerID,
                        accountID: row["account_id"],
                        displayName: row["display_name"],
                        isEnabled: row["is_enabled"],
                        sourceMode: sourceMode,
                        webDataStoreID: webDataStoreID,
                        executablePath: row["executable_path"]
                    )
                }
            }
            return ProviderAccountLoadResult(accounts: accounts)
        } catch {
            return ProviderAccountLoadResult(accounts: [], warning: "Provider account settings could not be loaded.")
        }
    }

    public func accountCount() throws -> Int {
        let database = try requireDatabase()
        return try database.pool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM provider_accounts"
            ) ?? 0
        }
    }

    public func insertIfEmpty(_ account: ProviderAccount) throws -> Bool {
        let database = try requireDatabase()
        let normalizedAccount = try Self.normalized([account])[0]
        return try database.pool.write { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM provider_accounts"
            ) ?? 0
            guard count == 0 else {
                return false
            }
            try Self.write([normalizedAccount], in: db)
            return true
        }
    }

    public func save(_ accounts: [ProviderAccount]) throws {
        let database = try requireDatabase()
        let normalizedAccounts = try Self.normalized(accounts)
        try database.pool.write { db in
            let existingKeys = try Set(Row.fetchAll(db, sql: "SELECT provider_id, account_id FROM provider_accounts").map {
                "\($0["provider_id"] as String):\($0["account_id"] as String)"
            })
            let retainedKeys = Set(normalizedAccounts.map(\.accountKey))
            for key in existingKeys.subtracting(retainedKeys) {
                let components = key.split(separator: ":", maxSplits: 1).map(String.init)
                let hasCredentialSlots = try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT EXISTS(
                            SELECT 1 FROM provider_credential_slots
                            WHERE provider_id = ? AND account_id = ?
                        )
                        """,
                    arguments: [components[0], components[1]]
                ) ?? false
                guard !hasCredentialSlots else {
                    throw StorageValidationError.accountContainsCredentials
                }
                try db.execute(
                    sql: "DELETE FROM provider_accounts WHERE provider_id = ? AND account_id = ?",
                    arguments: [components[0], components[1]]
                )
            }

            try Self.write(normalizedAccounts, in: db)
        }
    }

    public static func displayNameKey(for displayName: String) -> String {
        displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    static func write(_ accounts: [ProviderAccount], in db: Database) throws {
        for (index, account) in accounts.enumerated() {
            let nameKey = displayNameKey(for: account.displayName)
            try db.execute(
                sql: """
                    INSERT INTO provider_accounts (
                        provider_id, account_id, display_name, display_name_key,
                        is_enabled, source_mode, web_data_store_id,
                        executable_path, sort_index
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(provider_id, account_id) DO UPDATE SET
                        display_name = excluded.display_name,
                        display_name_key = excluded.display_name_key,
                        is_enabled = excluded.is_enabled,
                        source_mode = excluded.source_mode,
                        web_data_store_id = excluded.web_data_store_id,
                        executable_path = excluded.executable_path,
                        sort_index = excluded.sort_index
                    """,
                arguments: [
                    account.providerID,
                    account.accountID,
                    account.displayName,
                    nameKey,
                    account.isEnabled,
                    account.sourceMode.rawValue,
                    account.webDataStoreID?.uuidString,
                    account.executablePath,
                    index
                ]
            )
        }
    }

    static func normalized(_ accounts: [ProviderAccount]) throws -> [ProviderAccount] {
        var seen = Set<String>()
        var normalized: [ProviderAccount] = []
        for var account in accounts {
            let trimmed = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            account.displayName = trimmed.isEmpty ? ProviderAccount.defaultDisplayName : trimmed
            let key = displayNameKey(for: account.displayName)
            guard seen.insert(key).inserted else {
                throw StorageValidationError.duplicateDisplayName
            }
            normalized.append(account)
        }
        return normalized
    }

    private func requireDatabase() throws -> AppDatabase {
        guard let database else { throw AppDatabaseError.unavailable }
        return database
    }
}

public enum StorageValidationError: LocalizedError, Equatable, Sendable {
    case duplicateDisplayName
    case accountContainsCredentials

    public var errorDescription: String? {
        switch self {
        case .duplicateDisplayName:
            "Account names must be globally unique."
        case .accountContainsCredentials:
            "Account credentials must be securely deleted before removing the account."
        }
    }
}

public final class DatabaseSnapshotStore: CurrentSnapshotStore, @unchecked Sendable {
    private let database: AppDatabase?

    public init(database: AppDatabase?) {
        self.database = database
    }

    public func load() -> SnapshotLoadResult {
        guard let database else {
            return SnapshotLoadResult(snapshots: [], warning: "Snapshots could not be loaded.")
        }
        do {
            return SnapshotLoadResult(snapshots: try database.pool.read(fetchSnapshots))
        } catch {
            return SnapshotLoadResult(snapshots: [], warning: "Snapshots could not be loaded.")
        }
    }

    public func save(_ snapshots: [UsageSnapshot]) throws {
        let database = try requireDatabase()
        try database.pool.write { db in
            for snapshot in snapshots {
                try Self.upsert(snapshot, in: db)
            }
        }
    }

    public func snapshot(providerID: String, accountID: String) throws -> UsageSnapshot? {
        let database = try requireDatabase()
        return try database.pool.read { db in
            try fetchSnapshot(providerID: providerID, accountID: accountID, db: db)
        }
    }

    static func upsert(_ snapshot: UsageSnapshot, in db: Database) throws {
        let existingUpdatedAt = try Double.fetchOne(
            db,
            sql: "SELECT last_updated_at FROM current_snapshots WHERE provider_id = ? AND account_id = ?",
            arguments: [snapshot.providerID, snapshot.accountID]
        )
        guard existingUpdatedAt == nil || snapshot.lastUpdatedAt.timeIntervalSince1970 >= existingUpdatedAt! else {
            return
        }

        try db.execute(
            sql: """
                INSERT INTO current_snapshots (
                    provider_id, account_id, display_name, status, plan_name, period_label,
                    used_percent, remaining_label, reset_at, last_updated_at, confidence, source
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(provider_id, account_id) DO UPDATE SET
                    display_name = excluded.display_name,
                    status = excluded.status,
                    plan_name = excluded.plan_name,
                    period_label = excluded.period_label,
                    used_percent = excluded.used_percent,
                    remaining_label = excluded.remaining_label,
                    reset_at = excluded.reset_at,
                    last_updated_at = excluded.last_updated_at,
                    confidence = excluded.confidence,
                    source = excluded.source
                """,
            arguments: [
                snapshot.providerID,
                snapshot.accountID,
                snapshot.displayName,
                snapshot.status.rawValue,
                snapshot.planName,
                snapshot.periodLabel,
                snapshot.usedPercent,
                snapshot.remainingLabel,
                snapshot.resetAt?.timeIntervalSince1970,
                snapshot.lastUpdatedAt.timeIntervalSince1970,
                snapshot.confidence.rawValue,
                snapshot.source
            ]
        )
        try db.execute(
            sql: "DELETE FROM snapshot_limit_windows WHERE provider_id = ? AND account_id = ?",
            arguments: [snapshot.providerID, snapshot.accountID]
        )
        try db.execute(
            sql: "DELETE FROM snapshot_warnings WHERE provider_id = ? AND account_id = ?",
            arguments: [snapshot.providerID, snapshot.accountID]
        )
        for (position, window) in snapshot.limitWindows.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO snapshot_limit_windows (
                        provider_id, account_id, position, window_id, display_name,
                        used_percent, remaining_label, reset_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    snapshot.providerID,
                    snapshot.accountID,
                    position,
                    window.id,
                    window.displayName,
                    window.usedPercent,
                    window.remainingLabel,
                    window.resetAt?.timeIntervalSince1970
                ]
            )
        }
        for (position, warning) in snapshot.warnings.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO snapshot_warnings (provider_id, account_id, position, message)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [snapshot.providerID, snapshot.accountID, position, warning]
            )
        }
    }

    private func fetchSnapshots(_ db: Database) throws -> [UsageSnapshot] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT snapshots.*, accounts.display_name AS account_display_name
            FROM current_snapshots AS snapshots
            JOIN provider_accounts AS accounts
              ON accounts.provider_id = snapshots.provider_id
             AND accounts.account_id = snapshots.account_id
            ORDER BY accounts.sort_index ASC
            """)
        return try rows.compactMap { row in
            let providerID: String = row["provider_id"]
            let accountID: String = row["account_id"]
            return try fetchSnapshot(providerID: providerID, accountID: accountID, db: db, row: row)
        }
    }

    private func fetchSnapshot(providerID: String, accountID: String, db: Database, row: Row? = nil) throws -> UsageSnapshot? {
        let snapshotRow: Row?
        if let row {
            snapshotRow = row
        } else {
            snapshotRow = try Row.fetchOne(db, sql: """
                SELECT snapshots.*, accounts.display_name AS account_display_name
                FROM current_snapshots AS snapshots
                JOIN provider_accounts AS accounts
                  ON accounts.provider_id = snapshots.provider_id
                 AND accounts.account_id = snapshots.account_id
                WHERE snapshots.provider_id = ? AND snapshots.account_id = ?
                """, arguments: [providerID, accountID])
        }
        guard let snapshotRow,
              let status = UsageStatus(rawValue: snapshotRow["status"]),
              let confidence = ConfidenceLevel(rawValue: snapshotRow["confidence"])
        else { return nil }

        let windows = try Row.fetchAll(
            db,
            sql: """
                SELECT window_id, display_name, used_percent, remaining_label, reset_at
                FROM snapshot_limit_windows
                WHERE provider_id = ? AND account_id = ?
                ORDER BY position ASC
                """,
            arguments: [providerID, accountID]
        ).map { row in
            UsageLimitWindow(
                id: row["window_id"],
                displayName: row["display_name"],
                usedPercent: row["used_percent"],
                remainingLabel: row["remaining_label"],
                resetAt: (row["reset_at"] as Double?).map(Date.init(timeIntervalSince1970:))
            )
        }
        let warnings = try String.fetchAll(
            db,
            sql: """
                SELECT message FROM snapshot_warnings
                WHERE provider_id = ? AND account_id = ?
                ORDER BY position ASC
                """,
            arguments: [providerID, accountID]
        )
        return UsageSnapshot(
            providerID: providerID,
            accountID: accountID,
            accountDisplayName: snapshotRow["account_display_name"],
            displayName: snapshotRow["display_name"],
            status: status,
            planName: snapshotRow["plan_name"],
            periodLabel: snapshotRow["period_label"],
            usedPercent: snapshotRow["used_percent"],
            remainingLabel: snapshotRow["remaining_label"],
            resetAt: (snapshotRow["reset_at"] as Double?).map(Date.init(timeIntervalSince1970:)),
            limitWindows: windows,
            lastUpdatedAt: Date(timeIntervalSince1970: snapshotRow["last_updated_at"]),
            confidence: confidence,
            source: snapshotRow["source"],
            warnings: warnings
        )
    }

    private func requireDatabase() throws -> AppDatabase {
        guard let database else { throw AppDatabaseError.unavailable }
        return database
    }
}

public final class DatabaseRefreshSettingsStore: RefreshSettingsStoreProtocol, @unchecked Sendable {
    private let database: AppDatabase?

    public init(database: AppDatabase?) {
        self.database = database
    }

    public func load(defaults: RefreshSettings = RefreshSettings()) -> RefreshSettingsLoadResult {
        guard let database else {
            return RefreshSettingsLoadResult(settings: defaults, warning: "Refresh settings could not be loaded and defaults were used.")
        }
        do {
            let interval = try database.pool.read { db in
                try String.fetchOne(db, sql: "SELECT interval FROM refresh_settings WHERE id = 1")
            }
            guard let interval else { return RefreshSettingsLoadResult(settings: defaults) }
            guard let refreshInterval = RefreshInterval(rawValue: interval) else {
                return RefreshSettingsLoadResult(settings: defaults, warning: "Refresh settings could not be loaded and defaults were used.")
            }
            return RefreshSettingsLoadResult(settings: RefreshSettings(interval: refreshInterval))
        } catch {
            return RefreshSettingsLoadResult(settings: defaults, warning: "Refresh settings could not be loaded and defaults were used.")
        }
    }

    public func save(_ settings: RefreshSettings) throws {
        guard let database else { throw AppDatabaseError.unavailable }
        try database.pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO refresh_settings (id, interval) VALUES (1, ?)
                    ON CONFLICT(id) DO UPDATE SET interval = excluded.interval
                    """,
                arguments: [settings.interval.rawValue]
            )
        }
    }
}

public final class DatabaseSourceDiagnosticStore: SourceDiagnosticStore, @unchecked Sendable {
    private let database: AppDatabase?

    public init(database: AppDatabase?) {
        self.database = database
    }

    public func load() -> [SourceDiagnostic] {
        guard let database else { return [] }
        do {
            return try database.pool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT provider_id, account_id, code, message, occurred_at
                    FROM source_diagnostics
                    ORDER BY occurred_at ASC, id ASC
                    """).map { row in
                    SourceDiagnostic(
                        providerID: row["provider_id"],
                        accountID: row["account_id"],
                        code: row["code"],
                        message: row["message"],
                        occurredAt: Date(timeIntervalSince1970: row["occurred_at"])
                    )
                }
            }
        } catch {
            return []
        }
    }

    public func loadRefreshStates() -> [SourceRefreshState] {
        guard let database else { return [] }
        do {
            return try database.pool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT provider_id, account_id, last_attempt_at,
                           last_successful_refresh_at, last_failed_refresh_at
                    FROM source_refresh_state
                    """).map { row in
                    SourceRefreshState(
                        providerID: row["provider_id"],
                        accountID: row["account_id"],
                        lastAttemptAt: (row["last_attempt_at"] as Double?).map(Date.init(timeIntervalSince1970:)),
                        lastSuccessfulRefreshAt: (row["last_successful_refresh_at"] as Double?).map(Date.init(timeIntervalSince1970:)),
                        lastFailedRefreshAt: (row["last_failed_refresh_at"] as Double?).map(Date.init(timeIntervalSince1970:))
                    )
                }
            }
        } catch {
            return []
        }
    }

    public func recordRefreshAttempt(providerID: String, accountID: String, occurredAt: Date) throws {
        try upsertRefreshState(
            providerID: providerID,
            accountID: accountID,
            lastAttemptAt: occurredAt
        )
    }

    public func recordRefreshSuccess(providerID: String, accountID: String, occurredAt: Date) throws {
        try upsertRefreshState(
            providerID: providerID,
            accountID: accountID,
            lastAttemptAt: occurredAt,
            lastSuccessfulRefreshAt: occurredAt
        )
    }

    public func recordRefreshFailure(providerID: String, accountID: String, occurredAt: Date) throws {
        try upsertRefreshState(
            providerID: providerID,
            accountID: accountID,
            lastAttemptAt: occurredAt,
            lastFailedRefreshAt: occurredAt
        )
    }

    public func replaceRefreshDiagnostics(
        providerID: String,
        accountID: String,
        occurredAt: Date,
        messages: [String]
    ) throws {
        guard let database else { throw AppDatabaseError.unavailable }
        try database.pool.write { db in
            try db.execute(
                sql: "DELETE FROM source_diagnostics WHERE provider_id = ? AND account_id = ? AND code LIKE 'refresh-%'",
                arguments: [providerID, accountID]
            )
            for (index, message) in messages.enumerated() where !message.isEmpty {
                try db.execute(
                    sql: """
                        INSERT INTO source_diagnostics (provider_id, account_id, code, message, occurred_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [providerID, accountID, "refresh-\(index)", message, occurredAt.timeIntervalSince1970]
                )
            }
        }
    }

    public func clearRefreshDiagnostics(providerID: String, accountID: String) throws {
        guard let database else { throw AppDatabaseError.unavailable }
        try database.pool.write { db in
            try db.execute(
                sql: "DELETE FROM source_diagnostics WHERE provider_id = ? AND account_id = ? AND code LIKE 'refresh-%'",
                arguments: [providerID, accountID]
            )
        }
    }

    public func recordGlobal(code: String, message: String, occurredAt: Date = Date()) throws {
        guard let database else { throw AppDatabaseError.unavailable }
        try database.pool.write { db in
            try db.execute(sql: "DELETE FROM source_diagnostics WHERE provider_id IS NULL AND account_id IS NULL AND code = ?", arguments: [code])
            try db.execute(
                sql: "INSERT INTO source_diagnostics (code, message, occurred_at) VALUES (?, ?, ?)",
                arguments: [code, message, occurredAt.timeIntervalSince1970]
            )
        }
    }

    private func upsertRefreshState(
        providerID: String,
        accountID: String,
        lastAttemptAt: Date,
        lastSuccessfulRefreshAt: Date? = nil,
        lastFailedRefreshAt: Date? = nil
    ) throws {
        guard let database else { throw AppDatabaseError.unavailable }
        try database.pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO source_refresh_state (
                        provider_id, account_id, last_attempt_at,
                        last_successful_refresh_at, last_failed_refresh_at
                    ) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(provider_id, account_id) DO UPDATE SET
                        last_attempt_at = excluded.last_attempt_at,
                        last_successful_refresh_at = COALESCE(
                            excluded.last_successful_refresh_at,
                            source_refresh_state.last_successful_refresh_at
                        ),
                        last_failed_refresh_at = COALESCE(
                            excluded.last_failed_refresh_at,
                            source_refresh_state.last_failed_refresh_at
                        )
                    """,
                arguments: [
                    providerID,
                    accountID,
                    lastAttemptAt.timeIntervalSince1970,
                    lastSuccessfulRefreshAt?.timeIntervalSince1970,
                    lastFailedRefreshAt?.timeIntervalSince1970
                ]
            )
        }
    }
}
