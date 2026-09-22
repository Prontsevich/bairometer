import Foundation
import GRDB

public enum NativeCapacityStoreError: Error, LocalizedError, Equatable, Sendable {
    case unavailable
    case accountUnavailable
    case sourceIdentityChanged
    case invalidSnapshot

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Native capacity storage is unavailable."
        case .accountUnavailable:
            "The provider account is unavailable."
        case .sourceIdentityChanged:
            "The credential source changed before refresh completed."
        case .invalidSnapshot:
            "The normalized capacity snapshot is invalid."
        }
    }
}

public enum CapacitySourceIdentityExpectation: Equatable, Sendable {
    case slot(ProviderCredentialSlot)
    case slotWithDirectTeamParent(
        slot: ProviderCredentialSlot,
        teamContextID: String
    )
    case noEnabledManagementSlot
}

public struct CapacitySourceMutation: Sendable {
    public let providerID: String
    public let accountID: String
    public let contextID: String
    public let sourceID: String
    public let accountContexts: [AccountContext]
    public let metrics: [CapacityMetric]
    public let completedAt: Date
    public let identityExpectation: CapacitySourceIdentityExpectation
    public let generationValidator: @Sendable () -> Bool

    public init(
        providerID: String,
        accountID: String,
        contextID: String,
        sourceID: String,
        accountContexts: [AccountContext],
        metrics: [CapacityMetric],
        completedAt: Date,
        identityExpectation: CapacitySourceIdentityExpectation,
        generationValidator: @escaping @Sendable () -> Bool = { true }
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.contextID = contextID
        self.sourceID = sourceID
        self.accountContexts = accountContexts
        self.metrics = metrics
        self.completedAt = completedAt
        self.identityExpectation = identityExpectation
        self.generationValidator = generationValidator
    }
}

public enum NativeCapacityOutcomeCheckpoint: Sendable {
    case afterMetrics
    case afterRefreshState
    case afterDiagnostic
}

public struct NativeCapacityOutcomeControl: Sendable {
    public let attemptedAt: Date
    public let completedAt: Date
    public let generationValidator: @Sendable () -> Bool
    public let checkpoint: @Sendable (NativeCapacityOutcomeCheckpoint) throws -> Void

    public init(
        attemptedAt: Date,
        completedAt: Date,
        generationValidator: @escaping @Sendable () -> Bool = { true },
        checkpoint: @escaping @Sendable (NativeCapacityOutcomeCheckpoint) throws -> Void = { _ in }
    ) {
        self.attemptedAt = attemptedAt
        self.completedAt = completedAt
        self.generationValidator = generationValidator
        self.checkpoint = checkpoint
    }
}

public protocol NativeCapacitySnapshotStore: Sendable {
    func isCurrentSource(_ slot: ProviderCredentialSlot) throws -> Bool

    func load(
        providerID: String,
        accountID: String,
        surface: ProviderSurface,
        sources: [SourceDescriptor]
    ) throws -> CapacitySnapshot?

    func replaceManagementMetricsWithUnavailableIfAbsent(
        _ mutation: CapacitySourceMutation,
        surface: ProviderSurface,
        sources: [SourceDescriptor]
    ) throws -> CapacitySnapshot?

    func recordSourceSuccess(
        _ mutation: CapacitySourceMutation,
        control: NativeCapacityOutcomeControl,
        surface: ProviderSurface,
        sources: [SourceDescriptor]
    ) throws -> CapacitySnapshot

    func recordSourceFailure(
        slot: ProviderCredentialSlot,
        code: CredentialContextDiagnosticCode,
        retryNotBefore: Date?,
        control: NativeCapacityOutcomeControl
    ) throws

    func validateDeferredSource(
        slot: ProviderCredentialSlot,
        generationValidator: @escaping @Sendable () -> Bool
    ) throws
}

