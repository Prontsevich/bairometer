import Foundation
import XCTest
@testable import BairometerCore

final class ClaudeUsageCLIParserTests: XCTestCase {
    func testVerifiedClaudeCodeFixtureProducesStablePlanWindows() throws {
        let result = try fixture("claude-usage-2.1.207")
        let windows = try ClaudeUsageCLIParser.parse(
            result,
            now: utcDate(year: 2026, month: 7, day: 13, hour: 12)
        )

        XCTAssertEqual(windows.map(\.id), ["session", "weekly-all", "weekly-fable"])
        XCTAssertEqual(windows.map(\.displayName), [
            "Current session",
            "Current week (all models)",
            "Current week (Fable)"
        ])
        XCTAssertEqual(windows.map(\.usedPercent), [12, 34, 56])
        XCTAssertNil(windows[0].resetAt)
        XCTAssertEqual(windows[1].resetAt, utcDate(year: 2026, month: 7, day: 17, hour: 14))
        XCTAssertEqual(windows[2].resetAt, utcDate(year: 2026, month: 7, day: 18, hour: 14, minute: 30))
    }

    func testGenericModelWindowDoesNotRequireFable() throws {
        let windows = try ClaudeUsageCLIParser.parse(
            """
            Current session: 1% used
            Current week (all models): 2% used · resets Jul 20 at 4pm (UTC)
            Current week (Sonnet 4.5): 3% used · resets Jul 21 at 4pm (UTC)
            """,
            now: utcDate(year: 2026, month: 7, day: 13, hour: 12)
        )

        XCTAssertEqual(windows.map(\.id), ["session", "weekly-all", "weekly-sonnet-4-5"])
    }

    func testModelWindowMayOmitResetTime() throws {
        let windows = try ClaudeUsageCLIParser.parse(
            """
            Current session: 1% used
            Current week (all models): 2% used · resets Jul 20 at 4pm (UTC)
            Current week (Fable): 0% used
            """,
            now: utcDate(year: 2026, month: 7, day: 13, hour: 12)
        )

        XCTAssertEqual(windows.map(\.id), ["session", "weekly-all", "weekly-fable"])
        XCTAssertNil(windows[2].resetAt)
    }

    func testResetWithoutMinutesAndYearRollsForward() throws {
        let windows = try ClaudeUsageCLIParser.parse(
            """
            Current session: 1% used · resets 11pm (UTC)
            Current week (all models): 2% used · resets Jan 1 at 1am (UTC)
            """,
            now: utcDate(year: 2026, month: 12, day: 31, hour: 23, minute: 30)
        )

        XCTAssertEqual(windows[0].resetAt, utcDate(year: 2027, month: 1, day: 1, hour: 23))
        XCTAssertEqual(windows[1].resetAt, utcDate(year: 2027, month: 1, day: 1, hour: 1))
    }

    func testCollidingModelSlugsReceiveDeterministicSuffixes() throws {
        let input = """
        Current session: 1% used
        Current week (all models): 2% used · resets Jul 20 at 4pm (UTC)
        Current week (A+B): 3% used · resets Jul 21 at 4pm (UTC)
        Current week (A B): 4% used · resets Jul 22 at 4pm (UTC)
        """

        let first = try ClaudeUsageCLIParser.parse(
            input,
            now: utcDate(year: 2026, month: 7, day: 13, hour: 12)
        )
        let second = try ClaudeUsageCLIParser.parse(
            input,
            now: utcDate(year: 2026, month: 7, day: 13, hour: 12)
        )

        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertTrue(first[2].id.hasPrefix("weekly-a-b-"))
        XCTAssertTrue(first[3].id.hasPrefix("weekly-a-b-"))
        XCTAssertNotEqual(first[2].id, first[3].id)
    }

    func testMultilineANSIOutputIsNormalized() throws {
        let result = """
        \u{001B}[1mCurrent session\u{001B}[0m
        7% used

        Current week (all models)
        8% used
        Resets Jul 20 at 4pm (UTC)
        """

        let windows = try ClaudeUsageCLIParser.parse(
            result,
            now: utcDate(year: 2026, month: 7, day: 13, hour: 12)
        )

        XCTAssertEqual(windows.map(\.usedPercent), [7, 8])
    }

    func testSessionOnlyOutputIsRejected() {
        XCTAssertThrowsError(
            try ClaudeUsageCLIParser.parse(
                "Current session: 4% used",
                now: utcDate(year: 2026, month: 7, day: 13, hour: 12)
            )
        ) {
            XCTAssertEqual(
                $0 as? ClaudeUsageCLIParserError,
                .missingRequiredWindow("Current week (all models)")
            )
        }
    }

    func testInvalidPercentageResetAndDuplicateRequiredWindowFailClosed() {
        let now = utcDate(year: 2026, month: 7, day: 13, hour: 12)
        XCTAssertThrowsError(try ClaudeUsageCLIParser.parse(
            """
            Current session: 101% used
            Current week (all models): 2% used · resets Jul 20 at 4pm (UTC)
            """,
            now: now
        )) {
            XCTAssertEqual(
                $0 as? ClaudeUsageCLIParserError,
                .invalidPercentage("Current session")
            )
        }

        XCTAssertThrowsError(try ClaudeUsageCLIParser.parse(
            """
            Current session: 1% used
            Current week (all models): 2% used · resets someday
            """,
            now: now
        )) {
            XCTAssertEqual(
                $0 as? ClaudeUsageCLIParserError,
                .invalidReset("Current week (all models)")
            )
        }

        XCTAssertThrowsError(try ClaudeUsageCLIParser.parse(
            """
            Current session: 1% used
            Current session: 2% used
            Current week (all models): 3% used · resets Jul 20 at 4pm (UTC)
            """,
            now: now
        )) {
            XCTAssertEqual(
                $0 as? ClaudeUsageCLIParserError,
                .duplicateWindow("Current session")
            )
        }
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func utcDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
