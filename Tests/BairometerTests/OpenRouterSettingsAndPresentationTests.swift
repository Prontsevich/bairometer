#if DEBUG
import BairometerCore
import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import Bairometer

@MainActor
final class OpenRouterSettingsAndPresentationTests: XCTestCase {
    func testNativeMenuActionBoundaryPreservesEnabledRoleAndInvocation() {
        var invoked: [String] = []
        let actions = [
            NativeMenuAction(
                id: "enabled",
                title: "Enabled action",
                systemImage: "key",
                isEnabled: true
            ) {
                invoked.append("enabled")
            },
            .separator(id: "separator"),
            NativeMenuAction(
                id: "remove",
                title: "Remove",
                systemImage: "trash",
                isEnabled: false,
                role: .destructive
            ) {
                invoked.append("remove")
            },
        ]

        XCTAssertEqual(actions.map(\.id), ["enabled", "separator", "remove"])
        XCTAssertEqual(actions[0].title, "Enabled action")
        XCTAssertTrue(actions[0].isEnabled)
        XCTAssertEqual(actions[0].role, .standard)
        XCTAssertNil(actions[1].title)
        XCTAssertNil(actions[1].action)
        XCTAssertFalse(actions[2].isEnabled)
        XCTAssertEqual(actions[2].role, .destructive)

        actions[0].action?()
        XCTAssertEqual(invoked, ["enabled"])
    }

    func testNativeMenuPresentationRetainsVisibleTargetsAcrossCoordinatorUpdate() {
        let coordinator = NativeMenuCoordinator()
        let anchor = NSView()
        var oldInvocationCount = 0
        var updatedInvocationCount = 0
        weak var oldTarget: MenuActionTarget?
        weak var updatedTarget: MenuActionTarget?
        weak var oldPresentation: NativeMenuPresentation?
        weak var updatedPresentation: NativeMenuPresentation?
        var oldVisibleItem: NSMenuItem?
        var updatedVisibleItem: NSMenuItem?

        coordinator.update(
            actions: [
                NativeMenuAction(
                    id: "action",
                    title: "Original",
                    isEnabled: true
                ) {
                    oldInvocationCount += 1
                },
            ]
        )

        coordinator.present(
            from: anchor,
            using: NativeMenuPopupRunner { presentation in
                oldPresentation = presentation
                let menu = presentation.menu
                let visibleItem = menu.items[0]
                oldVisibleItem = visibleItem
                oldTarget = visibleItem.target as? MenuActionTarget
                XCTAssertNotNil(oldTarget)
                XCTAssertEqual(visibleItem.title, "Original")
                XCTAssertTrue(visibleItem.isEnabled)

                coordinator.update(
                    actions: [
                        NativeMenuAction(
                            id: "action",
                            title: "Updated",
                            isEnabled: false,
                            role: .destructive
                        ) {
                            updatedInvocationCount += 1
                        },
                    ]
                )

                XCTAssertNotNil(visibleItem.target)
                (visibleItem.target as? MenuActionTarget)?.invoke(visibleItem)
                XCTAssertEqual(oldInvocationCount, 1)
                XCTAssertEqual(updatedInvocationCount, 0)
            }
        )

        XCTAssertNil(oldPresentation)
        XCTAssertNil(oldVisibleItem?.target)
        XCTAssertEqual(oldInvocationCount, 1)

        coordinator.present(
            from: anchor,
            using: NativeMenuPopupRunner { presentation in
                updatedPresentation = presentation
                let menu = presentation.menu
                let visibleItem = menu.items[0]
                updatedVisibleItem = visibleItem
                updatedTarget = visibleItem.target as? MenuActionTarget
                XCTAssertNotNil(updatedTarget)
                XCTAssertEqual(visibleItem.title, "Updated")
                XCTAssertFalse(visibleItem.isEnabled)
                XCTAssertEqual(visibleItem.attributedTitle?.string, "Updated")
                (visibleItem.target as? MenuActionTarget)?.invoke(visibleItem)
            }
        )

        XCTAssertNil(updatedPresentation)
        XCTAssertNil(updatedVisibleItem?.target)
        XCTAssertEqual(oldInvocationCount, 1)
        XCTAssertEqual(updatedInvocationCount, 1)
    }

    func testNativeMenuCancelledPresentationReleasesSnapshotAndAllowsNextClick() {
        let coordinator = NativeMenuCoordinator()
        let anchor = NSView()
        var invocationCount = 0
        weak var cancelledTarget: MenuActionTarget?
        weak var nextTarget: MenuActionTarget?
        weak var cancelledPresentation: NativeMenuPresentation?
        weak var nextPresentation: NativeMenuPresentation?
        var cancelledVisibleItem: NSMenuItem?
        var nextVisibleItem: NSMenuItem?

        coordinator.update(
            actions: [
                NativeMenuAction(id: "action", title: "Cancel") {
                    invocationCount += 1
                },
            ]
        )
        coordinator.present(
            from: anchor,
            using: NativeMenuPopupRunner { presentation in
                cancelledPresentation = presentation
                let menu = presentation.menu
                cancelledVisibleItem = menu.items[0]
                cancelledTarget = menu.items[0].target as? MenuActionTarget
                XCTAssertNotNil(cancelledTarget)
            }
        )

        XCTAssertNil(cancelledPresentation)
        XCTAssertNil(cancelledVisibleItem?.target)
        XCTAssertEqual(invocationCount, 0)

        coordinator.update(
            actions: [
                NativeMenuAction(id: "action", title: "Next") {
                    invocationCount += 1
                },
            ]
        )
        coordinator.present(
            from: anchor,
            using: NativeMenuPopupRunner { presentation in
                nextPresentation = presentation
                let menu = presentation.menu
                let visibleItem = menu.items[0]
                nextVisibleItem = visibleItem
                nextTarget = visibleItem.target as? MenuActionTarget
                XCTAssertNotNil(nextTarget)
                XCTAssertEqual(visibleItem.title, "Next")
                (visibleItem.target as? MenuActionTarget)?.invoke(visibleItem)
            }
        )

        XCTAssertNil(nextPresentation)
        XCTAssertNil(nextVisibleItem?.target)
        XCTAssertEqual(invocationCount, 1)
    }

    func testKeyAvailableCapacityProjectionClampsAndRejectsZeroTotalBar() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let account = ProviderAccount(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "account",
            displayName: "OpenRouter",
            isEnabled: true,
            sourceMode: .openRouterAPI
        )
        let root = AccountContext(
            contextID: "root",
            kind: .personal,
            regionID: "global"
        )
        let ordinary = AccountContext(
            contextID: "ordinary",
            kind: .credential,
            displayName: "Key",
            regionID: "global",
            parentContextID: root.contextID
        )

