@testable import BairometerCore
import Foundation
import GRDB
import XCTest

final class MiniMaxRefreshCoordinatorTests: XCTestCase {
    func testRegistryWiresExplicitSourceAndSanitizedAdapterProjection() async throws {
        XCTAssertEqual(
            ProviderSourceMode.defaultMode(for: "minimax"),
            .miniMaxTokenPlan
        )
        XCTAssertEqual(
            ProviderSourceMode.resolvedMode(.manual, for: "minimax"),
            .miniMaxTokenPlan
        )
        XCTAssertEqual(
            MiniMaxProviderContract.surface.accountContextKinds,
            [.team, .credential]
        )
        XCTAssertEqual(
            MiniMaxProviderContract.source.authRequirement.category,
            .subscriptionKey
        )
        XCTAssertEqual(
            MiniMaxProviderContract.source.authRequirement.storageBoundary,
            .keychain
        )

        let completedAt = Date(timeIntervalSince1970: 1_000)
        let refresher = StaticMiniMaxRefresher(
            result: MiniMaxAccountRefreshResult(
                snapshot: nil,
                completedAt: completedAt,
                successfulSourceCount: 1,
                failedSourceCount: 0,
                deferredSourceCount: 0,
                suppressedSourceCount: 0,
                configuredSourceCount: 1,
                hasMappingDiagnostics: false
            )
        )
        let registry = ProviderRegistry(
            ollamaWebPageClient: UnavailableOllamaWebPageClient(),
            miniMaxRefreshCoordinator: refresher
        )
        let adapter = try XCTUnwrap(
            registry.adaptersByID[MiniMaxProviderContract.providerID]
                as? MiniMaxProviderAdapter
        )
        XCTAssertEqual(
            adapter.capabilities.supportedSourceModes,
            [.miniMaxTokenPlan]
        )

        let snapshot = try await adapter.fetchSnapshot(
            account: miniMaxAccount("account")
        )
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.lastUpdatedAt, completedAt)
        XCTAssertNil(snapshot.usedPercent)
        XCTAssertNil(snapshot.resetAt)
        XCTAssertTrue(snapshot.limitWindows.isEmpty)
        XCTAssertEqual(
            snapshot.remainingLabel,
            "Native MiniMax Token Plan capacity stored"
        )
        XCTAssertFalse(snapshot.source.contains("account"))

        let defaultAdapter = try XCTUnwrap(
            ProviderRegistry.defaultAdapters.first {
                $0.id == MiniMaxProviderContract.providerID
            } as? MiniMaxProviderAdapter
        )
        await XCTAssertThrowsErrorAsync(
            try await defaultAdapter.fetchSnapshot(
                account: miniMaxAccount("default")
            )
        ) { error in
            XCTAssertEqual(
                error as? ProviderAdapterError,
                ProviderAdapterError(
                    providerID: "minimax",
                    message: "MiniMax credential refresh is unavailable."
                )
            )
        }

