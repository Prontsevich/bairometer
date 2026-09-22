#if DEBUG
import BairometerCore
import Foundation
import XCTest
@testable import Bairometer

final class KeychainVerificationCommandTests: XCTestCase {
    func testCreateFailsClosedWithoutReplacingAnExistingCredentialFreeAccount() throws {
        let directory = temporaryDirectory()
        let existingAccount = ProviderAccount(
            providerID: "mock",
            accountID: "existing",
            displayName: "Existing account",
            isEnabled: true
        )
        let database = try AppDatabase(directory: directory)
        let accountStore = DatabaseProviderConfigurationStore(database: database)
        try accountStore.save([existingAccount])
        let keychain = VerificationKeychainService()
        let command = KeychainVerificationCommand(
            operation: .create,
            storageDirectory: directory,
            keychainService: keychain
        )

        XCTAssertThrowsError(try command.run()) {
            XCTAssertEqual($0 as? CredentialStoreError, .storageUnavailable)
        }
        XCTAssertEqual(
            accountStore.load(knownProviderIDs: ["mock"]).accounts,
            [existingAccount]
        )
        XCTAssertEqual(try accountStore.accountCount(), 1)
        XCTAssertTrue(keychain.isEmpty)
    }

    func testReplaceAndDeleteRejectAnyAdditionalAccount() throws {
        let directory = temporaryDirectory()
        let keychain = VerificationKeychainService()
        let create = KeychainVerificationCommand(
            operation: .create,
            storageDirectory: directory,
            keychainService: keychain
        )
        let reference = try XCTUnwrap(create.run())
        let originalValue = try keychain.value(reference: reference)

        let database = try AppDatabase(directory: directory)
        let accountStore = DatabaseProviderConfigurationStore(database: database)
        let temporaryAccount = try XCTUnwrap(
            accountStore.load(
                knownProviderIDs: ["keychain-verification"]
            ).accounts.first
        )
        let unrelatedAccount = ProviderAccount(
            providerID: "mock",
            accountID: "existing",
            displayName: "Existing account",
            isEnabled: true
        )
        try accountStore.save([temporaryAccount, unrelatedAccount])

        for operation in [
            KeychainVerificationCommand.Operation.replace,
            .delete
        ] {
            let command = KeychainVerificationCommand(
                operation: operation,
                storageDirectory: directory,
                keychainService: keychain
            )
            XCTAssertThrowsError(try command.run()) {
                XCTAssertEqual($0 as? CredentialStoreError, .storageUnavailable)
            }
        }

        XCTAssertEqual(try accountStore.accountCount(), 2)
        XCTAssertEqual(try keychain.value(reference: reference), originalValue)
    }

