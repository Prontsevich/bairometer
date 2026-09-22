@testable import BairometerCore
import Foundation
import GRDB
import XCTest

final class OpenRouterRefreshCoordinatorTests: XCTestCase {
    func testProviderRegistrationDescriptorsAndSourceModeAreStable() throws {
        let adapter = try XCTUnwrap(
            ProviderRegistry.defaultAdapters.first {
                $0.id == OpenRouterProviderContract.providerID
            } as? OpenRouterProviderAdapter
        )

        XCTAssertEqual(
            ProviderSourceMode.defaultMode(for: "openrouter"),
            .openRouterAPI
        )
        XCTAssertEqual(
            ProviderSourceMode.resolvedMode(.manual, for: "openrouter"),
            .openRouterAPI
        )
        XCTAssertEqual(
            adapter.capabilities.supportedSourceModes,
            [.openRouterAPI]
        )
        XCTAssertEqual(
            Set(OpenRouterProviderContract.sources.map(\.sourceID)),
            ["current-key-api", "management-api"]
        )
        XCTAssertEqual(
            OpenRouterProviderContract.currentKeySource.authRequirement.privilege,
            .leastPrivilege
        )
        XCTAssertEqual(
            OpenRouterProviderContract.managementSource.authRequirement.privilege,
            .elevated
        )

        let account = ProviderAccount(
            providerID: "openrouter",
            accountID: "account",
            displayName: "OpenRouter",
            isEnabled: true
        )
        let encoded = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(
            ProviderAccount.self,
            from: encoded
        )
        XCTAssertEqual(decoded.sourceMode, .openRouterAPI)
        XCTAssertTrue(
            String(decoding: encoded, as: UTF8.self)
                .contains(#""sourceMode":"openrouter-api""#)
        )
    }

    func testAdapterCompatibilitySnapshotNeverFabricatesPercentage() async throws {
        let observedAt = Date(timeIntervalSince1970: 42)
        let refresher = StaticOpenRouterRefresher(
            result: OpenRouterAccountRefreshResult(
                snapshot: CapacitySnapshot(
                    providerID: "openrouter",
                    surfaceID: "api-account",
                    savedAccountID: "account",
                    accountContexts: [
                        AccountContext(
                            contextID: "root",
                            kind: .personal,
                            regionID: "global"
                        )
                    ],
                    observedAt: observedAt,
                    metrics: []
                ),
                completedAt: observedAt,
                successfulSourceCount: 1,
                failedSourceCount: 0,
                deferredSourceCount: 0,
                suppressedSourceCount: 0,
                configuredSourceCount: 1
            )
        )
        let adapter = OpenRouterProviderAdapter(refreshCoordinator: refresher)
        let snapshot = try await adapter.fetchSnapshot(
            account: ProviderAccount(
                providerID: "openrouter",
                accountID: "account",
                displayName: "OpenRouter",
                isEnabled: true
            )
        )

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertNil(snapshot.usedPercent)
        XCTAssertNil(snapshot.resetAt)
        XCTAssertTrue(snapshot.limitWindows.isEmpty)
        XCTAssertEqual(snapshot.remainingLabel, "Native OpenRouter capacity stored")
    }

    func testPartialFailurePreservesSiblingAndRootLastValidMetrics() async throws {
        let fixture = try makeFixture(
            accountID: "primary",
            ordinarySlots: ["first", "second"],
            includesManagement: true
        )
        let client = ScriptedOpenRouterClient()
        await client.setOrdinary(.success(1), slotID: "first")
        await client.setOrdinary(.success(2), slotID: "second")
        await client.setManagement(.success(100), slotID: "management")
        let coordinator = makeCoordinator(fixture: fixture, client: client)

        _ = try await coordinator.refresh(account: fixture.account)

        await client.setOrdinary(
            .failure(.authenticationFailure),
            slotID: "first"
        )
        await client.setOrdinary(.success(22), slotID: "second")
        await client.setManagement(.success(120), slotID: "management")

        let result = try await coordinator.refresh(account: fixture.account)
        let snapshot = try XCTUnwrap(result.snapshot)
        XCTAssertEqual(result.successfulSourceCount, 2)
        XCTAssertEqual(result.failedSourceCount, 1)
        XCTAssertEqual(
            try consumedValue(
                metricID: "key-total-usage",
                contextID: "first",
                snapshot: snapshot
            ),
            1
        )
        XCTAssertEqual(
            try consumedValue(
                metricID: "key-total-usage",
                contextID: "second",
                snapshot: snapshot
            ),
            22
        )
        XCTAssertEqual(
            try consumedValue(
                metricID: "account-credits",
                contextID: fixture.rootContextID,
                snapshot: snapshot
            ),
            120
        )
        XCTAssertEqual(
            snapshot.metrics.filter {
                $0.metricID == "account-credits"
            }.count,
            1
        )

        let diagnostics = try fixture.credentialStore.loadDiagnostics(
            providerID: "openrouter",
            accountID: "primary"
        )
        XCTAssertEqual(diagnostics.map(\.slotID), ["first"])
        XCTAssertEqual(diagnostics.first?.code, .authentication)
        let states = try fixture.credentialStore.loadRefreshStates(
            providerID: "openrouter",
            accountID: "primary"
        )
        XCTAssertNotNil(
            states.first { $0.slotID == "first" }?.lastSuccessfulRefreshAt
        )
        XCTAssertNotNil(
            states.first { $0.slotID == "first" }?.lastFailedRefreshAt
        )
        XCTAssertNotNil(
            states.first { $0.slotID == "first" }?.lastCompletedAt
        )
        let compatibility = try await compatibilitySnapshot(
            result: result,
            account: fixture.account
        )
        XCTAssertEqual(compatibility.status, .warning)
    }

    func testManagementFailureRetainsLastValidThenAbsenceBecomesUnavailable() async throws {
        let fixture = try makeFixture(
            accountID: "credits",
            ordinarySlots: ["ordinary"],
            includesManagement: true
        )
        let client = ScriptedOpenRouterClient()
        await client.setOrdinary(.success(7), slotID: "ordinary")
        await client.setManagement(.success(75), slotID: "management")
        let coordinator = makeCoordinator(fixture: fixture, client: client)
        _ = try await coordinator.refresh(account: fixture.account)

        await client.setManagement(
            .failure(.serviceUnavailable(retryAfter: nil)),
            slotID: "management"
        )
        let failed = try await coordinator.refresh(account: fixture.account)
        XCTAssertEqual(
            try consumedValue(
                metricID: "account-credits",
                contextID: fixture.rootContextID,
                snapshot: XCTUnwrap(failed.snapshot)
            ),
            75
        )

        try fixture.credentialStore.deleteCredential(
            providerID: "openrouter",
            accountID: "credits",
            slotID: "management"
        )
        let absent = try await coordinator.refresh(account: fixture.account)
        let credits = try XCTUnwrap(
            absent.snapshot?.metrics.first {
                $0.metricID == "account-credits"
            }
        )
        XCTAssertEqual(credits.accountContextID, fixture.rootContextID)
        XCTAssertEqual(credits.availability, .unavailable)
        XCTAssertNil(credits.values)
    }

    func testDeletingManagementCredentialInFlightEndsSameRefreshUnavailable() async throws {
        let fixture = try makeFixture(
            accountID: "delete-management-race",
            ordinarySlots: ["ordinary"],
            includesManagement: true
        )
        let seedClient = ScriptedOpenRouterClient()
        await seedClient.setOrdinary(.success(7), slotID: "ordinary")
        await seedClient.setManagement(.success(75), slotID: "management")
        _ = try await makeCoordinator(
            fixture: fixture,
            client: seedClient
        ).refresh(account: fixture.account)

        let gate = DeterministicRequestGate()
        let raceClient = ScriptedOpenRouterClient(gate: gate)
        await raceClient.setOrdinary(.success(22), slotID: "ordinary")
        await raceClient.setManagement(.success(120), slotID: "management")
        let raceCoordinator = makeCoordinator(
            fixture: fixture,
            client: raceClient
        )
        let refresh = Task {
            try await raceCoordinator.refresh(account: fixture.account)
        }
        await gate.waitForEntries(2)
        try fixture.credentialStore.deleteCredential(
            providerID: "openrouter",
            accountID: "delete-management-race",
            slotID: "management"
        )
        await gate.releaseAll()
        let result = try await refresh.value
        let snapshot = try XCTUnwrap(result.snapshot)

        XCTAssertGreaterThanOrEqual(result.suppressedSourceCount, 1)
        XCTAssertEqual(
            try consumedValue(
                metricID: "key-total-usage",
                contextID: "ordinary",
                snapshot: snapshot
            ),
            22
        )
        let credits = snapshot.metrics.filter {
            $0.metricID == "account-credits"
                && $0.sourceID
                    == OpenRouterProviderContract.managementSourceID
        }
        XCTAssertEqual(credits.count, 1)
        XCTAssertEqual(credits.first?.availability, .unavailable)
        XCTAssertNil(credits.first?.values)
        XCTAssertFalse(credits.contains { $0.availability == .known })
        XCTAssertFalse(
            try fixture.credentialStore.loadRefreshStates(
                providerID: "openrouter",
                accountID: "delete-management-race"
            ).contains { $0.slotID == "management" }
        )
        XCTAssertFalse(
            try fixture.credentialStore.loadDiagnostics(
                providerID: "openrouter",
                accountID: "delete-management-race"
            ).contains { $0.slotID == "management" }
        )
    }

    func testDisablingManagementCredentialInFlightEndsSameRefreshUnavailable() async throws {
        let fixture = try makeFixture(
            accountID: "disable-management-race",
            ordinarySlots: ["ordinary"],
            includesManagement: true
        )
        let seedClient = ScriptedOpenRouterClient()
        await seedClient.setOrdinary(.success(7), slotID: "ordinary")
        await seedClient.setManagement(.success(75), slotID: "management")
        _ = try await makeCoordinator(
            fixture: fixture,
            client: seedClient
        ).refresh(account: fixture.account)
        let managementStateBefore = try XCTUnwrap(
            fixture.credentialStore.loadRefreshStates(
                providerID: "openrouter",
                accountID: "disable-management-race"
            ).first { $0.slotID == "management" }
        )

        let gate = DeterministicRequestGate()
        let raceClient = ScriptedOpenRouterClient(gate: gate)
        await raceClient.setOrdinary(.success(22), slotID: "ordinary")
        await raceClient.setManagement(.success(120), slotID: "management")
        let raceCoordinator = makeCoordinator(
            fixture: fixture,
            client: raceClient
        )
        let refresh = Task {
            try await raceCoordinator.refresh(account: fixture.account)
        }
        await gate.waitForEntries(2)
        try fixture.credentialStore.setCredentialEnabled(
            false,
            providerID: "openrouter",
            accountID: "disable-management-race",
            slotID: "management"
        )
        await gate.releaseAll()
        let result = try await refresh.value
        let snapshot = try XCTUnwrap(result.snapshot)

        XCTAssertGreaterThanOrEqual(result.suppressedSourceCount, 1)
        XCTAssertEqual(
            try consumedValue(
                metricID: "key-total-usage",
                contextID: "ordinary",
                snapshot: snapshot
            ),
            22
        )
        let credits = snapshot.metrics.filter {
            $0.metricID == "account-credits"
                && $0.sourceID
                    == OpenRouterProviderContract.managementSourceID
        }
        XCTAssertEqual(credits.count, 1)
        XCTAssertEqual(credits.first?.availability, .unavailable)
        XCTAssertNil(credits.first?.values)
        XCTAssertFalse(credits.contains { $0.availability == .known })
        XCTAssertEqual(
            try fixture.credentialStore.loadRefreshStates(
                providerID: "openrouter",
                accountID: "disable-management-race"
            ).first { $0.slotID == "management" },
            managementStateBefore
        )
        XCTAssertFalse(
            try fixture.credentialStore.loadDiagnostics(
                providerID: "openrouter",
                accountID: "disable-management-race"
            ).contains { $0.slotID == "management" }
        )
    }

    func testRetryAfterAndExponentialBackoffDeferLaterAttemptsWithoutSleeping() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 10_000))
        let fixture = try makeFixture(
            accountID: "retry",
            ordinarySlots: ["ordinary"],
            includesManagement: false
        )
        let client = ScriptedOpenRouterClient()
        await client.setOrdinary(
            .failure(.throttled(retryAfter: .seconds(120))),
            slotID: "ordinary"
        )
        let coordinator = OpenRouterRefreshCoordinator(
            credentialStore: fixture.credentialStore,
            capacityStore: fixture.capacityStore,
            client: client,
            policy: OpenRouterRefreshPolicy(
                maximumConcurrentSources: 4,
                initialBackoff: 30,
                maximumBackoff: 300
            ),
            now: { clock.now }
        )

        let first = try await coordinator.refresh(account: fixture.account)
        XCTAssertEqual(first.failedSourceCount, 1)
        let firstCallCount = await client.callCount(slotID: "ordinary")
        XCTAssertEqual(firstCallCount, 1)

        let deferred = try await coordinator.refresh(account: fixture.account)
        XCTAssertEqual(deferred.deferredSourceCount, 1)
        let deferredCallCount = await client.callCount(slotID: "ordinary")
        XCTAssertEqual(deferredCallCount, 1)

        clock.advance(by: 121)
        await client.setOrdinary(
            .failure(.timedOut),
            slotID: "ordinary"
        )
        _ = try await coordinator.refresh(account: fixture.account)
        let finalCallCount = await client.callCount(slotID: "ordinary")
        XCTAssertEqual(finalCallCount, 2)
        let state = try XCTUnwrap(
            fixture.credentialStore.loadRefreshStates(
                providerID: "openrouter",
                accountID: "retry"
            ).first
        )
        XCTAssertEqual(state.consecutiveFailureCount, 2)
        XCTAssertEqual(
            state.retryNotBefore,
            clock.now.addingTimeInterval(60)
        )
    }

    func testRetryAfterHTTPDateHonorsExactBoundary() {
        let now = Date(timeIntervalSince1970: 10_000)
        let boundary = Date(timeIntervalSince1970: 10_120)
        let policy = OpenRouterRefreshPolicy()

        XCTAssertEqual(
            policy.retryDate(
                after: 7,
                retryAfter: .date(boundary),
                now: now
            ),
            boundary
        )
        XCTAssertEqual(
            policy.retryDate(
                after: 7,
                retryAfter: .date(now.addingTimeInterval(-1)),
                now: now
            ),
            now
        )
    }

    func testSuccessOutcomeRollsBackMetricsStateAndDiagnosticAtFailpoint() throws {
        let fixture = try makeFixture(
            accountID: "atomic-success",
            ordinarySlots: ["ordinary"],
            includesManagement: false
        )
        let slot = try XCTUnwrap(
            fixture.credentialStore.loadCredentialContexts(
                providerID: "openrouter",
                accountID: "atomic-success"
            ).first?.slot
        )
        let contexts = try fixture.credentialStore.loadContexts(
            providerID: "openrouter",
            accountID: "atomic-success"
        ).map(\.contractContext)
        let completedAt = Date(timeIntervalSince1970: 20_000)

        XCTAssertThrowsError(
            try fixture.capacityStore.recordSourceSuccess(
                CapacitySourceMutation(
                    providerID: "openrouter",
                    accountID: "atomic-success",
                    contextID: slot.contextID,
                    sourceID: OpenRouterProviderContract.currentKeySourceID,
                    accountContexts: contexts,
                    metrics: ScriptedOpenRouterClient.ordinaryMetrics(
                        contextID: slot.contextID,
                        value: 3
                    ),
                    completedAt: completedAt,
                    identityExpectation: .slot(slot)
                ),
                control: NativeCapacityOutcomeControl(
                    attemptedAt: completedAt,
                    completedAt: completedAt,
                    checkpoint: {
                        if case .afterMetrics = $0 {
                            throw DeterministicTestError.injected
                        }
                    }
                ),
                surface: OpenRouterProviderContract.surface,
                sources: OpenRouterProviderContract.sources
            )
        )

        XCTAssertNil(
            try fixture.capacityStore.load(
                providerID: "openrouter",
                accountID: "atomic-success",
                surface: OpenRouterProviderContract.surface,
                sources: OpenRouterProviderContract.sources
            )
        )
        XCTAssertTrue(
            try fixture.credentialStore.loadRefreshStates(
                providerID: "openrouter",
                accountID: "atomic-success"
            ).isEmpty
        )
        XCTAssertTrue(
            try fixture.credentialStore.loadDiagnostics(
                providerID: "openrouter",
                accountID: "atomic-success"
            ).isEmpty
        )
    }

    func testSuccessOutcomeRevalidatesGenerationBeforeCommit() throws {
        let fixture = try makeFixture(
            accountID: "generation-commit",
            ordinarySlots: ["ordinary"],
            includesManagement: false
        )
        let slot = try XCTUnwrap(
            fixture.credentialStore.loadCredentialContexts(
                providerID: "openrouter",
                accountID: "generation-commit"
            ).first?.slot
        )
        let contexts = try fixture.credentialStore.loadContexts(
            providerID: "openrouter",
            accountID: "generation-commit"
        ).map(\.contractContext)
        let generation = LockedTestFlag(true)
        let completedAt = Date(timeIntervalSince1970: 20_000)

        XCTAssertThrowsError(
            try fixture.capacityStore.recordSourceSuccess(
                CapacitySourceMutation(
                    providerID: "openrouter",
                    accountID: "generation-commit",
                    contextID: slot.contextID,
                    sourceID: OpenRouterProviderContract.currentKeySourceID,
                    accountContexts: contexts,
                    metrics: ScriptedOpenRouterClient.ordinaryMetrics(
                        contextID: slot.contextID,
                        value: 3
                    ),
                    completedAt: completedAt,
                    identityExpectation: .slot(slot)
                ),
                control: NativeCapacityOutcomeControl(
                    attemptedAt: completedAt,
                    completedAt: completedAt,
                    generationValidator: { generation.value },
                    checkpoint: {
                        if case .afterDiagnostic = $0 {
                            generation.set(false)
                        }
                    }
                ),
                surface: OpenRouterProviderContract.surface,
                sources: OpenRouterProviderContract.sources
            )
        )
        XCTAssertNil(
            try fixture.capacityStore.load(
                providerID: "openrouter",
                accountID: "generation-commit",
                surface: OpenRouterProviderContract.surface,
                sources: OpenRouterProviderContract.sources
            )
        )
        XCTAssertTrue(
            try fixture.credentialStore.loadRefreshStates(
                providerID: "openrouter",
                accountID: "generation-commit"
            ).isEmpty
        )
    }

    func testFailureOutcomeRollsBackStateAndDiagnosticAtFailpoint() async throws {
        let fixture = try makeFixture(
            accountID: "atomic-failure",
            ordinarySlots: ["ordinary"],
            includesManagement: false
        )
        let client = ScriptedOpenRouterClient()
        await client.setOrdinary(.success(4), slotID: "ordinary")
        _ = try await makeCoordinator(
            fixture: fixture,
            client: client
        ).refresh(account: fixture.account)
        let slot = try XCTUnwrap(
            fixture.credentialStore.loadCredentialContexts(
                providerID: "openrouter",
                accountID: "atomic-failure"
            ).first?.slot
        )
        let originalState = try fixture.credentialStore.loadRefreshStates(
            providerID: "openrouter",
            accountID: "atomic-failure"
        )

        XCTAssertThrowsError(
            try fixture.capacityStore.recordSourceFailure(
                slot: slot,
                code: .authentication,
                retryNotBefore: nil,
                control: NativeCapacityOutcomeControl(
                    attemptedAt: Date(timeIntervalSince1970: 21_000),
                    completedAt: Date(timeIntervalSince1970: 21_000),
                    checkpoint: {
                        if case .afterRefreshState = $0 {
                            throw DeterministicTestError.injected
                        }
                    }
                )
            )
        )

        XCTAssertEqual(
            try fixture.credentialStore.loadRefreshStates(
                providerID: "openrouter",
                accountID: "atomic-failure"
            ),
            originalState
        )
        XCTAssertTrue(
            try fixture.credentialStore.loadDiagnostics(
                providerID: "openrouter",
                accountID: "atomic-failure"
            ).isEmpty
        )
        XCTAssertEqual(
            try consumedValue(
                metricID: "key-total-usage",
                contextID: "ordinary",
                snapshot: XCTUnwrap(
                    fixture.capacityStore.load(
                        providerID: "openrouter",
                        accountID: "atomic-failure",
                        surface: OpenRouterProviderContract.surface,
                        sources: OpenRouterProviderContract.sources
                    )
                )
            ),
            4
        )
    }

    func testCredentialReplacementSuppressesOldRevisionAndNextRefreshSucceeds() async throws {
        let fixture = try makeFixture(
            accountID: "revision",
            ordinarySlots: ["ordinary"],
            includesManagement: false
        )
        let gate = DeterministicRequestGate()
        let client = ScriptedOpenRouterClient(gate: gate)
        await client.setOrdinary(.success(8), slotID: "ordinary")
        let coordinator = makeCoordinator(fixture: fixture, client: client)

        let oldTask = Task {
            try await coordinator.refresh(account: fixture.account)
        }
        await gate.waitForEntries(1)
        try fixture.credentialStore.replaceCredential(
            CredentialSecret("replacement-secret"),
            providerID: "openrouter",
            accountID: "revision",
            slotID: "ordinary"
        )
        await gate.releaseAll()
        let oldResult = try await oldTask.value

        XCTAssertEqual(oldResult.successfulSourceCount, 0)
        XCTAssertEqual(oldResult.suppressedSourceCount, 1)
        XCTAssertFalse(
            oldResult.snapshot?.metrics.contains {
                $0.accountContextID == "ordinary"
            } ?? false
        )
        XCTAssertTrue(
            try fixture.credentialStore.loadRefreshStates(
                providerID: "openrouter",
                accountID: "revision"
            ).isEmpty
        )
        XCTAssertTrue(
            try fixture.credentialStore.loadDiagnostics(
                providerID: "openrouter",
                accountID: "revision"
            ).isEmpty
        )

        let nextResult = try await coordinator.refresh(account: fixture.account)
        XCTAssertEqual(nextResult.successfulSourceCount, 1)
        let observedRevisions = await client.observedRevisions(slotID: "ordinary")
        XCTAssertEqual(
            observedRevisions,
            [1, 2]
        )
        XCTAssertEqual(
            try fixture.credentialStore.loadCredentialContexts(
                providerID: "openrouter",
                accountID: "revision"
            ).first?.slot.credentialRevision,
            2
        )
    }

    func testOverlappingRefreshesCancelPriorNetworkTasksAndShareAccountLimiter() async throws {
        let fixture = try makeFixture(
            accountID: "overlap",
            ordinarySlots: ["one", "two", "three", "four", "five", "six"],
            includesManagement: false
        )
        let gate = DeterministicRequestGate()
        let client = ScriptedOpenRouterClient(gate: gate)
        for slotID in ["one", "two", "three", "four", "five", "six"] {
            await client.setOrdinary(.success(1), slotID: slotID)
        }
        let coordinator = makeCoordinator(fixture: fixture, client: client)

        let first = Task {
            try await coordinator.refresh(account: fixture.account)
        }
        await gate.waitForEntries(4)
        let second = Task {
            try await coordinator.refresh(account: fixture.account)
        }
        await gate.waitForEntries(8)
        await gate.releaseAll()

        do {
            _ = try await first.value
            XCTFail("Expected the superseded refresh to be cancelled.")
        } catch is CancellationError {
            // Expected.
        }
        let secondResult = try await second.value
        XCTAssertEqual(secondResult.successfulSourceCount, 6)
        let maximumActiveRequests = await client.maximumActiveRequests
        XCTAssertLessThanOrEqual(maximumActiveRequests, 4)
    }

    func testTruthfulTotalFailureLastValidDeferredAndManagementAbsentOutcomes() async throws {
        let firstFailure = try makeFixture(
            accountID: "first-failure",
            ordinarySlots: ["ordinary"],
            includesManagement: false
        )
        let firstFailureClient = ScriptedOpenRouterClient()
        await firstFailureClient.setOrdinary(
            .failure(.authenticationFailure),
            slotID: "ordinary"
        )
        let firstFailureResult = try await makeCoordinator(
            fixture: firstFailure,
            client: firstFailureClient
        ).refresh(account: firstFailure.account)
        XCTAssertEqual(firstFailureResult.successfulSourceCount, 0)
        XCTAssertEqual(firstFailureResult.failedSourceCount, 1)
        XCTAssertNil(firstFailureResult.lastUsableObservationAt)
        let firstFailureCompatibility = try await compatibilitySnapshot(
            result: firstFailureResult,
            account: firstFailure.account
        )
        XCTAssertEqual(
            firstFailureCompatibility.status,
            .error
        )

        let lastValid = try makeFixture(
            accountID: "last-valid",
            ordinarySlots: ["ordinary"],
            includesManagement: false
        )
        let lastValidClient = ScriptedOpenRouterClient()
        await lastValidClient.setOrdinary(.success(5), slotID: "ordinary")
        let lastValidCoordinator = makeCoordinator(
            fixture: lastValid,
            client: lastValidClient
        )
        _ = try await lastValidCoordinator.refresh(account: lastValid.account)
        await lastValidClient.setOrdinary(
            .failure(.authenticationFailure),
            slotID: "ordinary"
        )
        let totalFailure = try await lastValidCoordinator.refresh(
            account: lastValid.account
        )
        XCTAssertEqual(totalFailure.successfulSourceCount, 0)
        XCTAssertEqual(totalFailure.failedSourceCount, 1)
        XCTAssertEqual(
            totalFailure.lastUsableObservationAt,
            Date(timeIntervalSince1970: 20_000)
        )
        XCTAssertEqual(
            try consumedValue(
                metricID: "key-total-usage",
                contextID: "ordinary",
                snapshot: XCTUnwrap(totalFailure.snapshot)
            ),
            5
        )
        let totalFailureCompatibility = try await compatibilitySnapshot(
            result: totalFailure,
            account: lastValid.account
        )
        XCTAssertEqual(
            totalFailureCompatibility.status,
            .error
        )

        let deferred = try makeFixture(
            accountID: "deferred",
            ordinarySlots: ["ordinary"],
            includesManagement: false
        )
        let deferredClient = ScriptedOpenRouterClient()
        await deferredClient.setOrdinary(.failure(.timedOut), slotID: "ordinary")
        let deferredCoordinator = makeCoordinator(
            fixture: deferred,
            client: deferredClient
        )
        _ = try await deferredCoordinator.refresh(account: deferred.account)
        let deferredResult = try await deferredCoordinator.refresh(
            account: deferred.account
        )
        XCTAssertEqual(deferredResult.successfulSourceCount, 0)
        XCTAssertEqual(deferredResult.failedSourceCount, 0)
        XCTAssertEqual(deferredResult.deferredSourceCount, 1)
        XCTAssertNil(deferredResult.lastUsableObservationAt)
        let deferredCompatibility = try await compatibilitySnapshot(
            result: deferredResult,
            account: deferred.account
        )
        XCTAssertEqual(
            deferredCompatibility.status,
            .error
        )

        let absent = try makeFixture(
            accountID: "management-absent",
            ordinarySlots: [],
            includesManagement: false
        )
        let absentResult = try await makeCoordinator(
            fixture: absent,
            client: ScriptedOpenRouterClient()
        ).refresh(account: absent.account)
        XCTAssertEqual(absentResult.configuredSourceCount, 0)
        XCTAssertEqual(absentResult.successfulSourceCount, 0)
        XCTAssertNil(absentResult.lastUsableObservationAt)
        let absentCompatibility = try await compatibilitySnapshot(
            result: absentResult,
            account: absent.account
        )
        XCTAssertEqual(absentCompatibility.status, .error)
        XCTAssertEqual(
            absentCompatibility.warnings,
            ["No enabled OpenRouter credential source is configured."]
        )
    }

    func testPerAccountConcurrencyIsBoundedAndSameChildNamesStayIsolated() async throws {
        let first = try makeFixture(
            accountID: "first-account",
            accountDisplayName: "First account",
            ordinarySlots: ["one", "two", "three", "four", "five"],
            childDisplayName: "Local key",
            includesManagement: false
        )
        let second = try makeFixture(
            accountID: "second-account",
            accountDisplayName: "Second account",
            ordinarySlots: ["one"],
            childDisplayName: "Local key",
            includesManagement: false
        )
        let gate = DeterministicRequestGate()
        let client = ScriptedOpenRouterClient(gate: gate)
        for slotID in ["one", "two", "three", "four", "five"] {
            await client.setOrdinary(.success(Decimal(slotID.count)), slotID: slotID)
        }

        let firstCoordinator = makeCoordinator(fixture: first, client: client)
        let firstTask = Task {
            try await firstCoordinator.refresh(account: first.account)
        }
        await gate.waitForEntries(4)
        let activeRequestCount = await client.activeRequestCount
        XCTAssertEqual(activeRequestCount, 4)
        await gate.releaseAll()
        let firstResult = try await firstTask.value
        XCTAssertEqual(firstResult.successfulSourceCount, 5)
        let maximumActiveRequests = await client.maximumActiveRequests
        XCTAssertLessThanOrEqual(maximumActiveRequests, 4)

        let secondCoordinator = makeCoordinator(fixture: second, client: client)
        let secondResult = try await secondCoordinator.refresh(account: second.account)
        XCTAssertEqual(secondResult.snapshot?.savedAccountID, "second-account")
        XCTAssertEqual(firstResult.snapshot?.savedAccountID, "first-account")
        XCTAssertEqual(
            firstResult.snapshot?.accountContexts
                .filter { $0.kind == .credential }
                .map(\.displayName),
            Array(repeating: "Local key", count: 5)
        )
        XCTAssertEqual(
            secondResult.snapshot?.accountContexts
                .first { $0.kind == .credential }?.displayName,
            "Local key"
        )
    }

    func testDifferentAccountsUseIndependentLimitersInOneDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let database = try AppDatabase(directory: directory)
        let first = try makeFixture(
            accountID: "shared-first",
            accountDisplayName: "Shared first",
            ordinarySlots: ["one", "two", "three", "four"],
            childDisplayName: "Same child",
            includesManagement: false,
            database: database,
            directory: directory
        )
        let secondAccount = ProviderAccount(
            providerID: "openrouter",
            accountID: "shared-second",
            displayName: "Shared second",
            isEnabled: true
        )
        try DatabaseProviderConfigurationStore(database: database).save([
            first.account,
            secondAccount
        ])
        let second = try makeFixture(
            accountID: secondAccount.accountID,
            accountDisplayName: secondAccount.displayName,
            ordinarySlots: ["one"],
            childDisplayName: "Same child",
            includesManagement: false,
            database: database,
            directory: directory,
            accountAlreadySaved: true
        )
        let gate = DeterministicRequestGate()
        let client = ScriptedOpenRouterClient(gate: gate)
        for slotID in ["one", "two", "three", "four"] {
            await client.setOrdinary(.success(1), slotID: slotID)
        }
        let firstCoordinator = makeCoordinator(fixture: first, client: client)
        let secondCoordinator = makeCoordinator(fixture: second, client: client)

        let firstTask = Task {
            try await firstCoordinator.refresh(account: first.account)
        }
        await gate.waitForEntries(4)
        let secondTask = Task {
            try await secondCoordinator.refresh(account: second.account)
        }
        await gate.waitForEntries(5)
        let activeRequestCount = await client.activeRequestCount
        XCTAssertEqual(activeRequestCount, 5)
        await gate.releaseAll()

        let firstResult = try await firstTask.value
        let secondResult = try await secondTask.value
        XCTAssertEqual(firstResult.snapshot?.savedAccountID, first.account.accountID)
        XCTAssertEqual(secondResult.snapshot?.savedAccountID, second.account.accountID)
        XCTAssertEqual(
            try DatabaseProviderConfigurationStore(
                database: database
            ).accountCount(),
            2
        )
        XCTAssertEqual(
            firstResult.snapshot?.accountContexts
                .filter { $0.kind == .credential }
                .map(\.displayName),
            Array(repeating: "Same child", count: 4)
        )
        XCTAssertEqual(
            secondResult.snapshot?.accountContexts
                .first { $0.kind == .credential }?.displayName,
            "Same child"
        )
    }

    func testLateDisabledSlotResultIsSuppressedWithoutRemovingSibling() async throws {
        let fixture = try makeFixture(
            accountID: "race",
            ordinarySlots: ["slow", "sibling"],
            includesManagement: false
        )
        let gate = DeterministicRequestGate()
        let client = ScriptedOpenRouterClient(gate: gate)
        await client.setOrdinary(.success(9), slotID: "slow")
        await client.setOrdinary(.success(4), slotID: "sibling")
        let coordinator = makeCoordinator(fixture: fixture, client: client)

        let task = Task {
            try await coordinator.refresh(account: fixture.account)
        }
        await gate.waitForEntries(2)
        try fixture.credentialStore.setCredentialEnabled(
            false,
            providerID: "openrouter",
            accountID: "race",
            slotID: "slow"
        )
        await gate.releaseAll()
        let result = try await task.value
        let snapshot = try XCTUnwrap(result.snapshot)

        XCTAssertGreaterThanOrEqual(result.suppressedSourceCount, 1)
        XCTAssertFalse(
            snapshot.metrics.contains { $0.accountContextID == "slow" }
        )
        XCTAssertTrue(
            snapshot.metrics.contains { $0.accountContextID == "sibling" }
        )
    }

    func testLateDisabledAccountResultIsSuppressedDeterministically() async throws {
        let fixture = try makeFixture(
            accountID: "disabled-account",
            ordinarySlots: ["slow"],
            includesManagement: false
        )
        let gate = DeterministicRequestGate()
        let client = ScriptedOpenRouterClient(gate: gate)
        await client.setOrdinary(.success(9), slotID: "slow")
        let coordinator = makeCoordinator(fixture: fixture, client: client)

        let task = Task {
            try await coordinator.refresh(account: fixture.account)
        }
        await gate.waitForEntries(1)
        try DatabaseProviderConfigurationStore(
            database: fixture.database
        ).save([
            ProviderAccount(
                providerID: fixture.account.providerID,
                accountID: fixture.account.accountID,
                displayName: fixture.account.displayName,
                isEnabled: false
            )
        ])
        await gate.releaseAll()
        let result = try await task.value

        XCTAssertEqual(result.successfulSourceCount, 0)
        XCTAssertGreaterThanOrEqual(result.suppressedSourceCount, 1)
        XCTAssertNil(
            try fixture.capacityStore.load(
                providerID: "openrouter",
                accountID: "disabled-account",
                surface: OpenRouterProviderContract.surface,
                sources: OpenRouterProviderContract.sources
            )
        )
        XCTAssertTrue(
            try fixture.credentialStore.loadDiagnostics(
                providerID: "openrouter",
                accountID: "disabled-account"
            ).isEmpty
        )
    }

    func testLateDisabledSlotFailureDoesNotPersistDiagnostic() async throws {
        let fixture = try makeFixture(
            accountID: "failure-race",
            ordinarySlots: ["slow"],
            includesManagement: false
        )
        let gate = DeterministicRequestGate()
        let client = ScriptedOpenRouterClient(gate: gate)
        await client.setOrdinary(
            .failure(.transportFailure),
            slotID: "slow"
        )
        let coordinator = makeCoordinator(fixture: fixture, client: client)

        let task = Task {
            try await coordinator.refresh(account: fixture.account)
        }
        await gate.waitForEntries(1)
        try fixture.credentialStore.setCredentialEnabled(
            false,
            providerID: "openrouter",
            accountID: "failure-race",
            slotID: "slow"
        )
        await gate.releaseAll()
        let result = try await task.value

        XCTAssertEqual(result.failedSourceCount, 0)
        XCTAssertGreaterThanOrEqual(result.suppressedSourceCount, 1)
        XCTAssertTrue(
            try fixture.credentialStore.loadDiagnostics(
                providerID: "openrouter",
                accountID: "failure-race"
            ).isEmpty
        )
    }

    func testLateAccountDeletionSuppressesOnlyDeletedAccountResult() async throws {
        let deleted = try makeFixture(
            accountID: "deleted",
            accountDisplayName: "Deleted account",
            ordinarySlots: ["slow"],
            includesManagement: false
        )
        let survivor = try makeFixture(
            accountID: "survivor",
            accountDisplayName: "Survivor account",
            ordinarySlots: ["fast"],
            includesManagement: false
        )
        let gate = DeterministicRequestGate()
        let client = ScriptedOpenRouterClient(gate: gate)
        await client.setOrdinary(.success(9), slotID: "slow")
        await client.setOrdinary(.success(4), slotID: "fast")
        let deletedCoordinator = makeCoordinator(fixture: deleted, client: client)
        let survivorCoordinator = makeCoordinator(fixture: survivor, client: client)

        let deletedTask = Task {
            try await deletedCoordinator.refresh(account: deleted.account)
        }
        let survivorTask = Task {
            try await survivorCoordinator.refresh(account: survivor.account)
        }
        await gate.waitForEntries(2)
        try deleted.credentialStore.deleteAccount(
            providerID: "openrouter",
            accountID: "deleted"
        )
        await gate.releaseAll()

        let deletedResult = try await deletedTask.value
        let survivorResult = try await survivorTask.value
        XCTAssertNil(deletedResult.snapshot)
        XCTAssertGreaterThanOrEqual(deletedResult.suppressedSourceCount, 1)
        XCTAssertNotNil(survivorResult.snapshot)
        XCTAssertEqual(
            try DatabaseProviderConfigurationStore(
                database: deleted.database
            ).accountCount(),
            0
        )
    }

    func testCancellationDoesNotPersistLateMetricsOrFailureDiagnostic() async throws {
        let fixture = try makeFixture(
            accountID: "cancelled",
            ordinarySlots: ["slow"],
            includesManagement: false
        )
        let gate = DeterministicRequestGate()
        let client = ScriptedOpenRouterClient(gate: gate)
        await client.setOrdinary(.success(9), slotID: "slow")
        let coordinator = makeCoordinator(fixture: fixture, client: client)

        let task = Task {
            try await coordinator.refresh(account: fixture.account)
        }
        await gate.waitForEntries(1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertNil(
            try fixture.capacityStore.load(
                providerID: "openrouter",
                accountID: "cancelled",
                surface: OpenRouterProviderContract.surface,
                sources: OpenRouterProviderContract.sources
            )
        )
        XCTAssertTrue(
            try fixture.credentialStore.loadDiagnostics(
                providerID: "openrouter",
                accountID: "cancelled"
            ).isEmpty
        )
    }

    func testNativeSQLiteRoundTripIsExactSanitizedAndLeavesLegacyColumns() async throws {
        let exact = try XCTUnwrap(
            Decimal(
                string: "1234567890.123456789012345678",
                locale: Locale(identifier: "en_US_POSIX")
            )
        )
        let fixture = try makeFixture(
            accountID: "privacy",
            ordinarySlots: ["ordinary"],
            includesManagement: false,
            secretPrefix: "never-store-this-secret"
        )
        let client = ScriptedOpenRouterClient()
        await client.setOrdinary(.success(exact), slotID: "ordinary")
        let coordinator = makeCoordinator(fixture: fixture, client: client)

        let result = try await coordinator.refresh(account: fixture.account)
        let reloaded = try XCTUnwrap(
            fixture.capacityStore.load(
                providerID: "openrouter",
                accountID: "privacy",
                surface: OpenRouterProviderContract.surface,
                sources: OpenRouterProviderContract.sources
            )
        )
        XCTAssertEqual(result.snapshot, reloaded)
        XCTAssertEqual(
            try consumedValue(
                metricID: "key-total-usage",
                contextID: "ordinary",
                snapshot: reloaded
            ),
            exact
        )
        try ProviderContractValidator.validate(
            snapshot: reloaded,
            surface: OpenRouterProviderContract.surface,
            sources: OpenRouterProviderContract.sources
        )

        let databaseText = try await fixture.database.pool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT normalized_metric_json FROM native_capacity_metrics"
            ).joined(separator: "\n")
        }
        XCTAssertTrue(
            databaseText.contains("1234567890.123456789012345678")
        )
        XCTAssertFalse(databaseText.contains("never-store-this-secret"))
        XCTAssertFalse(databaseText.localizedCaseInsensitiveContains("provider message"))
        let legacyColumns = try await fixture.database.pool.read {
            try $0.columns(in: "current_snapshots").map(\.name)
        }
        XCTAssertTrue(legacyColumns.contains("used_percent"))
    }

    func testV6DatabaseMigratesToV7AndReopensWithoutLosingLegacyData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let account = ProviderAccount(
            providerID: "openrouter",
            accountID: "legacy",
            displayName: "Legacy OpenRouter",
            isEnabled: true
        )
        let legacySnapshot = UsageSnapshot(
            providerID: "openrouter",
            accountID: "legacy",
            accountDisplayName: "Legacy OpenRouter",
            displayName: "OpenRouter",
            status: .ok,
            remainingLabel: "Legacy snapshot",
            lastUpdatedAt: Date(timeIntervalSince1970: 9_000),
            confidence: .live,
            source: "legacy"
        )

        do {
            let v6 = try AppDatabase(
                directory: directory,
                migrationTarget: "v6-account-credential-contexts"
            )
            try DatabaseProviderConfigurationStore(database: v6).save([account])
            try DatabaseSnapshotStore(database: v6).save([legacySnapshot])
            try v6.pool.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO provider_account_contexts (
                            provider_id, account_id, context_id, kind,
                            display_name, region_id, parent_context_id
                        ) VALUES (?, ?, ?, 'credential', ?, 'global', NULL)
                        """,
                    arguments: [
                        "openrouter", "legacy", "legacy-key", "Legacy key"
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO provider_credential_slots (
                            provider_id, account_id, slot_id, context_id, role,
                            is_enabled, keychain_reference, lifecycle_state
                        ) VALUES (?, ?, ?, ?, 'ordinary', 1, ?, 'active')
                        """,
                    arguments: [
                        "openrouter", "legacy", "legacy-key", "legacy-key",
                        "legacy-reference"
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO credential_refresh_state (
                            provider_id, account_id, slot_id, last_attempt_at,
                            last_successful_refresh_at, last_failed_refresh_at
                        ) VALUES (?, ?, ?, ?, ?, NULL)
                        """,
                    arguments: [
                        "openrouter", "legacy", "legacy-key", 8_900, 8_900
                    ]
                )
            }
        }

        let migrated = try AppDatabase(directory: directory)
        let loadedAccounts = DatabaseProviderConfigurationStore(
            database: migrated
        ).load(knownProviderIDs: ["openrouter"])
        XCTAssertEqual(loadedAccounts.accounts, [account])
        XCTAssertEqual(
            try DatabaseSnapshotStore(database: migrated).snapshot(
                providerID: "openrouter",
                accountID: "legacy"
            ),
            legacySnapshot
        )
        let migratedSlot = try XCTUnwrap(
            AccountCredentialStore(
                database: migrated,
                keychainService: InMemoryCredentialKeychain()
            ).loadCredentialContexts(
                providerID: "openrouter",
                accountID: "legacy"
            ).first?.slot
        )
        XCTAssertEqual(migratedSlot.credentialRevision, 1)
        let migratedState = try XCTUnwrap(
            DatabaseCredentialMetadataStore(
                database: migrated
            ).loadRefreshStates(
                providerID: "openrouter",
                accountID: "legacy"
            ).first
        )
        XCTAssertEqual(
            migratedState.lastSuccessfulRefreshAt,
            Date(timeIntervalSince1970: 8_900)
        )
        XCTAssertNil(migratedState.lastCompletedAt)
        XCTAssertNil(migratedState.retryNotBefore)
        XCTAssertEqual(migratedState.consecutiveFailureCount, 0)
        XCTAssertNoThrow(try AppDatabase(directory: directory))
    }

    private func makeCoordinator(
        fixture: OpenRouterFixture,
        client: ScriptedOpenRouterClient
    ) -> OpenRouterRefreshCoordinator {
        OpenRouterRefreshCoordinator(
            credentialStore: fixture.credentialStore,
            capacityStore: fixture.capacityStore,
            client: client,
            policy: OpenRouterRefreshPolicy(
                maximumConcurrentSources: 4,
                initialBackoff: 30,
                maximumBackoff: 300
            ),
            now: { Date(timeIntervalSince1970: 20_000) }
        )
    }

    private func makeFixture(
        accountID: String,
        accountDisplayName: String = "OpenRouter account",
        ordinarySlots: [String],
        childDisplayName: String? = nil,
        includesManagement: Bool,
        secretPrefix: String = "synthetic",
        database suppliedDatabase: AppDatabase? = nil,
        directory suppliedDirectory: URL? = nil,
        accountAlreadySaved: Bool = false
    ) throws -> OpenRouterFixture {
        let directory: URL
        let database: AppDatabase
        if let suppliedDatabase, let suppliedDirectory {
            directory = suppliedDirectory
            database = suppliedDatabase
        } else {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            addTeardownBlock {
                try? FileManager.default.removeItem(at: directory)
            }
            database = try AppDatabase(directory: directory)
        }
        let account = ProviderAccount(
            providerID: "openrouter",
            accountID: accountID,
            displayName: accountDisplayName,
            isEnabled: true
        )
        if !accountAlreadySaved {
            try DatabaseProviderConfigurationStore(database: database).save([account])
        }

        let keychain = InMemoryCredentialKeychain()
        let credentialStore = AccountCredentialStore(
            database: database,
            keychainService: keychain
        )
        let rootContextID = "\(accountID)-root"
        try credentialStore.createContext(
            ProviderAccountContextConfiguration(
                providerID: "openrouter",
                accountID: accountID,
                contextID: rootContextID,
                kind: .personal,
                displayName: accountDisplayName,
                regionID: "global"
            )
        )
        for slotID in ordinarySlots {
            try credentialStore.createContext(
                ProviderAccountContextConfiguration(
                    providerID: "openrouter",
                    accountID: accountID,
                    contextID: slotID,
                    kind: .credential,
                    displayName: childDisplayName ?? slotID,
                    regionID: "global",
                    parentContextID: rootContextID
                )
            )
            try credentialStore.createCredential(
                providerID: "openrouter",
                accountID: accountID,
                slotID: slotID,
                contextID: slotID,
                role: .ordinary,
                credential: CredentialSecret("\(secretPrefix)-\(accountID)-\(slotID)")
            )
        }
        if includesManagement {
            try credentialStore.createCredential(
                providerID: "openrouter",
                accountID: accountID,
                slotID: "management",
                contextID: rootContextID,
                role: .management,
                credential: CredentialSecret(
                    "\(secretPrefix)-\(accountID)-management"
                )
            )
        }
        return OpenRouterFixture(
            directory: directory,
            database: database,
            account: account,
            rootContextID: rootContextID,
            credentialStore: credentialStore,
            capacityStore: DatabaseCapacitySnapshotStore(database: database)
        )
    }

    private func consumedValue(
        metricID: String,
        contextID: String,
        snapshot: CapacitySnapshot
    ) throws -> Decimal {
        try XCTUnwrap(
            snapshot.metrics.first {
                $0.metricID == metricID
                    && $0.accountContextID == contextID
            }?.values?.consumed?.value
        )
    }

    private func compatibilitySnapshot(
        result: OpenRouterAccountRefreshResult,
        account: ProviderAccount
    ) async throws -> UsageSnapshot {
        try await OpenRouterProviderAdapter(
            refreshCoordinator: StaticOpenRouterRefresher(result: result)
        ).fetchSnapshot(account: account)
    }
}

private struct OpenRouterFixture {
    let directory: URL
    let database: AppDatabase
    let account: ProviderAccount
    let rootContextID: String
    let credentialStore: AccountCredentialStore
    let capacityStore: DatabaseCapacitySnapshotStore
}

private struct StaticOpenRouterRefresher: OpenRouterAccountRefreshing {
    let result: OpenRouterAccountRefreshResult

    func refresh(
        account: ProviderAccount
    ) async throws -> OpenRouterAccountRefreshResult {
        result
    }

    func invalidateAccount(providerID: String, accountID: String) {}
}

private final class InMemoryCredentialKeychain: KeychainService, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: CredentialSecret] = [:]

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
}

private actor ScriptedOpenRouterClient: OpenRouterAPIClient {
    enum Response: Sendable {
        case success(Decimal)
        case failure(OpenRouterAPIClientError)
    }

    private var ordinaryResponses: [String: Response] = [:]
    private var managementResponses: [String: Response] = [:]
    private var calls: [String: Int] = [:]
    private var revisions: [String: [Int]] = [:]
    private var activeRequests = 0
    private(set) var maximumActiveRequests = 0
    private let gate: DeterministicRequestGate?

    init(gate: DeterministicRequestGate? = nil) {
        self.gate = gate
    }

    func setOrdinary(_ response: Response, slotID: String) {
        ordinaryResponses[slotID] = response
    }

    func setManagement(_ response: Response, slotID: String) {
        managementResponses[slotID] = response
    }

    func callCount(slotID: String) -> Int {
        calls[slotID, default: 0]
    }

    func observedRevisions(slotID: String) -> [Int] {
        revisions[slotID, default: []]
    }

    var activeRequestCount: Int {
        activeRequests
    }

    func fetchCurrentKeyCapacity(
        credential: OpenRouterOrdinaryCredential
    ) async throws -> OpenRouterCurrentKeyCapacity {
        let slotID = credential.credentialSlotID
        revisions[slotID, default: []].append(credential.credentialRevision)
        let response = ordinaryResponses[slotID] ?? .success(0)
        try await begin(slotID: slotID)
        defer { end() }
        switch response {
        case let .success(value):
            return OpenRouterCurrentKeyCapacity(
                metrics: Self.ordinaryMetrics(
                    contextID: credential.accountContextID,
                    value: value
                ),
                includesBYOKInLimit: true,
                tier: .paid,
                expiresAt: nil
            )
        case let .failure(error):
            throw error
        }
    }

    func fetchManagementCredits(
        credential: OpenRouterManagementCredential
    ) async throws -> OpenRouterManagementCreditsCapacity {
        let slotID = credential.credentialSlotID
        let response = managementResponses[slotID] ?? .success(0)
        try await begin(slotID: slotID)
        defer { end() }
        switch response {
        case let .success(value):
            return OpenRouterManagementCreditsCapacity(
                metric: CapacityMetric(
                    metricID: "account-credits",
                    accountContextID: credential.accountContextID,
                    sourceID: "management-api",
                    capability: "credits",
                    displayName: "Account credits",
                    availability: .known,
                    unit: CapacityUnit(
                        kind: .currency,
                        currencyCode: "USD"
                    ),
                    values: CapacityValues(
                        consumed: CapacityValue(
                            value: value,
                            origin: .reported
                        ),
                        limit: CapacityValue(
                            value: value + 10,
                            origin: .reported
                        )
                    ),
                    window: CapacityWindow(kind: .none),
                    freshness: ObservationFreshness(
                        observedAt: Date(timeIntervalSince1970: 20_000)
                    ),
                    confidence: .live
                )
            )
        case let .failure(error):
            throw error
        }
    }

    private func begin(slotID: String) async throws {
        calls[slotID, default: 0] += 1
        activeRequests += 1
        maximumActiveRequests = max(maximumActiveRequests, activeRequests)
        do {
            try await gate?.enter()
        } catch {
            activeRequests -= 1
            throw error
        }
    }

    private func end() {
        activeRequests -= 1
    }

    static func ordinaryMetrics(
        contextID: String,
        value: Decimal
    ) -> [CapacityMetric] {
        let freshness = ObservationFreshness(
            observedAt: Date(timeIntervalSince1970: 20_000)
        )
        return [
            CapacityMetric(
                metricID: "key-total-usage",
                accountContextID: contextID,
                sourceID: "current-key-api",
                capability: "spend",
                displayName: "API key total usage",
                availability: .known,
                unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
                values: CapacityValues(
                    consumed: CapacityValue(value: value, origin: .reported)
                ),
                window: CapacityWindow(kind: .lifetime),
                freshness: freshness,
                confidence: .live
            ),
            CapacityMetric(
                metricID: "key-total-byok-usage",
                accountContextID: contextID,
                sourceID: "current-key-api",
                capability: "spend",
                displayName: "API key total BYOK usage",
                availability: .known,
                unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
                values: CapacityValues(
                    consumed: CapacityValue(
                        value: value / 10,
                        origin: .reported
                    )
                ),
                window: CapacityWindow(kind: .lifetime),
                freshness: freshness,
                confidence: .live
            ),
            CapacityMetric(
                metricID: "key-credit-limit",
                accountContextID: contextID,
                sourceID: "current-key-api",
                capability: "credits",
                displayName: "API key credit limit",
                availability: .known,
                unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
                values: CapacityValues(
                    remaining: CapacityValue(
                        value: 10 - value,
                        origin: .reported
                    ),
                    limit: CapacityValue(value: 10, origin: .reported)
                ),
                window: CapacityWindow(
                    kind: .fixed,
                    durationSeconds: 2_592_000,
                    nextTransition: CapacityTransition(
                        kind: .reset,
                        at: Date(timeIntervalSince1970: 30_000)
                    )
                ),
                freshness: freshness,
                confidence: .live
            )
        ]
    }
}

private actor DeterministicRequestGate {
    private var entryCount = 0
    private var released = false
    private var blocked: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var entryWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []

    func enter() async throws {
        entryCount += 1
        resumeSatisfiedEntryWaiters()
        guard !released else {
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if released {
                    continuation.resume()
                } else {
                    blocked[waiterID] = continuation
                }
            }
        } onCancel: {
            Task {
                await self.cancel(waiterID)
            }
        }
    }

    func waitForEntries(_ count: Int) async {
        guard entryCount < count else {
            return
        }
        await withCheckedContinuation { continuation in
            entryWaiters.append((count, continuation))
        }
    }

    func releaseAll() {
        released = true
        let continuations = blocked.values
        blocked.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func cancel(_ waiterID: UUID) {
        blocked.removeValue(forKey: waiterID)?
            .resume(throwing: CancellationError())
    }

    private func resumeSatisfiedEntryWaiters() {
        var remaining: [
            (count: Int, continuation: CheckedContinuation<Void, Never>)
        ] = []
        for waiter in entryWaiters {
            if entryCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        entryWaiters = remaining
    }
}

private enum DeterministicTestError: Error {
    case injected
}

private final class LockedTestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Bool

    init(_ value: Bool) {
        storedValue = value
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Bool) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}

private final class TestClock: @unchecked Sendable {
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