        var invalidSource = miniMaxAccount("invalid")
        invalidSource.sourceMode = .openRouterAPI
        await XCTAssertThrowsErrorAsync(
            try await adapter.fetchSnapshot(account: invalidSource)
        ) { error in
            XCTAssertEqual(
                error as? ProviderAdapterError,
                ProviderAdapterError(
                    providerID: "minimax",
                    message: "MiniMax source configuration is invalid."
                )
            )
        }
    }

    func testCoordinatorRequiresExactlyOneEnabledOrdinarySlot() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["first", "second"])
        ])
        let client = ScriptedMiniMaxClient()
        await client.enqueue(.success(1))
        let coordinator = makeCoordinator(environment: environment, client: client)

        await XCTAssertThrowsErrorAsync(
            try await coordinator.refresh(account: environment.accounts["account"]!)
        ) { error in
            XCTAssertEqual(
                error as? ProviderAdapterError,
                ProviderAdapterError(
                    providerID: "minimax",
                    message: "MiniMax requires exactly one enabled Subscription Key."
                )
            )
        }
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testSuccessfulRefreshPersistsOnlyTeamMetricsAndSanitizedState() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        await client.enqueue(
            .success(4, hasMappingDiagnostic: true)
        )
        let coordinator = makeCoordinator(environment: environment, client: client)

        let result = try await coordinator.refresh(
            account: environment.accounts["account"]!
        )
        let snapshot = try XCTUnwrap(result.snapshot)
        let teamContextID = environment.teamContextIDs["account"]!
        let credentialContextID = environment.credentialContextIDs["account"]!.first!

        XCTAssertEqual(result.successfulSourceCount, 1)
        XCTAssertTrue(result.hasMappingDiagnostics)
        XCTAssertEqual(snapshot.metrics.count, 1)
        XCTAssertEqual(snapshot.metrics.first?.metricID, "quota-category-a.current")
        XCTAssertTrue(snapshot.metrics.allSatisfy {
            $0.accountContextID == teamContextID
        })
        XCTAssertFalse(snapshot.metrics.contains {
            $0.accountContextID == credentialContextID
        })
        XCTAssertEqual(snapshot.metrics.first?.unit, CapacityUnit(kind: .percent))
        XCTAssertEqual(snapshot.metrics.first?.values?.consumed?.value, 4)
        XCTAssertEqual(snapshot.metrics.first?.values?.consumed?.origin, .derived)
        XCTAssertEqual(snapshot.metrics.first?.values?.remaining?.value, 96)
        XCTAssertEqual(snapshot.metrics.first?.values?.remaining?.origin, .reported)
        XCTAssertEqual(snapshot.metrics.first?.values?.limit?.value, 100)
        XCTAssertEqual(snapshot.metrics.first?.derivations, [
            Derivation(
                kind: .consumedFromLimitMinusRemaining,
                target: .consumed,
                inputs: [.limit, .remaining]
            )
        ])
        XCTAssertEqual(
            snapshot.metrics.first?.displayName,
            "Included usage — current rolling window"
        )
        XCTAssertFalse(snapshot.metrics.first?.displayName.contains("general") == true)
        XCTAssertFalse(snapshot.metrics.first?.displayName.contains("video") == true)

        let states = try environment.credentialStore.loadRefreshStates(
            providerID: "minimax",
            accountID: "account"
        )
        XCTAssertNotNil(states.first?.lastSuccessfulRefreshAt)
        XCTAssertNil(states.first?.lastFailedRefreshAt)
        XCTAssertEqual(states.first?.consecutiveFailureCount, 0)

        let credentialDiagnostics = try environment.credentialStore.loadDiagnostics(
            providerID: "minimax",
            accountID: "account"
        )
        XCTAssertTrue(credentialDiagnostics.isEmpty)
        let sourceDiagnostics = environment.diagnosticStore.load().filter {
            $0.providerID == "minimax" && $0.accountID == "account"
        }
        XCTAssertEqual(sourceDiagnostics.count, 1)
        XCTAssertEqual(
            sourceDiagnostics.first?.message,
            "MiniMax ignored an unrecognized quota category."
        )
        XCTAssertFalse(sourceDiagnostics.first?.message.contains("4") == true)
        XCTAssertFalse(sourceDiagnostics.first?.message.contains("secret") == true)
    }

    func testMalformedAndExpiredFailuresPreserveLastValidSnapshot() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        let coordinator = makeCoordinator(environment: environment, client: client)
        await client.enqueue(.success(3))
        _ = try await coordinator.refresh(account: environment.accounts["account"]!)

        await client.enqueue(.malformed)
        let malformed = try await coordinator.refresh(
            account: environment.accounts["account"]!
        )
        XCTAssertEqual(malformed.failedSourceCount, 1)
        XCTAssertFalse(malformed.hasMappingDiagnostics)
        XCTAssertEqual(try consumedValue(malformed.snapshot), 3)
        XCTAssertEqual(
            try environment.credentialStore.loadDiagnostics(
                providerID: "minimax",
                accountID: "account"
            ).first?.code,
            .transientFailure
        )

        await client.enqueue(
            .failure(.unavailableSubscription)
        )
        let expired = try await coordinator.refresh(
            account: environment.accounts["account"]!
        )
        XCTAssertEqual(expired.failedSourceCount, 1)
        XCTAssertEqual(try consumedValue(expired.snapshot), 3)
        XCTAssertEqual(
            try environment.credentialStore.loadDiagnostics(
                providerID: "minimax",
                accountID: "account"
            ).first?.code,
            .insufficientPrivilege
        )
        let states = try environment.credentialStore.loadRefreshStates(
            providerID: "minimax",
            accountID: "account"
        )
        XCTAssertNotNil(states.first?.lastSuccessfulRefreshAt)
        XCTAssertNotNil(states.first?.lastFailedRefreshAt)
        XCTAssertEqual(states.first?.consecutiveFailureCount, 2)
    }

    func testUnavailableSubscriptionProjectionRemainsDistinctFromAuthentication() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        let coordinator = makeCoordinator(environment: environment, client: client)
        let account = try XCTUnwrap(environment.accounts["account"])

        await client.enqueue(.failure(.unavailableSubscription))
        let unavailable = try await coordinator.refresh(account: account)
        XCTAssertEqual(unavailable.failureDiagnosticCode, .insufficientPrivilege)
        XCTAssertEqual(
            try environment.credentialStore.loadDiagnostics(
                providerID: account.providerID,
                accountID: account.accountID
            ).first?.code,
            .insufficientPrivilege
        )

        let adapter = MiniMaxProviderAdapter(
            refreshCoordinator: StaticMiniMaxRefresher(result: unavailable)
        )
        let failureSnapshot = try await adapter.fetchSnapshot(account: account)
        XCTAssertEqual(
            failureSnapshot.warnings,
            [MiniMaxProviderContract.unavailableSubscriptionWarning]
        )

        await client.enqueue(.failure(.authenticationFailure))
        let authentication = try await coordinator.refresh(account: account)
        XCTAssertEqual(authentication.failureDiagnosticCode, .authentication)
        XCTAssertEqual(
            try environment.credentialStore.loadDiagnostics(
                providerID: account.providerID,
                accountID: account.accountID
            ).first?.code,
            .authentication
        )

        await client.enqueue(.success(5))
        let success = try await coordinator.refresh(account: account)
        XCTAssertNil(success.failureDiagnosticCode)
        XCTAssertEqual(try consumedValue(success.snapshot), 5)
        XCTAssertTrue(
            try environment.credentialStore.loadDiagnostics(
                providerID: account.providerID,
                accountID: account.accountID
            ).isEmpty
        )
    }

    func testUnknownQuotaCategoryOnlyPreservesSnapshotAndPersistsSanitizedDiagnostic() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        let coordinator = makeCoordinator(environment: environment, client: client)
        await client.enqueue(.success(3))
        let previous = try await coordinator.refresh(
            account: environment.accounts["account"]!
        )
        let previousObservedAt = try XCTUnwrap(
            previous.snapshot?.metrics.first?.freshness.observedAt
        )

        await client.enqueue(.unknownQuotaCategoryOnly)
        let result = try await coordinator.refresh(
            account: environment.accounts["account"]!
        )

        XCTAssertEqual(result.successfulSourceCount, 0)
        XCTAssertEqual(result.failedSourceCount, 0)
        XCTAssertTrue(result.hasMappingDiagnostics)
        XCTAssertEqual(try consumedValue(result.snapshot), 3)
        XCTAssertEqual(
            result.snapshot?.metrics.first?.freshness.observedAt,
            previousObservedAt
        )
        let persisted = try environment.capacityStore.load(
            providerID: "minimax",
            accountID: "account",
            surface: MiniMaxProviderContract.surface,
            sources: MiniMaxProviderContract.sources
        )
        XCTAssertEqual(try consumedValue(persisted), 3)
        XCTAssertEqual(
            persisted?.metrics.first?.freshness.observedAt,
            previousObservedAt
        )
        XCTAssertTrue(
            try environment.credentialStore.loadDiagnostics(
                providerID: "minimax",
                accountID: "account"
            ).isEmpty
        )
        let sourceDiagnostics = environment.diagnosticStore.load().filter {
            $0.providerID == "minimax" && $0.accountID == "account"
        }
        XCTAssertEqual(sourceDiagnostics.count, 1)
        XCTAssertEqual(
            sourceDiagnostics.first?.message,
            "MiniMax ignored an unrecognized quota category."
        )
    }

    func testPostFetchInvalidationCancelsBeforeNativePersistence() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        await client.enqueue(.success(1))
        let baselineCoordinator = makeCoordinator(
            environment: environment,
            client: client
        )
        _ = try await baselineCoordinator.refresh(
            account: environment.accounts["account"]!
        )

        let gate = MiniMaxPostFetchGate()
        let coordinator = makeCoordinator(
            environment: environment,
            client: client,
            postFetchCheckpoint: { await gate.wait() }
        )
        await client.enqueue(.success(8))
        let refresh = Task {
            try await coordinator.refresh(account: environment.accounts["account"]!)
        }
        await gate.waitForEntry()
        coordinator.invalidateAccount(providerID: "minimax", accountID: "account")
        await gate.release()

        await XCTAssertThrowsErrorAsync(try await refresh.value) { error in
            XCTAssertTrue(error is CancellationError)
        }
        let persisted = try environment.capacityStore.load(
            providerID: "minimax",
            accountID: "account",
            surface: MiniMaxProviderContract.surface,
            sources: MiniMaxProviderContract.sources
        )
        XCTAssertEqual(try consumedValue(persisted), 1)
        XCTAssertTrue(
            environment.diagnosticStore.load().filter {
                $0.providerID == "minimax" && $0.accountID == "account"
            }.isEmpty
        )
        XCTAssertTrue(
            try environment.credentialStore.loadDiagnostics(
                providerID: "minimax",
                accountID: "account"
            ).isEmpty
        )
    }

    func testInvalidatedUnknownQuotaCategoryOnlyResultCancelsWithoutDiagnostics() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        let coordinator = makeCoordinator(environment: environment, client: client)
        await client.enqueue(.success(1))
        _ = try await coordinator.refresh(account: environment.accounts["account"]!)

        let gate = MiniMaxRequestGate()
        await client.enqueue(.unknownQuotaCategoryOnly, gate: gate)
        let refresh = Task {
            try await coordinator.refresh(account: environment.accounts["account"]!)
        }
        await gate.waitForEntry()
        coordinator.invalidateAccount(providerID: "minimax", accountID: "account")

        await XCTAssertThrowsErrorAsync(try await refresh.value) { error in
            XCTAssertTrue(error is CancellationError)
        }
        let persisted = try environment.capacityStore.load(
            providerID: "minimax",
            accountID: "account",
            surface: MiniMaxProviderContract.surface,
            sources: MiniMaxProviderContract.sources
        )
        XCTAssertEqual(try consumedValue(persisted), 1)
        XCTAssertTrue(
            environment.diagnosticStore.load().filter {
                $0.providerID == "minimax" && $0.accountID == "account"
            }.isEmpty
        )
        XCTAssertTrue(
            try environment.credentialStore.loadDiagnostics(
                providerID: "minimax",
                accountID: "account"
            ).isEmpty
        )
    }

    func testReparentedUnknownQuotaCategoryOnlyResultIsSuppressedWithoutDiagnostic() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        let coordinator = makeCoordinator(environment: environment, client: client)
        await client.enqueue(.success(1))
        _ = try await coordinator.refresh(account: environment.accounts["account"]!)

        let gate = MiniMaxRequestGate()
        await client.enqueue(.unknownQuotaCategoryOnly, gate: gate)
        let refresh = Task {
            try await coordinator.refresh(account: environment.accounts["account"]!)
        }
        await gate.waitForEntry()
        try await environment.database.pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO provider_account_contexts (
                        provider_id, account_id, context_id, kind,
                        display_name, region_id, parent_context_id
                    ) VALUES ('minimax', 'account', 'replacement-team', 'team',
                              'Replacement Team', 'global', NULL)
                    """
            )
            try db.execute(
                sql: """
                    UPDATE provider_account_contexts
                    SET parent_context_id = 'replacement-team'
                    WHERE provider_id = 'minimax'
                      AND account_id = 'account'
                      AND context_id = 'team'
                    """
            )
            try db.execute(
                sql: """
                    UPDATE provider_account_contexts
                    SET parent_context_id = 'replacement-team'
                    WHERE provider_id = 'minimax'
                      AND account_id = 'account'
                      AND context_id = 'credential-1'
                    """
            )
        }
        await gate.release()

        let result = try await refresh.value
        XCTAssertEqual(result.suppressedSourceCount, 1)
        XCTAssertEqual(try consumedValue(result.snapshot), 1)
        XCTAssertTrue(
            environment.diagnosticStore.load().filter {
                $0.providerID == "minimax" && $0.accountID == "account"
            }.isEmpty
        )
    }

    func testRetryAfterDefersWithoutSleepingOrMutatingLastValid() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        let clock = MiniMaxTestClock(Date(timeIntervalSince1970: 10_000))
        let coordinator = makeCoordinator(
            environment: environment,
            client: client,
            clock: clock
        )
        await client.enqueue(.success(2))
        _ = try await coordinator.refresh(account: environment.accounts["account"]!)
        await client.enqueue(
            .failure(.throttled(retryAfter: .seconds(120)))
        )
        let throttled = try await coordinator.refresh(
            account: environment.accounts["account"]!
        )
        XCTAssertEqual(throttled.failedSourceCount, 1)
        XCTAssertEqual(try consumedValue(throttled.snapshot), 2)
        let state = try XCTUnwrap(
            environment.credentialStore.loadRefreshStates(
                providerID: "minimax",
                accountID: "account"
            ).first
        )
        XCTAssertEqual(
            state.retryNotBefore,
            Date(timeIntervalSince1970: 10_120)
        )

        await client.enqueue(.success(9))
        let deferred = try await coordinator.refresh(
            account: environment.accounts["account"]!
        )
        XCTAssertEqual(deferred.deferredSourceCount, 1)
        let deferredCallCount = await client.callCount()
        XCTAssertEqual(deferredCallCount, 2)
        XCTAssertEqual(try consumedValue(deferred.snapshot), 2)

        clock.advance(by: 120)
        let recovered = try await coordinator.refresh(
            account: environment.accounts["account"]!
        )
        XCTAssertEqual(recovered.successfulSourceCount, 1)
        let recoveredCallCount = await client.callCount()
        XCTAssertEqual(recoveredCallCount, 3)
        XCTAssertEqual(try consumedValue(recovered.snapshot), 9)
    }

    func testInvalidationCancelsLateResultWithoutChangingSnapshotOrDiagnostics() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        let coordinator = makeCoordinator(environment: environment, client: client)
        await client.enqueue(.success(1))
        _ = try await coordinator.refresh(account: environment.accounts["account"]!)

        let gate = MiniMaxRequestGate()
        await client.enqueue(.success(8), gate: gate)
        let task = Task {
            try await coordinator.refresh(account: environment.accounts["account"]!)
        }
        await gate.waitForEntry()
        coordinator.invalidateAccount(providerID: "minimax", accountID: "account")

        await XCTAssertThrowsErrorAsync(try await task.value) { error in
            XCTAssertTrue(error is CancellationError)
        }
        let persisted = try environment.capacityStore.load(
            providerID: "minimax",
            accountID: "account",
            surface: MiniMaxProviderContract.surface,
            sources: MiniMaxProviderContract.sources
        )
        XCTAssertEqual(try consumedValue(persisted), 1)
        XCTAssertTrue(
            try environment.credentialStore.loadDiagnostics(
                providerID: "minimax",
                accountID: "account"
            ).isEmpty
        )
    }

    func testSupersedingRefreshCancelsPriorRequestAndCommitsOnlyLatest() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        let coordinator = makeCoordinator(environment: environment, client: client)
        let firstGate = MiniMaxRequestGate()
        await client.enqueue(.success(4), gate: firstGate)
        await client.enqueue(.success(7))

        let first = Task {
            try await coordinator.refresh(account: environment.accounts["account"]!)
        }
        await firstGate.waitForEntry()
        let second = try await coordinator.refresh(
            account: environment.accounts["account"]!
        )

        await XCTAssertThrowsErrorAsync(try await first.value) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(second.successfulSourceCount, 1)
        XCTAssertEqual(try consumedValue(second.snapshot), 7)
        XCTAssertTrue(
            try environment.credentialStore.loadDiagnostics(
                providerID: "minimax",
                accountID: "account"
            ).isEmpty
        )
    }

    func testLateDisabledAccountResultIsSuppressedAndPreservesSnapshot() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        let coordinator = makeCoordinator(environment: environment, client: client)
        await client.enqueue(.success(1))
        _ = try await coordinator.refresh(account: environment.accounts["account"]!)

        let gate = MiniMaxRequestGate()
        await client.enqueue(.success(5), gate: gate)
        let refresh = Task {
            try await coordinator.refresh(account: environment.accounts["account"]!)
        }
        await gate.waitForEntry()
        var disabled = environment.accounts["account"]!
        disabled.isEnabled = false
        try DatabaseProviderConfigurationStore(database: environment.database)
            .save([disabled])
        await gate.release()

        let result = try await refresh.value
        XCTAssertEqual(result.suppressedSourceCount, 1)
        XCTAssertEqual(try consumedValue(result.snapshot), 1)
        XCTAssertTrue(
            try environment.credentialStore.loadDiagnostics(
                providerID: "minimax",
                accountID: "account"
            ).isEmpty
        )
    }

    func testLateCredentialReparentIsSuppressedAndPreservesSnapshot() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        let coordinator = makeCoordinator(environment: environment, client: client)
        await client.enqueue(.success(1))
        _ = try await coordinator.refresh(account: environment.accounts["account"]!)

        let gate = MiniMaxRequestGate()
        await client.enqueue(.success(5), gate: gate)
        let refresh = Task {
            try await coordinator.refresh(account: environment.accounts["account"]!)
        }
        await gate.waitForEntry()
        try await environment.database.pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO provider_account_contexts (
                        provider_id, account_id, context_id, kind,
                        display_name, region_id, parent_context_id
                    ) VALUES ('minimax', 'account', 'replacement-team', 'team',
                              'Replacement Team', 'global', NULL)
                    """
            )
            try db.execute(
                sql: """
                    UPDATE provider_account_contexts
                    SET parent_context_id = 'replacement-team'
                    WHERE provider_id = 'minimax'
                      AND account_id = 'account'
                      AND context_id = 'team'
                    """
            )
            try db.execute(
                sql: """
                    UPDATE provider_account_contexts
                    SET parent_context_id = 'replacement-team'
                    WHERE provider_id = 'minimax'
                      AND account_id = 'account'
                      AND context_id = 'credential-1'
                    """
            )
        }
        await gate.release()

        let result = try await refresh.value
        XCTAssertEqual(result.suppressedSourceCount, 1)
        XCTAssertEqual(try consumedValue(result.snapshot), 1)
        XCTAssertTrue(
            try environment.credentialStore.loadDiagnostics(
                providerID: "minimax",
                accountID: "account"
            ).isEmpty
        )
    }

    func testAlreadyDisabledSavedAccountDoesNotCallProvider() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "account", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        let coordinator = makeCoordinator(environment: environment, client: client)
        var disabled = environment.accounts["account"]!
        disabled.isEnabled = false
        try DatabaseProviderConfigurationStore(database: environment.database)
            .save([disabled])
        await client.enqueue(.success(5))

        let result = try await coordinator.refresh(
            account: environment.accounts["account"]!
        )

        XCTAssertEqual(result.suppressedSourceCount, 1)
        XCTAssertNil(result.snapshot)
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(
            try environment.credentialStore.loadDiagnostics(
                providerID: "minimax",
                accountID: "account"
            ).isEmpty
        )
    }

    func testTwoAccountsRemainIsolatedAcrossSuccessAndFailure() async throws {
        let environment = try makeEnvironment([
            AccountSetup(accountID: "first", ordinarySlotIDs: ["subscription"]),
            AccountSetup(accountID: "second", ordinarySlotIDs: ["subscription"])
        ])
        let client = ScriptedMiniMaxClient()
        let coordinator = makeCoordinator(environment: environment, client: client)
        await client.enqueue(.success(1))
        await client.enqueue(.success(2))
        _ = try await coordinator.refresh(account: environment.accounts["first"]!)
        _ = try await coordinator.refresh(account: environment.accounts["second"]!)

        await client.enqueue(
            .success(10, hasMappingDiagnostic: true)
        )
        await client.enqueue(
            .failure(.authenticationFailure)
        )
        let firstResult = try await coordinator.refresh(
            account: environment.accounts["first"]!
        )
        let secondResult = try await coordinator.refresh(
            account: environment.accounts["second"]!
        )

        XCTAssertEqual(try consumedValue(firstResult.snapshot), 10)
        XCTAssertEqual(try consumedValue(secondResult.snapshot), 2)
        XCTAssertEqual(firstResult.successfulSourceCount, 1)
        XCTAssertEqual(secondResult.failedSourceCount, 1)
        XCTAssertTrue(
            try environment.credentialStore.loadDiagnostics(
                providerID: "minimax",
                accountID: "first"
            ).isEmpty
        )
        XCTAssertEqual(
            try environment.credentialStore.loadDiagnostics(
                providerID: "minimax",
                accountID: "second"
            ).first?.code,
            .authentication
        )
        let sourceDiagnostics = environment.diagnosticStore.load()
        XCTAssertEqual(
            sourceDiagnostics.filter { $0.accountID == "first" }.count,
            1
        )
        XCTAssertTrue(
            sourceDiagnostics.filter { $0.accountID == "second" }.isEmpty
        )
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 4)
        let firstReference = try XCTUnwrap(
            environment.credentialStore.loadCredentialContexts(
                providerID: "minimax",
                accountID: "first"
            ).first?.slot.keychainReference
        )
        let secondReference = try XCTUnwrap(
            environment.credentialStore.loadCredentialContexts(
                providerID: "minimax",
                accountID: "second"
            ).first?.slot.keychainReference
        )
        XCTAssertEqual(
            environment.keychain.readReferences(),
            [firstReference, secondReference, firstReference, secondReference]
        )
    }

    private func makeCoordinator(
        environment: MiniMaxEnvironment,
        client: ScriptedMiniMaxClient,
        clock: MiniMaxTestClock = MiniMaxTestClock(
            Date(timeIntervalSince1970: 30_000)
        ),
        postFetchCheckpoint: @escaping @Sendable () async -> Void = {}
    ) -> MiniMaxRefreshCoordinator {
        MiniMaxRefreshCoordinator(
            credentialStore: environment.credentialStore,
            capacityStore: environment.capacityStore,
            diagnosticStore: environment.diagnosticStore,
            client: client,
            policy: MiniMaxRefreshPolicy(
                initialBackoff: 30,
                maximumBackoff: 300
            ),
            now: { clock.now },
            postFetchCheckpoint: postFetchCheckpoint
        )
    }

    private func makeEnvironment(
        _ setups: [AccountSetup]
    ) throws -> MiniMaxEnvironment {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let database = try AppDatabase(directory: directory)
        let accounts = Dictionary(
            uniqueKeysWithValues: setups.map {
                ($0.accountID, miniMaxAccount($0.accountID))
            }
        )
        try DatabaseProviderConfigurationStore(database: database)
            .save(Array(accounts.values))
        let keychain = MiniMaxInMemoryKeychain()
        let credentialStore = AccountCredentialStore(
            database: database,
            keychainService: keychain
        )
        var teamContextIDs: [String: String] = [:]
        var credentialContextIDs: [String: [String]] = [:]

        for setup in setups {
            let teamContextID = "team"
            teamContextIDs[setup.accountID] = teamContextID
            try credentialStore.createContext(
                ProviderAccountContextConfiguration(
                    providerID: "minimax",
                    accountID: setup.accountID,
                    contextID: teamContextID,
                    kind: .team,
                    displayName: "Configured Team",
                    regionID: "global"
                )
            )
            var childIDs: [String] = []
            for (index, slotID) in setup.ordinarySlotIDs.enumerated() {
                let contextID = "credential-\(index + 1)"
                childIDs.append(contextID)
                try credentialStore.createContext(
                    ProviderAccountContextConfiguration(
                        providerID: "minimax",
                        accountID: setup.accountID,
                        contextID: contextID,
                        kind: .credential,
                        displayName: "Subscription Key",
                        regionID: "global",
                        parentContextID: teamContextID
                    )
                )
                try credentialStore.createCredential(
                    providerID: "minimax",
                    accountID: setup.accountID,
                    slotID: slotID,
                    contextID: contextID,
                    role: .ordinary,
                    credential: CredentialSecret(
                        "synthetic-secret-\(setup.accountID)-\(index)"
                    )
                )
            }
            credentialContextIDs[setup.accountID] = childIDs
        }

        return MiniMaxEnvironment(
            database: database,
            accounts: accounts,
            teamContextIDs: teamContextIDs,
            credentialContextIDs: credentialContextIDs,
            credentialStore: credentialStore,
            capacityStore: DatabaseCapacitySnapshotStore(database: database),
            diagnosticStore: DatabaseSourceDiagnosticStore(database: database),
            keychain: keychain
        )
    }

    private func consumedValue(
        _ snapshot: CapacitySnapshot?
    ) throws -> Decimal {
        try XCTUnwrap(try XCTUnwrap(snapshot).metrics.first?.values?.consumed?.value)
    }
}