    func testDebugStagingUsesAuthorizedAppleDevelopmentSigningForDPK() throws {
        let script = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("script/stage_app_bundle.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains("-allowProvisioningUpdates"))
        XCTAssertTrue(script.contains("-allowProvisioningDeviceRegistration"))
        XCTAssertTrue(script.contains("embedded.provisionprofile"))
        XCTAssertTrue(script.contains("Apple Development:"))
        XCTAssertTrue(script.contains("com.apple.application-identifier"))
        XCTAssertTrue(script.contains("keychain-access-groups"))
        XCTAssertTrue(script.contains("--entitlements \"$SIGNING_ENTITLEMENTS\""))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(
            script.contains(
                "DEVELOPMENT_TEAM=\"${BAIROMETER_DEVELOPMENT_TEAM:-}\""
            )
        )
        XCTAssertTrue(
            script.contains(
                "error: DEBUG staging requires BAIROMETER_DEVELOPMENT_TEAM."
            )
        )
        XCTAssertTrue(
            script.contains(
                "BAIROMETER_DEVELOPMENT_TEAM=YOUR_TEAM_ID"
            )
        )
        XCTAssertFalse(script.contains("LOCAL_AD_HOC_REQUIREMENT"))
        XCTAssertFalse(script.contains("--requirements"))
    }

    func testLocalSigningSupportRequestsOnlyTheAppDefaultKeychainGroup() throws {
        let supportDirectory = repositoryRoot
            .appendingPathComponent("Support/LocalSigning")
        let entitlements = try String(
            contentsOf: supportDirectory
                .appendingPathComponent("BairometerLocalSigning.entitlements"),
            encoding: .utf8
        )
        let project = try String(
            contentsOf: supportDirectory
                .appendingPathComponent(
                    "BairometerLocalSigning.xcodeproj/project.pbxproj"
                ),
            encoding: .utf8
        )

        XCTAssertTrue(entitlements.contains("<key>keychain-access-groups</key>"))
        XCTAssertTrue(
            entitlements.contains(
                "$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)"
            )
        )
        XCTAssertFalse(entitlements.contains("application-identifier"))
        XCTAssertFalse(entitlements.contains("com.apple.security.app-sandbox"))
        XCTAssertTrue(project.contains("com.apple.Keychain"))
        XCTAssertFalse(project.contains("DEVELOPMENT_TEAM ="))
        XCTAssertTrue(
            project.contains(
                "PRODUCT_BUNDLE_IDENTIFIER = io.github.Prontsevich.Bairometer;"
            )
        )
        XCTAssertTrue(project.contains("CODE_SIGN_STYLE = Automatic;"))
        XCTAssertTrue(project.contains("CODE_SIGN_IDENTITY = \"Apple Development\";"))
    }

    func testSigningDocumentationUsesOnlyExplicitTeamPlaceholder() throws {
        let agents = try String(
            contentsOf: repositoryRoot.appendingPathComponent("AGENTS.md"),
            encoding: .utf8
        )
        let plan = try String(
            contentsOf: repositoryRoot.appendingPathComponent("docs/plan.md"),
            encoding: .utf8
        )
        let contributing = try String(
            contentsOf: repositoryRoot.appendingPathComponent("CONTRIBUTING.md"),
            encoding: .utf8
        )

        for document in [agents, plan, contributing] {
            XCTAssertTrue(
                document.contains(
                    "BAIROMETER_DEVELOPMENT_TEAM=YOUR_TEAM_ID"
                )
            )
        }
        XCTAssertTrue(
            agents.contains(
                "Release staging requires an explicit Developer ID Application identity"
            )
        )
        XCTAssertTrue(contributing.contains("Apple Development"))
        XCTAssertTrue(contributing.contains("Xcode-managed provisioning profile"))
        XCTAssertTrue(contributing.contains("BAIROMETER_DEVELOPER_IDENTITY"))
        XCTAssertTrue(contributing.contains("BAIROMETER_PROVISIONING_PROFILE"))
        XCTAssertTrue(contributing.contains("BAIROMETER_NOTARYTOOL_PROFILE"))
        XCTAssertTrue(contributing.contains("YOUR_NOTARYTOOL_PROFILE"))
        XCTAssertTrue(
            contributing.contains(
                "notarize_release.sh 0.2.0 20260813.1 arm64"
            )
        )

        let prohibitedProfile = ["Bairometer", "Notary"].joined(separator: "-")
        for document in [agents, plan, contributing] {
            XCTAssertFalse(document.contains(prohibitedProfile))
        }
    }

    func testReleaseStagingRequiresAuthorizedDeveloperIDSigning() throws {
        let script = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("script/stage_app_bundle.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains("BAIROMETER_DEVELOPER_IDENTITY"))
        XCTAssertTrue(script.contains("BAIROMETER_PROVISIONING_PROFILE"))
        XCTAssertTrue(script.contains("ProvisionsAllDevices"))
        XCTAssertTrue(script.contains("DeveloperCertificates.0"))
        XCTAssertTrue(script.contains("PROFILE_CERTIFICATE_SHA1"))
        XCTAssertTrue(script.contains("--options runtime"))
        XCTAssertTrue(script.contains("--timestamp"))
        XCTAssertTrue(script.contains("com.apple.application-identifier"))
        XCTAssertTrue(script.contains("com.apple.developer.team-identifier"))
        XCTAssertTrue(script.contains("keychain-access-groups"))
        XCTAssertTrue(
            script.contains(
                "script/validate_release_entitlements.sh"
            )
        )
        XCTAssertTrue(
            script.contains(
                "Staged $APP_BUNDLE (Developer ID; profile $PROFILE_NAME)"
            )
        )
        XCTAssertFalse(script.contains("--sign - --timestamp=none"))
        XCTAssertFalse(script.contains("non-credential-capable ad-hoc release"))
    }

    func testReleasePackagingRevalidatesDeveloperIDAfterArchiveRoundTrip() throws {
        let packageScript = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("script/package_release.sh"),
            encoding: .utf8
        )
        let validator = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("script/validate_release_bundle.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(packageScript.contains("script/validate_release_bundle.sh"))
        XCTAssertTrue(packageScript.contains("--signed-submission"))
        XCTAssertTrue(validator.contains("embedded.provisionprofile"))
        XCTAssertTrue(validator.contains("Authority=$EXPECTED_IDENTITY"))
        XCTAssertTrue(validator.contains("TeamIdentifier=$EXPECTED_TEAM"))
        XCTAssertTrue(validator.contains("flags="))
        XCTAssertTrue(validator.contains("runtime"))
        XCTAssertTrue(validator.contains("Timestamp="))
        XCTAssertTrue(validator.contains("script/validate_release_entitlements.sh"))
        XCTAssertTrue(validator.contains("--verify"))
        XCTAssertTrue(validator.contains("--deep"))
        XCTAssertTrue(validator.contains("--strict"))
    }

    func testNotarizationRequiresExplicitProfileAndAcceptedSubmission() throws {
        let scriptURL = repositoryRoot
            .appendingPathComponent("script/notarize_release.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("BAIROMETER_NOTARYTOOL_PROFILE"))
        XCTAssertTrue(script.contains("notarytool submit"))
        XCTAssertTrue(script.contains("--wait"))
        XCTAssertTrue(script.contains("--output-format json"))
        XCTAssertTrue(script.contains("SUBMISSION_STATUS\" != \"Accepted"))
        XCTAssertTrue(script.contains("stapler staple"))
        XCTAssertTrue(script.contains("--require-notarization"))
        XCTAssertTrue(script.contains("-signed.zip"))
        XCTAssertTrue(script.contains("PUBLISH_PREFIX"))
        XCTAssertTrue(script.contains("/usr/bin/mktemp"))
        XCTAssertTrue(script.contains("PUBLISH_COMPARE_COMMAND"))
        XCTAssertTrue(script.contains("PUBLISH_RENAME_COMMAND"))
        XCTAssertTrue(script.contains("BAIROMETER_NOTARIZATION_TEST_MODE"))
        XCTAssertTrue(script.contains("PUBLISH_COPY_COMMAND=\"/bin/cp\""))
        XCTAssertTrue(script.contains("PUBLISH_COMPARE_COMMAND=\"/usr/bin/cmp\""))
        XCTAssertTrue(script.contains("PUBLISH_RENAME_COMMAND=\"/bin/mv\""))
        XCTAssertTrue(script.contains("final archive path is obstructed"))
        XCTAssertTrue(script.contains("published release is not a nonempty regular file"))

        let result = try runScript(
            scriptURL,
            arguments: ["0.2.0", "1", "arm64"],
            removingEnvironment: ["BAIROMETER_NOTARYTOOL_PROFILE"]
        )
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(
            result.output.contains(
                "notarization requires BAIROMETER_NOTARYTOOL_PROFILE"
            ),
            result.output
        )
    }

    func testNotarizationFixturesFailClosedWithoutAppleServices() throws {
        let fixtureTest = repositoryRoot
            .appendingPathComponent("script/test_notarize_release.sh")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: fixtureTest.path)
        )
        let result = try runScript(fixtureTest, arguments: [])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("PASS: notarization fixtures"))
    }

