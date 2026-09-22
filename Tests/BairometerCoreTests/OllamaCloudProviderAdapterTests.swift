import XCTest
@testable import BairometerCore

final class OllamaCloudProviderAdapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testParserBuildsSessionAndWeeklyWindows() throws {
        let payload = OllamaUsagePagePayload(
            session: OllamaUsagePageWindowPayload(
                usedPercent: 42,
                resetAt: now.addingTimeInterval(3_600)
            ),
            weekly: OllamaUsagePageWindowPayload(
                usedPercent: 71,
                resetAt: now.addingTimeInterval(86_400)
            )
        )

        let windows = try OllamaUsagePageParser.limitWindows(from: payload, now: now)

        XCTAssertEqual(windows.map(\.id), ["session", "weekly"])
        XCTAssertEqual(windows.map(\.displayName), ["Session", "Weekly"])
        XCTAssertEqual(windows.map(\.usedPercent), [42, 71])
        XCTAssertEqual(windows[0].resetAt, now.addingTimeInterval(3_600))
        XCTAssertEqual(windows[1].resetAt, now.addingTimeInterval(86_400))
    }

    func testParserBuildsMonthlyWindowFromNewPageVariant() throws {
        let payload = OllamaUsagePagePayload(
            session: nil,
            weekly: nil,
            monthly: OllamaUsagePageMonthlyWindowPayload(
                usedPercent: 5.87,
                usedLabel: "$3.52",
                limitLabel: "$60",
                resetAt: now.addingTimeInterval(14 * 86_400)
            )
        )

        let windows = try OllamaUsagePageParser.limitWindows(from: payload, now: now)

        XCTAssertEqual(windows.map(\.id), ["monthly"])
        XCTAssertEqual(windows.map(\.displayName), ["Monthly"])
        XCTAssertEqual(windows.map(\.usedPercent), [5.87])
        XCTAssertEqual(windows[0].remainingLabel, "$3.52 of $60")
        XCTAssertEqual(windows[0].resetAt, now.addingTimeInterval(14 * 86_400))
    }

    func testParserCombinesLegacyAndMonthlyWindows() throws {
        let payload = OllamaUsagePagePayload(
            session: OllamaUsagePageWindowPayload(usedPercent: 42),
            weekly: OllamaUsagePageWindowPayload(usedPercent: 71),
            monthly: OllamaUsagePageMonthlyWindowPayload(
                usedPercent: 10,
                usedLabel: "$6",
                limitLabel: "$60"
            )
        )

        let windows = try OllamaUsagePageParser.limitWindows(from: payload, now: now)

        XCTAssertEqual(windows.map(\.id), ["session", "weekly", "monthly"])
        XCTAssertEqual(windows[2].remainingLabel, "$6 of $60")
    }

    func testParserRejectsMonthlyPercentageOutOfRange() {
        let payload = OllamaUsagePagePayload(
            session: nil,
            weekly: nil,
            monthly: OllamaUsagePageMonthlyWindowPayload(usedPercent: 101)
        )

        XCTAssertThrowsError(try OllamaUsagePageParser.limitWindows(from: payload, now: now)) { error in
            XCTAssertEqual(error as? OllamaUsagePageParseError, .invalidPercentage("Monthly"))
        }
    }

    func testParserRejectsPayloadWithoutAnyWindow() {
        let payload = OllamaUsagePagePayload(
            session: nil,
            weekly: nil,
            monthly: nil
        )

        XCTAssertThrowsError(try OllamaUsagePageParser.limitWindows(from: payload, now: now)) { error in
            XCTAssertEqual(error as? OllamaUsagePageParseError, .missingWindow("usage"))
        }
    }

    func testParserRejectsInvalidPercentage() {
        let payload = OllamaUsagePagePayload(
            session: OllamaUsagePageWindowPayload(usedPercent: 101),
            weekly: OllamaUsagePageWindowPayload(usedPercent: 50)
        )

        XCTAssertThrowsError(try OllamaUsagePageParser.limitWindows(from: payload, now: now)) { error in
            XCTAssertEqual(error as? OllamaUsagePageParseError, .invalidPercentage("Session"))
        }
    }

    func testParserRejectsMissingPercentage() {
        let payload = OllamaUsagePagePayload(
            session: OllamaUsagePageWindowPayload(usedPercent: nil),
            weekly: OllamaUsagePageWindowPayload(usedPercent: 50)
        )

        XCTAssertThrowsError(try OllamaUsagePageParser.limitWindows(from: payload, now: now)) { error in
            XCTAssertEqual(error as? OllamaUsagePageParseError, .missingPercentage("Session"))
        }
    }

    func testParserRejectsPastReset() {
        let payload = OllamaUsagePagePayload(
            session: OllamaUsagePageWindowPayload(
                usedPercent: 30,
                resetAt: now.addingTimeInterval(-1)
            ),
            weekly: OllamaUsagePageWindowPayload(usedPercent: 50)
        )

        XCTAssertThrowsError(try OllamaUsagePageParser.limitWindows(from: payload, now: now)) { error in
            XCTAssertEqual(error as? OllamaUsagePageParseError, .invalidReset("Session"))
        }
    }

    func testWebPageModeBuildsLiveSnapshotWithCompatibilityWarning() async throws {
        let payload = OllamaUsagePagePayload(
            session: OllamaUsagePageWindowPayload(usedPercent: 42),
            weekly: OllamaUsagePageWindowPayload(usedPercent: 71)
        )
        let adapter = OllamaCloudProviderAdapter(client: StubOllamaClient(payload: payload))
        let account = ProviderAccount(
            providerID: "ollama-cloud",
            accountID: "work",
            displayName: "Work",
            isEnabled: true,
            sourceMode: .ollamaWebPage,
            webDataStoreID: UUID()
        )

        let snapshot = try await adapter.fetchSnapshot(account: account)

        XCTAssertEqual(snapshot.confidence, .live)
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.limitWindows.map(\.id), ["session", "weekly"])
        XCTAssertEqual(snapshot.source, OllamaUsagePageParser.sourceDescription)
        XCTAssertEqual(snapshot.warnings, [OllamaUsagePageParser.compatibilityWarning])
    }

    func testWebPageModeRequiresConnectionProfile() async {
        let adapter = OllamaCloudProviderAdapter(client: StubOllamaClient(payload: nil))
        let account = ProviderAccount(
            providerID: "ollama-cloud",
            isEnabled: true,
            sourceMode: .ollamaWebPage
        )

        do {
            _ = try await adapter.fetchSnapshot(account: account)
            XCTFail("Expected missing connection error")
        } catch let error as ProviderAdapterError {
            XCTAssertEqual(error.message, "Ollama experimental web source is not connected.")
            XCTAssertFalse(error.isTransient)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct StubOllamaClient: OllamaWebPageClient {
    let payload: OllamaUsagePagePayload?

    func fetchUsage(account: ProviderAccount) async throws -> OllamaUsagePagePayload {
        guard let payload else {
            throw ProviderAdapterError(
                providerID: "ollama-cloud",
                message: "Stub client has no payload."
            )
        }
        return payload
    }
}