private struct AccountSetup {
    let accountID: String
    let ordinarySlotIDs: [String]
}

private struct MiniMaxEnvironment {
    let database: AppDatabase
    let accounts: [String: ProviderAccount]
    let teamContextIDs: [String: String]
    let credentialContextIDs: [String: [String]]
    let credentialStore: AccountCredentialStore
    let capacityStore: DatabaseCapacitySnapshotStore
    let diagnosticStore: DatabaseSourceDiagnosticStore
    let keychain: MiniMaxInMemoryKeychain
}

private func miniMaxAccount(_ accountID: String) -> ProviderAccount {
    ProviderAccount(
        providerID: "minimax",
        accountID: accountID,
        displayName: "MiniMax \(accountID)",
        isEnabled: true,
        sourceMode: .miniMaxTokenPlan
    )
}

private struct StaticMiniMaxRefresher: MiniMaxAccountRefreshing {
    let result: MiniMaxAccountRefreshResult

    func refresh(account: ProviderAccount) async throws -> MiniMaxAccountRefreshResult {
        result
    }

    func invalidateAccount(providerID: String, accountID: String) {}
}

private actor ScriptedMiniMaxClient: MiniMaxAPIClient {
    enum Outcome: Sendable {
        case success(Decimal, hasMappingDiagnostic: Bool = false)
        case unknownQuotaCategoryOnly
        case failure(MiniMaxAPIClientError)
        case malformed
    }

    private struct Script: Sendable {
        let outcome: Outcome
        let gate: MiniMaxRequestGate?
    }

    private var scripts: [Script] = []
    private var calls = 0

    func enqueue(
        _ outcome: Outcome,
        gate: MiniMaxRequestGate? = nil
    ) {
        scripts.append(Script(outcome: outcome, gate: gate))
    }

    func callCount() -> Int {
        calls
    }

    func fetchTokenPlanCapacity(
        credential: MiniMaxSubscriptionKey
    ) async throws -> MiniMaxCapacityResult {
        calls += 1
        guard !scripts.isEmpty else {
            throw MiniMaxAPIClientError.transportFailure
        }
        let script = scripts.removeFirst()
        try await script.gate?.enter()
        let observedAt = Date(
            timeIntervalSince1970: 20_000 + Double(calls)
        )

        switch script.outcome {
        case let .success(value, hasMappingDiagnostic):
            return MiniMaxCapacityResult(
                observedAt: observedAt,
                metrics: [
                    CapacityMetric(
                        metricID: "quota-category-a.current",
                        accountContextID: "credential-1",
                        sourceID: MiniMaxProviderContract.sourceID,
                        capability: "quota-windows",
                        displayName: "Token Plan capacity A",
                        availability: .known,
                        unit: CapacityUnit(kind: .percent),
                        values: CapacityValues(
                            consumed: CapacityValue(
                                value: value,
                                origin: .derived
                            ),
                            remaining: CapacityValue(
                                value: 100 - value,
                                origin: .reported
                            ),
                            limit: CapacityValue(value: 100, origin: .reported)
                        ),
                        window: CapacityWindow(
                            kind: .rolling,
                            durationSeconds: 300,
                            startsAt: observedAt,
                            endsAt: observedAt.addingTimeInterval(300),
                            nextTransition: CapacityTransition(
                                kind: .reset,
                                at: observedAt.addingTimeInterval(300)
                            )
                        ),
                        freshness: ObservationFreshness(observedAt: observedAt),
                        confidence: .live,
                        derivations: [
                            Derivation(
                                kind: .consumedFromLimitMinusRemaining,
                                target: .consumed,
                                inputs: [.limit, .remaining]
                            )
                        ]
                    )
                ],
                diagnostics: hasMappingDiagnostic
                    ? [MiniMaxMappingDiagnostic(code: .unknownQuotaCategory)]
                    : []
            )
        case .unknownQuotaCategoryOnly:
            return MiniMaxCapacityResult(
                observedAt: observedAt,
                metrics: [],
                diagnostics: [
                    MiniMaxMappingDiagnostic(code: .unknownQuotaCategory)
                ]
            )
        case let .failure(error):
            throw error
        case .malformed:
            return MiniMaxCapacityResult(
                observedAt: observedAt,
                metrics: [],
                diagnostics: []
            )
        }
    }
}