    func testReleaseEntrypointFailsClosedWithoutSigningInputs() throws {
        let script = repositoryRoot
            .appendingPathComponent("script/package_release.sh")
        let removedEnvironment: Set<String> = [
            "BAIROMETER_DEVELOPMENT_TEAM",
            "BAIROMETER_DEVELOPER_IDENTITY",
            "BAIROMETER_PROVISIONING_PROFILE"
        ]
        let cases: [([String: String], String)] = [
            (
                [:],
                "RELEASE staging requires BAIROMETER_DEVELOPMENT_TEAM."
            ),
            (
                ["BAIROMETER_DEVELOPMENT_TEAM": "TEST_TEAM"],
                "RELEASE staging requires BAIROMETER_DEVELOPER_IDENTITY."
            ),
            (
                [
                    "BAIROMETER_DEVELOPMENT_TEAM": "TEST_TEAM",
                    "BAIROMETER_DEVELOPER_IDENTITY":
                        "Developer ID Application: Test Identity (TEST_TEAM)"
                ],
                "RELEASE staging requires an existing BAIROMETER_PROVISIONING_PROFILE."
            )
        ]

        for (environment, expectedError) in cases {
            let result = try runScript(
                script,
                arguments: ["0.2.0", "1", "arm64"],
                removingEnvironment: removedEnvironment,
                environmentOverrides: environment
            )

            XCTAssertNotEqual(result.status, 0)
            XCTAssertTrue(
                result.output.contains(expectedError),
                result.output
            )
        }
    }

