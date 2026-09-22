import BairometerCore
import XCTest
@testable import Bairometer

final class AccountDetailsDiagnosticsPresentationTests: XCTestCase {
    func testMiniMaxUnavailableSubscriptionIsOnlyPresentedAsSourceState() {
        let account = ProviderAccount(
            providerID: MiniMaxProviderContract.providerID,
            accountID: "account",
            displayName: "MiniMax",
            isEnabled: true,
            sourceMode: .miniMaxTokenPlan
        )
        let issue = AccountRefreshIssue(
            occurredAt: Date(timeIntervalSince1970: 1_000),
            warnings: [MiniMaxProviderContract.unavailableSubscriptionWarning]
        )

        XCTAssertTrue(
            AccountDetailsRefreshIssuePresentation.hasUnavailableSubscription(
                for: account,
                issue: issue
            )
        )
        XCTAssertNil(
            AccountDetailsRefreshIssuePresentation.diagnosticMessages(
                for: account,
                issue: issue,
                locale: Locale(identifier: "en_US")
            )
        )
    }

    func testNonMiniMaxRefreshWarningsRemainInDiagnostics() {
        let account = ProviderAccount(
            providerID: "other",
            accountID: "account",
            displayName: "Other",
            isEnabled: true
        )
        let issue = AccountRefreshIssue(
            occurredAt: Date(timeIntervalSince1970: 1_000),
            warnings: [MiniMaxProviderContract.unavailableSubscriptionWarning]
        )

        XCTAssertFalse(
            AccountDetailsRefreshIssuePresentation.hasUnavailableSubscription(
                for: account,
                issue: issue
            )
        )
        XCTAssertEqual(
            AccountDetailsRefreshIssuePresentation.diagnosticMessages(
                for: account,
                issue: issue,
                locale: Locale(identifier: "en_US")
            ),
            [MiniMaxProviderContract.unavailableSubscriptionWarning]
        )
    }

    func testSnapshotWarningsFilterUnavailableSubscriptionMarkerOnlyForMiniMax() {
        let miniMax = ProviderAccount(
            providerID: MiniMaxProviderContract.providerID,
            accountID: "minimax-account",
            displayName: "MiniMax",
            isEnabled: true,
            sourceMode: .miniMaxTokenPlan
        )
        let other = ProviderAccount(
            providerID: "other",
            accountID: "other-account",
            displayName: "Other",
            isEnabled: true
        )
        let warnings = [MiniMaxProviderContract.unavailableSubscriptionWarning]

        XCTAssertTrue(
            AccountDetailsRefreshIssuePresentation.snapshotWarnings(
                for: miniMax,
                warnings: warnings
            ).isEmpty
        )
        XCTAssertEqual(
            AccountDetailsRefreshIssuePresentation.snapshotWarnings(
                for: other,
                warnings: warnings
            ),
            warnings
        )
    }
}