private actor MiniMaxRequestGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var blocked: [UUID: CheckedContinuation<Void, Error>] = [:]

    func enter() async throws {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        guard !released else { return }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if released {
                    continuation.resume()
                } else {
                    blocked[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func waitForEntry() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        let continuations = blocked.values
        blocked.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func cancel(_ id: UUID) {
        blocked.removeValue(forKey: id)?.resume(
            throwing: CancellationError()
        )
    }
}

private actor MiniMaxPostFetchGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var blocked: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        guard !released else { return }
        await withCheckedContinuation { continuation in
            blocked.append(continuation)
        }
    }

    func waitForEntry() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        let continuations = blocked
        blocked.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private final class MiniMaxInMemoryKeychain: KeychainService, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: CredentialSecret] = [:]
    private var reads: [String] = []

    func createCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard values[reference] == nil else {
            throw KeychainServiceError.duplicateReference
        }
        values[reference] = credential
    }

    func readCredential(reference: String) throws -> CredentialSecret {
        lock.lock()
        defer { lock.unlock() }
        guard let value = values[reference] else {
            throw KeychainServiceError.credentialNotFound
        }
        reads.append(reference)
        return value
    }

    func replaceCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard values[reference] != nil else {
            throw KeychainServiceError.credentialNotFound
        }
        values[reference] = credential
    }

    func deleteCredential(reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: reference)
    }

    func readReferences() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }
}

private final class MiniMaxTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw.", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
