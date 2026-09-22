import Foundation
import GRDB
import XCTest
@testable import BairometerCore

final class CredentialContextStoreTests: XCTestCase {
    func testCredentialContextsRoundTripWithIndependentItemsAndRefreshBoundaries() throws {
        let database = try configuredDatabase(accounts: [
            account(providerID: "openrouter", accountID: "personal")
        ])
        let keychain = FakeCredentialKeychainService()
        let store = AccountCredentialStore(
            database: database,
            keychainService: keychain
        )
        try createOpenRouterContextTree(
            store: store,
            providerID: "openrouter",
            accountID: "personal"
        )

        let firstSlot = try store.createCredential(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary-primary",
            contextID: "key-primary",
            role: .ordinary,
            credential: CredentialSecret("private-primary-value")
        )
        let secondSlot = try store.createCredential(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary-secondary",
            contextID: "key-secondary",
            role: .ordinary,
            credential: CredentialSecret("private-secondary-value")
        )
        let managementSlot = try store.createCredential(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "management",
            contextID: "billing-root",
            role: .management,
            credential: CredentialSecret("private-management-value")
        )

        XCTAssertEqual(
            Set([firstSlot, secondSlot, managementSlot].map(\.keychainReference)).count,
            3
        )
        XCTAssertEqual(keychain.items.count, 3)
        XCTAssertEqual(
            try value(
                store.readCredential(
                    providerID: "openrouter",
                    accountID: "personal",
                    slotID: "ordinary-primary"
                )
            ),
            "private-primary-value"
        )

        try store.replaceCredential(
            CredentialSecret("private-primary-replacement"),
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary-primary"
        )
        let loadedAfterReplace = try store.loadCredentialContexts(
            providerID: "openrouter",
            accountID: "personal"
        )
        XCTAssertEqual(
            loadedAfterReplace.first {
                $0.slot.slotID == "ordinary-primary"
            }?.slot.keychainReference,
            firstSlot.keychainReference
        )
        XCTAssertEqual(
            try value(
                store.readCredential(
                    providerID: "openrouter",
                    accountID: "personal",
                    slotID: "ordinary-primary"
                )
            ),
            "private-primary-replacement"
        )

        try store.setCredentialEnabled(
            false,
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary-secondary"
        )
        XCTAssertThrowsError(
            try store.readCredential(
                providerID: "openrouter",
                accountID: "personal",
                slotID: "ordinary-secondary"
            )
        ) {
            XCTAssertEqual($0 as? CredentialStoreError, .credentialDisabled)
        }
        try store.setCredentialEnabled(
            true,
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary-secondary"
        )

        try store.recordRefreshSuccess(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary-primary",
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        try store.recordRefreshFailure(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary-secondary",
            code: .authentication,
            occurredAt: Date(timeIntervalSince1970: 200)
        )

        let states = try store.loadRefreshStates(
            providerID: "openrouter",
            accountID: "personal"
        )
        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(
            states.first { $0.slotID == "ordinary-primary" }?
                .lastSuccessfulRefreshAt,
            Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(
            states.first { $0.slotID == "ordinary-secondary" }?
                .lastFailedRefreshAt,
            Date(timeIntervalSince1970: 200)
        )

        let diagnostics = try store.loadDiagnostics(
            providerID: "openrouter",
            accountID: "personal"
        )
        XCTAssertEqual(diagnostics.map(\.slotID), ["ordinary-secondary"])
        XCTAssertEqual(diagnostics.map(\.message), [
            "Credential authentication failed."
        ])

        try assertDatabaseDoesNotContain(
            [
                "private-primary-value",
                "private-primary-replacement",
                "private-secondary-value",
                "private-management-value"
            ],
            database: database
        )
    }

    func testContextTreeAndCredentialRoleValidationFailClosed() throws {
        let database = try configuredDatabase(accounts: [
            account(providerID: "openrouter", accountID: "personal")
        ])
        let store = AccountCredentialStore(
            database: database,
            keychainService: FakeCredentialKeychainService()
        )
        try store.createContext(
            context(
                providerID: "openrouter",
                accountID: "personal",
                contextID: "root",
                kind: .personal
            )
        )

        XCTAssertThrowsError(
            try store.createContext(
                context(
                    providerID: "openrouter",
                    accountID: "personal",
                    contextID: "second-root",
                    kind: .organization
                )
            )
        ) {
            XCTAssertEqual($0 as? CredentialStoreError, .invalidContextTree)
        }
        XCTAssertThrowsError(
            try store.createContext(
                context(
                    providerID: "openrouter",
                    accountID: "personal",
                    contextID: "missing-parent",
                    kind: .credential,
                    parentContextID: "unknown"
                )
            )
        ) {
            XCTAssertEqual($0 as? CredentialStoreError, .invalidContextTree)
        }

        try store.createContext(
            context(
                providerID: "openrouter",
                accountID: "personal",
                contextID: "ordinary",
                kind: .credential,
                parentContextID: "root"
            )
        )

        XCTAssertThrowsError(
            try store.createContext(
                context(
                    providerID: "openrouter",
                    accountID: "personal",
                    contextID: "credential-child",
                    kind: .project,
                    parentContextID: "ordinary"
                )
            )
        ) {
            XCTAssertEqual($0 as? CredentialStoreError, .invalidContextTree)
        }
        XCTAssertThrowsError(
            try store.createCredential(
                providerID: "openrouter",
                accountID: "personal",
                slotID: "wrong-ordinary",
                contextID: "root",
                role: .ordinary,
                credential: CredentialSecret("not-persisted")
            )
        ) {
            XCTAssertEqual($0 as? CredentialStoreError, .invalidCredentialRole)
        }
        XCTAssertThrowsError(
            try store.createCredential(
                providerID: "openrouter",
                accountID: "personal",
                slotID: "wrong-management",
                contextID: "ordinary",
                role: .management,
                credential: CredentialSecret("not-persisted")
            )
        ) {
            XCTAssertEqual($0 as? CredentialStoreError, .invalidCredentialRole)
        }

        try store.createCredential(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary",
            contextID: "ordinary",
            role: .ordinary,
            credential: CredentialSecret("private-role-validation-value")
        )
        XCTAssertThrowsError(
            try store.updateContext(
                context(
                    providerID: "openrouter",
                    accountID: "personal",
                    contextID: "ordinary",
                    kind: .project,
                    parentContextID: "root"
                )
            )
        ) {
            XCTAssertEqual($0 as? CredentialStoreError, .invalidCredentialRole)
        }
        XCTAssertEqual(
            try store.loadCredentialContexts(
                providerID: "openrouter",
                accountID: "personal"
            ).first?.context.kind,
            .credential
        )
    }

    func testManagementUniquenessAndAccountIsolation() throws {
        let database = try configuredDatabase(accounts: [
            account(providerID: "openrouter", accountID: "first"),
            account(providerID: "openrouter", accountID: "second")
        ])
        let keychain = FakeCredentialKeychainService()
        let store = AccountCredentialStore(
            database: database,
            keychainService: keychain
        )
        for accountID in ["first", "second"] {
            try store.createContext(
                context(
                    providerID: "openrouter",
                    accountID: accountID,
                    contextID: "root",
                    kind: .personal
                )
            )
            try store.createContext(
                context(
                    providerID: "openrouter",
                    accountID: accountID,
                    contextID: "ordinary",
                    kind: .credential,
                    parentContextID: "root"
                )
            )
        }

        try store.createCredential(
            providerID: "openrouter",
            accountID: "first",
            slotID: "first-key",
            contextID: "ordinary",
            role: .ordinary,
            credential: CredentialSecret("first-private-value")
        )
        try store.createCredential(
            providerID: "openrouter",
            accountID: "second",
            slotID: "second-key",
            contextID: "ordinary",
            role: .ordinary,
            credential: CredentialSecret("second-private-value")
        )
        try store.createCredential(
            providerID: "openrouter",
            accountID: "first",
            slotID: "management",
            contextID: "root",
            role: .management,
            credential: CredentialSecret("management-private-value")
        )

        XCTAssertThrowsError(
            try store.readCredential(
                providerID: "openrouter",
                accountID: "second",
                slotID: "first-key"
            )
        ) {
            XCTAssertEqual($0 as? CredentialStoreError, .slotNotFound)
        }
        XCTAssertEqual(
            try value(
                store.readCredential(
                    providerID: "openrouter",
                    accountID: "second",
                    slotID: "second-key"
                )
            ),
            "second-private-value"
        )

        try store.createContext(
            context(
                providerID: "openrouter",
                accountID: "first",
                contextID: "another-root-child",
                kind: .workspace,
                parentContextID: "root"
            )
        )
        XCTAssertThrowsError(
            try store.createCredential(
                providerID: "openrouter",
                accountID: "first",
                slotID: "second-management",
                contextID: "root",
                role: .management,
                credential: CredentialSecret("not-persisted")
            )
        ) {
            XCTAssertEqual(
                $0 as? CredentialStoreError,
                .managementCredentialAlreadyExists
            )
        }
    }

    func testKeychainCreateFailureLeavesRecoverableInaccessibleMetadata() throws {
        let database = try configuredDatabase(accounts: [
            account(providerID: "openrouter", accountID: "personal")
        ])
        let keychain = FakeCredentialKeychainService()
        let store = AccountCredentialStore(
            database: database,
            keychainService: keychain
        )
        try createSingleCredentialTree(store: store)
        keychain.createError = .accessDenied

        XCTAssertThrowsError(
            try store.createCredential(
                providerID: "openrouter",
                accountID: "personal",
                slotID: "ordinary",
                contextID: "ordinary",
                role: .ordinary,
                credential: CredentialSecret("private-create-value")
            )
        ) {
            XCTAssertEqual(
                $0 as? CredentialStoreError,
                .keychain(.accessDenied)
            )
            XCTAssertFalse(
                $0.localizedDescription.contains("private-create-value")
            )
        }
        let pending = try XCTUnwrap(
            store.loadCredentialContexts(
                providerID: "openrouter",
                accountID: "personal"
            ).first
        )
        XCTAssertEqual(pending.slot.lifecycleState, .pendingCreation)
        XCTAssertFalse(keychain.items.keys.contains(pending.slot.keychainReference))
        XCTAssertThrowsError(
            try store.readCredential(
                providerID: "openrouter",
                accountID: "personal",
                slotID: "ordinary"
            )
        ) {
            XCTAssertEqual(
                $0 as? CredentialStoreError,
                .credentialPendingCreation
            )
        }

        keychain.createError = nil
        let recovered = try store.recoverPendingCreation(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary",
            credential: CredentialSecret("private-recovered-value")
        )

        XCTAssertEqual(recovered.lifecycleState, .active)
        XCTAssertEqual(
            try value(
                store.readCredential(
                    providerID: "openrouter",
                    accountID: "personal",
                    slotID: "ordinary"
                )
            ),
            "private-recovered-value"
        )
    }

    func testDatabaseFinalizationFailuresKeepReferencedTombstonesForRetry() throws {
        let database = try configuredDatabase(accounts: [
            account(providerID: "openrouter", accountID: "personal")
        ])
        let keychain = FakeCredentialKeychainService()
        let baseMetadata = DatabaseCredentialMetadataStore(database: database)
        let metadata = FailingCredentialMetadataStore(base: baseMetadata)
        let store = AccountCredentialStore(
            metadataStore: metadata,
            keychainService: keychain
        )
        try createSingleCredentialTree(store: store)

        metadata.failNextActivation = true
        XCTAssertThrowsError(
            try store.createCredential(
                providerID: "openrouter",
                accountID: "personal",
                slotID: "ordinary",
                contextID: "ordinary",
                role: .ordinary,
                credential: CredentialSecret("private-activation-value")
            )
        ) {
            XCTAssertEqual($0 as? CredentialStoreError, .storageUnavailable)
        }
        var pending = try XCTUnwrap(
            store.loadCredentialContexts(
                providerID: "openrouter",
                accountID: "personal"
            ).first
        )
        XCTAssertEqual(pending.slot.lifecycleState, .pendingCreation)
        XCTAssertNotNil(keychain.items[pending.slot.keychainReference])

        _ = try store.recoverPendingCreation(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary"
        )

        metadata.failNextRemoval = true
        XCTAssertThrowsError(
            try store.deleteCredential(
                providerID: "openrouter",
                accountID: "personal",
                slotID: "ordinary"
            )
        ) {
            XCTAssertEqual($0 as? CredentialStoreError, .storageUnavailable)
        }
        pending = try XCTUnwrap(
            store.loadCredentialContexts(
                providerID: "openrouter",
                accountID: "personal"
            ).first
        )
        XCTAssertEqual(pending.slot.lifecycleState, .pendingDeletion)
        XCTAssertFalse(pending.slot.isEnabled)
        XCTAssertNil(keychain.items[pending.slot.keychainReference])
        XCTAssertThrowsError(
            try store.readCredential(
                providerID: "openrouter",
                accountID: "personal",
                slotID: "ordinary"
            )
        ) {
            XCTAssertEqual(
                $0 as? CredentialStoreError,
                .credentialPendingDeletion
            )
        }

        try store.deleteCredential(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary"
        )
        XCTAssertTrue(
            try store.loadCredentialContexts(
                providerID: "openrouter",
                accountID: "personal"
            ).isEmpty
        )
        XCTAssertEqual(
            try store.loadContexts(
                providerID: "openrouter",
                accountID: "personal"
            ).map(\.contextID),
            ["root"]
        )
    }

    func testDeleteFailureDisablesCredentialAndRawAccountDeleteIsRejected() throws {
        let database = try configuredDatabase(accounts: [
            account(providerID: "openrouter", accountID: "personal")
        ])
        let keychain = FakeCredentialKeychainService()
        let store = AccountCredentialStore(
            database: database,
            keychainService: keychain
        )
        try createSingleCredentialTree(store: store)
        let slot = try store.createCredential(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary",
            contextID: "ordinary",
            role: .ordinary,
            credential: CredentialSecret("private-delete-value")
        )
        keychain.deleteError = .accessDenied

        XCTAssertThrowsError(
            try store.deleteCredential(
                providerID: "openrouter",
                accountID: "personal",
                slotID: "ordinary"
            )
        ) {
            XCTAssertEqual(
                $0 as? CredentialStoreError,
                .keychain(.accessDenied)
            )
        }
        let pending = try XCTUnwrap(
            store.loadCredentialContexts(
                providerID: "openrouter",
                accountID: "personal"
            ).first
        )
        XCTAssertEqual(pending.slot.lifecycleState, .pendingDeletion)
        XCTAssertFalse(pending.slot.isEnabled)
        XCTAssertNotNil(keychain.items[slot.keychainReference])
        XCTAssertThrowsError(
            try DatabaseProviderConfigurationStore(database: database).save([])
        ) {
            XCTAssertEqual(
                $0 as? StorageValidationError,
                .accountContainsCredentials
            )
        }

        keychain.deleteError = nil
        try store.deleteCredential(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "ordinary"
        )
        XCTAssertNil(keychain.items[slot.keychainReference])
    }

    func testAccountDeleteFailureKeepsAllSlotsPendingAndRetryCleansEverything() throws {
        let account = account(providerID: "openrouter", accountID: "personal")
        let database = try configuredDatabase(accounts: [account])
        let keychain = FakeCredentialKeychainService()
        let store = AccountCredentialStore(
            database: database,
            keychainService: keychain
        )
        try createOpenRouterContextTree(
            store: store,
            providerID: "openrouter",
            accountID: "personal"
        )
        let first = try store.createCredential(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "first",
            contextID: "key-primary",
            role: .ordinary,
            credential: CredentialSecret("private-first-value")
        )
        let second = try store.createCredential(
            providerID: "openrouter",
            accountID: "personal",
            slotID: "second",
            contextID: "key-secondary",
            role: .ordinary,
            credential: CredentialSecret("private-second-value")
        )
        try DatabaseSnapshotStore(database: database).save([
            UsageSnapshot(
                providerID: account.providerID,
                accountID: account.accountID,
                accountDisplayName: account.displayName,
                displayName: "OpenRouter",
                status: .ok,
                lastUpdatedAt: Date(),
                confidence: .live,
                source: "Test"
            )
        ])
        keychain.deleteFailuresByReference[second.keychainReference] = .accessDenied

        XCTAssertThrowsError(
            try store.deleteAccount(
                providerID: "openrouter",
                accountID: "personal"
            )
        ) {
            XCTAssertEqual(
                $0 as? CredentialStoreError,
                .keychain(.accessDenied)
            )
        }
        let pending = try store.loadCredentialContexts(
            providerID: "openrouter",
            accountID: "personal"
        )
        XCTAssertEqual(Set(pending.map(\.slot.lifecycleState)), [.pendingDeletion])
        XCTAssertTrue(pending.allSatisfy { !$0.slot.isEnabled })
        XCTAssertNil(keychain.items[first.keychainReference])
        XCTAssertNotNil(keychain.items[second.keychainReference])
        XCTAssertEqual(
            DatabaseProviderConfigurationStore(database: database)
                .load(knownProviderIDs: ["openrouter"]).accounts.count,
            1
        )

        keychain.deleteFailuresByReference.removeAll()
        try store.deleteAccount(
            providerID: "openrouter",
            accountID: "personal"
        )

        XCTAssertTrue(keychain.items.isEmpty)
        XCTAssertTrue(
            DatabaseProviderConfigurationStore(database: database)
                .load(knownProviderIDs: ["openrouter"]).accounts.isEmpty
        )
        XCTAssertTrue(DatabaseSnapshotStore(database: database).load().snapshots.isEmpty)
    }

    func testCreateAndDeleteAreSerializedAcrossStoreInstances() throws {
        let database = try configuredDatabase(accounts: [
            account(providerID: "openrouter", accountID: "personal")
        ])
        let keychain = InterleavingCredentialKeychainService()
        let creatingStore = AccountCredentialStore(
            database: database,
            keychainService: keychain
        )
        let deletingStore = AccountCredentialStore(
            database: database,
            keychainService: keychain
        )
        try createSingleCredentialTree(store: creatingStore)

        keychain.blockNextCreate()
        let errors = ConcurrentErrorRecorder()
        let createReturned = DispatchSemaphore(value: 0)
        let deleteStarted = DispatchSemaphore(value: 0)
        let deleteReturned = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            do {
                try creatingStore.createCredential(
                    providerID: "openrouter",
                    accountID: "personal",
                    slotID: "ordinary",
                    contextID: "ordinary",
                    role: .ordinary,
                    credential: try CredentialSecret("private-race-value")
                )
            } catch {
                errors.record(error)
            }
            createReturned.signal()
        }

        XCTAssertEqual(
            keychain.createEntered.wait(timeout: .now() + 2),
            .success
        )

        DispatchQueue.global().async {
            deleteStarted.signal()
            do {
                try deletingStore.deleteCredential(
                    providerID: "openrouter",
                    accountID: "personal",
                    slotID: "ordinary"
                )
            } catch {
                errors.record(error)
            }
            deleteReturned.signal()
        }

        XCTAssertEqual(deleteStarted.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(
            deleteReturned.wait(timeout: .now() + 0.2),
            .timedOut,
            "Delete must wait until creation has completed its SQLite/Keychain sequence."
        )
        keychain.allowCreate.signal()
        XCTAssertEqual(createReturned.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(deleteReturned.wait(timeout: .now() + 2), .success)

        XCTAssertTrue(errors.descriptions.isEmpty, errors.descriptions.joined(separator: "\n"))
        XCTAssertTrue(keychain.isEmpty)
        XCTAssertTrue(
            try creatingStore.loadCredentialContexts(
                providerID: "openrouter",
                accountID: "personal"
            ).isEmpty
        )
    }

    func testRecoveryAndDeleteAreSerializedAcrossStoreInstances() throws {
        let database = try configuredDatabase(accounts: [
            account(providerID: "openrouter", accountID: "personal")
        ])
        let keychain = InterleavingCredentialKeychainService()
        let recoveringStore = AccountCredentialStore(
            database: database,
            keychainService: keychain
        )
        let deletingStore = AccountCredentialStore(
            database: database,
            keychainService: keychain
        )
        try createSingleCredentialTree(store: recoveringStore)

        keychain.failNextCreate()
        XCTAssertThrowsError(
            try recoveringStore.createCredential(
                providerID: "openrouter",
                accountID: "personal",
                slotID: "ordinary",
                contextID: "ordinary",
                role: .ordinary,
                credential: CredentialSecret("private-failed-value")
            )
        )

        keychain.blockNextCreate()
        let errors = ConcurrentErrorRecorder()
        let recoveryReturned = DispatchSemaphore(value: 0)
        let deleteStarted = DispatchSemaphore(value: 0)
        let deleteReturned = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            do {
                try recoveringStore.recoverPendingCreation(
                    providerID: "openrouter",
                    accountID: "personal",
                    slotID: "ordinary",
                    credential: try CredentialSecret("private-recovered-race-value")
                )
            } catch {
                errors.record(error)
            }
            recoveryReturned.signal()
        }

        XCTAssertEqual(
            keychain.createEntered.wait(timeout: .now() + 2),
            .success
        )

        DispatchQueue.global().async {
            deleteStarted.signal()
            do {
                try deletingStore.deleteCredential(
                    providerID: "openrouter",
                    accountID: "personal",
                    slotID: "ordinary"
                )
            } catch {
                errors.record(error)
            }
            deleteReturned.signal()
        }

        XCTAssertEqual(deleteStarted.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(
            deleteReturned.wait(timeout: .now() + 0.2),
            .timedOut,
            "Delete must wait until pending-creation recovery has completed."
        )
        keychain.allowCreate.signal()
        XCTAssertEqual(recoveryReturned.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(deleteReturned.wait(timeout: .now() + 2), .success)

        XCTAssertTrue(errors.descriptions.isEmpty, errors.descriptions.joined(separator: "\n"))
        XCTAssertTrue(keychain.isEmpty)
        XCTAssertTrue(
            try recoveringStore.loadCredentialContexts(
                providerID: "openrouter",
                accountID: "personal"
            ).isEmpty
        )
    }

    func testAdditiveMigrationPreservesExistingAccountsAndSnapshots() throws {
        let directory = temporaryDirectory()
        let account = account(providerID: "mock", accountID: "legacy")
        var database: AppDatabase? = try AppDatabase(directory: directory)
        try DatabaseProviderConfigurationStore(database: database).save([account])
        try DatabaseSnapshotStore(database: database).save([
            UsageSnapshot(
                providerID: account.providerID,
                accountID: account.accountID,
                accountDisplayName: account.displayName,
                displayName: "Mock",
                status: .ok,
                usedPercent: 42,
                lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
                confidence: .live,
                source: "Test"
            )
        ])
        try database?.pool.write { db in
            try db.execute(sql: "DROP TABLE credential_diagnostics")
            try db.execute(sql: "DROP TABLE credential_refresh_state")
            try db.execute(sql: "DROP TABLE provider_credential_slots")
            try db.execute(sql: "DROP TABLE provider_account_contexts")
            try db.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                arguments: ["v6-account-credential-contexts"]
            )
        }
        database = nil

        let migrated = try AppDatabase(directory: directory)
        let loadedAccounts = DatabaseProviderConfigurationStore(database: migrated)
            .load(knownProviderIDs: ["mock"]).accounts
        let loadedSnapshots = DatabaseSnapshotStore(database: migrated)
            .load().snapshots

        XCTAssertEqual(loadedAccounts, [account])
        XCTAssertEqual(loadedSnapshots.first?.usedPercent, 42)
        XCTAssertTrue(
            try AccountCredentialStore(
                database: migrated,
                keychainService: FakeCredentialKeychainService()
            ).loadContexts(providerID: "mock", accountID: "legacy").isEmpty
        )
    }

    func testCredentialSchemaContainsReferencesAndConfigurationButNoSecretColumns() throws {
        let database = try AppDatabase(directory: temporaryDirectory())
        let columns = try database.pool.read { db in
            try ["provider_account_contexts", "provider_credential_slots"]
                .flatMap { table in
                    try db.columns(in: table).map(\.name)
                }
        }
        let forbidden = [
            "secret",
            "token",
            "api_key",
            "cookie",
            "raw_payload",
            "raw_response",
            "credential_value"
        ]

        XCTAssertTrue(columns.contains("keychain_reference"))
        for name in forbidden {
            XCTAssertFalse(columns.contains(name), "Unexpected column: \(name)")
        }
    }

    private func configuredDatabase(
        accounts: [ProviderAccount]
    ) throws -> AppDatabase {
        let database = try AppDatabase(directory: temporaryDirectory())
        try DatabaseProviderConfigurationStore(database: database).save(accounts)
        return database
    }

    private func createSingleCredentialTree(
        store: AccountCredentialStore
    ) throws {
        try store.createContext(
            context(
                providerID: "openrouter",
                accountID: "personal",
                contextID: "root",
                kind: .personal
            )
        )
        try store.createContext(
            context(
                providerID: "openrouter",
                accountID: "personal",
                contextID: "ordinary",
                kind: .credential,
                parentContextID: "root"
            )
        )
    }

    private func createOpenRouterContextTree(
        store: AccountCredentialStore,
        providerID: String,
        accountID: String
    ) throws {
        try store.createContext(
            context(
                providerID: providerID,
                accountID: accountID,
                contextID: "billing-root",
                kind: .personal
            )
        )
        try store.createContext(
            context(
                providerID: providerID,
                accountID: accountID,
                contextID: "key-primary",
                kind: .credential,
                displayName: "Primary key",
                parentContextID: "billing-root"
            )
        )
        try store.createContext(
            context(
                providerID: providerID,
                accountID: accountID,
                contextID: "key-secondary",
                kind: .credential,
                displayName: "Secondary key",
                parentContextID: "billing-root"
            )
        )
    }

    private func account(
        providerID: String,
        accountID: String
    ) -> ProviderAccount {
        ProviderAccount(
            providerID: providerID,
            accountID: accountID,
            displayName: "\(providerID)-\(accountID)",
            isEnabled: true
        )
    }

    private func context(
        providerID: String,
        accountID: String,
        contextID: String,
        kind: AccountContextKind,
        displayName: String? = nil,
        parentContextID: String? = nil
    ) -> ProviderAccountContextConfiguration {
        ProviderAccountContextConfiguration(
            providerID: providerID,
            accountID: accountID,
            contextID: contextID,
            kind: kind,
            displayName: displayName,
            regionID: "global",
            parentContextID: parentContextID
        )
    }

    private func value(_ credential: CredentialSecret) throws -> String {
        try credential.withUTF8String { $0 }
    }

    private func assertDatabaseDoesNotContain(
        _ values: [String],
        database: AppDatabase
    ) throws {
        try database.pool.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
        let urls = [
            database.url,
            URL(fileURLWithPath: database.url.path + "-wal")
        ]
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            for value in values {
                XCTAssertNil(
                    data.range(of: Data(value.utf8)),
                    "Database persistence contains credential material."
                )
            }
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private final class FakeCredentialKeychainService: KeychainService, @unchecked Sendable {
    var items: [String: String] = [:]
    var createError: KeychainServiceError?
    var readError: KeychainServiceError?
    var replaceError: KeychainServiceError?
    var deleteError: KeychainServiceError?
    var deleteFailuresByReference: [String: KeychainServiceError] = [:]

    func createCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        if let createError {
            throw createError
        }
        guard items[reference] == nil else {
            throw KeychainServiceError.duplicateReference
        }
        items[reference] = try credential.withUTF8String { $0 }
    }

    func readCredential(reference: String) throws -> CredentialSecret {
        if let readError {
            throw readError
        }
        guard let value = items[reference] else {
            throw KeychainServiceError.credentialNotFound
        }
        return try CredentialSecret(value)
    }

    func replaceCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        if let replaceError {
            throw replaceError
        }
        guard items[reference] != nil else {
            throw KeychainServiceError.credentialNotFound
        }
        items[reference] = try credential.withUTF8String { $0 }
    }

    func deleteCredential(reference: String) throws {
        if let error = deleteFailuresByReference[reference] ?? deleteError {
            throw error
        }
        items.removeValue(forKey: reference)
    }
}

private final class InterleavingCredentialKeychainService: KeychainService, @unchecked Sendable {
    let createEntered = DispatchSemaphore(value: 0)
    let allowCreate = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var items: [String: String] = [:]
    private var shouldBlockNextCreate = false
    private var shouldFailNextCreate = false

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return items.isEmpty
    }

    func blockNextCreate() {
        lock.lock()
        shouldBlockNextCreate = true
        lock.unlock()
    }

    func failNextCreate() {
        lock.lock()
        shouldFailNextCreate = true
        lock.unlock()
    }

    func createCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        lock.lock()
        let shouldFail = shouldFailNextCreate
        shouldFailNextCreate = false
        let shouldBlock = shouldBlockNextCreate
        shouldBlockNextCreate = false
        lock.unlock()

        if shouldFail {
            throw KeychainServiceError.accessDenied
        }
        if shouldBlock {
            createEntered.signal()
            allowCreate.wait()
        }

        let value = try credential.withUTF8String { $0 }
        lock.lock()
        defer { lock.unlock() }
        guard items[reference] == nil else {
            throw KeychainServiceError.duplicateReference
        }
        items[reference] = value
    }

    func readCredential(reference: String) throws -> CredentialSecret {
        lock.lock()
        let value = items[reference]
        lock.unlock()
        guard let value else {
            throw KeychainServiceError.credentialNotFound
        }
        return try CredentialSecret(value)
    }

    func replaceCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        let value = try credential.withUTF8String { $0 }
        lock.lock()
        defer { lock.unlock() }
        guard items[reference] != nil else {
            throw KeychainServiceError.credentialNotFound
        }
        items[reference] = value
    }