    func testReleaseEntitlementValidatorIsExactAndOrderIndependent() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let appIdentifier = "TEST_TEAM.io.example.Bairometer"
        let appIdentifierEntry = """
          <key>com.apple.application-identifier</key>
          <string>\(appIdentifier)</string>
        """
        let teamEntry = """
          <key>com.apple.developer.team-identifier</key>
          <string>TEST_TEAM</string>
        """
        let keychainEntry = """
          <key>keychain-access-groups</key>
          <array>
            <string>\(appIdentifier)</string>
          </array>
        """
        let validator = repositoryRoot
            .appendingPathComponent("script/validate_release_entitlements.sh")

        for (name, entries) in [
            ("expected-order", [appIdentifierEntry, teamEntry, keychainEntry]),
            ("reordered", [keychainEntry, appIdentifierEntry, teamEntry])
        ] {
            let fixture = try writeEntitlements(
                entries,
                name: name,
                directory: directory
            )
            let result = try runScript(
                validator,
                arguments: [fixture.path, "TEST_TEAM", "io.example.Bairometer"]
            )
            XCTAssertEqual(result.status, 0, "\(name): \(result.output)")
        }

        let invalidFixtures: [(String, [String])] = [
            ("missing-team", [appIdentifierEntry, keychainEntry]),
            (
                "wrong-value",
                [
                    appIdentifierEntry.replacingOccurrences(
                        of: appIdentifier,
                        with: "TEST_TEAM.io.example.Other"
                    ),
                    teamEntry,
                    keychainEntry
                ]
            ),
            (
                "extra-key",
                [
                    appIdentifierEntry,
                    teamEntry,
                    keychainEntry,
                    "<key>unexpected</key><dict><key>nested</key><true/></dict>"
                ]
            ),
            (
                "extra-keychain-group",
                [
                    appIdentifierEntry,
                    teamEntry,
                    """
                      <key>keychain-access-groups</key>
                      <array>
                        <string>\(appIdentifier)</string>
                        <string>TEST_TEAM.io.example.Other</string>
                      </array>
                    """
                ]
            )
        ]

        for (name, entries) in invalidFixtures {
            let fixture = try writeEntitlements(
                entries,
                name: name,
                directory: directory
            )
            let result = try runScript(
                validator,
                arguments: [fixture.path, "TEST_TEAM", "io.example.Bairometer"]
            )
            XCTAssertNotEqual(result.status, 0, "\(name) unexpectedly passed")
        }
    }

    func testProtectedReleaseWorkflowFixtures() throws {
        let fixtureTest = repositoryRoot
            .appendingPathComponent("script/test_release_workflow.sh")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: fixtureTest.path)
        )
        let result = try runScript(fixtureTest, arguments: [])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("PASS: protected release workflow fixtures")
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func writeEntitlements(
        _ entries: [String],
        name: String,
        directory: URL
    ) throws -> URL {
        let url = directory.appendingPathComponent("\(name).plist")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(entries.joined(separator: "\n"))
        </dict>
        </plist>
        """
        try plist.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func runScript(
        _ script: URL,
        arguments: [String],
        removingEnvironment removedKeys: Set<String> = [],
        environmentOverrides: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        var environment = ProcessInfo.processInfo.environment
        for key in removedKeys {
            environment.removeValue(forKey: key)
        }
        for (key, value) in environmentOverrides {
            environment[key] = value
        }

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.currentDirectoryURL = repositoryRoot
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(decoding: data, as: UTF8.self)
        )
    }
}

private final class VerificationKeychainService: KeychainService, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return items.isEmpty
    }

    func value(reference: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let value = items[reference] else {
            throw KeychainServiceError.credentialNotFound
        }
        return value
    }

    func createCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        let value = try credential.withUTF8String { $0 }
        lock.lock()
        defer { lock.unlock() }
        guard items[reference] == nil else {
            throw KeychainServiceError.duplicateReference
        }
        items[reference] = value
    }

    func readCredential(reference: String) throws -> CredentialSecret {
        try CredentialSecret(value(reference: reference))
    }

    func replaceCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        let value = try credential.withUTF8String { $0 }
        lock.lock()
        defer { lock.unlock() }
        guard items[reference] != nil else {
            throw KeychainServiceError.credentialNotFound
        }
        items[reference] = value
    }

    func deleteCredential(reference: String) throws {
        lock.lock()
        items.removeValue(forKey: reference)
        lock.unlock()
    }
}
#endif