        func capacity(
            available: Decimal,
            total: Decimal
        ) -> OpenRouterKeyCapacityPresentation? {
            let snapshot = CapacitySnapshot(
                providerID: account.providerID,
                surfaceID: OpenRouterProviderContract.surfaceID,
                savedAccountID: account.accountID,
                accountContexts: [root, ordinary],
                observedAt: now,
                metrics: [
                    metric(
                        id: "key-credit-limit",
                        contextID: ordinary.contextID,
                        values: CapacityValues(
                            remaining: CapacityValue(
                                value: available,
                                origin: .reported
                            ),
                            limit: CapacityValue(
                                value: total,
                                origin: .reported
                            )
                        ),
                        observedAt: now
                    ),
                ]
            )
            return OpenRouterCapacityPresentation(
                account: account,
                snapshot: snapshot,
                credentialContexts: [
                    credential(context: ordinary, role: .ordinary),
                ],
                refreshStates: [],
                diagnostics: [],
                now: now,
                locale: Locale(identifier: "en_US")
            )
            .credentials.first?.dashboardMetric?.keyCapacity
        }

        XCTAssertNil(capacity(available: 0, total: 0)?.availableFraction)
        XCTAssertEqual(
            capacity(available: -1, total: 10)?.availableFraction,
            0
        )
        XCTAssertEqual(
            capacity(available: 12, total: 10)?.availableFraction,
            1
        )
    }

    func testSettingsCRUDPreservesAccountsAndRecoversMissingKeychainItem() throws {
        let directory = temporaryDirectory()
        let keychain = SettingsTestKeychain()
        let model = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            credentialKeychainService: keychain
        )
        let personal = try XCTUnwrap(
            model.addAccount(
                providerID: OpenRouterProviderContract.providerID,
                displayName: "Personal"
            )
        )
        let work = try XCTUnwrap(
            model.addAccount(
                providerID: OpenRouterProviderContract.providerID,
                displayName: "Work"
            )
        )

        XCTAssertEqual(
            try model.accountCredentialStore.loadContexts(
                providerID: personal.providerID,
                accountID: personal.accountID
            ).filter { $0.parentContextID == nil }.count,
            1
        )

        let personalPrimary = try model.createOpenRouterOrdinaryCredential(
            for: personal,
            displayName: "Primary",
            credentialValue: "synthetic-personal-primary"
        )
        let personalBackup = try model.createOpenRouterOrdinaryCredential(
            for: personal,
            displayName: "Backup",
            credentialValue: "synthetic-personal-backup"
        )
        _ = try model.createOpenRouterOrdinaryCredential(
            for: work,
            displayName: "Primary",
            credentialValue: "synthetic-work-primary"
        )
        _ = try model.createOpenRouterManagementCredential(
            for: personal,
            credentialValue: "synthetic-personal-management"
        )

        XCTAssertEqual(keychain.credentialCount, 4)
        XCTAssertThrowsError(
            try model.createOpenRouterOrdinaryCredential(
                for: personal,
                displayName: "primary",
                credentialValue: "synthetic-duplicate"
            )
        ) {
            XCTAssertEqual($0 as? OpenRouterSettingsError, .duplicateName)
        }
        XCTAssertThrowsError(
            try model.createOpenRouterManagementCredential(
                for: personal,
                credentialValue: "synthetic-duplicate-management"
            )
        ) {
            XCTAssertEqual(
                $0 as? OpenRouterSettingsError,
                .managementCredentialExists
            )
        }

        try model.renameOpenRouterOrdinaryCredential(
            for: personal,
            contextID: personalBackup.context.contextID,
            displayName: "Secondary"
        )
        XCTAssertEqual(
            model.openRouterCredentialContexts(for: personal)
                .first(where: {
                    $0.context.contextID == personalBackup.context.contextID
                })?.context.displayName,
            "Secondary"
        )

        try model.setOpenRouterCredentialEnabled(
            false,
            for: personal,
            slotID: personalPrimary.slot.slotID
        )
        XCTAssertFalse(
            try XCTUnwrap(
                model.openRouterCredentialContexts(for: personal)
                    .first(where: {
                        $0.slot.slotID == personalPrimary.slot.slotID
                    })
            ).slot.isEnabled
        )
        try model.setOpenRouterCredentialEnabled(
            true,
            for: personal,
            slotID: personalPrimary.slot.slotID
        )

        keychain.drop(reference: personalPrimary.slot.keychainReference)
        try model.replaceOpenRouterCredential(
            for: personal,
            slotID: personalPrimary.slot.slotID,
            credentialValue: "synthetic-personal-recovered"
        )
        let recovered = try XCTUnwrap(
            model.openRouterCredentialContexts(for: personal)
                .first(where: {
                    $0.slot.slotID == personalPrimary.slot.slotID
                })
        )
        XCTAssertTrue(keychain.contains(reference: recovered.slot.keychainReference))
        XCTAssertEqual(recovered.slot.credentialRevision, 2)

        try model.deleteOpenRouterCredential(
            for: personal,
            slotID: personalBackup.slot.slotID
        )
        XCTAssertFalse(
            model.openRouterCredentialContexts(for: personal)
                .contains(where: {
                    $0.slot.slotID == personalBackup.slot.slotID
                })
        )
        XCTAssertEqual(keychain.credentialCount, 3)

        let reloaded = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            credentialKeychainService: keychain
        )
        XCTAssertEqual(
            Set(
                reloaded.providerAccounts
                    .filter {
                        $0.providerID == OpenRouterProviderContract.providerID
                    }
                    .map(\.displayName)
            ),
            ["Personal", "Work"]
        )
        XCTAssertEqual(
            reloaded.openRouterCredentialContexts(for: personal)
                .filter { $0.slot.role == .ordinary }
                .map(\.context.displayName),
            ["Primary"]
        )

        reloaded.deleteAccount(
            providerID: personal.providerID,
            accountID: personal.accountID
        )
        XCTAssertFalse(reloaded.providerAccounts.contains { $0.id == personal.id })
        XCTAssertEqual(keychain.credentialCount, 1)
    }

    func testManagementDisableImmediatelyMakesSharedCreditsUnavailable() async throws {
        let directory = temporaryDirectory()
        let keychain = SettingsTestKeychain()
        let model = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            refreshCoordinator: ProviderRefreshCoordinator(
                retryPolicy: ProviderRetryPolicy(maxAttempts: 1, initialDelay: 0)
            ),
            openRouterAPIClient: SyntheticOpenRouterVerificationClient(
                failingOrdinarySlotID: "never"
            ),
            credentialKeychainService: keychain
        )
        let account = try XCTUnwrap(
            model.addAccount(
                providerID: OpenRouterProviderContract.providerID,
                displayName: "Capacity"
            )
        )
        _ = try model.createOpenRouterOrdinaryCredential(
            for: account,
            displayName: "Primary",
            credentialValue: "synthetic-primary"
        )
        let management = try model.createOpenRouterManagementCredential(
            for: account,
            credentialValue: "synthetic-management"
        )

        model.refreshAccount(
            providerID: account.providerID,
            accountID: account.accountID
        )
        await model.waitForRefreshCompletionForTesting()
        XCTAssertEqual(
            model.openRouterCapacityPresentation(
                for: account,
                locale: Locale(identifier: "en_US")
            )?.sharedCredits.state,
            .current
        )

        try model.setOpenRouterCredentialEnabled(
            false,
            for: account,
            slotID: management.slot.slotID
        )

        let presentation = try XCTUnwrap(
            model.openRouterCapacityPresentation(
                for: account,
                locale: Locale(identifier: "en_US")
            )
        )
        XCTAssertEqual(presentation.sharedCredits.state, .unavailable)
        XCTAssertEqual(presentation.sharedCredits.valueText, "Unavailable")
        XCTAssertEqual(presentation.credentials.count, 1)
        XCTAssertTrue(
            presentation.credentials[0].metrics.contains {
                $0.displayName == "Total usage"
            }
        )
    }

    func testGlobalRefreshRejectsLateFailureAfterCredentialReplaceOrDisable() async throws {
        for disablesCredential in [false, true] {
            let directory = temporaryDirectory()
            let keychain = SettingsTestKeychain()
            let client = BarrierOpenRouterClient()
            let model = AppModel(
                storageDirectory: directory,
                userDefaults: isolatedDefaults(),
                refreshCoordinator: ProviderRefreshCoordinator(
                    retryPolicy: ProviderRetryPolicy(
                        maxAttempts: 1,
                        initialDelay: 0
                    )
                ),
                openRouterAPIClient: client,
                credentialKeychainService: keychain
            )
            let account = try XCTUnwrap(
                model.addAccount(
                    providerID: OpenRouterProviderContract.providerID,
                    displayName: disablesCredential ? "Disable" : "Replace"
                )
            )
            let credential = try model.createOpenRouterOrdinaryCredential(
                for: account,
                displayName: "Primary",
                credentialValue: "synthetic-initial"
            )

            model.refreshAccount(
                providerID: account.providerID,
                accountID: account.accountID
            )
            await model.waitForRefreshCompletionForTesting()
            let successfulSnapshot = try XCTUnwrap(model.snapshot(for: account))
            let successfulAt = try XCTUnwrap(
                model.sourceRefreshStates[account.id]?.lastSuccessfulRefreshAt
            )
            XCTAssertNil(
                model.sourceRefreshStates[account.id]?.lastFailedRefreshAt
            )
            let persistedBeforeMutation = AppModel(
                storageDirectory: directory,
                userDefaults: isolatedDefaults(),
                refreshCoordinator: ProviderRefreshCoordinator(
                    retryPolicy: ProviderRetryPolicy(
                        maxAttempts: 1,
                        initialDelay: 0
                    )
                ),
                openRouterAPIClient: client,
                credentialKeychainService: keychain
            )
            let persistedSnapshotBeforeMutation = try XCTUnwrap(
                persistedBeforeMutation.snapshot(for: account)
            )
            let persistedSuccessBeforeMutation = try XCTUnwrap(
                persistedBeforeMutation.sourceRefreshStates[account.id]?
                    .lastSuccessfulRefreshAt
            )

            await client.blockNextOrdinaryRequest()
            model.refresh()
            await client.waitUntilOrdinaryRequestIsBlocked()
            do {
                if disablesCredential {
                    try model.setOpenRouterCredentialEnabled(
                        false,
                        for: account,
                        slotID: credential.slot.slotID
                    )
                } else {
                    try model.replaceOpenRouterCredential(
                        for: account,
                        slotID: credential.slot.slotID,
                        credentialValue: "synthetic-replacement"
                    )
                }
            } catch {
                await client.releaseBlockedOrdinaryRequest()
                throw error
            }
            await client.releaseBlockedOrdinaryRequest()
            await model.waitForRefreshCompletionForTesting()

            XCTAssertEqual(model.snapshot(for: account), successfulSnapshot)
            XCTAssertNil(model.accountRefreshIssues[account.id])
            XCTAssertNil(model.providerRefreshStatuses[account.id])
            XCTAssertEqual(
                model.sourceRefreshStates[account.id]?.lastSuccessfulRefreshAt,
                successfulAt
            )
            XCTAssertNil(
                model.sourceRefreshStates[account.id]?.lastFailedRefreshAt
            )
            XCTAssertTrue(
                model.openRouterCredentialDiagnostics(for: account).isEmpty
            )

            let reloaded = AppModel(
                storageDirectory: directory,
                userDefaults: isolatedDefaults(),
                refreshCoordinator: ProviderRefreshCoordinator(
                    retryPolicy: ProviderRetryPolicy(
                        maxAttempts: 1,
                        initialDelay: 0
                    )
                ),
                openRouterAPIClient: client,
                credentialKeychainService: keychain
            )
            XCTAssertEqual(
                reloaded.snapshot(for: account),
                persistedSnapshotBeforeMutation
            )
            XCTAssertNil(reloaded.accountRefreshIssues[account.id])
            XCTAssertEqual(
                reloaded.sourceRefreshStates[account.id]?.lastSuccessfulRefreshAt,
                persistedSuccessBeforeMutation
            )
            XCTAssertNil(
                reloaded.sourceRefreshStates[account.id]?.lastFailedRefreshAt
            )
            XCTAssertTrue(
                reloaded.openRouterCredentialDiagnostics(for: account).isEmpty
            )
        }
    }

    func testNativePresentationKeepsHierarchyUSDResetAndSourceStatesDistinct() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let account = ProviderAccount(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "account",
            displayName: "OpenRouter",
            isEnabled: true,
            sourceMode: .openRouterAPI
        )
        let root = AccountContext(
            contextID: "root",
            kind: .personal,
            regionID: "global"
        )
        let primary = AccountContext(
            contextID: "primary",
            kind: .credential,
            displayName: "Primary",
            regionID: "global",
            parentContextID: root.contextID
        )
        let backup = AccountContext(
            contextID: "backup",
            kind: .credential,
            displayName: "Backup",
            regionID: "global",
            parentContextID: root.contextID
        )
        let snapshot = CapacitySnapshot(
            providerID: account.providerID,
            surfaceID: OpenRouterProviderContract.surfaceID,
            savedAccountID: account.accountID,
            accountContexts: [root, primary, backup],
            observedAt: now,
            metrics: [
                metric(
                    id: "account-credits",
                    contextID: root.contextID,
                    sourceID: OpenRouterProviderContract.managementSourceID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 12, origin: .reported),
                        remaining: CapacityValue(value: 88, origin: .derived),
                        limit: CapacityValue(value: 100, origin: .reported)
                    ),
                    observedAt: now
                ),
                metric(
                    id: "key-credit-limit",
                    contextID: primary.contextID,
                    values: CapacityValues(
                        remaining: CapacityValue(value: 8.75, origin: .reported),
                        limit: CapacityValue(value: 10, origin: .reported)
                    ),
                    observedAt: now,
                    window: CapacityWindow(
                        kind: .fixed,
                        nextTransition: CapacityTransition(
                            kind: .reset,
                            at: now.addingTimeInterval(3_600)
                        )
                    )
                ),
                metric(
                    id: "key-total-usage",
                    contextID: primary.contextID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 1.25, origin: .reported)
                    ),
                    observedAt: now
                ),
                metric(
                    id: "key-weekly-usage",
                    contextID: primary.contextID,
                    availability: .unknown,
                    values: nil,
                    observedAt: now
                ),
                metric(
                    id: "key-monthly-byok-usage",
                    contextID: primary.contextID,
                    availability: .unlimited,
                    values: nil,
                    observedAt: now
                ),
                metric(
                    id: "key-total-usage",
                    contextID: backup.contextID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 2, origin: .reported)
                    ),
                    observedAt: now.addingTimeInterval(-1_000)
                )
            ]
        )
        let presentation = OpenRouterCapacityPresentation(
            account: account,
            snapshot: snapshot,
            credentialContexts: [
                credential(context: primary, role: .ordinary),
                credential(context: backup, role: .ordinary),
                credential(context: root, role: .management)
            ],
            refreshStates: [],
            diagnostics: [
                CredentialContextDiagnostic(
                    providerID: account.providerID,
                    accountID: account.accountID,
                    slotID: backup.contextID,
                    code: .authentication,
                    occurredAt: now
                )
            ],
            now: now,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(presentation.state, .partial)
        XCTAssertEqual(presentation.sharedCredits.displayName, "Account credits")
        XCTAssertEqual(
            presentation.sharedCredits.dashboardValueText,
            "$88"
        )
        XCTAssertTrue(
            presentation.sharedCredits.valueText.contains("$88 left")
        )
        XCTAssertFalse(
            presentation.sharedCredits.valueText.contains("total")
        )
        XCTAssertEqual(
            presentation.sharedCredits.accountCredits,
            OpenRouterAccountCreditsPresentation(
                leftText: "$88",
                usedText: "$12",
                accessibilityValue: "Left, $88, Used, $12"
            )
        )
        XCTAssertFalse(presentation.sharedCredits.valueText.contains("%"))
        XCTAssertEqual(presentation.credentials.map(\.displayName), ["Backup", "Primary"])
        XCTAssertEqual(presentation.credentials[0].state, .partial)
        XCTAssertEqual(
            presentation.credentials[0].statusText,
            "Key authentication failed"
        )
        let primaryPresentation = presentation.credentials[1]
        XCTAssertTrue(
            primaryPresentation.metrics.contains {
                $0.valueText == "$8.75 available of $10"
                    && $0.dashboardValueText == "$8.75"
                    && $0.dashboardAccessibilityValue
                        == "$8.75 available of $10"
                    && $0.keyCapacity?.visualValueText == "$8.75 / $10"
                    && $0.keyCapacity?.availableFraction == 0.875
                    && $0.resetText == "Resets in 1 hour"
            }
        )
        XCTAssertEqual(
            primaryPresentation.dashboardMetric?.metricID,
            "key-credit-limit"
        )
        XCTAssertTrue(
            primaryPresentation.metrics.contains {
                $0.state == .unknown && $0.valueText == "Unknown"
            }
        )
        XCTAssertTrue(
            primaryPresentation.metrics.contains {
                $0.state == .unlimited && $0.valueText == "Unlimited"
            }
        )
        let primaryDetails = primaryPresentation.detailsPresentation
        XCTAssertFalse(primaryDetails.isExpandedByDefault)
        XCTAssertTrue(primaryDetails.collapsedMetrics.isEmpty)
        XCTAssertEqual(
            primaryDetails.expandedMetrics.map(\.metricID),
            primaryPresentation.metrics.map(\.metricID)
        )
        XCTAssertEqual(primaryDetails.summaryValueText, "$8.75")
        XCTAssertEqual(primaryDetails.resetText, "Resets in 1 hour")
        XCTAssertEqual(
            Set(primaryDetails.usageRows.map(\.scopeText)),
            ["Week", "Month", "Total"]
        )
        XCTAssertNotNil(primaryDetails.updateText)
        XCTAssertFalse(primaryDetails.showsPerMetricFreshness)
        XCTAssertEqual(
            Set(primaryDetails.resetGroups.map(\.resetText)),
            ["No reset", "Resets in 1 hour"]
        )
        XCTAssertFalse(
            primaryDetails.expandedSummaryAccessibilityValue.contains(
                "Resets in 1 hour"
            )
        )
        for metric in primaryDetails.expandedMetrics {
            XCTAssertEqual(
                metric.visibleAccessibilityValue(
                    showsReset: false,
                    showsFreshness: false
                ),
                metric.valueText
            )
        }
        let fullMetricProjection = primaryDetails.expandedMetrics[0]
        XCTAssertEqual(
            fullMetricProjection.visibleAccessibilityValue(
                showsReset: true,
                showsFreshness: true
            ),
            fullMetricProjection.accessibilityValue
        )

        let backupDetails = presentation.credentials[0].detailsPresentation
        XCTAssertEqual(
            backupDetails.summaryValueText,
            "Key authentication failed"
        )
        XCTAssertNil(backupDetails.exceptionText)
        XCTAssertTrue(
            backupDetails.collapsedAccessibilityValue.contains(
                "Key authentication failed"
            )
        )

        let russian = OpenRouterCapacityPresentation(
            account: account,
            snapshot: snapshot,
            credentialContexts: [
                credential(context: primary, role: .ordinary)
            ],
            refreshStates: [],
            diagnostics: [],
            now: now,
            locale: Locale(identifier: "ru_RU")
        )
        XCTAssertTrue(
            russian.credentials[0].metrics.contains {
                $0.dashboardValueText == "$8,75"
                    && $0.valueText == "Доступно $8,75 из $10"
            }
        )
    }

    func testResetGroupsKeepKeyLimitSeparateFromMonthlyUsageAtSameTimestamp() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let transition = now.addingTimeInterval(3_600)
        let window = CapacityWindow(
            kind: .fixed,
            durationSeconds: 2_592_000,
            startsAt: now.addingTimeInterval(-2_588_400),
            endsAt: transition,
            nextTransition: CapacityTransition(kind: .reset, at: transition)
        )

        let groups = resetGroups(
            metrics: [
                resetMetric(id: "key-credit-limit", now: now, window: window),
                resetMetric(id: "key-monthly-usage", now: now, window: window),
            ],
            now: now
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(
            groups.map(\.scopeNames),
            [["Limit"], ["Month · Usage"]]
        )
        XCTAssertTrue(groups[0].id.hasPrefix("key-limit:"))
        XCTAssertTrue(groups[1].id.hasPrefix("usage-month:"))
        XCTAssertTrue(groups.allSatisfy { $0.resetText == "Resets in 1 hour" })
    }

    func testResetGroupsMergeExactStandardAndBYOKPeriodWindows() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let transition = now.addingTimeInterval(3_600)
        let window = CapacityWindow(
            kind: .fixed,
            durationSeconds: 2_592_000,
            startsAt: now.addingTimeInterval(-2_588_400),
            endsAt: transition,
            nextTransition: CapacityTransition(kind: .reset, at: transition)
        )

        let forwardGroups = resetGroups(
            metrics: [
                resetMetric(id: "key-monthly-usage", now: now, window: window),
                resetMetric(
                    id: "key-monthly-byok-usage",
                    now: now,
                    window: window
                ),
            ],
            now: now
        )
        let reversedGroups = resetGroups(
            metrics: [
                resetMetric(
                    id: "key-monthly-byok-usage",
                    now: now,
                    window: window
                ),
                resetMetric(id: "key-monthly-usage", now: now, window: window),
            ],
            now: now
        )

        XCTAssertEqual(forwardGroups, reversedGroups)
        XCTAssertEqual(forwardGroups.count, 1)
        XCTAssertEqual(forwardGroups[0].scopeNames, ["Month"])
        XCTAssertEqual(forwardGroups[0].resetText, "Resets in 1 hour")
        XCTAssertTrue(forwardGroups[0].id.hasPrefix("usage-month:"))
    }

    func testResetGroupsKeepLifetimeKeyLimitSeparateFromTotalUsage() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let lifetime = CapacityWindow(kind: .lifetime)

        let groups = resetGroups(
            metrics: [
                resetMetric(
                    id: "key-credit-limit",
                    now: now,
                    window: lifetime
                ),
                resetMetric(
                    id: "key-total-usage",
                    now: now,
                    window: lifetime
                ),
            ],
            now: now
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(
            groups.map(\.scopeNames),
            [["Limit"], ["Total · Usage"]]
        )
        XCTAssertTrue(groups[0].id.hasPrefix("key-limit:"))
        XCTAssertTrue(groups[1].id.hasPrefix("usage-total:"))
        XCTAssertTrue(groups.allSatisfy { $0.resetText == "No reset" })
    }

    func testResetGroupsKeepDistinctSameKindWindowsSeparate() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let transition = now.addingTimeInterval(3_600)
        let usageWindow = CapacityWindow(
            kind: .fixed,
            durationSeconds: 604_800,
            startsAt: now.addingTimeInterval(-601_200),
            endsAt: transition,
            nextTransition: CapacityTransition(kind: .reset, at: transition)
        )
        let byokWindow = CapacityWindow(
            kind: .fixed,
            durationSeconds: 604_801,
            startsAt: now.addingTimeInterval(-601_201),
            endsAt: transition,
            nextTransition: CapacityTransition(kind: .reset, at: transition)
        )

        let usageMetric = resetMetric(
            id: "key-weekly-usage",
            now: now,
            window: usageWindow
        )
        let byokMetric = resetMetric(
            id: "key-weekly-byok-usage",
            now: now,
            window: byokWindow
        )
        let forwardGroups = resetGroups(
            metrics: [
                usageMetric,
                byokMetric,
            ],
            now: now
        )
        let reversedGroups = resetGroups(
            metrics: [byokMetric, usageMetric],
            now: now
        )

        XCTAssertEqual(forwardGroups, reversedGroups)
        XCTAssertEqual(forwardGroups.count, 2)
        XCTAssertEqual(
            forwardGroups.map(\.scopeNames),
            [["Week · Usage"], ["Week · BYOK"]]
        )
        XCTAssertEqual(
            forwardGroups.map(\.id),
            forwardGroups.map(\.id).sorted()
        )
        XCTAssertTrue(forwardGroups.allSatisfy {
            $0.id.hasPrefix("usage-week:")
        })
    }

    func testSharedCreditsRequireActiveEnabledManagementCredential() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let account = ProviderAccount(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "account",
            displayName: "OpenRouter",
            isEnabled: true,
            sourceMode: .openRouterAPI
        )
        let root = AccountContext(
            contextID: "root",
            kind: .personal,
            regionID: "global"
        )
        let snapshot = CapacitySnapshot(
            providerID: account.providerID,
            surfaceID: OpenRouterProviderContract.surfaceID,
            savedAccountID: account.accountID,
            accountContexts: [root],
            observedAt: now,
            metrics: [
                metric(
                    id: "account-credits",
                    contextID: root.contextID,
                    sourceID: OpenRouterProviderContract.managementSourceID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 10, origin: .reported),
                        remaining: CapacityValue(value: 90, origin: .derived),
                        limit: CapacityValue(value: 100, origin: .reported)
                    ),
                    observedAt: now
                )
            ]
        )
        let oldDiagnostic = CredentialContextDiagnostic(
            providerID: account.providerID,
            accountID: account.accountID,
            slotID: root.contextID,
            code: .authentication,
            occurredAt: now
        )
        let invalidManagementVariants: [[ProviderCredentialContext]] = [
            [],
            [
                credential(
                    context: root,
                    role: .management,
                    isEnabled: false
                )
            ],
            [
                credential(
                    context: root,
                    role: .management,
                    lifecycleState: .pendingCreation
                )
            ],
            [
                credential(
                    context: root,
                    role: .management,
                    lifecycleState: .pendingDeletion
                )
            ]
        ]

        for credentials in invalidManagementVariants {
            let presentation = OpenRouterCapacityPresentation(
                account: account,
                snapshot: snapshot,
                credentialContexts: credentials,
                refreshStates: [],
                diagnostics: [oldDiagnostic],
                now: now,
                locale: Locale(identifier: "en_US")
            )

            XCTAssertEqual(presentation.sharedCredits.state, .unavailable)
            XCTAssertEqual(presentation.sharedCredits.valueText, "Unavailable")
            XCTAssertEqual(presentation.state, .unavailable)
            XCTAssertEqual(presentation.statusText, "Unavailable")
        }
    }

    func testHealthyKeyWithoutFiniteLimitUsesNoKeyLimitWithoutTimestamp() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let account = ProviderAccount(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "account",
            displayName: "OpenRouter",
            isEnabled: true,
            sourceMode: .openRouterAPI
        )
        let root = AccountContext(
            contextID: "root",
            kind: .personal,
            regionID: "global"
        )
        let ordinary = AccountContext(
            contextID: "ordinary",
            kind: .credential,
            displayName: "Ordinary",
            regionID: "global",
            parentContextID: root.contextID
        )
        let snapshot = CapacitySnapshot(
            providerID: account.providerID,
            surfaceID: OpenRouterProviderContract.surfaceID,
            savedAccountID: account.accountID,
            accountContexts: [root, ordinary],
            observedAt: now,
            metrics: [
                metric(
                    id: "key-total-usage",
                    contextID: ordinary.contextID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 1, origin: .reported)
                    ),
                    observedAt: now
                )
            ]
        )
        let presentation = OpenRouterCapacityPresentation(
            account: account,
            snapshot: snapshot,
            credentialContexts: [
                credential(context: ordinary, role: .ordinary)
            ],
            refreshStates: [
                CredentialContextRefreshState(
                    providerID: account.providerID,
                    accountID: account.accountID,
                    slotID: ordinary.contextID,
                    lastAttemptAt: now,
                    lastSuccessfulRefreshAt: now,
                    lastFailedRefreshAt: nil
                )
            ],
            diagnostics: [],
            now: now,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertTrue(presentation.credentials[0].statusText.hasPrefix("Updated "))
        XCTAssertEqual(presentation.credentials[0].dashboardValueText, "No key limit")
        XCTAssertEqual(
            presentation.credentials[0].dashboardAccessibilityValue,
            "No key limit"
        )
    }

    func testStaleUnlimitedMetricRemainsUnlimitedButAggregatesAsStale() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let account = ProviderAccount(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "account",
            displayName: "OpenRouter",
            isEnabled: true,
            sourceMode: .openRouterAPI
        )
        let root = AccountContext(
            contextID: "root",
            kind: .personal,
            regionID: "global"
        )
        let ordinary = AccountContext(
            contextID: "ordinary",
            kind: .credential,
            displayName: "Ordinary",
            regionID: "global",
            parentContextID: root.contextID
        )
        let snapshot = CapacitySnapshot(
            providerID: account.providerID,
            surfaceID: OpenRouterProviderContract.surfaceID,
            savedAccountID: account.accountID,
            accountContexts: [root, ordinary],
            observedAt: now,
            metrics: [
                metric(
                    id: "key-monthly-byok-usage",
                    contextID: ordinary.contextID,
                    availability: .unlimited,
                    values: nil,
                    observedAt: now.addingTimeInterval(
                        -TimeInterval(
                            OpenRouterProviderContract.maximumAgeSeconds + 1
                        )
                    )
                )
            ]
        )
        let presentation = OpenRouterCapacityPresentation(
            account: account,
            snapshot: snapshot,
            credentialContexts: [
                credential(context: ordinary, role: .ordinary)
            ],
            refreshStates: [],
            diagnostics: [],
            now: now,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(presentation.credentials[0].metrics[0].valueText, "Unlimited")
        XCTAssertEqual(presentation.credentials[0].metrics[0].state, .stale)
        XCTAssertEqual(presentation.credentials[0].state, .stale)
        XCTAssertEqual(presentation.credentials[0].dashboardValueText, "Stale")
        XCTAssertFalse(
            presentation.credentials[0].dashboardAccessibilityValue
                .contains("Updated")
        )
        XCTAssertEqual(presentation.state, .stale)
        XCTAssertEqual(presentation.statusText, "Stale")
    }

    func testDisabledOnlyCredentialMetricsDoNotAffectAccountState() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let account = ProviderAccount(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "account",
            displayName: "OpenRouter",
            isEnabled: true,
            sourceMode: .openRouterAPI
        )
        let root = AccountContext(
            contextID: "root",
            kind: .personal,
            regionID: "global"
        )
        let ordinary = AccountContext(
            contextID: "ordinary",
            kind: .credential,
            displayName: "Disabled",
            regionID: "global",
            parentContextID: root.contextID
        )
        let metricVariants = [
            metric(
                id: "key-total-usage",
                contextID: ordinary.contextID,
                values: CapacityValues(
                    consumed: CapacityValue(value: 1, origin: .reported)
                ),
                observedAt: now
            ),
            metric(
                id: "key-monthly-byok-usage",
                contextID: ordinary.contextID,
                availability: .unlimited,
                values: nil,
                observedAt: now.addingTimeInterval(
                    -TimeInterval(
                        OpenRouterProviderContract.maximumAgeSeconds + 1
                    )
                )
            )
        ]

        for savedMetric in metricVariants {
            let snapshot = CapacitySnapshot(
                providerID: account.providerID,
                surfaceID: OpenRouterProviderContract.surfaceID,
                savedAccountID: account.accountID,
                accountContexts: [root, ordinary],
                observedAt: now,
                metrics: [savedMetric]
            )
            let presentation = OpenRouterCapacityPresentation(
                account: account,
                snapshot: snapshot,
                credentialContexts: [
                    credential(
                        context: ordinary,
                        role: .ordinary,
                        isEnabled: false
                    )
                ],
                refreshStates: [],
                diagnostics: [],
                now: now,
                locale: Locale(identifier: "en_US")
            )

            XCTAssertEqual(presentation.credentials[0].state, .disabled)
            XCTAssertFalse(presentation.credentials[0].metrics.isEmpty)
            XCTAssertEqual(presentation.state, .unavailable)
            XCTAssertEqual(presentation.statusText, "Unavailable")
        }
    }

    func testDisabledStaleSiblingDoesNotDowngradeActiveCurrentCredential() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let account = ProviderAccount(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "account",
            displayName: "OpenRouter",
            isEnabled: true,
            sourceMode: .openRouterAPI
        )
        let root = AccountContext(
            contextID: "root",
            kind: .personal,
            regionID: "global"
        )
        let active = AccountContext(
            contextID: "active",
            kind: .credential,
            displayName: "Active",
            regionID: "global",
            parentContextID: root.contextID
        )
        let disabled = AccountContext(
            contextID: "disabled",
            kind: .credential,
            displayName: "Disabled",
            regionID: "global",
            parentContextID: root.contextID
        )
        let snapshot = CapacitySnapshot(
            providerID: account.providerID,
            surfaceID: OpenRouterProviderContract.surfaceID,
            savedAccountID: account.accountID,
            accountContexts: [root, active, disabled],
            observedAt: now,
            metrics: [
                metric(
                    id: "key-total-usage",
                    contextID: active.contextID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 1, origin: .reported)
                    ),
                    observedAt: now
                ),
                metric(
                    id: "key-monthly-byok-usage",
                    contextID: disabled.contextID,
                    availability: .unlimited,
                    values: nil,
                    observedAt: now.addingTimeInterval(
                        -TimeInterval(
                            OpenRouterProviderContract.maximumAgeSeconds + 1
                        )
                    )
                )
            ]
        )
        let presentation = OpenRouterCapacityPresentation(
            account: account,
            snapshot: snapshot,
            credentialContexts: [
                credential(context: active, role: .ordinary),
                credential(
                    context: disabled,
                    role: .ordinary,
                    isEnabled: false
                )
            ],
            refreshStates: [],
            diagnostics: [],
            now: now,
            locale: Locale(identifier: "en_US")
        )

        let activePresentation = presentation.credentials.first {
            $0.slotID == active.contextID
        }
        let disabledPresentation = presentation.credentials.first {
            $0.slotID == disabled.contextID
        }
        XCTAssertEqual(activePresentation?.state, .current)
        XCTAssertEqual(disabledPresentation?.state, .disabled)
        XCTAssertEqual(disabledPresentation?.metrics.first?.state, .stale)
        XCTAssertEqual(presentation.state, .current)
        XCTAssertEqual(presentation.statusText, "Current")
    }

    func testSettingsDetailHidesOnlyHealthyOpenRouterMetadataAndKeepsAccountFailure() {
        let account = ProviderAccount(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "account",
            displayName: "OpenRouter My",
            isEnabled: true,
            sourceMode: .openRouterAPI
        )
        let healthy = SettingsAccountDetailPresentation(
            account: account,
            providerDisplayName: "OpenRouter",
            refreshStatus: .succeeded(Date(timeIntervalSince1970: 2_000_000)),
            refreshIssue: nil,
            diagnosticsAvailability: .supported,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertNil(healthy.providerSubtitle)
        XCTAssertNil(healthy.accountExceptionText)

        let failed = SettingsAccountDetailPresentation(
            account: account,
            providerDisplayName: "OpenRouter",
            refreshStatus: .failed(Date(timeIntervalSince1970: 2_000_001)),
            refreshIssue: AccountRefreshIssue(
                occurredAt: Date(timeIntervalSince1970: 2_000_001),
                warnings: ["Synthetic top-level failure without slot diagnostics."]
            ),
            diagnosticsAvailability: .failed,
            locale: Locale(identifier: "ru_RU")
        )

        XCTAssertNil(failed.providerSubtitle)
        XCTAssertEqual(failed.accountExceptionText, "Не удалось обновить")
        XCTAssertEqual(
            OpenRouterSettingsAccessibilityID.accountException,
            "settings.openrouter.account-exception"
        )

        let otherProvider = ProviderAccount(
            providerID: "claude-code",
            accountID: "account",
            displayName: "Claude Work",
            isEnabled: true,
            sourceMode: .claudeStatusLine
        )
        let other = SettingsAccountDetailPresentation(
            account: otherProvider,
            providerDisplayName: "Claude Code",
            refreshStatus: .succeeded(Date(timeIntervalSince1970: 2_000_000)),
            refreshIssue: nil,
            diagnosticsAvailability: .supported,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(other.providerSubtitle, "Claude Code")
        XCTAssertNil(other.accountExceptionText)
    }

    func testManagementCredentialRowProjectsEveryNonCurrentSharedCreditState() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let current = managementCapacityFixture(
            availability: .known,
            observedAt: now,
            now: now
        )
        let currentRow = OpenRouterSettingsCredentialRowPresentation(
            credential: current.credential,
            capacityPresentation: current.presentation,
            diagnostic: nil,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertNil(currentRow.visibleStatusText)
        XCTAssertEqual(currentRow.accessibilityValue, "Enabled")
        XCTAssertEqual(currentRow.statusState, .current)

        let stale = managementCapacityFixture(
            availability: .known,
            observedAt: now.addingTimeInterval(
                -TimeInterval(OpenRouterProviderContract.maximumAgeSeconds + 1)
            ),
            now: now
        )
        let staleRow = OpenRouterSettingsCredentialRowPresentation(
            credential: stale.credential,
            capacityPresentation: stale.presentation,
            diagnostic: nil,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(staleRow.visibleStatusText, "Stale")
        XCTAssertEqual(staleRow.accessibilityValue, "Stale")
        XCTAssertEqual(staleRow.statusState, .stale)

        let unknown = managementCapacityFixture(
            availability: .unknown,
            observedAt: now,
            now: now
        )
        let unknownRow = OpenRouterSettingsCredentialRowPresentation(
            credential: unknown.credential,
            capacityPresentation: unknown.presentation,
            diagnostic: nil,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(unknownRow.visibleStatusText, "Unknown")
        XCTAssertEqual(unknownRow.accessibilityValue, "Unknown")
        XCTAssertEqual(unknownRow.statusState, .unknown)

        let unavailable = managementCapacityFixture(
            availability: nil,
            observedAt: now,
            now: now
        )
        let unavailableRow = OpenRouterSettingsCredentialRowPresentation(
            credential: unavailable.credential,
            capacityPresentation: unavailable.presentation,
            diagnostic: nil,
            locale: Locale(identifier: "ru_RU")
        )
        XCTAssertEqual(unavailableRow.visibleStatusText, "Недоступно")
        XCTAssertEqual(unavailableRow.accessibilityValue, "Недоступно")
        XCTAssertEqual(unavailableRow.statusState, .unavailable)

        let disabledCredential = credential(
            context: current.context,
            role: .management,
            isEnabled: false
        )
        let disabledRow = OpenRouterSettingsCredentialRowPresentation(
            credential: disabledCredential,
            capacityPresentation: current.presentation,
            diagnostic: nil,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(disabledRow.visibleStatusText, "Disabled")
        XCTAssertEqual(disabledRow.accessibilityValue, "Disabled")
        XCTAssertEqual(disabledRow.statusState, .disabled)

        let diagnostic = CredentialContextDiagnostic(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "account",
            slotID: current.credential.slot.slotID,
            code: .insufficientPrivilege,
            occurredAt: now
        )
        let diagnosticRow = OpenRouterSettingsCredentialRowPresentation(
            credential: current.credential,
            capacityPresentation: current.presentation,
            diagnostic: diagnostic,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(
            diagnosticRow.visibleStatusText,
            "Key privileges are insufficient"
        )
        XCTAssertEqual(diagnosticRow.statusState, .credentialError)
        XCTAssertEqual(
            diagnosticRow.accessibilityIdentifier,
            "settings.openrouter.credential.root"
        )
        XCTAssertEqual(
            diagnosticRow.actionsAccessibilityIdentifier,
            "settings.openrouter.actions.root"
        )
        XCTAssertEqual(
            OpenRouterSettingsAccessibilityID.missingManagement,
            "settings.openrouter.management-missing"
        )
    }

    func testDetailsKeepFullLocalizedBYOKMetricLabelsAtCompactWidthContract() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let account = ProviderAccount(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "account",
            displayName: "OpenRouter",
            isEnabled: true,
            sourceMode: .openRouterAPI
        )
        let root = AccountContext(
            contextID: "root",
            kind: .personal,
            regionID: "global"
        )
        let ordinary = AccountContext(
            contextID: "ordinary",
            kind: .credential,
            displayName: "Ordinary",
            regionID: "global",
            parentContextID: root.contextID
        )
        let snapshot = CapacitySnapshot(
            providerID: account.providerID,
            surfaceID: OpenRouterProviderContract.surfaceID,
            savedAccountID: account.accountID,
            accountContexts: [root, ordinary],
            observedAt: now,
            metrics: [
                metric(
                    id: "key-total-byok-usage",
                    contextID: ordinary.contextID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 1, origin: .reported)
                    ),
                    observedAt: now
                ),
                metric(
                    id: "key-monthly-byok-usage",
                    contextID: ordinary.contextID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 2, origin: .reported)
                    ),
                    observedAt: now
                )
            ]
        )

        for (localeID, expectedLabels) in [
            ("en_US", ["Monthly BYOK usage", "Total BYOK usage"]),
            ("ru_RU", ["Расход BYOK за месяц", "Расход BYOK за всё время"]),
        ] {
            let presentation = OpenRouterCapacityPresentation(
                account: account,
                snapshot: snapshot,
                credentialContexts: [
                    credential(context: ordinary, role: .ordinary)
                ],
                refreshStates: [],
                diagnostics: [],
                now: now,
                locale: Locale(identifier: localeID)
            )
            let metrics = presentation.credentials[0].metrics
            XCTAssertEqual(Set(metrics.map(\.displayName)), Set(expectedLabels))
            XCTAssertTrue(metrics.allSatisfy {
                !$0.accessibilityValue.isEmpty && $0.displayName.count > 0
            })

            let collapsedRenderer = ImageRenderer(
                content: OpenRouterCapacityDetailsContent(
                    presentation: presentation
                )
                .frame(width: 360)
            )
            let collapsedImage = try XCTUnwrap(collapsedRenderer.nsImage)
            XCTAssertEqual(collapsedImage.size.width, 360, accuracy: 0.5)
            XCTAssertGreaterThan(collapsedImage.size.height, 0)

            let expandedRenderer = ImageRenderer(
                content: OpenRouterCapacityDetailsContent(
                    presentation: presentation,
                    initiallyExpandedCredentialID: ordinary.contextID
                )
                .frame(width: 360)
            )
            let expandedImage = try XCTUnwrap(expandedRenderer.nsImage)
            XCTAssertEqual(expandedImage.size.width, 360, accuracy: 0.5)
            XCTAssertGreaterThan(
                expandedImage.size.height,
                collapsedImage.size.height
            )
        }
    }

    private func managementCapacityFixture(
        availability: CapacityAvailability?,
        observedAt: Date,
        now: Date
    ) -> (
        context: AccountContext,
        credential: ProviderCredentialContext,
        presentation: OpenRouterCapacityPresentation
    ) {
        let account = ProviderAccount(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "account",
            displayName: "OpenRouter",
            isEnabled: true,
            sourceMode: .openRouterAPI
        )
        let root = AccountContext(
            contextID: "root",
            kind: .personal,
            regionID: "global"
        )
        let management = credential(context: root, role: .management)
        let snapshot = availability.map {
            CapacitySnapshot(
                providerID: account.providerID,
                surfaceID: OpenRouterProviderContract.surfaceID,
                savedAccountID: account.accountID,
                accountContexts: [root],
                observedAt: now,
                metrics: [
                    metric(
                        id: "account-credits",
                        contextID: root.contextID,
                        sourceID: OpenRouterProviderContract.managementSourceID,
                        availability: $0,
                        values: $0 == .known
                            ? CapacityValues(
                                remaining: CapacityValue(
                                    value: 12.2,
                                    origin: .reported
                                )
                            )
                            : nil,
                        observedAt: observedAt
                    )
                ]
            )
        }
        let presentation = OpenRouterCapacityPresentation(
            account: account,
            snapshot: snapshot,
            credentialContexts: [management],
            refreshStates: [],
            diagnostics: [],
            now: now,
            locale: Locale(identifier: "en_US")
        )
        return (root, management, presentation)
    }

    private func metric(
        id: String,
        contextID: String,
        sourceID: String = OpenRouterProviderContract.currentKeySourceID,
        availability: CapacityAvailability = .known,
        values: CapacityValues?,
        observedAt: Date,
        window: CapacityWindow = CapacityWindow(kind: .lifetime)
    ) -> CapacityMetric {
        CapacityMetric(
            metricID: id,
            accountContextID: contextID,
            sourceID: sourceID,
            capability: id.contains("usage") ? "spend" : "credits",
            displayName: "Synthetic",
            availability: availability,
            unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
            values: values,
            window: window,
            freshness: ObservationFreshness(observedAt: observedAt),
            confidence: .live
        )
    }

    private func resetMetric(
        id: String,
        now: Date,
        window: CapacityWindow
    ) -> CapacityMetric {
        metric(
            id: id,
            contextID: "reset-test",
            values: CapacityValues(
                consumed: CapacityValue(value: 1, origin: .reported),
                remaining: id == "key-credit-limit"
                    ? CapacityValue(value: 9, origin: .reported)
                    : nil,
                limit: id == "key-credit-limit"
                    ? CapacityValue(value: 10, origin: .reported)
                    : nil
            ),
            observedAt: now,
            window: window
        )
    }

    private func resetGroups(
        metrics: [CapacityMetric],
        now: Date
    ) -> [OpenRouterCredentialResetPresentation] {
        let account = ProviderAccount(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "account",
            displayName: "OpenRouter",
            isEnabled: true,
            sourceMode: .openRouterAPI
        )
        let context = AccountContext(
            contextID: "reset-test",
            kind: .credential,
            displayName: "Reset test",
            regionID: "global"
        )
        let snapshot = CapacitySnapshot(
            providerID: account.providerID,
            surfaceID: OpenRouterProviderContract.surfaceID,
            savedAccountID: account.accountID,
            accountContexts: [context],
            observedAt: now,
            metrics: metrics
        )
        let presentation = OpenRouterCapacityPresentation(
            account: account,
            snapshot: snapshot,
            credentialContexts: [
                credential(context: context, role: .ordinary)
            ],
            refreshStates: [],
            diagnostics: [],
            now: now,
            locale: Locale(identifier: "en_US")
        )
        return presentation.credentials[0].detailsPresentation.resetGroups
    }

    private func credential(
        context: AccountContext,
        role: ProviderCredentialRole,
        isEnabled: Bool = true,
        lifecycleState: CredentialLifecycleState = .active
    ) -> ProviderCredentialContext {
        ProviderCredentialContext(
            context: ProviderAccountContextConfiguration(
                providerID: OpenRouterProviderContract.providerID,
                accountID: "account",
                contextID: context.contextID,
                kind: context.kind,
                displayName: context.displayName,
                regionID: context.regionID,
                parentContextID: context.parentContextID
            ),
            slot: ProviderCredentialSlot(
                providerID: OpenRouterProviderContract.providerID,
                accountID: "account",
                slotID: context.contextID,
                contextID: context.contextID,
                role: role,
                isEnabled: isEnabled,
                keychainReference: "reference-\(context.contextID)",
                lifecycleState: lifecycleState
            )
        )
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
        let suiteName = "OpenRouterSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private final class SettingsTestKeychain: KeychainService, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: CredentialSecret] = [:]

    var credentialCount: Int {
        lock.withLock { values.count }
    }

    func contains(reference: String) -> Bool {
        lock.withLock { values[reference] != nil }
    }

    func drop(reference: String) {
        _ = lock.withLock {
            values.removeValue(forKey: reference)
        }
    }

    func createCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        try lock.withLock {
            guard values[reference] == nil else {
                throw KeychainServiceError.duplicateReference
            }
            values[reference] = credential
        }
    }

    func readCredential(reference: String) throws -> CredentialSecret {
        try lock.withLock {
            guard let credential = values[reference] else {
                throw KeychainServiceError.credentialNotFound
            }
            return credential
        }
    }

    func replaceCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        try lock.withLock {
            guard values[reference] != nil else {
                throw KeychainServiceError.credentialNotFound
            }
            values[reference] = credential
        }
    }

    func deleteCredential(reference: String) throws {
        _ = lock.withLock {
            values.removeValue(forKey: reference)
        }
    }
}

