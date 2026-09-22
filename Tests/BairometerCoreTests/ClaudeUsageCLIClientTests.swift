import Foundation
import XCTest
@testable import BairometerCore

final class ClaudeUsageCLIClientTests: XCTestCase {
    func testAutomaticCandidatesUsePathBeforeStandardLocationsAndDeduplicate() {
        let home = URL(fileURLWithPath: "/tmp/claude-home")

        let candidates = ClaudeExecutableLocator.automaticCandidates(
            path: "/custom/bin:/opt/homebrew/bin:/custom/bin",
            homeDirectory: home
        )

        XCTAssertEqual(candidates.map(\.path), [
            "/custom/bin/claude",
            "/opt/homebrew/bin/claude",
            "/tmp/claude-home/.local/bin/claude",
            "/tmp/claude-home/.local/share/mise/shims/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ])
    }

    func testConfiguredExecutableTakesPrecedenceAndMissingOverrideDoesNotFallback() throws {
        let executableURL = try temporaryExecutable(body: "#!/bin/sh\nexit 0\n")
        XCTAssertEqual(
            try ClaudeExecutableLocator().locate(executablePath: executableURL.path),
            executableURL
        )
        XCTAssertThrowsError(
            try ClaudeExecutableLocator().locate(executablePath: "/missing/claude")
        ) {
            XCTAssertEqual($0 as? ClaudeUsageCLIClientError, .configuredExecutableNotFound)
        }
    }

    func testProcessClientUsesSafeArgumentsLocaleAndDecodesEnvelope() async throws {
        let workingDirectoryURL = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executableURL = try temporaryExecutable(body: """
        #!/bin/sh
        [ "$#" -eq 8 ] || exit 31
        [ "$1" = "--safe-mode" ] || exit 32
        [ "$2" = "-p" ] || exit 33
        [ "$3" = "/usage" ] || exit 34
        [ "$4" = "--output-format" ] || exit 35
        [ "$5" = "json" ] || exit 36
        [ "$6" = "--tools" ] || exit 37
        [ -z "$7" ] || exit 38
        [ "$8" = "--no-session-persistence" ] || exit 39
        [ "$TZ" = "UTC" ] || exit 40
        [ "$LC_ALL" = "en_US.UTF-8" ] || exit 41
        [ "$LANG" = "en_US.UTF-8" ] || exit 42
        printf '{"type":"result","subtype":"success","is_error":false,"result":"%s","num_turns":0,"total_cost_usd":0,"usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"modelUsage":{}}' "$(pwd -P)"
        """)
        let client = ProcessClaudeUsageCLIClient(
            timeout: 2,
            environment: {
                [
                    "PATH": "/usr/bin",
                    "HOME": "/tmp",
                    "EXPECTED_WORKING_DIRECTORY": workingDirectoryURL.path,
                    "PWD": "/Users/example/Documents",
                    "OLDPWD": "/Users/example/Downloads",
                    "INIT_CWD": "/Users/example/Music"
                ]
            },
            workingDirectoryURL: workingDirectoryURL
        )

        let envelope = try await client.fetchUsage(executablePath: executableURL.path)

        XCTAssertEqual(envelope.numTurns, 0)
        XCTAssertEqual(envelope.usage.totalTokens, 0)
        XCTAssertEqual(envelope.result, workingDirectoryURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workingDirectoryURL.path))
    }

    func testNonZeroInferenceMetadataIsRejected() async throws {
        let executableURL = try temporaryExecutable(body: shellReturningEnvelope(
            numTurns: 1,
            totalCostUSD: 0,
            inputTokens: 0
        ))
        let client = ProcessClaudeUsageCLIClient(timeout: 2)

        do {
            _ = try await client.fetchUsage(executablePath: executableURL.path)
            XCTFail("Expected inference metadata rejection.")
        } catch let error as ClaudeUsageCLIClientError {
            XCTAssertEqual(error, .inferenceActivityDetected)
        }
    }

    func testAuthenticationFailureIsSanitized() async throws {
        let executableURL = try temporaryExecutable(body: """
        #!/bin/sh
        printf '%s' '{"type":"result","subtype":"error","is_error":true,"result":"Please login to continue","num_turns":0,"total_cost_usd":0,"usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}'
        """)
        let client = ProcessClaudeUsageCLIClient(timeout: 2)

        do {
            _ = try await client.fetchUsage(executablePath: executableURL.path)
            XCTFail("Expected authentication failure.")
        } catch let error as ClaudeUsageCLIClientError {
            XCTAssertEqual(error, .authenticationUnavailable)
            XCTAssertFalse(error.localizedDescription.contains("Please login"))
        }
    }

    func testNonZeroExitIsSanitizedAndTransient() async throws {
        let executableURL = try temporaryExecutable(body: shellReturningEnvelope(
            numTurns: 0,
            totalCostUSD: 0,
            inputTokens: 0
        ) + "\nexit 7\n")
        let client = ProcessClaudeUsageCLIClient(timeout: 2)

        do {
            _ = try await client.fetchUsage(executablePath: executableURL.path)
            XCTFail("Expected process exit failure.")
        } catch let error as ClaudeUsageCLIClientError {
            XCTAssertEqual(error, .processExited)
            XCTAssertTrue(error.isTransient)
            XCTAssertFalse(error.localizedDescription.contains("Current session"))
        }
    }

    func testMalformedAndOversizedResponsesFailClosed() async throws {
        let malformedURL = try temporaryExecutable(body: "#!/bin/sh\nprintf '%s' '{bad json'\n")
        let malformedClient = ProcessClaudeUsageCLIClient(timeout: 2)
        do {
            _ = try await malformedClient.fetchUsage(executablePath: malformedURL.path)
            XCTFail("Expected malformed response failure.")
        } catch let error as ClaudeUsageCLIClientError {
            XCTAssertEqual(error, .malformedResponse)
        }

        let oversizedURL = try temporaryExecutable(body: "#!/bin/sh\nprintf '%0100d' 0\n")
        let oversizedClient = ProcessClaudeUsageCLIClient(timeout: 2, responseLimit: 32)
        do {
            _ = try await oversizedClient.fetchUsage(executablePath: oversizedURL.path)
            XCTFail("Expected oversized response failure.")
        } catch let error as ClaudeUsageCLIClientError {
            XCTAssertEqual(error, .responseTooLarge)
        }
    }

    func testTimeoutAndCancellationTerminateTheProcess() async throws {
        let executableURL = try temporaryExecutable(body: "#!/bin/sh\nexec /bin/sleep 5\n")
        let timeoutClient = ProcessClaudeUsageCLIClient(timeout: 0.05)
        do {
            _ = try await timeoutClient.fetchUsage(executablePath: executableURL.path)
            XCTFail("Expected timeout failure.")
        } catch let error as ClaudeUsageCLIClientError {
            XCTAssertEqual(error, .timedOut)
        }

        let cancellationClient = ProcessClaudeUsageCLIClient(timeout: 5)
        let task = Task {
            try await cancellationClient.fetchUsage(executablePath: executableURL.path)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testStderrIsDiscardedWhileValidStdoutSucceeds() async throws {
        let executableURL = try temporaryExecutable(body: """
        #!/bin/sh
        printf '%s' 'private stderr value' >&2
        printf '%s' '{"type":"result","subtype":"success","is_error":false,"result":"Current session: 1% used\\nCurrent week (all models): 2% used · resets Jul 20 at 4pm (UTC)","num_turns":0,"total_cost_usd":0,"usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}'
        """)
        let client = ProcessClaudeUsageCLIClient(timeout: 2)

        let envelope = try await client.fetchUsage(executablePath: executableURL.path)

        XCTAssertFalse(envelope.result.contains("private stderr value"))
    }

    private func shellReturningEnvelope(
        numTurns: Int,
        totalCostUSD: Double,
        inputTokens: Int
    ) -> String {
        """
        #!/bin/sh
        printf '%s' '{"type":"result","subtype":"success","is_error":false,"result":"Current session: 1% used\\nCurrent week (all models): 2% used · resets Jul 20 at 4pm (UTC)","num_turns":\(numTurns),"total_cost_usd":\(totalCostUSD),"usage":{"input_tokens":\(inputTokens),"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}'
        """
    }

    private func temporaryExecutable(body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("claude")
        try Data(body.utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        return executableURL
    }
}
