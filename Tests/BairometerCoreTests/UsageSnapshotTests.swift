import XCTest
@testable import BairometerCore

final class UsageSnapshotTests: XCTestCase {
    func testUsageLimitWindowRoundTripsThroughJSON() throws {
        let window = UsageLimitWindow(
            id: "rolling-5-hour",
            displayName: "5-hour",
            usedPercent: 64,
            remainingLabel: "Approx. 36% remaining",
            resetAt: Date(timeIntervalSince1970: 1_800)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(window)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UsageLimitWindow.self, from: data)

        XCTAssertEqual(decoded, window)
        XCTAssertEqual(decoded.id, "rolling-5-hour")
    }

    func testUsageSnapshotRoundTripsThroughJSON() throws {
        let snapshot = UsageSnapshot(
            providerID: "mock",
            accountID: "work",
            accountDisplayName: "Work",
            displayName: "Mock Provider",
            status: .ok,
            planName: "Development",
            periodLabel: "Rolling mock window",
            usedPercent: 42,
            remainingLabel: "Approx. 58% remaining",
            resetAt: Date(timeIntervalSince1970: 1_800),
            limitWindows: [
                UsageLimitWindow(
                    id: "weekly",
                    displayName: "Weekly",
                    usedPercent: 42,
                    remainingLabel: "Approx. 58% remaining",
                    resetAt: Date(timeIntervalSince1970: 1_800)
                )
            ],
            lastUpdatedAt: Date(timeIntervalSince1970: 1_200),
            confidence: .localEstimate,
            source: "Generated mock data",
            warnings: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.id, "mock:work")
        XCTAssertEqual(decoded.displayLimitWindows, snapshot.limitWindows)
    }

    func testLegacyUsageSnapshotBuildsDisplayLimitWindow() throws {
        let json = """
        {
          "providerID": "mock",
          "accountID": "work",
          "accountDisplayName": "Work",
          "displayName": "Mock Provider",
          "status": "ok",
          "planName": "Development",
          "periodLabel": "Rolling mock window",
          "usedPercent": 42,
          "remainingLabel": "Approx. 58% remaining",
          "resetAt": "1970-01-01T00:30:00Z",
          "lastUpdatedAt": "1970-01-01T00:20:00Z",
          "confidence": "local-estimate",
          "source": "Generated mock data",
          "warnings": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UsageSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.limitWindows, [])
        XCTAssertEqual(snapshot.displayLimitWindows, [
            UsageLimitWindow(
                id: "primary",
                displayName: "Rolling mock window",
                usedPercent: 42,
                remainingLabel: "Approx. 58% remaining",
                resetAt: Date(timeIntervalSince1970: 1_800)
            )
        ])
    }
}