    func deleteCredential(reference: String) throws {
        lock.lock()
        items.removeValue(forKey: reference)
        lock.unlock()
    }
}

private final class ConcurrentErrorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    var descriptions: [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func record(_ error: Error) {
        lock.lock()
        values.append(String(describing: error))
        lock.unlock()
    }
}

private final class FailingCredentialMetadataStore: CredentialMetadataStore, @unchecked Sendable {
    let base: any CredentialMetadataStore
    var failNextActivation = false
    var failNextRemoval = false

    init(base: any CredentialMetadataStore) {
        self.base = base
    }

    func loadContexts(
        providerID: String,
        accountID: String
    ) throws -> [ProviderAccountContextConfiguration] {
        try base.loadContexts(providerID: providerID, accountID: accountID)
    }

    func loadCredentialContexts(
        providerID: String,
        accountID: String
    ) throws -> [ProviderCredentialContext] {
        try base.loadCredentialContexts(providerID: providerID, accountID: accountID)
    }

    func createContext(_ context: ProviderAccountContextConfiguration) throws {
        try base.createContext(context)
    }

    func updateContext(_ context: ProviderAccountContextConfiguration) throws {
        try base.updateContext(context)
    }

    func insertPendingSlot(_ slot: ProviderCredentialSlot) throws {
        try base.insertPendingSlot(slot)
    }

