import Foundation
import GRDB

public final class AccountCredentialStore: @unchecked Sendable {
    private let metadataStore: any CredentialMetadataStore
    private let keychainService: any KeychainService
    private let operationCoordinator = CredentialAccountOperationCoordinator.shared

    public init(
        database: AppDatabase?,
        keychainService: any KeychainService = MacOSKeychainService()
    ) {
        metadataStore = DatabaseCredentialMetadataStore(database: database)
        self.keychainService = keychainService
    }

    init(
        metadataStore: any CredentialMetadataStore,
        keychainService: any KeychainService
    ) {
        self.metadataStore = metadataStore
        self.keychainService = keychainService
    }

    public func loadContexts(
        providerID: String,
        accountID: String
    ) throws -> [ProviderAccountContextConfiguration] {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        return try metadataStore.loadContexts(
            providerID: providerID,
            accountID: accountID
        )
    }

    public func loadCredentialContexts(
        providerID: String,
        accountID: String
    ) throws -> [ProviderCredentialContext] {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        return try metadataStore.loadCredentialContexts(
            providerID: providerID,
            accountID: accountID
        )
    }

    public func createContext(
        _ context: ProviderAccountContextConfiguration
    ) throws {
        let operationLock = accountOperationLock(
            providerID: context.providerID,
            accountID: context.accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        try metadataStore.createContext(context)
    }

    public func updateContext(
        _ context: ProviderAccountContextConfiguration
    ) throws {
        let operationLock = accountOperationLock(
            providerID: context.providerID,
            accountID: context.accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        try metadataStore.updateContext(context)
    }

    @discardableResult
    public func createCredential(
        providerID: String,
        accountID: String,
        slotID: String,
        contextID: String,
        role: ProviderCredentialRole,
        isEnabled: Bool = true,
        credential: CredentialSecret
    ) throws -> ProviderCredentialSlot {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        let reference = UUID().uuidString.lowercased()
        let pendingSlot = ProviderCredentialSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            contextID: contextID,
            role: role,
            isEnabled: isEnabled,
            keychainReference: reference,
            lifecycleState: .pendingCreation
        )
        try metadataStore.insertPendingSlot(pendingSlot)

        do {
            try keychainService.createCredential(credential, reference: reference)
        } catch {
            throw mapKeychainError(error)
        }

        try metadataStore.activateSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
        return try requireSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
    }

    @discardableResult
    public func recoverPendingCreation(
        providerID: String,
        accountID: String,
        slotID: String,
        credential: CredentialSecret? = nil
    ) throws -> ProviderCredentialSlot {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        let slot = try requireSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
        guard slot.lifecycleState == .pendingCreation else {
            return slot
        }

        do {
            if let credential {
                try metadataStore.incrementCredentialRevision(
                    providerID: providerID,
                    accountID: accountID,
                    slotID: slotID
                )
                do {
                    _ = try keychainService.readCredential(
                        reference: slot.keychainReference
                    )
                    try keychainService.replaceCredential(
                        credential,
                        reference: slot.keychainReference
                    )
                } catch KeychainServiceError.credentialNotFound {
                    try keychainService.createCredential(
                        credential,
                        reference: slot.keychainReference
                    )
                }
            } else {
                _ = try keychainService.readCredential(
                    reference: slot.keychainReference
                )
            }
        } catch {
            throw mapKeychainError(error)
        }

        try metadataStore.activateSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
        return try requireSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
    }

    public func readCredential(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws -> CredentialSecret {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        let slot = try readableSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
        do {
            return try keychainService.readCredential(
                reference: slot.keychainReference
            )
        } catch {
            throw mapKeychainError(error)
        }
    }

    public func replaceCredential(
        _ credential: CredentialSecret,
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        let slot = try requireSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
        switch slot.lifecycleState {
        case .active:
            break
        case .pendingCreation:
            throw CredentialStoreError.credentialPendingCreation
        case .pendingDeletion:
            throw CredentialStoreError.credentialPendingDeletion
        }

        try metadataStore.incrementCredentialRevision(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
        do {
            do {
                try keychainService.replaceCredential(
                    credential,
                    reference: slot.keychainReference
                )
            } catch KeychainServiceError.credentialNotFound {
                try keychainService.createCredential(
                    credential,
                    reference: slot.keychainReference
                )
            }
        } catch {
            throw mapKeychainError(error)
        }
    }

    public func setCredentialEnabled(
        _ isEnabled: Bool,
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        let slot = try requireSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
        switch slot.lifecycleState {
        case .active:
            break
        case .pendingCreation:
            throw CredentialStoreError.credentialPendingCreation
        case .pendingDeletion:
            throw CredentialStoreError.credentialPendingDeletion
        }

        if isEnabled {
            do {
                _ = try keychainService.readCredential(
                    reference: slot.keychainReference
                )
            } catch {
                throw mapKeychainError(error)
            }
        }

        try metadataStore.setSlotEnabled(
            isEnabled,
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
    }

    public func deleteCredential(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        let slot = try requireSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
        if slot.lifecycleState != .pendingDeletion {
            try metadataStore.markSlotPendingDeletion(
                providerID: providerID,
                accountID: accountID,
                slotID: slotID
            )
        }

        do {
            try keychainService.deleteCredential(
                reference: slot.keychainReference
            )
        } catch {
            throw mapKeychainError(error)
        }

        try metadataStore.removeSlotAndCredentialContext(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
    }

    public func deleteAccount(
        providerID: String,
        accountID: String
    ) throws {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        let slots = try metadataStore.markAccountSlotsPendingDeletion(
            providerID: providerID,
            accountID: accountID
        )

        for slot in slots {
            do {
                try keychainService.deleteCredential(
                    reference: slot.keychainReference
                )
            } catch {
                throw mapKeychainError(error)
            }
        }

        try metadataStore.deleteAccount(providerID: providerID, accountID: accountID)
    }

    public func loadRefreshStates(
        providerID: String,
        accountID: String
    ) throws -> [CredentialContextRefreshState] {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        return try metadataStore.loadRefreshStates(
            providerID: providerID,
            accountID: accountID
        )
    }

    public func recordRefreshAttempt(
        providerID: String,
        accountID: String,
        slotID: String,
        occurredAt: Date
    ) throws {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        try metadataStore.recordRefreshAttempt(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            occurredAt: occurredAt
        )
    }

    public func recordRefreshSuccess(
        providerID: String,
        accountID: String,
        slotID: String,
        occurredAt: Date,
        completedAt: Date? = nil
    ) throws {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        try metadataStore.recordRefreshSuccess(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            occurredAt: occurredAt,
            completedAt: completedAt ?? occurredAt
        )
    }

    public func recordRefreshFailure(
        providerID: String,
        accountID: String,
        slotID: String,
        code: CredentialContextDiagnosticCode,
        occurredAt: Date,
        completedAt: Date? = nil,
        retryNotBefore: Date? = nil
    ) throws {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        try metadataStore.recordRefreshFailure(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            occurredAt: occurredAt,
            completedAt: completedAt ?? occurredAt,
            retryNotBefore: retryNotBefore
        )
        try metadataStore.replaceDiagnostic(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            code: code,
            occurredAt: occurredAt
        )
    }

    public func clearDiagnostic(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        try metadataStore.replaceDiagnostic(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            code: nil,
            occurredAt: Date()
        )
    }

    public func loadDiagnostics(
        providerID: String,
        accountID: String
    ) throws -> [CredentialContextDiagnostic] {
        let operationLock = accountOperationLock(
            providerID: providerID,
            accountID: accountID
        )
        operationLock.lock()
        defer { operationLock.unlock() }
        return try metadataStore.loadDiagnostics(
            providerID: providerID,
            accountID: accountID
        )
    }

    private func readableSlot(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws -> ProviderCredentialSlot {
        let slot = try requireSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
        switch slot.lifecycleState {
        case .active:
            guard slot.isEnabled else {
                throw CredentialStoreError.credentialDisabled
            }
            return slot
        case .pendingCreation:
            throw CredentialStoreError.credentialPendingCreation
        case .pendingDeletion:
            throw CredentialStoreError.credentialPendingDeletion
        }
    }

    private func accountOperationLock(
        providerID: String,
        accountID: String
    ) -> NSRecursiveLock {
        operationCoordinator.lock(
            providerID: providerID,
            accountID: accountID
        )
    }

    private func requireSlot(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws -> ProviderCredentialSlot {
        guard let slot = try metadataStore.loadSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        ) else {
            throw CredentialStoreError.slotNotFound
        }
        return slot
    }

    private func mapKeychainError(_ error: Error) -> CredentialStoreError {
        guard let keychainError = error as? KeychainServiceError else {
            return .storageUnavailable
        }
        if keychainError == .credentialNotFound {
            return .credentialMissing
        }
        return .keychain(keychainError)
    }
}

final class CredentialAccountOperationCoordinator: @unchecked Sendable {
    static let shared = CredentialAccountOperationCoordinator()

    private struct AccountKey: Hashable {
        let providerID: String
        let accountID: String
    }

    private let registryLock = NSLock()
    private var locks: [AccountKey: NSRecursiveLock] = [:]

    private init() {}

    func lock(providerID: String, accountID: String) -> NSRecursiveLock {
        let key = AccountKey(providerID: providerID, accountID: accountID)
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = locks[key] {
            return existing
        }
        let created = NSRecursiveLock()
        locks[key] = created
        return created
    }
}

protocol CredentialMetadataStore: Sendable {
    func loadContexts(
        providerID: String,
        accountID: String
    ) throws -> [ProviderAccountContextConfiguration]
    func loadCredentialContexts(
        providerID: String,
        accountID: String
    ) throws -> [ProviderCredentialContext]
    func createContext(_ context: ProviderAccountContextConfiguration) throws
    func updateContext(_ context: ProviderAccountContextConfiguration) throws
    func insertPendingSlot(_ slot: ProviderCredentialSlot) throws
    func loadSlot(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws -> ProviderCredentialSlot?
    func activateSlot(providerID: String, accountID: String, slotID: String) throws
    func setSlotEnabled(
        _ isEnabled: Bool,
        providerID: String,
        accountID: String,
        slotID: String
    ) throws
    func incrementCredentialRevision(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws
    func markSlotPendingDeletion(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws
    func markAccountSlotsPendingDeletion(
        providerID: String,
        accountID: String
    ) throws -> [ProviderCredentialSlot]
    func removeSlotAndCredentialContext(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws
    func deleteAccount(providerID: String, accountID: String) throws
    func loadRefreshStates(
        providerID: String,
        accountID: String
    ) throws -> [CredentialContextRefreshState]
    func upsertRefreshState(
        providerID: String,
        accountID: String,
        slotID: String,
        lastAttemptAt: Date,
        lastSuccessfulRefreshAt: Date?,
        lastFailedRefreshAt: Date?
    ) throws
    func recordRefreshAttempt(
        providerID: String,
        accountID: String,
        slotID: String,
        occurredAt: Date
    ) throws
    func recordRefreshSuccess(
        providerID: String,
        accountID: String,
        slotID: String,
        occurredAt: Date,
        completedAt: Date
    ) throws
    func recordRefreshFailure(
        providerID: String,
        accountID: String,
        slotID: String,
        occurredAt: Date,
        completedAt: Date,
        retryNotBefore: Date?
    ) throws
    func replaceDiagnostic(
        providerID: String,
        accountID: String,
        slotID: String,
        code: CredentialContextDiagnosticCode?,
        occurredAt: Date
    ) throws
    func loadDiagnostics(
        providerID: String,
        accountID: String
    ) throws -> [CredentialContextDiagnostic]
}

extension CredentialMetadataStore {
    func incrementCredentialRevision(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {}

    func recordRefreshAttempt(
        providerID: String,
        accountID: String,
        slotID: String,
        occurredAt: Date
    ) throws {
        try upsertRefreshState(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            lastAttemptAt: occurredAt,
            lastSuccessfulRefreshAt: nil,
            lastFailedRefreshAt: nil
        )
    }

    func recordRefreshSuccess(
        providerID: String,
        accountID: String,
        slotID: String,
        occurredAt: Date,
        completedAt: Date
    ) throws {
        try upsertRefreshState(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            lastAttemptAt: occurredAt,
            lastSuccessfulRefreshAt: completedAt,
            lastFailedRefreshAt: nil
        )
    }

    func recordRefreshFailure(
        providerID: String,
        accountID: String,
        slotID: String,
        occurredAt: Date,
        completedAt: Date,
        retryNotBefore: Date?
    ) throws {
        try upsertRefreshState(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            lastAttemptAt: occurredAt,
            lastSuccessfulRefreshAt: nil,
            lastFailedRefreshAt: completedAt
        )
    }
}

final class DatabaseCredentialMetadataStore: CredentialMetadataStore, @unchecked Sendable {
    private let database: AppDatabase?

    init(database: AppDatabase?) {
        self.database = database
    }

    func loadContexts(
        providerID: String,
        accountID: String
    ) throws -> [ProviderAccountContextConfiguration] {
        let database = try requireDatabase()
        do {
            return try database.pool.read { db in
                try Self.fetchContexts(
                    providerID: providerID,
                    accountID: accountID,
                    db: db
                )
            }
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func loadCredentialContexts(
        providerID: String,
        accountID: String
    ) throws -> [ProviderCredentialContext] {
        let database = try requireDatabase()
        do {
            return try database.pool.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT
                            context.context_id,
                            context.kind,
                            context.display_name,
                            context.region_id,
                            context.parent_context_id,
                            slot.slot_id,
                            slot.role,
                            slot.is_enabled,
                            slot.keychain_reference,
                            slot.lifecycle_state,
                            slot.credential_revision
                        FROM provider_credential_slots AS slot
                        JOIN provider_account_contexts AS context
                          ON context.provider_id = slot.provider_id
                         AND context.account_id = slot.account_id
                         AND context.context_id = slot.context_id
                        WHERE slot.provider_id = ? AND slot.account_id = ?
                        ORDER BY slot.rowid ASC
                        """,
                    arguments: [providerID, accountID]
                )
                return try rows.map { row in
                    guard
                        let kind = AccountContextKind(
                            rawValue: row["kind"] as String
                        ),
                        let role = ProviderCredentialRole(
                            rawValue: row["role"] as String
                        ),
                        let lifecycleState = CredentialLifecycleState(
                            rawValue: row["lifecycle_state"] as String
                        )
                    else {
                        throw CredentialStoreError.storageUnavailable
                    }
                    let context = ProviderAccountContextConfiguration(
                        providerID: providerID,
                        accountID: accountID,
                        contextID: row["context_id"],
                        kind: kind,
                        displayName: row["display_name"],
                        regionID: row["region_id"],
                        parentContextID: row["parent_context_id"]
                    )
                    let slot = ProviderCredentialSlot(
                        providerID: providerID,
                        accountID: accountID,
                        slotID: row["slot_id"],
                        contextID: context.contextID,
                        role: role,
                        isEnabled: row["is_enabled"],
                        keychainReference: row["keychain_reference"],
                        lifecycleState: lifecycleState,
                        credentialRevision: row["credential_revision"]
                    )
                    return ProviderCredentialContext(context: context, slot: slot)
                }
            }
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func createContext(_ context: ProviderAccountContextConfiguration) throws {
        let database = try requireDatabase()
        do {
            try database.pool.write { db in
                try Self.requireAccount(
                    providerID: context.providerID,
                    accountID: context.accountID,
                    db: db
                )
                var contexts = try Self.fetchContexts(
                    providerID: context.providerID,
                    accountID: context.accountID,
                    db: db
                )
                guard !contexts.contains(where: { $0.contextID == context.contextID })
                else {
                    throw CredentialStoreError.invalidContextTree
                }
                let normalized = try Self.normalized(context)
                contexts.append(normalized)
                try Self.validate(contexts)
                try Self.insert(normalized, db: db)
            }
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func updateContext(_ context: ProviderAccountContextConfiguration) throws {
        let database = try requireDatabase()
        do {
            try database.pool.write { db in
                var contexts = try Self.fetchContexts(
                    providerID: context.providerID,
                    accountID: context.accountID,
                    db: db
                )
                guard let index = contexts.firstIndex(where: {
                    $0.contextID == context.contextID
                }) else {
                    throw CredentialStoreError.contextNotFound
                }
                let normalized = try Self.normalized(context)
                contexts[index] = normalized
                try Self.validate(contexts)
                if let roleRawValue = try String.fetchOne(
                    db,
                    sql: """
                        SELECT role
                        FROM provider_credential_slots
                        WHERE provider_id = ? AND account_id = ?
                          AND context_id = ?
                        """,
                    arguments: [
                        normalized.providerID,
                        normalized.accountID,
                        normalized.contextID
                    ]
                ) {
                    guard let role = ProviderCredentialRole(
                        rawValue: roleRawValue
                    ) else {
                        throw CredentialStoreError.storageUnavailable
                    }
                    try Self.validateRole(role, context: normalized)
                }
                try db.execute(
                    sql: """
                        UPDATE provider_account_contexts
                        SET kind = ?, display_name = ?, region_id = ?,
                            parent_context_id = ?
                        WHERE provider_id = ? AND account_id = ? AND context_id = ?
                        """,
                    arguments: [
                        normalized.kind.rawValue,
                        normalized.displayName,
                        normalized.regionID,
                        normalized.parentContextID,
                        normalized.providerID,
                        normalized.accountID,
                        normalized.contextID
                    ]
                )
            }
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func insertPendingSlot(_ slot: ProviderCredentialSlot) throws {
        let database = try requireDatabase()
        do {
            try database.pool.write { db in
                guard slot.lifecycleState == .pendingCreation,
                      !slot.slotID.isEmpty,
                      !slot.keychainReference.isEmpty
                else {
                    throw CredentialStoreError.storageUnavailable
                }
                guard let context = try Self.fetchContext(
                    providerID: slot.providerID,
                    accountID: slot.accountID,
                    contextID: slot.contextID,
                    db: db
                ) else {
                    throw CredentialStoreError.contextNotFound
                }
                try Self.validateRole(slot.role, context: context)

                if slot.role == .management,
                   try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT EXISTS(
                            SELECT 1 FROM provider_credential_slots
                            WHERE provider_id = ? AND account_id = ?
                              AND role = 'management'
                        )
                        """,
                    arguments: [slot.providerID, slot.accountID]
                   ) == true {
                    throw CredentialStoreError.managementCredentialAlreadyExists
                }
                if try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT EXISTS(
                            SELECT 1 FROM provider_credential_slots
                            WHERE provider_id = ? AND account_id = ?
                              AND context_id = ?
                        )
                        """,
                    arguments: [slot.providerID, slot.accountID, slot.contextID]
                ) == true {
                    throw CredentialStoreError.contextAlreadyHasCredential
                }

                try db.execute(
                    sql: """
                        INSERT INTO provider_credential_slots (
                            provider_id, account_id, slot_id, context_id, role,
                            is_enabled, keychain_reference, lifecycle_state,
                            credential_revision
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        slot.providerID,
                        slot.accountID,
                        slot.slotID,
                        slot.contextID,
                        slot.role.rawValue,
                        slot.isEnabled,
                        slot.keychainReference,
                        slot.lifecycleState.rawValue,
                        slot.credentialRevision
                    ]
                )
            }
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func loadSlot(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws -> ProviderCredentialSlot? {
        let database = try requireDatabase()
        do {
            return try database.pool.read { db in
                try Self.fetchSlot(
                    providerID: providerID,
                    accountID: accountID,
                    slotID: slotID,
                    db: db
                )
            }
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func activateSlot(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        try updateSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            requiredState: .pendingCreation,
            sql: """
                UPDATE provider_credential_slots
                SET lifecycle_state = 'active'
                WHERE provider_id = ? AND account_id = ? AND slot_id = ?
                  AND lifecycle_state = 'pending-creation'
                """
        )
    }

    func setSlotEnabled(
        _ isEnabled: Bool,
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        try updateSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            requiredState: .active,
            sql: """
                UPDATE provider_credential_slots
                SET is_enabled = ?
                WHERE provider_id = ? AND account_id = ? AND slot_id = ?
                  AND lifecycle_state = 'active'
                """,
            leadingArguments: [isEnabled]
        )
    }

    func incrementCredentialRevision(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        try updateSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            requiredState: nil,
            sql: """
                UPDATE provider_credential_slots
                SET credential_revision = credential_revision + 1
                WHERE provider_id = ? AND account_id = ? AND slot_id = ?
                """
        )
    }

    func markSlotPendingDeletion(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        let database = try requireDatabase()
        do {
            try database.pool.write { db in
                guard try Self.fetchSlot(
                    providerID: providerID,
                    accountID: accountID,
                    slotID: slotID,
                    db: db
                ) != nil else {
                    throw CredentialStoreError.slotNotFound
                }
                try db.execute(
                    sql: """
                        UPDATE provider_credential_slots
                        SET is_enabled = 0, lifecycle_state = 'pending-deletion'
                        WHERE provider_id = ? AND account_id = ? AND slot_id = ?
                        """,
                    arguments: [providerID, accountID, slotID]
                )
            }
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func markAccountSlotsPendingDeletion(
        providerID: String,
        accountID: String
    ) throws -> [ProviderCredentialSlot] {
        let database = try requireDatabase()
        do {
            return try database.pool.write { db in
                try Self.requireAccount(
                    providerID: providerID,
                    accountID: accountID,
                    db: db
                )
                try db.execute(
                    sql: """
                        UPDATE provider_credential_slots
                        SET is_enabled = 0, lifecycle_state = 'pending-deletion'
                        WHERE provider_id = ? AND account_id = ?
                        """,
                    arguments: [providerID, accountID]
                )
                return try Self.fetchSlots(
                    providerID: providerID,
                    accountID: accountID,
                    db: db
                )
            }
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func removeSlotAndCredentialContext(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        let database = try requireDatabase()
        do {
            try database.pool.write { db in
                guard let slot = try Self.fetchSlot(
                    providerID: providerID,
                    accountID: accountID,
                    slotID: slotID,
                    db: db
                ) else {
                    throw CredentialStoreError.slotNotFound
                }
                guard slot.lifecycleState == .pendingDeletion else {
                    throw CredentialStoreError.credentialPendingDeletion
                }
                try db.execute(
                    sql: """
                        DELETE FROM provider_credential_slots
                        WHERE provider_id = ? AND account_id = ? AND slot_id = ?
                        """,
                    arguments: [providerID, accountID, slotID]
                )
                if slot.role == .ordinary {
                    try db.execute(
                        sql: """
                            DELETE FROM provider_account_contexts
                            WHERE provider_id = ? AND account_id = ?
                              AND context_id = ? AND kind = 'credential'
                            """,
                        arguments: [providerID, accountID, slot.contextID]
                    )
                }
            }
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func deleteAccount(providerID: String, accountID: String) throws {
        let database = try requireDatabase()
        do {
            try database.pool.write { db in
                let unsafeCount = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM provider_credential_slots
                        WHERE provider_id = ? AND account_id = ?
                          AND lifecycle_state <> 'pending-deletion'
                        """,
                    arguments: [providerID, accountID]
                ) ?? 0
                guard unsafeCount == 0 else {
                    throw CredentialStoreError.credentialPendingDeletion
                }
                try db.execute(
                    sql: """
                        DELETE FROM provider_credential_slots
                        WHERE provider_id = ? AND account_id = ?
                        """,
                    arguments: [providerID, accountID]
                )
                try db.execute(
                    sql: """
                        DELETE FROM provider_accounts
                        WHERE provider_id = ? AND account_id = ?
                        """,
                    arguments: [providerID, accountID]
                )
            }
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func loadRefreshStates(
        providerID: String,
        accountID: String
    ) throws -> [CredentialContextRefreshState] {
        let database = try requireDatabase()
        do {
            return try database.pool.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT slot_id, last_attempt_at,
                               last_successful_refresh_at,
                               last_failed_refresh_at,
                               last_completed_at,
                               retry_not_before,
                               consecutive_failure_count
                        FROM credential_refresh_state
                        WHERE provider_id = ? AND account_id = ?
                        ORDER BY slot_id ASC
                        """,
                    arguments: [providerID, accountID]
                ).map { row in
                    CredentialContextRefreshState(
                        providerID: providerID,
                        accountID: accountID,
                        slotID: row["slot_id"],
                        lastAttemptAt: (row["last_attempt_at"] as Double?).map(
                            Date.init(timeIntervalSince1970:)
                        ),
                        lastSuccessfulRefreshAt: (
                            row["last_successful_refresh_at"] as Double?
                        ).map(Date.init(timeIntervalSince1970:)),
                        lastFailedRefreshAt: (
                            row["last_failed_refresh_at"] as Double?
                        ).map(Date.init(timeIntervalSince1970:)),
                        lastCompletedAt: (
                            row["last_completed_at"] as Double?
                        ).map(Date.init(timeIntervalSince1970:)),
                        retryNotBefore: (
                            row["retry_not_before"] as Double?
                        ).map(Date.init(timeIntervalSince1970:)),
                        consecutiveFailureCount: row["consecutive_failure_count"] as Int
                    )
                }
            }
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func recordRefreshAttempt(
        providerID: String,
        accountID: String,
        slotID: String,
        occurredAt: Date
    ) throws {
        let database = try requireDatabase()
        do {
            try database.pool.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO credential_refresh_state (
                            provider_id, account_id, slot_id, last_attempt_at
                        ) VALUES (?, ?, ?, ?)
                        ON CONFLICT(provider_id, account_id, slot_id) DO UPDATE SET
                            last_attempt_at = excluded.last_attempt_at
                        """,
                    arguments: [
                        providerID,
                        accountID,
                        slotID,
                        occurredAt.timeIntervalSince1970
                    ]
                )
            }
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func upsertRefreshState(
        providerID: String,
        accountID: String,
        slotID: String,
        lastAttemptAt: Date,
        lastSuccessfulRefreshAt: Date?,
        lastFailedRefreshAt: Date?
    ) throws {
        if let lastSuccessfulRefreshAt {
            try recordRefreshSuccess(
                providerID: providerID,
                accountID: accountID,
                slotID: slotID,
                occurredAt: lastAttemptAt,
                completedAt: lastSuccessfulRefreshAt
            )
        } else if let lastFailedRefreshAt {
            try recordRefreshFailure(
                providerID: providerID,
                accountID: accountID,
                slotID: slotID,
                occurredAt: lastAttemptAt,
                completedAt: lastFailedRefreshAt,
                retryNotBefore: nil
            )
        } else {
            try recordRefreshAttempt(
                providerID: providerID,
                accountID: accountID,
                slotID: slotID,
                occurredAt: lastAttemptAt
            )
        }
    }

    func recordRefreshSuccess(
        providerID: String,
        accountID: String,
        slotID: String,
        occurredAt: Date,
        completedAt: Date
    ) throws {
        let database = try requireDatabase()
        do {
            try database.pool.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO credential_refresh_state (
                            provider_id,
                            account_id,
                            slot_id,
                            last_attempt_at,
                            last_successful_refresh_at,
                            last_completed_at,
                            retry_not_before,
                            consecutive_failure_count
                        ) VALUES (?, ?, ?, ?, ?, ?, NULL, 0)
                        ON CONFLICT(provider_id, account_id, slot_id) DO UPDATE SET
                            last_attempt_at = excluded.last_attempt_at,
                            last_successful_refresh_at =
                                excluded.last_successful_refresh_at,
                            last_completed_at = excluded.last_completed_at,
                            retry_not_before = NULL,
                            consecutive_failure_count = 0
                        """,
                    arguments: [
                        providerID,
                        accountID,
                        slotID,
                        occurredAt.timeIntervalSince1970,
                        completedAt.timeIntervalSince1970,
                        completedAt.timeIntervalSince1970
                    ]
                )
            }
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func recordRefreshFailure(
        providerID: String,
        accountID: String,
        slotID: String,
        occurredAt: Date,
        completedAt: Date,
        retryNotBefore: Date?
    ) throws {
        let database = try requireDatabase()
        do {
            try database.pool.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO credential_refresh_state (
                            provider_id,
                            account_id,
                            slot_id,
                            last_attempt_at,
                            last_failed_refresh_at,
                            last_completed_at,
                            retry_not_before,
                            consecutive_failure_count
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
                        providerID,
                        accountID,
                        slotID,
                        occurredAt.timeIntervalSince1970,
                        completedAt.timeIntervalSince1970,
                        completedAt.timeIntervalSince1970,
                        retryNotBefore?.timeIntervalSince1970
                    ]
                )
            }
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func replaceDiagnostic(
        providerID: String,
        accountID: String,
        slotID: String,
        code: CredentialContextDiagnosticCode?,
        occurredAt: Date
    ) throws {
        let database = try requireDatabase()
        do {
            try database.pool.write { db in
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
                            providerID,
                            accountID,
                            slotID,
                            code.rawValue,
                            occurredAt.timeIntervalSince1970
                        ]
                    )
                }
            }
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    func loadDiagnostics(
        providerID: String,
        accountID: String
    ) throws -> [CredentialContextDiagnostic] {
        let database = try requireDatabase()
        do {
            return try database.pool.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT slot_id, code, occurred_at
                        FROM credential_diagnostics
                        WHERE provider_id = ? AND account_id = ?
                        ORDER BY occurred_at ASC, id ASC
                        """,
                    arguments: [providerID, accountID]
                ).map { row in
                    guard let code = CredentialContextDiagnosticCode(
                        rawValue: row["code"] as String
                    ) else {
                        throw CredentialStoreError.storageUnavailable
                    }
                    return CredentialContextDiagnostic(
                        providerID: providerID,
                        accountID: accountID,
                        slotID: row["slot_id"],
                        code: code,
                        occurredAt: Date(
                            timeIntervalSince1970: row["occurred_at"]
                        )
                    )
                }
            }
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    private func updateSlot(
        providerID: String,
        accountID: String,
        slotID: String,
        requiredState: CredentialLifecycleState?,
        sql: String,
        leadingArguments: StatementArguments = []
    ) throws {
        let database = try requireDatabase()
        do {
            try database.pool.write { db in
                guard let slot = try Self.fetchSlot(
                    providerID: providerID,
                    accountID: accountID,
                    slotID: slotID,
                    db: db
                ) else {
                    throw CredentialStoreError.slotNotFound
                }
                if let requiredState, slot.lifecycleState != requiredState {
                    switch slot.lifecycleState {
                    case .active:
                        throw CredentialStoreError.storageUnavailable
                    case .pendingCreation:
                        throw CredentialStoreError.credentialPendingCreation
                    case .pendingDeletion:
                        throw CredentialStoreError.credentialPendingDeletion
                    }
                }
                var arguments = leadingArguments
                arguments += [providerID, accountID, slotID]
                try db.execute(sql: sql, arguments: arguments)
            }
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.storageUnavailable
        }
    }

    private func requireDatabase() throws -> AppDatabase {
        guard let database else {
            throw CredentialStoreError.storageUnavailable
        }
        return database
    }

    private static func requireAccount(
        providerID: String,
        accountID: String,
        db: Database
    ) throws {
        let exists = try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM provider_accounts
                    WHERE provider_id = ? AND account_id = ?
                )
                """,
            arguments: [providerID, accountID]
        ) ?? false
        guard exists else {
            throw CredentialStoreError.accountNotFound
        }
    }

    private static func fetchContexts(
        providerID: String,
        accountID: String,
        db: Database
    ) throws -> [ProviderAccountContextConfiguration] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT context_id, kind, display_name, region_id, parent_context_id
                FROM provider_account_contexts
                WHERE provider_id = ? AND account_id = ?
                ORDER BY rowid ASC
                """,
            arguments: [providerID, accountID]
        ).map { row in
            guard let kind = AccountContextKind(rawValue: row["kind"] as String)
            else {
                throw CredentialStoreError.storageUnavailable
            }
            return ProviderAccountContextConfiguration(
                providerID: providerID,
                accountID: accountID,
                contextID: row["context_id"],
                kind: kind,
                displayName: row["display_name"],
                regionID: row["region_id"],
                parentContextID: row["parent_context_id"]
            )
        }
    }

    private static func fetchContext(
        providerID: String,
        accountID: String,
        contextID: String,
        db: Database
    ) throws -> ProviderAccountContextConfiguration? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT context_id, kind, display_name, region_id, parent_context_id
                FROM provider_account_contexts
                WHERE provider_id = ? AND account_id = ? AND context_id = ?
                """,
            arguments: [providerID, accountID, contextID]
        ) else {
            return nil
        }
        guard let kind = AccountContextKind(rawValue: row["kind"] as String)
        else {
            throw CredentialStoreError.storageUnavailable
        }
        return ProviderAccountContextConfiguration(
            providerID: providerID,
            accountID: accountID,
            contextID: row["context_id"],
            kind: kind,
            displayName: row["display_name"],
            regionID: row["region_id"],
            parentContextID: row["parent_context_id"]
        )
    }

    private static func fetchSlot(
        providerID: String,
        accountID: String,
        slotID: String,
        db: Database
    ) throws -> ProviderCredentialSlot? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT context_id, role, is_enabled, keychain_reference,
                       lifecycle_state, credential_revision
                FROM provider_credential_slots
                WHERE provider_id = ? AND account_id = ? AND slot_id = ?
                """,
            arguments: [providerID, accountID, slotID]
        ) else {
            return nil
        }
        guard
            let role = ProviderCredentialRole(rawValue: row["role"] as String),
            let lifecycleState = CredentialLifecycleState(
                rawValue: row["lifecycle_state"] as String
            )
        else {
            throw CredentialStoreError.storageUnavailable
        }
        return ProviderCredentialSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            contextID: row["context_id"],
            role: role,
            isEnabled: row["is_enabled"],
            keychainReference: row["keychain_reference"],
            lifecycleState: lifecycleState,
            credentialRevision: row["credential_revision"]
        )
    }

    private static func fetchSlots(
        providerID: String,
        accountID: String,
        db: Database
    ) throws -> [ProviderCredentialSlot] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT slot_id, context_id, role, is_enabled,
                       keychain_reference, lifecycle_state, credential_revision
                FROM provider_credential_slots
                WHERE provider_id = ? AND account_id = ?
                ORDER BY rowid ASC
                """,
            arguments: [providerID, accountID]
        ).map { row in
            guard
                let role = ProviderCredentialRole(rawValue: row["role"] as String),
                let lifecycleState = CredentialLifecycleState(
                    rawValue: row["lifecycle_state"] as String
                )
            else {
                throw CredentialStoreError.storageUnavailable
            }
            return ProviderCredentialSlot(
                providerID: providerID,
                accountID: accountID,
                slotID: row["slot_id"],
                contextID: row["context_id"],
                role: role,
                isEnabled: row["is_enabled"],
                keychainReference: row["keychain_reference"],
                lifecycleState: lifecycleState,
                credentialRevision: row["credential_revision"]
            )
        }
    }

    private static func normalized(
        _ context: ProviderAccountContextConfiguration
    ) throws -> ProviderAccountContextConfiguration {
        let contextID = context.contextID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let regionID = context.regionID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !contextID.isEmpty, !regionID.isEmpty else {
            throw CredentialStoreError.invalidContextTree
        }
        let displayName = context.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ProviderAccountContextConfiguration(
            providerID: context.providerID,
            accountID: context.accountID,
            contextID: contextID,
            kind: context.kind,
            displayName: displayName?.isEmpty == true ? nil : displayName,
            regionID: regionID,
            parentContextID: context.parentContextID
        )
    }

    private static func validate(
        _ contexts: [ProviderAccountContextConfiguration]
    ) throws {
        guard let first = contexts.first else {
            throw CredentialStoreError.invalidContextTree
        }
        guard contexts.allSatisfy({
            $0.providerID == first.providerID && $0.accountID == first.accountID
        }) else {
            throw CredentialStoreError.invalidContextTree
        }

        let contextIDs = Set(contexts.map(\.contextID))
        guard contextIDs.count == contexts.count else {
            throw CredentialStoreError.invalidContextTree
        }
        let roots = contexts.filter { $0.parentContextID == nil }
        guard roots.count == 1, roots[0].kind != .credential else {
            throw CredentialStoreError.invalidContextTree
        }
        guard contexts.allSatisfy({ context in
            guard let parentContextID = context.parentContextID else {
                return true
            }
            return contextIDs.contains(parentContextID)
                && parentContextID != context.contextID
        }) else {
            throw CredentialStoreError.invalidContextTree
        }

        let parentByID = Dictionary(
            uniqueKeysWithValues: contexts.map {
                ($0.contextID, $0.parentContextID)
            }
        )
        for context in contexts {
            var visited = Set<String>()
            var currentID: String? = context.contextID
            while let identifier = currentID {
                guard visited.insert(identifier).inserted else {
                    throw CredentialStoreError.invalidContextTree
                }
                currentID = parentByID[identifier] ?? nil
            }
        }

        let credentialIDs = Set(
            contexts.filter { $0.kind == .credential }.map(\.contextID)
        )
        guard contexts.allSatisfy({
            guard let parentContextID = $0.parentContextID else {
                return true
            }
            return !credentialIDs.contains(parentContextID)
        }) else {
            throw CredentialStoreError.invalidContextTree
        }
    }

    private static func validateRole(
        _ role: ProviderCredentialRole,
        context: ProviderAccountContextConfiguration
    ) throws {
        switch role {
        case .ordinary:
            guard context.kind == .credential,
                  context.parentContextID != nil else {
                throw CredentialStoreError.invalidCredentialRole
            }
        case .management:
            guard context.kind != .credential,
                  context.parentContextID == nil else {
                throw CredentialStoreError.invalidCredentialRole
            }
        }
    }

    private static func insert(
        _ context: ProviderAccountContextConfiguration,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO provider_account_contexts (
                    provider_id, account_id, context_id, kind,
                    display_name, region_id, parent_context_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                context.providerID,
                context.accountID,
                context.contextID,
                context.kind.rawValue,
                context.displayName,
                context.regionID,
                context.parentContextID
            ]
        )
    }
}
