import BairometerCore
import XCTest
@testable import Bairometer

final class DashboardAccountPresentationTests: XCTestCase {
    func testUsageWindowFormatsPercentResetAndSupportingText() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = makeSnapshot(
            limitWindows: [
                UsageLimitWindow(
                    id: "five-hour",
                    displayName: "5-hour",
                    usedPercent: 41.6,
                    remainingLabel: "Approx. 58% remaining",
                    resetAt: now.addingTimeInterval(7_200)
                )
            ]
        )

        let presentation = DashboardAccountPresentation(
            row: makeRow(snapshot: snapshot),
            isStale: false,
            isGlobalRefresh: false,
            now: now
        )

        XCTAssertEqual(presentation.windows.count, 1)
        XCTAssertEqual(presentation.windows[0].displayText, "41.6% used")
        XCTAssertEqual(presentation.windows[0].resetText, "resets in 2 hours")
        XCTAssertEqual(presentation.windows[0].supportingText, "Approx. 58% remaining")
        XCTAssertEqual(presentation.windows[0].accessibilityValue, "41.6% used, Approx. 58% remaining")
        XCTAssertNil(presentation.bodyMessage)
    }

    func testUsageWindowUsesRussianDecimalSeparatorAndLocalizedCopy() {
        let snapshot = makeSnapshot(
            limitWindows: [
                UsageLimitWindow(id: "weekly", displayName: "Weekly", usedPercent: 35.4)
            ]
        )

        let presentation = DashboardAccountPresentation(
            row: makeRow(snapshot: snapshot),
            isStale: false,
            isGlobalRefresh: false,
            locale: Locale(identifier: "ru_RU")
        )

        XCTAssertEqual(presentation.windows[0].displayName, "Weekly")
        XCTAssertTrue(presentation.windows[0].displayText.contains("35,4"))
        XCTAssertTrue(presentation.windows[0].displayText.hasPrefix("Ушло"))
        XCTAssertEqual(presentation.windows[0].accessibilityValue, presentation.windows[0].displayText)
        XCTAssertEqual(snapshot.limitWindows[0].usedPercent, 35.4)
        XCTAssertEqual(snapshot.limitWindows[0].displayName, "Weekly")
    }

    func testUsageWindowOmitsFractionForWholePercentages() {
        let presentation = DashboardAccountPresentation(
            row: makeRow(snapshot: makeSnapshot()),
            isStale: false,
            isGlobalRefresh: false
        )

        XCTAssertEqual(presentation.windows[0].displayText, "42% used")
    }

    func testLeftModeUsesClampedComplementForTextMeterAndAccessibility() {
        let snapshot = makeSnapshot(limitWindows: [
            UsageLimitWindow(id: "five-hour", displayName: "5-hour", usedPercent: 41.6)
        ])
        let presentation = DashboardAccountPresentation(
            row: makeRow(snapshot: snapshot),
            isStale: false,
            isGlobalRefresh: false,
            displayModeForWindow: { _ in .left }
        )

        let window = try! XCTUnwrap(presentation.windows.first)
        XCTAssertEqual(window.displayPercent, 58.4, accuracy: 0.0001)
        XCTAssertEqual(window.displayText, "58.4% left")
        XCTAssertEqual(window.accessibilityValue, "58.4% left")
        XCTAssertEqual(window.toggleHelp, "5-hour is 58.4% left. Activate to show 41.6% used.")
    }

    func testLeftModeClampsOutOfRangeCanonicalPercentWithoutChangingSeverity() {
        let snapshot = makeSnapshot(
            status: .warning,
            limitWindows: [
                UsageLimitWindow(id: "weekly", displayName: "Weekly", usedPercent: 120)
            ]
        )
        let left = DashboardAccountPresentation(
            row: makeRow(snapshot: snapshot),
            isStale: false,
            isGlobalRefresh: false,
            displayModeForWindow: { _ in .left }
        )
        let used = DashboardAccountPresentation(
            row: makeRow(snapshot: snapshot),
            isStale: false,
            isGlobalRefresh: false
        )

        XCTAssertEqual(left.windows.first?.displayPercent, 0)
        XCTAssertEqual(left.windows.first?.displayText, "0% left")
        XCTAssertEqual(left.state, used.state)
        XCTAssertEqual(left.statusText, used.statusText)
    }

    func testManualAndUnavailableAccountsDoNotInventUsageBars() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = makeSnapshot(
            status: .unavailable,
            confidence: .manual,
            limitWindows: [
                UsageLimitWindow(id: "manual", displayName: "Manual", usedPercent: 42)
            ]
        )

        let manual = DashboardAccountPresentation(
            row: makeRow(snapshot: snapshot, sourceMode: .manual),
            isStale: false,
            isGlobalRefresh: false,
            now: now
        )

        XCTAssertEqual(manual.state, .manual)
        XCTAssertTrue(manual.windows.isEmpty)
        XCTAssertEqual(manual.bodyMessage, "Manual source — open provider usage")

        let unavailableSnapshot = makeSnapshot(status: .unavailable, remainingLabel: "Open provider usage page")
        let unavailable = DashboardAccountPresentation(
            row: makeRow(snapshot: unavailableSnapshot, sourceMode: .claudeStatusLine),
            isStale: false,
            isGlobalRefresh: false,
            now: now
        )

        XCTAssertEqual(unavailable.state, .unavailable)
        XCTAssertTrue(unavailable.windows.isEmpty)
        XCTAssertEqual(unavailable.bodyMessage, "Open provider usage page")
    }

    func testMockAccountDisplaysGeneratedUsageDespiteCompatibilityManualSource() {
        let snapshot = UsageSnapshot(
            providerID: "mock",
            accountID: "work",
            accountDisplayName: "Work",
            displayName: "Mock Provider",
            status: .ok,
            limitWindows: [
                UsageLimitWindow(id: "weekly", displayName: "Weekly", usedPercent: 42)
            ],
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000_000),
            confidence: .localEstimate,
            source: "Generated mock data"
        )
        let account = ProviderAccount(
            providerID: "mock",
            accountID: "work",
            displayName: "Work",
            isEnabled: true,
            sourceMode: .manual
        )
        let presentation = DashboardAccountPresentation(
            row: AccountSnapshotRow(
                account: account,
                providerDisplayName: "Mock Provider",
                snapshot: snapshot,
                refreshStatus: .idle,
                refreshIssue: nil
            ),
            isStale: false,
            isGlobalRefresh: false
        )

        XCTAssertEqual(presentation.state, .normal)
        XCTAssertEqual(presentation.windows.count, 1)
        XCTAssertNil(presentation.bodyMessage)
    }

    func testFailedAndStaleStatesKeepLastValidUsageVisible() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = makeSnapshot(limitWindows: [
            UsageLimitWindow(id: "weekly", displayName: "7-day", usedPercent: 24)
        ])

        let stale = DashboardAccountPresentation(
            row: makeRow(snapshot: snapshot),
            isStale: true,
            isGlobalRefresh: false,
            now: now
        )
        XCTAssertEqual(stale.state, .stale)
        XCTAssertEqual(stale.statusText, "Stale")
        XCTAssertEqual(stale.windows.count, 1)

        let failed = DashboardAccountPresentation(
            row: makeRow(
                snapshot: snapshot,
                refreshIssue: AccountRefreshIssue(occurredAt: now, warnings: ["Timed out"])
            ),
            isStale: false,
            isGlobalRefresh: false,
            now: now
        )
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.statusText, "Refresh failed")
        XCTAssertEqual(failed.windows.count, 1)
    }

    func testMiniMaxUnavailableSubscriptionFailureUsesLocalizedPresentation() {
        let account = ProviderAccount(
            providerID: MiniMaxProviderContract.providerID,
            accountID: "minimax-account",
            displayName: "MiniMax",
            isEnabled: true,
            sourceMode: .miniMaxTokenPlan
        )
        let issue = AccountRefreshIssue(
            occurredAt: Date(timeIntervalSince1970: 1_000_000),
            warnings: [MiniMaxProviderContract.unavailableSubscriptionWarning]
        )

        let english = DashboardAccountPresentation(
            row: AccountSnapshotRow(
                account: account,
                providerDisplayName: "MiniMax",
                snapshot: nil,
                refreshStatus: .failed(issue.occurredAt),
                refreshIssue: issue
            ),
            isStale: false,
            isGlobalRefresh: false,
            locale: Locale(identifier: "en_US")
        )
        let russian = DashboardAccountPresentation(
            row: AccountSnapshotRow(
                account: account,
                providerDisplayName: "MiniMax",
                snapshot: nil,
                refreshStatus: .failed(issue.occurredAt),
                refreshIssue: issue
            ),
            isStale: false,
            isGlobalRefresh: false,
            locale: Locale(identifier: "ru_RU")
        )
        let unrelated = DashboardAccountPresentation(
            row: makeRow(
                snapshot: nil,
                refreshIssue: AccountRefreshIssue(
                    occurredAt: issue.occurredAt,
                    warnings: ["Timed out"]
                )
            ),
            isStale: false,
            isGlobalRefresh: false
        )
        let laterAuthentication = DashboardAccountPresentation(
            row: AccountSnapshotRow(
                account: account,
                providerDisplayName: "MiniMax",
                snapshot: makeSnapshot(
                    status: .error,
                    providerID: MiniMaxProviderContract.providerID,
                    accountID: account.accountID,
                    warnings: [MiniMaxProviderContract.unavailableSubscriptionWarning]
                ),
                refreshStatus: .failed(issue.occurredAt),
                refreshIssue: AccountRefreshIssue(
                    occurredAt: issue.occurredAt,
                    warnings: ["Authentication failed"]
                )
            ),
            isStale: false,
            isGlobalRefresh: false
        )
        let laterSuccess = DashboardAccountPresentation(
            row: AccountSnapshotRow(
                account: account,
                providerDisplayName: "MiniMax",
                snapshot: makeSnapshot(
                    status: .ok,
                    providerID: MiniMaxProviderContract.providerID,
                    accountID: account.accountID,
                    warnings: [MiniMaxProviderContract.unavailableSubscriptionWarning]
                ),
                refreshStatus: .succeeded(issue.occurredAt),
                refreshIssue: nil
            ),
            isStale: false,
            isGlobalRefresh: false
        )

        XCTAssertEqual(english.statusText, "MiniMax Token Plan subscription is unavailable or expired")
        XCTAssertNil(english.bodyMessage)
        XCTAssertEqual(russian.statusText, "Подписка MiniMax Token Plan недоступна или истекла")
        XCTAssertEqual(unrelated.statusText, "Refresh failed")
        XCTAssertEqual(laterAuthentication.statusText, "Refresh failed")
        XCTAssertNotEqual(
            laterSuccess.statusText,
            "MiniMax Token Plan subscription is unavailable or expired"
        )
    }

    func testRefreshAvailabilityMatchesGlobalAndAccountRefreshRules() {
        let row = makeRow(snapshot: makeSnapshot())

        let ready = DashboardAccountPresentation(
            row: row,
            isStale: false,
            isGlobalRefresh: false
        )
        XCTAssertTrue(ready.canRefresh)
        XCTAssertEqual(ready.refreshHelp, "Refresh Work")

        let globalRefresh = DashboardAccountPresentation(
            row: row,
            isStale: false,
            isGlobalRefresh: true
        )
        XCTAssertFalse(globalRefresh.canRefresh)
        XCTAssertEqual(globalRefresh.refreshHelp, "Refreshing all accounts.")

        let accountRefresh = DashboardAccountPresentation(
            row: makeRow(snapshot: makeSnapshot(), refreshStatus: .refreshing),
            isStale: false,
            isGlobalRefresh: false
        )
        XCTAssertFalse(accountRefresh.canRefresh)
        XCTAssertTrue(accountRefresh.isRefreshing)
        XCTAssertEqual(accountRefresh.state, .refreshing)
    }

    func testNoDataAccountHasVisibleStateWithoutUsageValues() {
        let presentation = DashboardAccountPresentation(
            row: makeRow(snapshot: nil),
            isStale: false,
            isGlobalRefresh: false
        )

        XCTAssertEqual(presentation.state, .noData)
        XCTAssertTrue(presentation.windows.isEmpty)
        XCTAssertEqual(presentation.bodyMessage, "No usage data")
    }

    func testExperimentalCompatibilityNoteDoesNotCreateWarningState() {
        let experimental = DashboardAccountPresentation(
            row: makeRow(
                snapshot: makeSnapshot(warnings: ["Experimental compatibility note"]),
                sourceMode: .ollamaWebPage
            ),
            isStale: false,
            isGlobalRefresh: false
        )

        XCTAssertEqual(experimental.state, .normal)
        XCTAssertNil(experimental.statusText)

        let realUsageWarning = DashboardAccountPresentation(
            row: makeRow(
                snapshot: makeSnapshot(
                    status: .warning,
                    warnings: ["Experimental compatibility note"]
                ),
                sourceMode: .ollamaWebPage
            ),
            isStale: false,
            isGlobalRefresh: false
        )

        XCTAssertEqual(realUsageWarning.state, .warning)
        XCTAssertEqual(realUsageWarning.statusText, "Warning")
    }

    func testUsageThresholdDoesNotCreateDashboardStatusText() {
        let presentation = DashboardAccountPresentation(
            row: makeRow(
                snapshot: makeSnapshot(
                    status: .warning,
                    limitWindows: [
                        UsageLimitWindow(id: "five-hour", displayName: "5-hour", usedPercent: 100)
                    ]
                )
            ),
            isStale: false,
            isGlobalRefresh: false
        )

        XCTAssertEqual(presentation.windows.first?.displayText, "100% used")
        XCTAssertNil(presentation.statusText)
    }

    private func makeRow(
        snapshot: UsageSnapshot?,
        providerID: String = "test",
        sourceMode: ProviderSourceMode = .claudeStatusLine,
        refreshStatus: ProviderRefreshStatus = .idle,
        refreshIssue: AccountRefreshIssue? = nil
    ) -> AccountSnapshotRow {
        let account = ProviderAccount(
            providerID: providerID,
            accountID: "work",
            displayName: "Work",
            isEnabled: true,
            sourceMode: sourceMode
        )
        return AccountSnapshotRow(
            account: account,
            providerDisplayName: "Test Provider",
            snapshot: snapshot,
            refreshStatus: refreshStatus,
            refreshIssue: refreshIssue
        )
    }

    private func makeSnapshot(
        status: UsageStatus = .ok,
        confidence: ConfidenceLevel = .live,
        remainingLabel: String? = nil,
        providerID: String = "test",
        accountID: String = "work",
        warnings: [String] = [],
        limitWindows: [UsageLimitWindow] = [
            UsageLimitWindow(id: "weekly", displayName: "7-day", usedPercent: 42)
        ]
    ) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            accountID: accountID,
            accountDisplayName: "Work",
            displayName: "Test Provider",
            status: status,
            remainingLabel: remainingLabel,
            limitWindows: limitWindows,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000_000),
            confidence: confidence,
            source: "Test source",
            warnings: warnings
        )
    }
}
