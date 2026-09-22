import BairometerCore
import Foundation
import XCTest
@testable import Bairometer

final class UITestHostTests: XCTestCase {
    func testProductionLaunchArgumentsDoNotEnableHost() {
        let options = AppLaunchOptions(
            arguments: ["/path/to/Bairometer"],
            bundleIdentifier: "io.github.Prontsevich.Bairometer"
        )

        XCTAssertNil(options.storageDirectory)
        XCTAssertNil(options.uiTestHostConfiguration)
    }

    func testHostBundleUsesSafeDefaultConfiguration() throws {
        let configuration = try XCTUnwrap(UITestHostConfiguration.parse(
            arguments: ["/path/to/BairometerTest", "-psn_0_12345"],
            bundleIdentifier: UITestHostConfiguration.bundleIdentifier
        ))

        XCTAssertEqual(configuration, .defaultConfiguration)
        XCTAssertEqual(configuration.scenario, .dashboardHealthy)
        XCTAssertEqual(configuration.language, .english)
        XCTAssertEqual(configuration.appearance, .dark)
        XCTAssertEqual(configuration.dashboardHeight, .standard)
    }

    func testHostArgumentsResolveEveryVariant() throws {
        let configuration = try XCTUnwrap(UITestHostConfiguration.parse(
            arguments: [
                "/path/to/Bairometer",
                UITestHostConfiguration.modeArgument,
                UITestHostScenario.dashboardMixed.rawValue,
                UITestHostConfiguration.languageArgument,
                UITestHostLanguage.russian.rawValue,
                UITestHostConfiguration.appearanceArgument,
                UITestHostAppearance.light.rawValue,
                UITestHostConfiguration.heightArgument,
                DashboardHeightPreset.tall.rawValue
            ],
            bundleIdentifier: "io.github.Prontsevich.Bairometer"
        ))

        XCTAssertEqual(configuration.scenario, .dashboardMixed)
        XCTAssertEqual(configuration.language, .russian)
        XCTAssertEqual(configuration.appearance, .light)
        XCTAssertEqual(configuration.dashboardHeight, .tall)
    }

    func testHostParserRejectsMissingInvalidAndDetachedValues() {
        XCTAssertThrowsError(try UITestHostConfiguration.parse(
            arguments: ["app", UITestHostConfiguration.modeArgument],
            bundleIdentifier: nil
        )) { error in
            XCTAssertEqual(
                error as? UITestHostConfigurationError,
                .missingValue(UITestHostConfiguration.modeArgument)
            )
        }

        XCTAssertThrowsError(try UITestHostConfiguration.parse(
            arguments: ["app", UITestHostConfiguration.modeArgument, "unknown"],
            bundleIdentifier: nil
        ))

        XCTAssertThrowsError(try UITestHostConfiguration.parse(
            arguments: ["app", UITestHostConfiguration.languageArgument, "en"],
            bundleIdentifier: nil
        )) { error in
            XCTAssertEqual(error as? UITestHostConfigurationError, .hostModeRequired)
        }
    }

