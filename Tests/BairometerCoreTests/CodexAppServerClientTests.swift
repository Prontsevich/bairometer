import Foundation
import XCTest
@testable import BairometerCore

final class CodexAppServerClientTests: XCTestCase {
    func testAutomaticCandidatesUsePathBeforeStandardLocationsAndDeduplicate() {
        let home = URL(fileURLWithPath: "/tmp/codex-home")

        let candidates = CodexExecutableLocator.automaticCandidates(
            path: "/custom/bin:/opt/homebrew/bin:/custom/bin",
            homeDirectory: home
        )

        XCTAssertEqual(candidates.map(\.path), [
            "/custom/bin/codex",
            "/opt/homebrew/bin/codex",
            "/tmp/codex-home/.local/bin/codex",
            "/tmp/codex-home/.local/share/mise/shims/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ])
    }

    func testConfiguredExecutableTakesPrecedence() throws {
        let executableURL = try temporaryExecutable(
            body: "#!/bin/sh\nexit 0\n",
            filename: "codex"
        )

        let located = try CodexExecutableLocator().locate(executablePath: executableURL.path)

        XCTAssertEqual(located, executableURL)
    }

    func testConfiguredMissingExecutableDoesNotFallbackToAutomaticDiscovery() {
        XCTAssertThrowsError(
            try CodexExecutableLocator().locate(executablePath: "/missing/codex")
        ) {
            XCTAssertEqual($0 as? CodexAppServerClientError, .configuredExecutableNotFound)
        }
    }

    func testProcessClientCompletesJSONLHandshakeAndReadsRateLimits() async throws {
        let workingDirectoryURL = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executableURL = try temporaryExecutable(
            body: """
            #!/bin/sh
            if [ "$(pwd -P)" = "$EXPECTED_WORKING_DIRECTORY" ]; then
                used_percent=37
            else
                used_percent=99
            fi
            IFS= read -r initialize
            printf '%s\\n' '{"id":1,"result":{}}'
            IFS= read -r initialized
            IFS= read -r rate_limits
            printf '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":%s,"windowDurationMins":300,"resetsAt":1900000000},"secondary":null}}}\\n' "$used_percent"
            """,
            filename: "codex"
        )
        let client = ProcessCodexAppServerClient(
            timeout: 2,
            environment: {
                [
                    "EXPECTED_WORKING_DIRECTORY": workingDirectoryURL.path,
                    "PWD": "/Users/example/Documents",
                    "OLDPWD": "/Users/example/Downloads",
                    "INIT_CWD": "/Users/example/Music"
                ]
            },
            workingDirectoryURL: workingDirectoryURL
        )

        let payload = try await client.fetchRateLimits(executablePath: executableURL.path)

        XCTAssertEqual(payload.rateLimits.limitID, "codex")
        XCTAssertEqual(payload.rateLimits.primary?.usedPercent, 37)
        XCTAssertNil(payload.rateLimits.secondary)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workingDirectoryURL.path))
    }

    func testProcessIsolationNormalizesInheritedDirectoryHints() {
        let workingDirectoryURL = URL(fileURLWithPath: "/private/tmp/Bairometer/ProviderCLI")

        let environment = ProviderCLIProcessIsolation.isolatedEnvironment(
            from: [
                "HOME": "/Users/example",
                "PWD": "/Users/example/Documents",
                "OLDPWD": "/Users/example/Downloads",
                "INIT_CWD": "/Users/example/Music"
            ],
            workingDirectoryURL: workingDirectoryURL
        )

        XCTAssertEqual(environment["HOME"], "/Users/example")
        XCTAssertEqual(environment["PWD"], workingDirectoryURL.path)
        XCTAssertNil(environment["OLDPWD"])
        XCTAssertNil(environment["INIT_CWD"])
    }

    private func temporaryExecutable(body: String, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent(filename)
        try Data(body.utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        return executableURL
    }
}