public final class DatabaseCapacitySnapshotStore:
    NativeCapacitySnapshotStore,
    @unchecked Sendable
{
    private let database: AppDatabase?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(database: AppDatabase?) {
        self.database = database

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    public func load(
        providerID: String,
        accountID: String,
        surface: ProviderSurface,
        sources: [SourceDescriptor]
    ) throws -> CapacitySnapshot? {
        guard let database else {
            throw NativeCapacityStoreError.unavailable
        }

        do {
            return try database.pool.read { db in
                try loadSnapshot(
                    providerID: providerID,
                    accountID: accountID,
                    surface: surface,
                    sources: sources,
                    db: db
                )
            }
        } catch let error as NativeCapacityStoreError {
            throw error
        } catch {
            throw NativeCapacityStoreError.unavailable
        }
    }

    public func isCurrentSource(_ slot: ProviderCredentialSlot) throws -> Bool {
        guard let database else {
            throw NativeCapacityStoreError.unavailable
        }
        do {
            return try database.pool.read { db in
                let accountEnabled = try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT is_enabled
                        FROM provider_accounts
                        WHERE provider_id = ? AND account_id = ?
                        """,
                    arguments: [slot.providerID, slot.accountID]
                ) == true
                guard accountEnabled,
                      slot.isEnabled,
                      slot.lifecycleState == .active,
                      let row = try Row.fetchOne(
                          db,
                          sql: """
                              SELECT context_id, role, is_enabled,
                                     keychain_reference, lifecycle_state,
                                     credential_revision
                              FROM provider_credential_slots
                              WHERE provider_id = ?
                                AND account_id = ?
                                AND slot_id = ?
                              """,
                          arguments: [
                              slot.providerID,
                              slot.accountID,
                              slot.slotID
                          ]
                      )
                else {
                    return false
                }
                return row["context_id"] as String == slot.contextID
                    && row["role"] as String == slot.role.rawValue
                    && row["is_enabled"] as Bool
                    && row["keychain_reference"] as String
                        == slot.keychainReference
                    && row["lifecycle_state"] as String
                        == CredentialLifecycleState.active.rawValue
                    && row["credential_revision"] as Int
                        == slot.credentialRevision
            }
        } catch {
            throw NativeCapacityStoreError.unavailable
        }
    }

    public func replaceManagementMetricsWithUnavailableIfAbsent(
        _ mutation: CapacitySourceMutation,
        surface: ProviderSurface,
        sources: [SourceDescriptor]
    ) throws -> CapacitySnapshot? {
        guard let database else {
            throw NativeCapacityStoreError.unavailable
        }
        guard case .noEnabledManagementSlot = mutation.identityExpectation,
              mutation.providerID == surface.providerID,
              mutation.sourceID
                == OpenRouterProviderContract.managementSourceID,
              mutation.metrics.count == 1,
              let sentinel = mutation.metrics.first,
              sentinel.metricID == "account-credits",
              sentinel.availability == .unavailable,
              sentinel.values == nil,
              sources.contains(where: {
                  $0.providerID == mutation.providerID
                      && $0.surfaceID == surface.surfaceID
                      && $0.sourceID == mutation.sourceID
              }),
              mutation.metrics.allSatisfy({
                  $0.accountContextID == mutation.contextID
                      && $0.sourceID == mutation.sourceID
              })
        else {
            throw NativeCapacityStoreError.invalidSnapshot
        }

        let lock = CredentialAccountOperationCoordinator.shared.lock(
            providerID: mutation.providerID,
            accountID: mutation.accountID
        )
        lock.lock()
        defer { lock.unlock() }
        do {
            return try database.pool.write { db in
                guard mutation.generationValidator() else {
                    throw NativeCapacityStoreError.sourceIdentityChanged
                }
                try requireEnabledAccount(mutation, db: db)
                let hasActiveManagementSlot = try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT EXISTS(
                            SELECT 1
                            FROM provider_credential_slots
                            WHERE provider_id = ?
                              AND account_id = ?
                              AND role = 'management'
                              AND is_enabled = 1
                              AND lifecycle_state = 'active'
                        )
                        """,
                    arguments: [mutation.providerID, mutation.accountID]
                ) ?? false
                guard !hasActiveManagementSlot else {
                    return nil
                }
                let snapshot = try replaceSourceMetricsInTransaction(
                    mutation,
                    surface: surface,
                    sources: sources,
                    db: db
                )
                try requireCurrentOutcome(
                    mutation,
                    validator: mutation.generationValidator,
                    db: db
                )
                return snapshot
            }
        } catch let error as NativeCapacityStoreError {
            throw error
        } catch {
            throw NativeCapacityStoreError.unavailable
        }
    }

    public func recordSourceSuccess(
        _ mutation: CapacitySourceMutation,
        control: NativeCapacityOutcomeControl,
        surface: ProviderSurface,
        sources: [SourceDescriptor]
    ) throws -> CapacitySnapshot {
        guard let database else { throw NativeCapacityStoreError.unavailable }
        let lock = CredentialAccountOperationCoordinator.shared.lock(
            providerID: mutation.providerID,
            accountID: mutation.accountID
        )
        lock.lock()
        defer { lock.unlock() }
        do {
            return try database.pool.write { db in
                try requireCurrentOutcome(mutation, validator: control.generationValidator, db: db)
                let snapshot = try replaceSourceMetricsInTransaction(
                    mutation,
                    surface: surface,
                    sources: sources,
                    db: db
                )
                try control.checkpoint(.afterMetrics)
                try upsertSuccessState(
                    slotID: slotID(for: mutation),
                    providerID: mutation.providerID,
                    accountID: mutation.accountID,
                    control: control,
                    db: db
                )
                try control.checkpoint(.afterRefreshState)
                try replaceDiagnostic(
                    providerID: mutation.providerID,
                    accountID: mutation.accountID,
                    slotID: slotID(for: mutation),
                    code: nil,
                    occurredAt: control.completedAt,
                    db: db
                )
                try control.checkpoint(.afterDiagnostic)
                try requireCurrentOutcome(mutation, validator: control.generationValidator, db: db)
                return snapshot
            }
        } catch let error as NativeCapacityStoreError {
            throw error
        } catch {
            throw NativeCapacityStoreError.unavailable
        }
    }

    public func recordSourceFailure(
        slot: ProviderCredentialSlot,
        code: CredentialContextDiagnosticCode,
        retryNotBefore: Date?,
        control: NativeCapacityOutcomeControl
    ) throws {
        guard let database else { throw NativeCapacityStoreError.unavailable }
        let mutation = identityMutation(for: slot, completedAt: control.completedAt)
        let lock = CredentialAccountOperationCoordinator.shared.lock(
            providerID: slot.providerID,
            accountID: slot.accountID
        )
        lock.lock()
        defer { lock.unlock() }
        do {
            try database.pool.write { db in
                try requireCurrentOutcome(mutation, validator: control.generationValidator, db: db)
                try upsertFailureState(
                    slot: slot,
                    retryNotBefore: retryNotBefore,
                    control: control,
                    db: db
                )
                try control.checkpoint(.afterRefreshState)
                try replaceDiagnostic(
                    providerID: slot.providerID,
                    accountID: slot.accountID,
                    slotID: slot.slotID,
                    code: code,
                    occurredAt: control.completedAt,
                    db: db
                )
                try control.checkpoint(.afterDiagnostic)
                try requireCurrentOutcome(mutation, validator: control.generationValidator, db: db)
            }
        } catch let error as NativeCapacityStoreError {
            throw error
        } catch {
            throw NativeCapacityStoreError.unavailable
        }
    }

    public func validateDeferredSource(
        slot: ProviderCredentialSlot,
        generationValidator: @escaping @Sendable () -> Bool
    ) throws {
        guard let database else { throw NativeCapacityStoreError.unavailable }
        let lock = CredentialAccountOperationCoordinator.shared.lock(
            providerID: slot.providerID,
            accountID: slot.accountID
        )
        lock.lock()
        defer { lock.unlock() }
        let mutation = identityMutation(for: slot, completedAt: Date())
        do {
            try database.pool.read { db in
                try requireCurrentOutcome(mutation, validator: generationValidator, db: db)
            }
        } catch let error as NativeCapacityStoreError {
            throw error
        } catch {
            throw NativeCapacityStoreError.unavailable
        }
    }

    private func replaceSourceMetricsInTransaction(
        _ mutation: CapacitySourceMutation,
        surface: ProviderSurface,
        sources: [SourceDescriptor],
        db: Database
    ) throws -> CapacitySnapshot {
        guard mutation.providerID == surface.providerID,
              sources.contains(where: {
                  $0.providerID == mutation.providerID
                      && $0.surfaceID == surface.surfaceID
                      && $0.sourceID == mutation.sourceID
              }),
              mutation.metrics.allSatisfy({
                  $0.accountContextID == mutation.contextID
                      && $0.sourceID == mutation.sourceID
              }),
              mutation.generationValidator()
        else {
            throw NativeCapacityStoreError.invalidSnapshot
        }
        try requireEnabledAccount(mutation, db: db)
        try requireCurrentIdentity(mutation, db: db)
        let metrics = try loadMetrics(
            providerID: mutation.providerID,
            accountID: mutation.accountID,
            excludingContextID: mutation.contextID,
            excludingSourceID: mutation.sourceID,
            db: db
        ) + mutation.metrics
        let snapshot = CapacitySnapshot(
            providerID: mutation.providerID,
            surfaceID: surface.surfaceID,
            savedAccountID: mutation.accountID,
            accountContexts: mutation.accountContexts,
            observedAt: metrics.map(\.freshness.observedAt).max() ?? mutation.completedAt,
            metrics: metrics
        )
        do {
            try ProviderContractValidator.validate(
                snapshot: snapshot,
                surface: surface,
                sources: sources
            )
        } catch {
            throw NativeCapacityStoreError.invalidSnapshot
        }
        try db.execute(
            sql: """
                INSERT INTO native_capacity_snapshots (
                    provider_id, account_id, contract_major, contract_minor,
                    surface_id, observed_at, completed_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(provider_id, account_id) DO UPDATE SET
                    contract_major = excluded.contract_major,
                    contract_minor = excluded.contract_minor,
                    surface_id = excluded.surface_id,
                    observed_at = excluded.observed_at,
                    completed_at = excluded.completed_at
                """,
            arguments: [
                mutation.providerID, mutation.accountID,
                Int64(snapshot.contractVersion.major),
                Int64(snapshot.contractVersion.minor), surface.surfaceID,
                snapshot.observedAt.timeIntervalSince1970,
                mutation.completedAt.timeIntervalSince1970
            ]
        )
        try db.execute(
            sql: """
                DELETE FROM native_capacity_metrics
                WHERE provider_id = ? AND account_id = ?
                  AND context_id = ? AND source_id = ?
                """,
            arguments: [
                mutation.providerID, mutation.accountID,
                mutation.contextID, mutation.sourceID
            ]
        )
        for metric in mutation.metrics {
            let data = try encoder.encode(metric)
            guard let json = String(data: data, encoding: .utf8) else {
                throw NativeCapacityStoreError.invalidSnapshot
            }
            try db.execute(
                sql: """
                    INSERT INTO native_capacity_metrics (
                        provider_id, account_id, context_id, source_id,
                        metric_id, normalized_metric_json, observed_at, completed_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    mutation.providerID, mutation.accountID,
                    mutation.contextID, mutation.sourceID, metric.metricID,
                    json, metric.freshness.observedAt.timeIntervalSince1970,
                    mutation.completedAt.timeIntervalSince1970
                ]
            )
        }
        guard mutation.generationValidator() else {
            throw NativeCapacityStoreError.sourceIdentityChanged
        }
        return snapshot
    }

    private func requireCurrentOutcome(
        _ mutation: CapacitySourceMutation,
        validator: @Sendable () -> Bool,
        db: Database
    ) throws {
        guard validator() else {
            throw NativeCapacityStoreError.sourceIdentityChanged
        }
        try requireEnabledAccount(mutation, db: db)
        try requireCurrentIdentity(mutation, db: db)
    }

    private func slotID(for mutation: CapacitySourceMutation) throws -> String {
        switch mutation.identityExpectation {
        case let .slot(slot),
             let .slotWithDirectTeamParent(slot, _):
            return slot.slotID
        case .noEnabledManagementSlot:
            throw NativeCapacityStoreError.sourceIdentityChanged
        }
    }

    private func identityMutation(
        for slot: ProviderCredentialSlot,
        completedAt: Date
    ) -> CapacitySourceMutation {
        CapacitySourceMutation(
            providerID: slot.providerID,
            accountID: slot.accountID,
            contextID: slot.contextID,
            sourceID: "",
            accountContexts: [],
            metrics: [],
            completedAt: completedAt,
            identityExpectation: .slot(slot)
        )
    }

    private func upsertSuccessState(
        slotID: String,
        providerID: String,
        accountID: String,
        control: NativeCapacityOutcomeControl,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO credential_refresh_state (
                    provider_id, account_id, slot_id, last_attempt_at,
                    last_successful_refresh_at, last_completed_at,
                    retry_not_before, consecutive_failure_count
                ) VALUES (?, ?, ?, ?, ?, ?, NULL, 0)
                ON CONFLICT(provider_id, account_id, slot_id) DO UPDATE SET
                    last_attempt_at = excluded.last_attempt_at,
                    last_successful_refresh_at = excluded.last_successful_refresh_at,
                    last_completed_at = excluded.last_completed_at,
                    retry_not_before = NULL,
                    consecutive_failure_count = 0
                """,
            arguments: [
                providerID, accountID, slotID,
                control.attemptedAt.timeIntervalSince1970,
                control.completedAt.timeIntervalSince1970,
                control.completedAt.timeIntervalSince1970
            ]
        )
    }

    private func upsertFailureState(
        slot: ProviderCredentialSlot,
        retryNotBefore: Date?,
        control: NativeCapacityOutcomeControl,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO credential_refresh_state (
                    provider_id, account_id, slot_id, last_attempt_at,
                    last_failed_refresh_at, last_completed_at,
                    retry_not_before, consecutive_failure_count
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 1)
                ON CONFLICT(provider_id, account_id, slot_id) DO UPDATE SET
                    last_attempt_at = excluded.last_attempt_at,
                    last_failed_refresh_at = excluded.last_failed_refresh_at,
                    last_completed_at = excluded.last_completed_at,
                    retry_not_before = excluded.retry_not_before,
                    consecutive_failure_count =
                        credential_refresh_state.consecutive_failure_count + 1
                """,
            arguments: [
                slot.providerID, slot.accountID, slot.slotID,
                control.attemptedAt.timeIntervalSince1970,
                control.completedAt.timeIntervalSince1970,
                control.completedAt.timeIntervalSince1970,
                retryNotBefore?.timeIntervalSince1970
            ]
        )
    }

    private func replaceDiagnostic(
        providerID: String,
        accountID: String,
        slotID: String,
        code: CredentialContextDiagnosticCode?,
        occurredAt: Date,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                DELETE FROM credential_diagnostics
                WHERE provider_id = ? AND account_id = ? AND slot_id = ?
                """,
            arguments: [providerID, accountID, slotID]
        )
        if let code {
            try db.execute(
                sql: """
                    INSERT INTO credential_diagnostics (
                        provider_id, account_id, slot_id, code, occurred_at
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    providerID, accountID, slotID, code.rawValue,
                    occurredAt.timeIntervalSince1970
                ]
            )
        }
    }

    private func loadSnapshot(
        providerID: String,
        accountID: String,
        surface: ProviderSurface,
        sources: [SourceDescriptor],
        db: Database
    ) throws -> CapacitySnapshot? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT contract_major, contract_minor, surface_id, observed_at
                FROM native_capacity_snapshots
                WHERE provider_id = ? AND account_id = ?
                """,
            arguments: [providerID, accountID]
        ) else {
            return nil
        }

        let contexts = try loadContexts(
            providerID: providerID,
            accountID: accountID,
            db: db
        )
        let snapshot = CapacitySnapshot(
            contractVersion: ContractVersion(
                major: UInt(row["contract_major"] as Int64),
                minor: UInt(row["contract_minor"] as Int64)
            ),
            providerID: providerID,
            surfaceID: row["surface_id"],
            savedAccountID: accountID,
            accountContexts: contexts,
            observedAt: Date(timeIntervalSince1970: row["observed_at"]),
            metrics: try loadMetrics(
                providerID: providerID,
                accountID: accountID,
                db: db
            )
        )
        do {
            try ProviderContractValidator.validate(
                snapshot: snapshot,
                surface: surface,
                sources: sources
            )
        } catch {
            throw NativeCapacityStoreError.invalidSnapshot
        }
        return snapshot
    }

    private func loadContexts(
        providerID: String,
        accountID: String,
        db: Database
    ) throws -> [AccountContext] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT context_id, kind, display_name, region_id, parent_context_id
                FROM provider_account_contexts
                WHERE provider_id = ? AND account_id = ?
                ORDER BY context_id
                """,
            arguments: [providerID, accountID]
        ).map { row in
            guard let kind = AccountContextKind(rawValue: row["kind"] as String) else {
                throw NativeCapacityStoreError.invalidSnapshot
            }
            return AccountContext(
                contextID: row["context_id"],
                kind: kind,
                displayName: row["display_name"],
                regionID: row["region_id"],
                parentContextID: row["parent_context_id"]
            )
        }
    }

    private func loadMetrics(
        providerID: String,
        accountID: String,
        excludingContextID: String? = nil,
        excludingSourceID: String? = nil,
        db: Database
    ) throws -> [CapacityMetric] {
        var sql = """
            SELECT normalized_metric_json
            FROM native_capacity_metrics
            WHERE provider_id = ? AND account_id = ?
            """
        var arguments: StatementArguments = [providerID, accountID]
        if let excludingContextID, let excludingSourceID {
            sql += """

                AND NOT (context_id = ? AND source_id = ?)
                """
            arguments += [excludingContextID, excludingSourceID]
        }
        sql += """

            ORDER BY context_id, source_id, metric_id
            """

        return try String.fetchAll(
            db,
            sql: sql,
            arguments: arguments
        ).map { normalizedJSON in
            guard let data = normalizedJSON.data(using: .utf8) else {
                throw NativeCapacityStoreError.invalidSnapshot
            }
            do {
                return try decoder.decode(CapacityMetric.self, from: data)
            } catch {
                throw NativeCapacityStoreError.invalidSnapshot
            }
        }
    }

    private func requireEnabledAccount(
        _ mutation: CapacitySourceMutation,
        db: Database
    ) throws {
        let isEnabled = try Bool.fetchOne(
            db,
            sql: """
                SELECT is_enabled
                FROM provider_accounts
                WHERE provider_id = ? AND account_id = ?
                """,
            arguments: [mutation.providerID, mutation.accountID]
        )
        guard isEnabled == true else {
            throw NativeCapacityStoreError.accountUnavailable
        }
    }

    private func requireCurrentIdentity(
        _ mutation: CapacitySourceMutation,
        db: Database
    ) throws {
        switch mutation.identityExpectation {
        case let .slot(slot):
            guard slot.contextID == mutation.contextID else {
                throw NativeCapacityStoreError.sourceIdentityChanged
            }
            try requireCurrentSlot(slot, mutation: mutation, db: db)

        case let .slotWithDirectTeamParent(slot, teamContextID):
            guard mutation.contextID == teamContextID,
                  slot.role == .ordinary
            else {
                throw NativeCapacityStoreError.sourceIdentityChanged
            }
            try requireCurrentSlot(slot, mutation: mutation, db: db)
            guard let contextRow = try Row.fetchOne(
                db,
                sql: """
                    SELECT child.kind AS child_kind,
                           child.parent_context_id AS parent_context_id,
                           child.region_id AS child_region_id,
                           parent.kind AS parent_kind,
                           parent.parent_context_id AS grandparent_context_id,
                           parent.region_id AS parent_region_id
                    FROM provider_account_contexts AS child
                    JOIN provider_account_contexts AS parent
                      ON parent.provider_id = child.provider_id
                     AND parent.account_id = child.account_id
                     AND parent.context_id = child.parent_context_id
                    WHERE child.provider_id = ?
                      AND child.account_id = ?
                      AND child.context_id = ?
                      AND parent.context_id = ?
                    """,
                arguments: [
                    mutation.providerID,
                    mutation.accountID,
                    slot.contextID,
                    teamContextID
                ]
            ),
                  contextRow["child_kind"] as String
                    == AccountContextKind.credential.rawValue,
                  contextRow["parent_context_id"] as String? == teamContextID,
                  contextRow["parent_kind"] as String
                    == AccountContextKind.team.rawValue,
                  contextRow["grandparent_context_id"] as String? == nil,
                  contextRow["child_region_id"] as String
                    == contextRow["parent_region_id"] as String
            else {
                throw NativeCapacityStoreError.sourceIdentityChanged
            }

        case .noEnabledManagementSlot:
            let count = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM provider_credential_slots
                    WHERE provider_id = ?
                      AND account_id = ?
                      AND role = 'management'
                      AND is_enabled = 1
                      AND lifecycle_state = 'active'
                    """,
                arguments: [mutation.providerID, mutation.accountID]
            ) ?? 0
            guard count == 0 else {
                throw NativeCapacityStoreError.sourceIdentityChanged
            }
        }
    }

    private func requireCurrentSlot(
        _ slot: ProviderCredentialSlot,
        mutation: CapacitySourceMutation,
        db: Database
    ) throws {
        guard slot.providerID == mutation.providerID,
              slot.accountID == mutation.accountID,
              slot.isEnabled,
              slot.lifecycleState == .active,
              let row = try Row.fetchOne(
                  db,
                  sql: """
                      SELECT context_id, role, is_enabled,
                             keychain_reference, lifecycle_state,
                             credential_revision
                      FROM provider_credential_slots
                      WHERE provider_id = ?
                        AND account_id = ?
                        AND slot_id = ?
                      """,
                  arguments: [
                      mutation.providerID,
                      mutation.accountID,
                      slot.slotID
                  ]
              ),
              row["context_id"] as String == slot.contextID,
              row["role"] as String == slot.role.rawValue,
              row["is_enabled"] as Bool,
              row["keychain_reference"] as String == slot.keychainReference,
              row["lifecycle_state"] as String
                == CredentialLifecycleState.active.rawValue,
              row["credential_revision"] as Int == slot.credentialRevision
        else {
            throw NativeCapacityStoreError.sourceIdentityChanged
        }
    }
}