private actor BarrierOpenRouterClient: OpenRouterAPIClient {
    private let base = SyntheticOpenRouterVerificationClient(
        failingOrdinarySlotID: "never"
    )
    private var shouldBlockNextOrdinaryRequest = false
    private var isOrdinaryRequestBlocked = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func blockNextOrdinaryRequest() {
        shouldBlockNextOrdinaryRequest = true
    }

    func waitUntilOrdinaryRequestIsBlocked() async {
        guard !isOrdinaryRequestBlocked else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func releaseBlockedOrdinaryRequest() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func fetchCurrentKeyCapacity(
        credential: OpenRouterOrdinaryCredential
    ) async throws -> OpenRouterCurrentKeyCapacity {
        guard shouldBlockNextOrdinaryRequest else {
            return try await base.fetchCurrentKeyCapacity(
                credential: credential
            )
        }
        shouldBlockNextOrdinaryRequest = false
        isOrdinaryRequestBlocked = true
        blockedWaiters.forEach { $0.resume() }
        blockedWaiters.removeAll()
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        isOrdinaryRequestBlocked = false
        throw OpenRouterAPIClientError.authenticationFailure
    }

    func fetchManagementCredits(
        credential: OpenRouterManagementCredential
    ) async throws -> OpenRouterManagementCreditsCapacity {
        try await base.fetchManagementCredits(credential: credential)
    }
}
#endif