    func loadSlot(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws -> ProviderCredentialSlot? {
        try base.loadSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
    }

    func activateSlot(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        if failNextActivation {
            failNextActivation = false
            throw CredentialStoreError.storageUnavailable
        }
        try base.activateSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
    }

    func setSlotEnabled(
        _ isEnabled: Bool,
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        try base.setSlotEnabled(
            isEnabled,
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
    }

    func markSlotPendingDeletion(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        try base.markSlotPendingDeletion(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
    }

    func markAccountSlotsPendingDeletion(
        providerID: String,
        accountID: String
    ) throws -> [ProviderCredentialSlot] {
        try base.markAccountSlotsPendingDeletion(
            providerID: providerID,
            accountID: accountID
        )
    }

    func removeSlotAndCredentialContext(
        providerID: String,
        accountID: String,
        slotID: String
    ) throws {
        if failNextRemoval {
            failNextRemoval = false
            throw CredentialStoreError.storageUnavailable
        }
        try base.removeSlotAndCredentialContext(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID
        )
    }

    func deleteAccount(providerID: String, accountID: String) throws {
        try base.deleteAccount(providerID: providerID, accountID: accountID)
    }

    func loadRefreshStates(
        providerID: String,
        accountID: String
    ) throws -> [CredentialContextRefreshState] {
        try base.loadRefreshStates(providerID: providerID, accountID: accountID)
    }

    func upsertRefreshState(
        providerID: String,
        accountID: String,
        slotID: String,
        lastAttemptAt: Date,
        lastSuccessfulRefreshAt: Date?,
        lastFailedRefreshAt: Date?
    ) throws {
        try base.upsertRefreshState(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            lastAttemptAt: lastAttemptAt,
            lastSuccessfulRefreshAt: lastSuccessfulRefreshAt,
            lastFailedRefreshAt: lastFailedRefreshAt
        )
    }

    func replaceDiagnostic(
        providerID: String,
        accountID: String,
        slotID: String,
        code: CredentialContextDiagnosticCode?,
        occurredAt: Date
    ) throws {
        try base.replaceDiagnostic(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID,
            code: code,
            occurredAt: occurredAt
        )
    }

    func loadDiagnostics(
        providerID: String,
        accountID: String
    ) throws -> [CredentialContextDiagnostic] {
        try base.loadDiagnostics(providerID: providerID, accountID: accountID)
    }
}
