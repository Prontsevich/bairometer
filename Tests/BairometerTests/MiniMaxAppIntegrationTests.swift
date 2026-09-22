#if DEBUG
import Foundation
import XCTest
@testable import Bairometer
@testable import BairometerCore

@MainActor
final class MiniMaxAppIntegrationTests: XCTestCase {
    func testProductionCompositionRefreshesConfiguredMiniMaxAccount() async throws {
        let directory = temporaryDirectory()
        let keychain = MiniMaxAppIntegrationKeychain()
        let client = InjectedMiniMaxAPIClient()
        let model = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            refreshCoordinator: ProviderRefreshCoordinator(
                retryPolicy: ProviderRetryPolicy(maxAttempts: 1, initialDelay: 0)
            ),
            miniMaxAPIClient: client,
            credentialKeychainService: keychain
        )
        let account = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "Local Team")
        )
        let credential = try configureCredential(model: model, account: account)
        await client.useContextID(credential.context.contextID)

        let initialCallCount = await client.callCount
        XCTAssertEqual(initialCallCount, 0)
        model.refreshAccount(
            providerID: account.providerID,
            accountID: account.accountID
        )
        await model.waitForRefreshCompletionForTesting()

        let refreshedCallCount = await client.callCount
        XCTAssertEqual(refreshedCallCount, 1)
        let projection = try XCTUnwrap(model.snapshot(for: account))
        XCTAssertEqual(projection.status, .ok)
        XCTAssertNil(projection.usedPercent)
        XCTAssertTrue(projection.limitWindows.isEmpty)
        XCTAssertFalse(projection.source.contains(InjectedMiniMaxAPIClient.rawMarker))
        XCTAssertFalse(projection.source.contains(MiniMaxAppIntegrationKeychain.secretMarker))

        let cachedNative = try XCTUnwrap(model.nativeCapacitySnapshot(for: account))
        XCTAssertEqual(
            cachedNative.metrics.map(\.metricID),
            [
                "quota-category-a.current",
                "quota-category-a.weekly",
                "quota-category-b.current",
                "quota-category-b.weekly",
            ]
        )
        XCTAssertEqual(
            cachedNative.metrics.map(\.values?.consumed?.value),
            [4, 8, 12, 16]
        )
        XCTAssertEqual(
            cachedNative.metrics.map(\.unit),
            Array(repeating: CapacityUnit(kind: .percent), count: 4)
        )
        XCTAssertEqual(
            cachedNative.metrics.map(\.window.kind),
            [.rolling, .fixed, .rolling, .fixed]
        )
        XCTAssertEqual(
            cachedNative.metrics.map(\.window.durationSeconds),
            [18_000, 604_800, 18_000, 604_800]
        )
        XCTAssertTrue(cachedNative.metrics.allSatisfy {
            guard let endsAt = $0.window.endsAt else {
                return false
            }
            return $0.window.nextTransition == CapacityTransition(
                kind: .reset,
                at: endsAt
            )
        })
        XCTAssertEqual(
            cachedNative.metrics.map(\.values?.remaining),
            [
                CapacityValue(value: 96, origin: .reported),
                CapacityValue(value: 92, origin: .reported),
                CapacityValue(value: 88, origin: .reported),
                CapacityValue(value: 84, origin: .reported),
            ]
        )
        XCTAssertTrue(cachedNative.metrics.allSatisfy {
            $0.values?.consumed?.origin == .derived
                && $0.values?.limit == CapacityValue(value: 100, origin: .reported)
                && $0.derivations == [
                    Derivation(
                        kind: .consumedFromLimitMinusRemaining,
                        target: .consumed,
                        inputs: [.limit, .remaining]
                    )
                ]
        })
        let presentation = try XCTUnwrap(
            MiniMaxCapacityPresentation(
                account: account,
                snapshot: cachedNative,
                now: cachedNative.observedAt,
                locale: Locale(identifier: "en_US")
            )
        )
        XCTAssertEqual(
            presentation.categories.flatMap(\.windows).map(\.id),
            cachedNative.metrics.map(\.metricID)
        )
        XCTAssertEqual(
            presentation.categories.flatMap(\.windows).map(\.capacityText),
            Array(repeating: "", count: 4)
        )
        XCTAssertEqual(
            presentation.categories.flatMap(\.windows).map(\.percentageText),
            ["4% used", "8% used", "12% used", "16% used"]
        )
        let visibleText = presentation.categories.flatMap { category in
            [category.displayName, category.accessibilityValue]
                + category.windows.flatMap {
                    [$0.displayName, $0.capacityText, $0.accessibilityValue]
                }
        }.joined(separator: " ").lowercased()
        XCTAssertFalse(
            presentation.categories.map { $0.displayName.lowercased() }
                .contains("general")
        )
        XCTAssertFalse(
            presentation.categories.map { $0.displayName.lowercased() }
                .contains("video")
        )
        XCTAssertFalse(visibleText.contains("unrecognized-category-marker"))
        XCTAssertFalse(visibleText.contains("total 100"))
        XCTAssertFalse(visibleText.contains("remaining 96"))

        let native = try XCTUnwrap(
            try model.nativeCapacitySnapshotStore.load(
                providerID: account.providerID,
                accountID: account.accountID,
                surface: MiniMaxProviderContract.surface,
                sources: MiniMaxProviderContract.sources
            )
        )
        XCTAssertEqual(native.savedAccountID, account.accountID)
        XCTAssertEqual(native.metrics, cachedNative.metrics)
        XCTAssertEqual(
            native.metrics.map(\.metricID),
            [
                "quota-category-a.current",
                "quota-category-a.weekly",
                "quota-category-b.current",
                "quota-category-b.weekly",
            ]
        )
        XCTAssertEqual(
            native.metrics.map(\.accountContextID),
            Array(
                repeating: "\(account.accountID)-\(AppModel.miniMaxRootContextSuffix)",
                count: 4
            )
        )
        XCTAssertEqual(
            native.metrics.map(\.displayName),
            [
                "Included usage — current rolling window",
                "Included usage — weekly window",
                "Included usage — current rolling window",
                "Included usage — weekly window",
            ]
        )
        XCTAssertTrue(model.diagnosticStore.load().allSatisfy {
            !$0.message.contains(InjectedMiniMaxAPIClient.rawMarker)
                && !$0.message.contains(MiniMaxAppIntegrationKeychain.secretMarker)
        })
        try assertStorage(
            at: directory,
            excludes: [
                InjectedMiniMaxAPIClient.rawMarker,
                MiniMaxAppIntegrationKeychain.secretMarker,
                "unrecognized-category-marker",
                "general",
                "video"
            ]
        )
    }

    func testAcceptedMiniMaxRefreshReloadsCurrentSettingsDiagnostics() async throws {
        let client = InjectedMiniMaxAPIClient()
        let model = AppModel(
            storageDirectory: temporaryDirectory(),
            userDefaults: isolatedDefaults(),
            refreshCoordinator: ProviderRefreshCoordinator(
                retryPolicy: ProviderRetryPolicy(maxAttempts: 1, initialDelay: 0)
            ),
            miniMaxAPIClient: client,
            credentialKeychainService: MiniMaxAppIntegrationKeychain()
        )
        let account = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "Settings Cache")
        )
        let credential = try configureCredential(model: model, account: account)
        await client.useContextID(credential.context.contextID)

        await client.enqueueFailure(.unavailableSubscription)
        model.refreshAccount(providerID: account.providerID, accountID: account.accountID)
        await model.waitForRefreshCompletionForTesting()
        XCTAssertEqual(
            model.miniMaxCredentialDiagnostics(for: account).first?.code,
            .insufficientPrivilege
        )

        await client.enqueueFailure(.authenticationFailure)
        model.refreshAccount(providerID: account.providerID, accountID: account.accountID)
        await model.waitForRefreshCompletionForTesting()
        XCTAssertEqual(
            model.miniMaxCredentialDiagnostics(for: account).first?.code,
            .authentication
        )

        model.refreshAccount(providerID: account.providerID, accountID: account.accountID)
        await model.waitForRefreshCompletionForTesting()
        XCTAssertTrue(model.miniMaxCredentialDiagnostics(for: account).isEmpty)
    }

    func testProductionQuotaCategoryMappingUsesOnlyLocalOutputLabels() throws {
        let mapping = MiniMaxProviderContract.reviewedQuotaCategories
        let categoryA = try XCTUnwrap(
            mapping.reviewedCategory(forProviderIdentifier: "general")
        )
        let categoryB = try XCTUnwrap(
            mapping.reviewedCategory(forProviderIdentifier: "video")
        )

        XCTAssertEqual(categoryA.stableID, "quota-category-a")
        XCTAssertEqual(categoryA.displayName, "Token Plan capacity A")
        XCTAssertEqual(categoryB.stableID, "quota-category-b")
        XCTAssertEqual(categoryB.displayName, "Token Plan capacity B")
        XCTAssertNil(mapping.reviewedCategory(
            forProviderIdentifier: "unknown-category"
        ))
        XCTAssertNil(mapping.reviewedCategory(forProviderIdentifier: "MiniMax-M2"))
        XCTAssertNil(mapping.reviewedCategory(forProviderIdentifier: "MiniMax-M*"))
        XCTAssertFalse(categoryA.displayName.contains("general"))
        XCTAssertFalse(categoryB.displayName.contains("video"))
    }

    func testMiniMaxSettingsCredentialLifecycleUsesOneIsolatedKeychainSlot() throws {
        let directory = temporaryDirectory()
        let keychain = MiniMaxAppIntegrationKeychain()
        let defaults = isolatedDefaults()
        let model = AppModel(
            storageDirectory: directory,
            userDefaults: defaults,
            miniMaxAPIClient: InjectedMiniMaxAPIClient(),
            credentialKeychainService: keychain
        )
        let account = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "Lifecycle")
        )
        XCTAssertEqual(account.sourceMode, .miniMaxTokenPlan)

        let initialContexts = try model.accountCredentialStore.loadContexts(
            providerID: account.providerID,
            accountID: account.accountID
        )
        XCTAssertEqual(initialContexts.count, 1)
        XCTAssertEqual(initialContexts[0].kind, .team)
        XCTAssertEqual(initialContexts[0].displayName, "Personal Default Team")
        XCTAssertEqual(initialContexts[0].regionID, "global")
        XCTAssertNil(initialContexts[0].parentContextID)
        XCTAssertTrue(model.miniMaxCredentialContexts(for: account).isEmpty)
        XCTAssertThrowsError(
            try model.createMiniMaxSubscriptionKey(
                for: account,
                credentialValue: ""
            )
        ) {
            XCTAssertEqual($0 as? MiniMaxSettingsError, .emptyCredential)
        }
        XCTAssertEqual(keychain.credentialCount, 0)

        let created = try model.createMiniMaxSubscriptionKey(
            for: account,
            credentialValue: "first-private-subscription-key"
        )
        XCTAssertEqual(created.slot.role, .ordinary)
        XCTAssertEqual(created.slot.slotID, AppModel.miniMaxSubscriptionSlotID)
        XCTAssertEqual(created.context.kind, .credential)
        XCTAssertEqual(created.context.parentContextID, initialContexts[0].contextID)
        let configuredContexts = try model.accountCredentialStore.loadContexts(
            providerID: account.providerID,
            accountID: account.accountID
        )
        XCTAssertEqual(configuredContexts.count, 2)
        XCTAssertEqual(
            configuredContexts.filter { $0.parentContextID == nil }.count,
            1
        )
        XCTAssertEqual(model.miniMaxCredentialContexts(for: account).count, 1)
        XCTAssertEqual(keychain.credentialCount, 1)
        XCTAssertTrue(
            try keychain.matchesCredential(
                reference: created.slot.keychainReference,
                value: "first-private-subscription-key"
            )
        )
        try seedRefreshMetadata(
            model: model,
            account: account,
            occurredAt: Date(timeIntervalSince1970: 75_000)
        )
        model.reloadMiniMaxPresentationData(for: account)
        XCTAssertEqual(model.miniMaxCredentialRefreshStates(for: account).count, 1)
        XCTAssertEqual(model.miniMaxCredentialDiagnostics(for: account).count, 1)

        XCTAssertThrowsError(
            try model.createMiniMaxSubscriptionKey(
                for: account,
                credentialValue: "second-slot-must-not-exist"
            )
        ) {
            XCTAssertEqual($0 as? MiniMaxSettingsError, .credentialExists)
        }
        XCTAssertThrowsError(
            try model.replaceMiniMaxSubscriptionKey(
                for: account,
                credentialValue: ""
            )
        ) {
            XCTAssertEqual($0 as? MiniMaxSettingsError, .emptyCredential)
        }

        try model.replaceMiniMaxSubscriptionKey(
            for: account,
            credentialValue: "replacement-private-subscription-key"
        )
        let replaced = try XCTUnwrap(
            model.miniMaxCredentialContexts(for: account).first
        )
        XCTAssertTrue(
            replaced.slot.keychainReference == created.slot.keychainReference
        )
        XCTAssertEqual(replaced.slot.credentialRevision, 2)
        XCTAssertEqual(model.miniMaxCredentialRefreshStates(for: account).count, 1)
        XCTAssertEqual(model.miniMaxCredentialDiagnostics(for: account).count, 1)
        XCTAssertTrue(
            try keychain.matchesCredential(
                reference: replaced.slot.keychainReference,
                value: "replacement-private-subscription-key"
            )
        )

        try model.setMiniMaxSubscriptionKeyEnabled(false, for: account)
        XCTAssertFalse(
            try XCTUnwrap(model.miniMaxCredentialContexts(for: account).first)
                .slot.isEnabled
        )
        try model.setMiniMaxSubscriptionKeyEnabled(true, for: account)
        XCTAssertTrue(
            try XCTUnwrap(model.miniMaxCredentialContexts(for: account).first)
                .slot.isEnabled
        )

        XCTAssertFalse(
            String(describing: defaults.dictionaryRepresentation()).contains(
                "replacement-private-subscription-key"
            )
        )
        XCTAssertFalse(
            initialContexts[0].displayName?.contains(
                replaced.slot.keychainReference
            ) ?? false
        )
        try assertStorage(
            at: directory,
            excludes: [
                "first-private-subscription-key",
                "replacement-private-subscription-key"
            ]
        )

        keychain.failDeletion(for: replaced.slot.keychainReference)
        XCTAssertThrowsError(
            try model.deleteMiniMaxSubscriptionKey(for: account)
        ) {
            XCTAssertEqual($0 as? MiniMaxSettingsError, .keychainUnavailable)
        }
        XCTAssertEqual(
            model.miniMaxCredentialContexts(for: account)
                .first?.slot.lifecycleState,
            .pendingDeletion
        )
        keychain.allowDeletion(for: replaced.slot.keychainReference)
        try model.deleteMiniMaxSubscriptionKey(for: account)
        XCTAssertTrue(model.miniMaxCredentialContexts(for: account).isEmpty)
        XCTAssertTrue(model.miniMaxCredentialRefreshStates(for: account).isEmpty)
        XCTAssertTrue(model.miniMaxCredentialDiagnostics(for: account).isEmpty)
        XCTAssertEqual(keychain.credentialCount, 0)
        let remainingContexts = try model.accountCredentialStore.loadContexts(
            providerID: account.providerID,
            accountID: account.accountID
        )
        XCTAssertEqual(remainingContexts, initialContexts)
    }

    func testSeveralMiniMaxAccountsKeepCredentialMutationsIsolated() throws {
        let keychain = MiniMaxAppIntegrationKeychain()
        let model = AppModel(
            storageDirectory: temporaryDirectory(),
            userDefaults: isolatedDefaults(),
            miniMaxAPIClient: InjectedMiniMaxAPIClient(),
            credentialKeychainService: keychain
        )
        let first = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "First")
        )
        let second = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "Second")
        )
        let firstCredential = try model.createMiniMaxSubscriptionKey(
            for: first,
            credentialValue: "first-isolated-secret"
        )
        let secondCredential = try model.createMiniMaxSubscriptionKey(
            for: second,
            credentialValue: "second-isolated-secret"
        )

        XCTAssertFalse(
            firstCredential.slot.keychainReference
                == secondCredential.slot.keychainReference
        )
        try model.replaceMiniMaxSubscriptionKey(
            for: first,
            credentialValue: "first-replaced-secret"
        )
        try model.setMiniMaxSubscriptionKeyEnabled(false, for: first)

        let unchangedSecond = try XCTUnwrap(
            model.miniMaxCredentialContexts(for: second).first
        )
        XCTAssertTrue(unchangedSecond.slot.isEnabled)
        XCTAssertEqual(unchangedSecond.slot.credentialRevision, 1)
        XCTAssertTrue(
            try keychain.matchesCredential(
                reference: unchangedSecond.slot.keychainReference,
                value: "second-isolated-secret"
            )
        )

        try model.deleteMiniMaxSubscriptionKey(for: first)
        XCTAssertFalse(
            keychain.containsCredential(
                reference: firstCredential.slot.keychainReference
            )
        )
        XCTAssertTrue(
            keychain.containsCredential(
                reference: secondCredential.slot.keychainReference
            )
        )
        XCTAssertEqual(model.miniMaxCredentialContexts(for: second).count, 1)
    }

    func testCredentialReplacementDiscardsAccountALateResultAndGlobalRefreshCompletesAccountB() async throws {
        let directory = temporaryDirectory()
        let keychain = MiniMaxAppIntegrationKeychain()
        let client = BarrierMiniMaxAPIClient()
        let model = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            refreshCoordinator: ProviderRefreshCoordinator(
                retryPolicy: ProviderRetryPolicy(maxAttempts: 1, initialDelay: 0)
            ),
            miniMaxAPIClient: client,
            credentialKeychainService: keychain
        )
        let accountA = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "Account A")
        )
        let accountB = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "Account B")
        )
        let credentialA = try model.createMiniMaxSubscriptionKey(
            for: accountA,
            credentialValue: "account-a-initial-secret"
        )
        let credentialB = try model.createMiniMaxSubscriptionKey(
            for: accountB,
            credentialValue: "account-b-secret"
        )
        await client.useContextIDs([
            credentialA.context.contextID,
            credentialB.context.contextID
        ])
        await client.blockNextRequest()

        model.refresh()
        await client.waitUntilRequestIsBlocked()
        try model.replaceMiniMaxSubscriptionKey(
            for: accountA,
            credentialValue: "account-a-replacement-secret"
        )
        await client.releaseBlockedRequest()
        await model.waitForRefreshCompletionForTesting()

        let callCount = await client.callCount
        XCTAssertEqual(callCount, 2)
        XCTAssertNil(model.snapshot(for: accountA))
        XCTAssertNil(model.accountRefreshIssues[accountA.id])
        XCTAssertNil(model.providerRefreshStatuses[accountA.id])
        XCTAssertTrue(model.miniMaxCredentialDiagnostics(for: accountA).isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(model.miniMaxCredentialContexts(for: accountA).first)
                .slot.credentialRevision,
            2
        )

        let snapshotB = try XCTUnwrap(model.snapshot(for: accountB))
        XCTAssertEqual(snapshotB.status, .ok)
        XCTAssertNil(model.accountRefreshIssues[accountB.id])
        XCTAssertNotNil(
            model.sourceRefreshStates[accountB.id]?.lastSuccessfulRefreshAt
        )
        guard case .succeeded = model.providerRefreshStatuses[accountB.id] else {
            return XCTFail("Account B did not finish its global refresh.")
        }
        XCTAssertNil(
            try model.nativeCapacitySnapshotStore.load(
                providerID: accountA.providerID,
                accountID: accountA.accountID,
                surface: MiniMaxProviderContract.surface,
                sources: MiniMaxProviderContract.sources
            )
        )
        XCTAssertNotNil(
            try model.nativeCapacitySnapshotStore.load(
                providerID: accountB.providerID,
                accountID: accountB.accountID,
                surface: MiniMaxProviderContract.surface,
                sources: MiniMaxProviderContract.sources
            )
        )

        let reloaded = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            miniMaxAPIClient: client,
            credentialKeychainService: keychain
        )
        XCTAssertNil(reloaded.snapshot(for: accountA))
        let reloadedSnapshotB = try XCTUnwrap(reloaded.snapshot(for: accountB))
        XCTAssertEqual(reloadedSnapshotB.id, snapshotB.id)
        XCTAssertEqual(reloadedSnapshotB.status, snapshotB.status)
        XCTAssertEqual(reloadedSnapshotB.remainingLabel, snapshotB.remainingLabel)
        XCTAssertEqual(reloadedSnapshotB.source, snapshotB.source)
        XCTAssertEqual(
            reloadedSnapshotB.lastUpdatedAt.timeIntervalSince1970,
            snapshotB.lastUpdatedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testCredentialReplacementDiscardsLateDirectAccountRefresh() async throws {
        let directory = temporaryDirectory()
        let keychain = MiniMaxAppIntegrationKeychain()
        let client = BarrierMiniMaxAPIClient()
        let model = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            refreshCoordinator: ProviderRefreshCoordinator(
                retryPolicy: ProviderRetryPolicy(maxAttempts: 1, initialDelay: 0)
            ),
            miniMaxAPIClient: client,
            credentialKeychainService: keychain
        )
        let accountA = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "Account A")
        )
        let credentialA = try model.createMiniMaxSubscriptionKey(
            for: accountA,
            credentialValue: "account-a-initial-secret"
        )
        let sourceDiagnostic = SourceDiagnostic(
            providerID: accountA.providerID,
            accountID: accountA.accountID,
            code: "refresh-0",
            message: "Sanitized direct-refresh persistence sentinel.",
            occurredAt: Date(timeIntervalSince1970: 76_543)
        )
        try model.diagnosticStore.replaceRefreshDiagnostics(
            providerID: accountA.providerID,
            accountID: accountA.accountID,
            occurredAt: sourceDiagnostic.occurredAt,
            messages: [sourceDiagnostic.message]
        )
        model.loadDiagnostics()
        XCTAssertEqual(
            model.diagnosticStore.load().filter {
                $0.providerID == accountA.providerID
                    && $0.accountID == accountA.accountID
            },
            [sourceDiagnostic]
        )
        await client.useContextIDs([credentialA.context.contextID])
        await client.blockNextRequest()

        model.refreshAccount(
            providerID: accountA.providerID,
            accountID: accountA.accountID
        )
        await client.waitUntilRequestIsBlocked()
        let refreshTask = try XCTUnwrap(model.accountRefreshTasks[accountA.id])
        try model.replaceMiniMaxSubscriptionKey(
            for: accountA,
            credentialValue: "account-a-replacement-secret"
        )
        await client.releaseBlockedRequest()
        await refreshTask.value

        let callCount = await client.callCount
        model.reloadMiniMaxPresentationData(for: accountA)
        XCTAssertEqual(callCount, 1)
        XCTAssertNil(model.snapshot(for: accountA))
        XCTAssertEqual(
            model.accountRefreshIssues[accountA.id],
            AccountRefreshIssue(
                occurredAt: sourceDiagnostic.occurredAt,
                warnings: [sourceDiagnostic.message]
            )
        )
        XCTAssertNil(model.providerRefreshStatuses[accountA.id])
        XCTAssertEqual(
            model.sourceDiagnostics.filter {
                $0.providerID == accountA.providerID
                    && $0.accountID == accountA.accountID
            },
            [sourceDiagnostic]
        )
        XCTAssertNil(model.sourceRefreshStates[accountA.id])
        XCTAssertTrue(model.miniMaxCredentialRefreshStates(for: accountA).isEmpty)
        XCTAssertTrue(model.miniMaxCredentialDiagnostics(for: accountA).isEmpty)
        XCTAssertEqual(
            model.diagnosticStore.load().filter {
                $0.providerID == accountA.providerID
                    && $0.accountID == accountA.accountID
            },
            [sourceDiagnostic]
        )
        XCTAssertNil(
            try model.nativeCapacitySnapshotStore.load(
                providerID: accountA.providerID,
                accountID: accountA.accountID,
                surface: MiniMaxProviderContract.surface,
                sources: MiniMaxProviderContract.sources
            )
        )

        let reloaded = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            miniMaxAPIClient: client,
            credentialKeychainService: keychain
        )
        reloaded.reloadMiniMaxPresentationData(for: accountA)
        XCTAssertNil(reloaded.snapshot(for: accountA))
        XCTAssertEqual(
            reloaded.sourceDiagnostics.filter {
                $0.providerID == accountA.providerID
                    && $0.accountID == accountA.accountID
            },
            [sourceDiagnostic]
        )
        XCTAssertEqual(
            reloaded.accountRefreshIssues[accountA.id],
            AccountRefreshIssue(
                occurredAt: sourceDiagnostic.occurredAt,
                warnings: [sourceDiagnostic.message]
            )
        )
        XCTAssertNil(reloaded.sourceRefreshStates[accountA.id])
        XCTAssertTrue(
            reloaded.miniMaxCredentialRefreshStates(for: accountA).isEmpty
        )
        XCTAssertTrue(reloaded.miniMaxCredentialDiagnostics(for: accountA).isEmpty)
        XCTAssertNil(
            try reloaded.nativeCapacitySnapshotStore.load(
                providerID: accountA.providerID,
                accountID: accountA.accountID,
                surface: MiniMaxProviderContract.surface,
                sources: MiniMaxProviderContract.sources
            )
        )
    }

    func testDeletingMiniMaxAccountRemovesOnlyItsCredentials() throws {
        let directory = temporaryDirectory()
        let keychain = MiniMaxAppIntegrationKeychain()
        let model = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            miniMaxAPIClient: InjectedMiniMaxAPIClient(),
            credentialKeychainService: keychain
        )
        let deletedAccount = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "Delete Me")
        )
        let retainedAccount = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "Keep Me")
        )
        try configureCredential(model: model, account: deletedAccount)
        try configureCredential(model: model, account: retainedAccount)
        let deletedReference = try XCTUnwrap(
            model.accountCredentialStore.loadCredentialContexts(
                providerID: deletedAccount.providerID,
                accountID: deletedAccount.accountID
            ).first?.slot.keychainReference
        )
        let retainedReference = try XCTUnwrap(
            model.accountCredentialStore.loadCredentialContexts(
                providerID: retainedAccount.providerID,
                accountID: retainedAccount.accountID
            ).first?.slot.keychainReference
        )
        let occurredAt = Date(timeIntervalSince1970: 60_000)
        try seedRefreshMetadata(
            model: model,
            account: deletedAccount,
            occurredAt: occurredAt
        )
        try seedRefreshMetadata(
            model: model,
            account: retainedAccount,
            occurredAt: occurredAt
        )

        model.deleteAccount(
            providerID: deletedAccount.providerID,
            accountID: deletedAccount.accountID
        )

        XCTAssertEqual(model.providerAccounts, [retainedAccount])
        let persisted = DatabaseProviderConfigurationStore(
            database: try AppDatabase(directory: directory)
        ).load(knownProviderIDs: ["minimax"])
        XCTAssertEqual(persisted.accounts, [retainedAccount])
        XCTAssertTrue(
            try model.accountCredentialStore.loadContexts(
                providerID: deletedAccount.providerID,
                accountID: deletedAccount.accountID
            ).isEmpty
        )
        XCTAssertTrue(
            try model.accountCredentialStore.loadCredentialContexts(
                providerID: deletedAccount.providerID,
                accountID: deletedAccount.accountID
            ).isEmpty
        )
        XCTAssertFalse(keychain.containsCredential(reference: deletedReference))
        XCTAssertTrue(keychain.containsCredential(reference: retainedReference))
        XCTAssertTrue(
            model.diagnosticStore.loadRefreshStates().filter {
                $0.providerID == deletedAccount.providerID
                    && $0.accountID == deletedAccount.accountID
            }.isEmpty
        )
        XCTAssertTrue(
            model.diagnosticStore.load().filter {
                $0.providerID == deletedAccount.providerID
                    && $0.accountID == deletedAccount.accountID
            }.isEmpty
        )
        XCTAssertTrue(
            try model.accountCredentialStore.loadRefreshStates(
                providerID: deletedAccount.providerID,
                accountID: deletedAccount.accountID
            ).isEmpty
        )
        XCTAssertTrue(
            try model.accountCredentialStore.loadDiagnostics(
                providerID: deletedAccount.providerID,
                accountID: deletedAccount.accountID
            ).isEmpty
        )
        XCTAssertEqual(
            model.diagnosticStore.loadRefreshStates().filter {
                $0.providerID == retainedAccount.providerID
                    && $0.accountID == retainedAccount.accountID
            }.count,
            1
        )
        XCTAssertEqual(
            model.diagnosticStore.load().filter {
                $0.providerID == retainedAccount.providerID
                    && $0.accountID == retainedAccount.accountID
            }.count,
            1
        )
        XCTAssertEqual(
            try model.accountCredentialStore.loadRefreshStates(
                providerID: retainedAccount.providerID,
                accountID: retainedAccount.accountID
            ).count,
            1
        )
        XCTAssertEqual(
            try model.accountCredentialStore.loadDiagnostics(
                providerID: retainedAccount.providerID,
                accountID: retainedAccount.accountID
            ).count,
            1
        )
        XCTAssertEqual(
            try model.accountCredentialStore.loadCredentialContexts(
                providerID: retainedAccount.providerID,
                accountID: retainedAccount.accountID
            ).map(\.slot.keychainReference),
            [retainedReference]
        )
    }

    func testMiniMaxDeletionKeychainFailureKeepsRecoverableAccountData() throws {
        let directory = temporaryDirectory()
        let keychain = MiniMaxAppIntegrationKeychain()
        let model = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            miniMaxAPIClient: InjectedMiniMaxAPIClient(),
            credentialKeychainService: keychain
        )
        let failedAccount = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "Retry Me")
        )
        let retainedAccount = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "Keep Me")
        )
        try configureCredential(model: model, account: failedAccount)
        try configureCredential(model: model, account: retainedAccount)
        let failedReference = try XCTUnwrap(
            model.accountCredentialStore.loadCredentialContexts(
                providerID: failedAccount.providerID,
                accountID: failedAccount.accountID
            ).first?.slot.keychainReference
        )
        let retainedReference = try XCTUnwrap(
            model.accountCredentialStore.loadCredentialContexts(
                providerID: retainedAccount.providerID,
                accountID: retainedAccount.accountID
            ).first?.slot.keychainReference
        )
        let occurredAt = Date(timeIntervalSince1970: 70_000)
        try seedRefreshMetadata(
            model: model,
            account: failedAccount,
            occurredAt: occurredAt
        )
        try seedRefreshMetadata(
            model: model,
            account: retainedAccount,
            occurredAt: occurredAt
        )
        keychain.failDeletion(for: failedReference)

        model.deleteAccount(
            providerID: failedAccount.providerID,
            accountID: failedAccount.accountID
        )

        XCTAssertEqual(model.providerAccounts, [failedAccount, retainedAccount])
        let persisted = DatabaseProviderConfigurationStore(
            database: try AppDatabase(directory: directory)
        ).load(knownProviderIDs: ["minimax"])
        XCTAssertEqual(persisted.accounts, [failedAccount, retainedAccount])
        let failedContexts = try model.accountCredentialStore.loadCredentialContexts(
            providerID: failedAccount.providerID,
            accountID: failedAccount.accountID
        )
        XCTAssertEqual(failedContexts.map(\.slot.keychainReference), [failedReference])
        XCTAssertEqual(
            failedContexts.map(\.slot.lifecycleState),
            [.pendingDeletion]
        )
        XCTAssertTrue(keychain.containsCredential(reference: failedReference))
        XCTAssertTrue(keychain.containsCredential(reference: retainedReference))
        XCTAssertEqual(
            try model.accountCredentialStore.loadRefreshStates(
                providerID: failedAccount.providerID,
                accountID: failedAccount.accountID
            ).count,
            1
        )
        XCTAssertEqual(
            try model.accountCredentialStore.loadDiagnostics(
                providerID: failedAccount.providerID,
                accountID: failedAccount.accountID
            ).count,
            1
        )
        XCTAssertEqual(
            model.diagnosticStore.loadRefreshStates().filter {
                $0.providerID == failedAccount.providerID
                    && $0.accountID == failedAccount.accountID
            }.count,
            1
        )
        XCTAssertEqual(
            model.diagnosticStore.load().filter {
                $0.providerID == failedAccount.providerID
                    && $0.accountID == failedAccount.accountID
            }.count,
            1
        )
        XCTAssertEqual(
            try model.accountCredentialStore.loadCredentialContexts(
                providerID: retainedAccount.providerID,
                accountID: retainedAccount.accountID
            ).map(\.slot.keychainReference),
            [retainedReference]
        )
        XCTAssertEqual(
            try model.accountCredentialStore.loadRefreshStates(
                providerID: retainedAccount.providerID,
                accountID: retainedAccount.accountID
            ).count,
            1
        )
        XCTAssertEqual(
            try model.accountCredentialStore.loadDiagnostics(
                providerID: retainedAccount.providerID,
                accountID: retainedAccount.accountID
            ).count,
            1
        )
        XCTAssertEqual(
            model.diagnosticStore.loadRefreshStates().filter {
                $0.providerID == retainedAccount.providerID
                    && $0.accountID == retainedAccount.accountID
            }.count,
            1
        )
        XCTAssertEqual(
            model.diagnosticStore.load().filter {
                $0.providerID == retainedAccount.providerID
                    && $0.accountID == retainedAccount.accountID
            }.count,
            1
        )
    }

    @discardableResult
    private func configureCredential(
        model: AppModel,
        account: ProviderAccount
    ) throws -> ProviderCredentialContext {
        try model.createMiniMaxSubscriptionKey(
            for: account,
            credentialValue: MiniMaxAppIntegrationKeychain.secretMarker
        )
    }

    private func seedRefreshMetadata(
        model: AppModel,
        account: ProviderAccount,
        occurredAt: Date
    ) throws {
        try model.diagnosticStore.recordRefreshFailure(
            providerID: account.providerID,
            accountID: account.accountID,
            occurredAt: occurredAt
        )
        try model.diagnosticStore.replaceRefreshDiagnostics(
            providerID: account.providerID,
            accountID: account.accountID,
            occurredAt: occurredAt,
            messages: ["MiniMax refresh diagnostic."]
        )
        try model.accountCredentialStore.recordRefreshFailure(
            providerID: account.providerID,
            accountID: account.accountID,
            slotID: AppModel.miniMaxSubscriptionSlotID,
            code: .transientFailure,
            occurredAt: occurredAt
        )
    }

    private func assertStorage(
        at directory: URL,
        excludes markers: [String]
    ) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        for url in urls where
            try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            let data = try Data(contentsOf: url)
            for marker in markers {
                XCTAssertNil(
                    data.range(of: Data(marker.utf8)),
                    "Persisted forbidden marker in \(url.lastPathComponent)."
                )
            }
        }
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "MiniMaxAppIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private actor InjectedMiniMaxAPIClient: MiniMaxAPIClient {
    static let rawMarker = "raw-response-marker"

    private(set) var callCount = 0
    private var contextID = "unconfigured-context"
    private var failures: [MiniMaxAPIClientError] = []

    func useContextID(_ contextID: String) {
        self.contextID = contextID
    }

    func enqueueFailure(_ error: MiniMaxAPIClientError) {
        failures.append(error)
    }

    func fetchTokenPlanCapacity(
        credential: MiniMaxSubscriptionKey
    ) async throws -> MiniMaxCapacityResult {
        callCount += 1
        if !failures.isEmpty {
            throw failures.removeFirst()
        }
        let observedAt = Date(timeIntervalSince1970: 50_000)
        return MiniMaxCapacityResult(
            observedAt: observedAt,
            metrics: [
                makeMetric(
                    id: "quota-category-a.current",
                    contextID: contextID,
                    observedAt: observedAt,
                    consumed: 4,
                    windowKind: .rolling,
                    durationSeconds: 18_000
                ),
                makeMetric(
                    id: "quota-category-a.weekly",
                    contextID: contextID,
                    observedAt: observedAt,
                    consumed: 8,
                    windowKind: .fixed,
                    durationSeconds: 604_800
                ),
                makeMetric(
                    id: "quota-category-b.current",
                    contextID: contextID,
                    observedAt: observedAt,
                    consumed: 12,
                    windowKind: .rolling,
                    durationSeconds: 18_000
                ),
                makeMetric(
                    id: "quota-category-b.weekly",
                    contextID: contextID,
                    observedAt: observedAt,
                    consumed: 16,
                    windowKind: .fixed,
                    durationSeconds: 604_800
                ),
            ],
            diagnostics: []
        )
    }

    private func makeMetric(
        id: String,
        contextID: String,
        observedAt: Date,
        consumed: Decimal,
        windowKind: CapacityWindowKind,
        durationSeconds: UInt
    ) -> CapacityMetric {
        CapacityMetric(
            metricID: id,
            accountContextID: contextID,
            sourceID: MiniMaxProviderContract.sourceID,
            capability: "quota-windows",
            displayName: "unrecognized-category-marker \(Self.rawMarker)",
            availability: .known,
            unit: CapacityUnit(kind: .percent),
            values: CapacityValues(
                consumed: CapacityValue(value: consumed, origin: .derived),
                remaining: CapacityValue(value: 100 - consumed, origin: .reported),
                limit: CapacityValue(value: 100, origin: .reported)
            ),
            window: CapacityWindow(
                kind: windowKind,
                durationSeconds: durationSeconds,
                startsAt: observedAt,
                endsAt: observedAt.addingTimeInterval(
                    TimeInterval(durationSeconds)
                ),
                nextTransition: CapacityTransition(
                    kind: .reset,
                    at: observedAt.addingTimeInterval(
                        TimeInterval(durationSeconds)
                    )
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
    }
}

private actor BarrierMiniMaxAPIClient: MiniMaxAPIClient {
    private var contextIDs: [String] = []
    private var shouldBlockNextRequest = false
    private var requestIsBlocked = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0

    func useContextIDs(_ contextIDs: [String]) {
        self.contextIDs = contextIDs
    }

    func blockNextRequest() {
        shouldBlockNextRequest = true
    }

    func waitUntilRequestIsBlocked() async {
        if requestIsBlocked {
            return
        }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func releaseBlockedRequest() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func fetchTokenPlanCapacity(
        credential: MiniMaxSubscriptionKey
    ) async throws -> MiniMaxCapacityResult {
        guard contextIDs.indices.contains(callCount) else {
            throw MiniMaxAPIClientError.decodingFailure
        }
        let contextID = contextIDs[callCount]
        callCount += 1

        if shouldBlockNextRequest {
            shouldBlockNextRequest = false
            requestIsBlocked = true
            let waiters = blockedWaiters
            blockedWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
            requestIsBlocked = false
        }

        let observedAt = Date(timeIntervalSince1970: 80_000)
        return MiniMaxCapacityResult(
            observedAt: observedAt,
            metrics: [
                CapacityMetric(
                    metricID: "quota-category-a.current",
                    accountContextID: contextID,
                    sourceID: MiniMaxProviderContract.sourceID,
                    capability: "quota-windows",
                    displayName: "Local test capacity",
                    availability: .known,
                    unit: CapacityUnit(kind: .percent),
                    values: CapacityValues(
                        consumed: CapacityValue(value: 1, origin: .derived),
                        remaining: CapacityValue(value: 99, origin: .reported),
                        limit: CapacityValue(value: 100, origin: .reported)
                    ),
                    window: CapacityWindow(
                        kind: .rolling,
                        durationSeconds: 18_000,
                        startsAt: observedAt,
                        endsAt: observedAt.addingTimeInterval(18_000)
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
            diagnostics: []
        )
    }
}

private final class MiniMaxAppIntegrationKeychain:
    KeychainService,
    @unchecked Sendable
{
    static let secretMarker = "integration-secret-marker"

    private let lock = NSLock()
    private var values: [String: CredentialSecret] = [:]
    private var deletionFailures: Set<String> = []

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
        guard let credential = values[reference] else {
            throw KeychainServiceError.credentialNotFound
        }
        return credential
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
        guard !deletionFailures.contains(reference) else {
            throw KeychainServiceError.accessDenied
        }
        values.removeValue(forKey: reference)
    }

    func containsCredential(reference: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return values[reference] != nil
    }

    var credentialCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return values.count
    }

    func matchesCredential(reference: String, value: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let credential = values[reference] else {
            throw KeychainServiceError.credentialNotFound
        }
        return try credential.withUTF8String { $0 == value }
    }

    func failDeletion(for reference: String) {
        lock.lock()
        defer { lock.unlock() }
        deletionFailures.insert(reference)
    }

    func allowDeletion(for reference: String) {
        lock.lock()
        defer { lock.unlock() }
        deletionFailures.remove(reference)
    }
}
#endif
