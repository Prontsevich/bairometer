import Foundation
import XCTest
@testable import BairometerCore

final class CodexAppServerProviderAdapterTests: XCTestCase {
    func testAppServerModeBuildsLiveSnapshotFromCurrentFixture() async throws {
        let payload = try fixture("codex-rate-limits-current")
        let adapter = CodexAppServerProviderAdapter(client: FixtureCodexClient(result: .success(payload)))
        let account = ProviderAccount(
            providerID: adapter.id,
            accountID: "work",
            displayName: "Work",
            isEnabled: true,
            sourceMode: .appServer
        )

        let snapshot = try await adapter.fetchSnapshot(account: account)

        XCTAssertEqual(snapshot.confidence, .live)
        XCTAssertEqual(snapshot.source, CodexRateLimitsParser.sourceDescription)
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.limitWindows.map(\.id), ["primary", "secondary"])
        XCTAssertEqual(snapshot.limitWindows.map(\.displayName), ["5-hour", "7-day"])
        XCTAssertEqual(snapshot.limitWindows.map(\.usedPercent), [24, 48])
        XCTAssertEqual(snapshot.warnings, [CodexRateLimitsParser.compatibilityWarning])
        XCTAssertNil(snapshot.planName)
        XCTAssertFalse(snapshot.warnings.joined(separator: " ").contains("secret balance"))
        XCTAssertFalse(snapshot.warnings.joined(separator: " ").contains("opaque-reset-credit"))
    }

    func testMissingSecondaryFixtureKeepsPrimaryWindow() throws {
        let parsed = try CodexRateLimitsParser.parse(fixture("codex-rate-limits-missing-secondary"))

        XCTAssertEqual(parsed.windows.map(\.id), ["primary"])
        XCTAssertTrue(parsed.warnings.isEmpty)
    }

    func testMultiBucketFixtureSelectsExplicitCodexBucket() throws {
        let parsed = try CodexRateLimitsParser.parse(fixture("codex-rate-limits-multi-bucket"))

        XCTAssertEqual(parsed.windows.map(\.usedPercent), [11, 22])
    }

    func testUnknownMultiBucketDoesNotFallbackToAnotherLimit() throws {
        XCTAssertThrowsError(try CodexRateLimitsParser.parse(fixture("codex-rate-limits-no-codex-bucket"))) {
            XCTAssertEqual($0 as? CodexRateLimitsParserError, .codexBucketUnavailable)
        }
    }

    func testInvalidPercentageDoesNotCreateQuotaWindow() throws {
        XCTAssertThrowsError(try CodexRateLimitsParser.parse(fixture("codex-rate-limits-invalid-percent"))) {
            XCTAssertEqual($0 as? CodexRateLimitsParserError, .noUsableWindows)
        }
    }

    func testMalformedFixtureReportsSafeAdapterDiagnostic() async throws {
        let malformedURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: "codex-rate-limits-malformed",
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(CodexRateLimitsPayload.self, from: Data(contentsOf: malformedURL))
        )

        let adapter = CodexAppServerProviderAdapter(
            client: FixtureCodexClient(result: .failure(.malformedResponse))
        )
        let account = ProviderAccount(
            providerID: adapter.id,
            isEnabled: true,
            sourceMode: .appServer
        )

        do {
            _ = try await adapter.fetchSnapshot(account: account)
            XCTFail("Expected malformed response to fail.")
        } catch let error as ProviderAdapterError {
            XCTAssertEqual(error.message, "Codex app-server returned an unsupported response.")
            XCTAssertEqual(error.recoverySuggestion, "Update Codex CLI and try refreshing again.")
            XCTAssertFalse(error.isTransient)
        }
    }

    func testTimeoutDiagnosticIsTransient() async throws {
        let adapter = CodexAppServerProviderAdapter(
            client: FixtureCodexClient(result: .failure(.timedOut))
        )
        let account = ProviderAccount(
            providerID: adapter.id,
            isEnabled: true,
            sourceMode: .appServer
        )

        do {
            _ = try await adapter.fetchSnapshot(account: account)
            XCTFail("Expected timeout to fail.")
        } catch let error as ProviderAdapterError {
            XCTAssertEqual(error.message, "Codex app-server timed out while reading rate limits.")
            XCTAssertTrue(error.isTransient)
        }
    }

    private func fixture(_ name: String) throws -> CodexRateLimitsPayload {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(CodexRateLimitsPayload.self, from: Data(contentsOf: url))
    }
}

private struct FixtureCodexClient: CodexAppServerClient {
    let result: Result<CodexRateLimitsPayload, CodexAppServerClientError>

    func fetchRateLimits(executablePath: String?) async throws -> CodexRateLimitsPayload {
        try result.get()
    }
}