    func testEveryScenarioBuildsPrivacySafeSyntheticFixtures() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)

        for scenario in UITestHostScenario.allCases {
            let fixture = UITestHostFixture.make(scenario: scenario, anchor: anchor)
            XCTAssertTrue(fixture.adapters.allSatisfy { $0 is UITestScriptedProviderAdapter })
            XCTAssertTrue(fixture.accounts.allSatisfy {
                $0.executablePath == nil && $0.webDataStoreID == nil && $0.localSnapshotPath == nil
            })
            XCTAssertTrue(fixture.snapshots.allSatisfy {
                $0.source == "Synthetic UI test fixture"
            })
        }
    }

    func testMixedFixtureContainsEveryRequiredPresentationState() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = UITestHostFixture.make(scenario: .dashboardMixed, anchor: anchor)

        XCTAssertEqual(fixture.accounts.count, 7)
        XCTAssertTrue(fixture.snapshots.contains(where: { $0.status == .warning }))
        XCTAssertEqual(fixture.refreshIssues.count, 1)
        XCTAssertTrue(fixture.accounts.contains(where: { $0.sourceMode == .manual }))
        XCTAssertTrue(fixture.accounts.contains(where: { account in
            account.providerID == "ui-test-empty" &&
                !fixture.snapshots.contains(where: { $0.id == account.id })
        }))
        let stale = fixture.snapshots.first { $0.accountID == "stale" }
        XCTAssertNotNil(stale)
        XCTAssertGreaterThan(
            anchor.timeIntervalSince(stale?.lastUpdatedAt ?? anchor),
            RefreshInterval.manualOnly.staleAfter
        )
        XCTAssertTrue(
            stale?.limitWindows.allSatisfy { ($0.resetAt ?? anchor) > anchor } == true
        )
    }

    func testOpenRouterFixturePreservesNativeHierarchyAndPrivacyBoundary() throws {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = UITestHostFixture.make(
            scenario: .dashboardOpenRouter,
            anchor: anchor
        )
        let account = try XCTUnwrap(fixture.accounts.first)
        let snapshot = try XCTUnwrap(fixture.nativeCapacitySnapshots[account.id])
        let credentials = try XCTUnwrap(fixture.credentialContexts[account.id])
        let diagnostics = try XCTUnwrap(fixture.credentialDiagnostics[account.id])

        XCTAssertEqual(account.providerID, OpenRouterProviderContract.providerID)
        XCTAssertEqual(
            snapshot.metrics.filter { $0.metricID == "account-credits" }.count,
            1
        )
        XCTAssertEqual(credentials.filter { $0.slot.role == .ordinary }.count, 3)
        XCTAssertEqual(credentials.filter { $0.slot.role == .management }.count, 1)
        XCTAssertEqual(diagnostics.map(\.code), [.authentication])
        XCTAssertTrue(credentials.allSatisfy {
            $0.slot.keychainReference.hasPrefix("synthetic-reference-")
                && !$0.slot.keychainReference.contains("sk-")
        })

        let presentation = OpenRouterCapacityPresentation(
            account: account,
            snapshot: snapshot,
            credentialContexts: credentials,
            refreshStates: fixture.credentialRefreshStates[account.id] ?? [],
            diagnostics: diagnostics,
            now: anchor,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(presentation.state, .partial)
        XCTAssertEqual(
            presentation.sharedCredits.dashboardValueText,
            "$87.5"
        )
        XCTAssertEqual(
            presentation.sharedCredits.displayValueLines,
            ["$87.5 left", "$12.5 used"]
        )
        XCTAssertFalse(presentation.sharedCredits.valueText.contains("total"))
        XCTAssertEqual(
            presentation.sharedCredits.accountCredits?.accessibilityValue,
            "Left, $87.5, Used, $12.5"
        )
        XCTAssertFalse(presentation.sharedCredits.valueText.contains("%"))
        XCTAssertTrue(presentation.credentials.contains { $0.state == .stale })
        XCTAssertTrue(presentation.credentials.contains { $0.state == .partial })
        let primary = try XCTUnwrap(
            presentation.credentials.first { $0.displayName == "Primary" }
        )
        XCTAssertEqual(primary.dashboardValueText, "$8.75")
        XCTAssertEqual(
            primary.dashboardAccessibilityValue,
            "$8.75 available of $10, Resets in 1 hour"
        )
        XCTAssertEqual(primary.dashboardMetric?.resetText, "Resets in 1 hour")
        XCTAssertFalse(primary.dashboardAccessibilityValue.contains("Updated"))
        let primaryDetails = primary.detailsPresentation
        XCTAssertFalse(primaryDetails.isExpandedByDefault)
        XCTAssertTrue(primaryDetails.collapsedMetrics.isEmpty)
        XCTAssertTrue(primaryDetails.expandedMetrics.contains {
                $0.metricID == "key-daily-usage"
                && $0.valueText == "$0 used"
        })
        XCTAssertTrue(primaryDetails.expandedMetrics.contains {
                $0.metricID == "key-daily-byok-usage"
                && $0.valueText == "$0 used"
        })
        XCTAssertEqual(
            primaryDetails.usageRows.map(\.scopeText),
            ["Day", "Week", "Month", "Total"]
        )
        XCTAssertEqual(
            primaryDetails.usageRows.first?.usageMetric?.tableValueText,
            "$0"
        )
        XCTAssertEqual(
            primaryDetails.usageRows.first?.byokMetric?.tableValueText,
            "$0"
        )
        XCTAssertNotNil(primaryDetails.updateText)
        XCTAssertEqual(
            Set(primaryDetails.resetGroups.map(\.resetText)),
            [
                "No reset",
                "Resets in 1 hour",
                "Resets in 2 hours",
                "Resets in 2 days",
                "Resets in 1 week",
            ]
        )
        let dailyResetGroup = try XCTUnwrap(
            primaryDetails.resetGroups.first {
                $0.resetText == "Resets in 2 hours"
            }
        )
        XCTAssertEqual(
            Set(dailyResetGroup.scopeNames),
            ["Day"]
        )
        XCTAssertEqual(
            dailyResetGroup.accessibilityLabel,
            "Day"
        )
        XCTAssertEqual(
            dailyResetGroup.accessibilityValue,
            "Resets in 2 hours"
        )
        XCTAssertEqual(
            primaryDetails.resetGroups.first {
                $0.resetText == "Resets in 2 days"
            }?.scopeNames,
            ["Week · Usage"]
        )
        XCTAssertEqual(
            primaryDetails.resetGroups.first {
                $0.resetText == "Resets in 1 week"
            }?.scopeNames,
            ["Month · BYOK"]
        )
        XCTAssertTrue(
            primaryDetails.expandedMetrics.allSatisfy {
                $0.visibleAccessibilityValue(
                    showsReset: false,
                    showsFreshness: false
                ) == $0.valueText
            }
        )
        XCTAssertEqual(
            primaryDetails.expandedSummaryAccessibilityValue,
            "$8.75 available of $10"
        )
        let failed = try XCTUnwrap(
            presentation.credentials.first {
                $0.displayName == "Authentication issue"
            }
        )
        XCTAssertEqual(
            failed.dashboardValueText,
            "Key authentication failed"
        )
        XCTAssertTrue(presentation.credentials.contains {
            $0.metrics.contains { $0.state == .unknown }
                && $0.metrics.contains { $0.state == .unlimited }
        })
    }

    func testMiniMaxFixturePresentsTwoPrivacySafeQuotaCategories() throws {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = UITestHostFixture.make(
            scenario: .dashboardMiniMax,
            anchor: anchor
        )
        let account = try XCTUnwrap(fixture.accounts.first)
        let snapshot = try XCTUnwrap(fixture.nativeCapacitySnapshots[account.id])

        XCTAssertEqual(account.providerID, MiniMaxProviderContract.providerID)
        XCTAssertEqual(account.sourceMode, .miniMaxTokenPlan)
        XCTAssertEqual(snapshot.metrics.count, 4)
        XCTAssertTrue(fixture.credentialContexts.isEmpty)
        XCTAssertTrue(fixture.credentialDiagnostics.isEmpty)

        let english = try XCTUnwrap(
            MiniMaxCapacityPresentation(
                account: account,
                snapshot: snapshot,
                now: anchor,
                locale: Locale(identifier: "en_US")
            )
        )
        XCTAssertEqual(english.categories.count, 2)
        XCTAssertEqual(
            english.categories.map(\.shortDisplayName),
            [
                "Text & multimedia",
                "Video generation",
            ]
        )
        XCTAssertEqual(english.categories.map(\.windows.count), [2, 2])
        XCTAssertEqual(english.categories.first?.windows.first?.capacityText, "")
        XCTAssertEqual(
            english.categories.first?.windows.first?.percentageText,
            "40% used"
        )
        XCTAssertFalse(
            english.categories.first?.windows.first?.accessibilityValue
                .contains("40% used, 40% used") == true
        )

        let russian = try XCTUnwrap(
            MiniMaxCapacityPresentation(
                account: account,
                snapshot: snapshot,
                now: anchor,
                locale: Locale(identifier: "ru_RU")
            )
        )
        XCTAssertEqual(
            russian.categories.map(\.shortDisplayName),
            [
                "Текст и мультимедиа",
                "Генерация видео",
            ]
        )

        let presentations = [english, russian]
        let presentationText = presentations.flatMap { presentation in
            presentation.categories.flatMap { category in
                [
                    category.displayName,
                    category.accessibilityIdentifier,
                    category.accessibilityValue,
                ] + category.windows.flatMap { window in
                    [
                        window.displayName,
                        window.capacityText,
                        window.percentageText ?? "",
                        window.resetText ?? "",
                        window.accessibilityLabel,
                        window.accessibilityValue,
                    ]
                }
            }
        }.joined(separator: " ").lowercased()
        let storedFixture = String(
            decoding: try JSONEncoder().encode(snapshot),
            as: UTF8.self
        ).lowercased()
        for rawIdentifier in ["general", "video"] {
            XCTAssertFalse(
                presentations.flatMap(\.categories)
                    .flatMap { [$0.shortDisplayName, $0.fullDisplayName] }
                    .map { $0.lowercased() }
                    .contains(rawIdentifier)
            )
            XCTAssertFalse(storedFixture.contains(rawIdentifier))
        }
        XCTAssertFalse(presentationText.contains("provider metadata marker"))
    }

    func testFieldsetHeaderControlMasksAreIndividualAndExact() {
        XCTAssertEqual(DashboardAccountHeaderLayout.controlSize, 24)
        XCTAssertEqual(
            DashboardAccountHeaderLayout.refreshGlyphVerticalOffset,
            -1
        )
        XCTAssertEqual(
            DashboardAccountHeaderLayout.controlConfiguration,
            TerminalIconButtonConfiguration(
                idleBackground: .fieldsetSurface,
                fixedHitTargetSize: 24
            )
        )
        XCTAssertEqual(OpenRouterSettingsLayout.actionControlSize, 32)
        XCTAssertEqual(
            OpenRouterSettingsLayout.headerActionTrailingAdjustment,
            6
        )
        XCTAssertEqual(
            OpenRouterSettingsLayout.fieldsetActionControlConfiguration,
            TerminalIconButtonConfiguration(
                idleBackground: .fieldsetSurface,
                fixedHitTargetSize: 32
            )
        )
        XCTAssertEqual(
            TerminalIconButtonConfiguration.transparent,
            TerminalIconButtonConfiguration(
                idleBackground: .transparent,
                fixedHitTargetSize: nil
            )
        )
        XCTAssertEqual(TerminalFieldsetLayout.controlsHeight, 32)
        XCTAssertEqual(TerminalFieldsetLayout.controlsVerticalOffset, -16)
        XCTAssertEqual(TerminalFieldsetLayout.controlsTrailingInset, 9)
    }

    func testOpenRouterSettingsFixtureCoversDisabledManagementAndKeyExceptions() throws {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = UITestHostFixture.make(
            scenario: .settingsOpenRouter,
            anchor: anchor
        )
        let account = try XCTUnwrap(fixture.accounts.first)
        let snapshot = try XCTUnwrap(fixture.nativeCapacitySnapshots[account.id])
        let credentials = try XCTUnwrap(fixture.credentialContexts[account.id])
        let management = try XCTUnwrap(
            credentials.first { $0.slot.role == .management }
        )

        XCTAssertFalse(management.slot.isEnabled)
        XCTAssertEqual(credentials.filter { $0.slot.role == .ordinary }.count, 3)

        let presentation = OpenRouterCapacityPresentation(
            account: account,
            snapshot: snapshot,
            credentialContexts: credentials,
            refreshStates: fixture.credentialRefreshStates[account.id] ?? [],
            diagnostics: fixture.credentialDiagnostics[account.id] ?? [],
            now: anchor,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(presentation.sharedCredits.state, .unavailable)
        XCTAssertTrue(presentation.credentials.contains { $0.state == .stale })
        XCTAssertTrue(presentation.credentials.contains { $0.state == .partial })
    }

    func testOpenRouterMissingManagementFixtureHasExplicitEmptyState() throws {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = UITestHostFixture.make(
            scenario: .settingsOpenRouterMissingManagement,
            anchor: anchor
        )
        let account = try XCTUnwrap(fixture.accounts.first)
        let snapshot = try XCTUnwrap(fixture.nativeCapacitySnapshots[account.id])
        let credentials = try XCTUnwrap(fixture.credentialContexts[account.id])
        let slotDiagnostics = try XCTUnwrap(
            fixture.credentialDiagnostics[account.id]
        )

        XCTAssertEqual(credentials.filter { $0.slot.role == .ordinary }.count, 3)
        XCTAssertTrue(credentials.allSatisfy { $0.slot.role != .management })
        XCTAssertEqual(fixture.refreshIssues.count, 1)
        XCTAssertNotNil(fixture.refreshIssues[account.id])
        XCTAssertTrue(slotDiagnostics.isEmpty)
        XCTAssertEqual(
            OpenRouterSettingsAccessibilityID.missingManagement,
            "settings.openrouter.management-missing"
        )
        XCTAssertEqual(
            OpenRouterSettingsAccessibilityID.addManagement,
            "settings.openrouter.add-management"
        )

        let presentation = OpenRouterCapacityPresentation(
            account: account,
            snapshot: snapshot,
            credentialContexts: credentials,
            refreshStates: fixture.credentialRefreshStates[account.id] ?? [],
            diagnostics: fixture.credentialDiagnostics[account.id] ?? [],
            now: anchor,
            locale: Locale(identifier: "ru_RU")
        )
        XCTAssertEqual(presentation.sharedCredits.state, .unavailable)
        XCTAssertEqual(presentation.sharedCredits.dashboardValueText, "Недоступно")
    }

    @MainActor
    func testOpenRouterHostRefreshPreservesSyntheticNativeFixture() async throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bairometer-ui-test-openrouter-\(UUID().uuidString)"
            )
        let options = AppLaunchOptions(
            arguments: [
                "app",
                UITestHostConfiguration.modeArgument,
                UITestHostScenario.dashboardOpenRouter.rawValue,
                AppLaunchOptions.storageDirectoryArgument,
                storageDirectory.path
            ],
            bundleIdentifier: UITestHostConfiguration.bundleIdentifier
        )
        let runtime = AppRuntime(launchOptions: options)
        let session = try XCTUnwrap(runtime.uiTestHostSession)
        defer { session.cleanup() }
        let account = try XCTUnwrap(runtime.appModel.providerAccounts.first)
        let before = try XCTUnwrap(
            runtime.appModel.openRouterCapacityPresentation(
                for: account,
                locale: Locale(identifier: "en_US")
            )
        )

        runtime.appModel.refresh()
        await runtime.appModel.waitForRefreshCompletionForTesting()

        let after = try XCTUnwrap(
            runtime.appModel.openRouterCapacityPresentation(
                for: account,
                locale: Locale(identifier: "en_US")
            )
        )
        XCTAssertEqual(after.sharedCredits, before.sharedCredits)
        XCTAssertEqual(after.credentials, before.credentials)
        XCTAssertEqual(after.credentials.count, 3)
        XCTAssertNil(runtime.appModel.accountRefreshIssues[account.id])
    }

    @MainActor
    func testMiniMaxHostRefreshPreservesSyntheticNativeFixture() async throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bairometer-ui-test-minimax-\(UUID().uuidString)"
            )
        let options = AppLaunchOptions(
            arguments: [
                "app",
                UITestHostConfiguration.modeArgument,
                UITestHostScenario.dashboardMiniMax.rawValue,
                AppLaunchOptions.storageDirectoryArgument,
                storageDirectory.path,
            ],
            bundleIdentifier: UITestHostConfiguration.bundleIdentifier
        )
        let runtime = AppRuntime(launchOptions: options)
        let session = try XCTUnwrap(runtime.uiTestHostSession)
        defer { session.cleanup() }
        let account = try XCTUnwrap(runtime.appModel.providerAccounts.first)
        let before = try XCTUnwrap(
            MiniMaxCapacityPresentation(
                account: account,
                snapshot: runtime.appModel.nativeCapacitySnapshot(for: account),
                locale: Locale(identifier: "en_US")
            )
        )

        runtime.appModel.refresh()
        await runtime.appModel.waitForRefreshCompletionForTesting()

        let after = try XCTUnwrap(
            MiniMaxCapacityPresentation(
                account: account,
                snapshot: runtime.appModel.nativeCapacitySnapshot(for: account),
                locale: Locale(identifier: "en_US")
            )
        )
        XCTAssertEqual(after.categories, before.categories)
        XCTAssertEqual(after.categories.count, 2)
        XCTAssertNil(runtime.appModel.accountRefreshIssues[account.id])
    }

    @MainActor
    func testHostRuntimeUsesIsolatedStoragePreferencesAndNoStatusItem() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bairometer-ui-test-unit-\(UUID().uuidString)")
        let options = AppLaunchOptions(
            arguments: [
                "app",
                UITestHostConfiguration.modeArgument,
                UITestHostScenario.dashboardHealthy.rawValue,
                AppLaunchOptions.storageDirectoryArgument,
                storageDirectory.path
            ],
            bundleIdentifier: "io.github.Prontsevich.Bairometer"
        )
        let runtime = AppRuntime(launchOptions: options)
        let session = try XCTUnwrap(runtime.uiTestHostSession)

        XCTAssertFalse(runtime.ownsMenuBarStatusItemController)
        XCTAssertEqual(runtime.appModel.refreshSettings.interval, .manualOnly)
        XCTAssertEqual(runtime.appModel.userDefaults, session.userDefaults)
        XCTAssertEqual(runtime.appLanguagePreference.language, .english)
        XCTAssertEqual(
            session.userDefaults.string(forKey: DashboardHeightPreset.storageKey),
            DashboardHeightPreset.standard.rawValue
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageDirectory.path))

        let suiteName = session.userDefaultsSuiteName
        session.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageDirectory.path))
        XCTAssertTrue(
            UserDefaults.standard.persistentDomain(forName: suiteName)?.isEmpty ?? true
        )
    }

    func testDirtyEditorScenarioStartsEditingSyntheticAccount() {
        let workspace = UITestHostScenario.settingsDirtyEditor
            .initialSettingsWorkspace(firstAccountID: "ui-test-live:primary")

        XCTAssertEqual(workspace.selection, .accounts)
        XCTAssertEqual(workspace.editorSession.selectedAccountID, "ui-test-live:primary")
        XCTAssertEqual(workspace.editorSession.mode, .editing)
        XCTAssertFalse(workspace.editorSession.isDirty)
        XCTAssertEqual(
            UITestHostScenario.settings.initialSettingsWorkspace(firstAccountID: "account"),
            SettingsWorkspaceState()
        )
        XCTAssertEqual(
            UITestHostScenario.settingsOpenRouter.initialSettingsWorkspace(
                firstAccountID: "openrouter:account"
            ),
            SettingsWorkspaceState()
        )
        XCTAssertEqual(
            UITestHostScenario.settingsOpenRouterMissingManagement
                .initialSettingsWorkspace(firstAccountID: "openrouter:account"),
            SettingsWorkspaceState()
        )
    }
}
