#if DEBUG
import BairometerCore
import Foundation
import XCTest
@testable import Bairometer

@MainActor
final class OpenRouterAppIntegrationTests: XCTestCase {
    func testManualScheduledAndLaunchRefreshUseHierarchicalOpenRouterPath() async throws {
        let directory = temporaryDirectory()
        let keychain = AppIntegrationKeychain()
        let client = CountingSyntheticOpenRouterClient()
        let model = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            refreshCoordinator: ProviderRefreshCoordinator(
                retryPolicy: ProviderRetryPolicy(
                    maxAttempts: 1,
                    initialDelay: 0
                )
            ),
            openRouterAPIClient: client,
            credentialKeychainService: keychain
        )
        let account = try XCTUnwrap(
            model.addAccount(
                providerID: "openrouter",
                displayName: "OpenRouter"
            )
        )
        try configureCredentials(model: model, account: account)

        model.refreshAccount(
            providerID: account.providerID,
            accountID: account.accountID
        )
        await model.waitForRefreshCompletionForTesting()
        let manualCallCount = await client.callCount
        XCTAssertEqual(manualCallCount, 2)
        XCTAssertNotNil(try nativeSnapshot(model: model, account: account))

        model.setRefreshInterval(.oneMinute)
        XCTAssertNotNil(model.scheduledRefreshTimer)
        model.scheduledRefreshTimer?.fire()
        await client.waitForCallCount(4)
        await model.waitForRefreshCompletionForTesting()

        let relaunched = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            refreshCoordinator: ProviderRefreshCoordinator(
                retryPolicy: ProviderRetryPolicy(
                    maxAttempts: 1,
                    initialDelay: 0
                )
            ),
            openRouterAPIClient: client,
            credentialKeychainService: keychain
        )
        XCTAssertEqual(
            relaunched.providerAccounts.first(where: {
                $0.providerID == account.providerID
                    && $0.accountID == account.accountID
            })?.sourceMode,
            .openRouterAPI
        )
        let runtime = AppRuntime(appModelForTesting: relaunched)
        runtime.start()
        runtime.start()
        await relaunched.waitForRefreshCompletionForTesting()
        XCTAssertTrue(relaunched.hasStartedLaunchRefresh)
        let launchCallCount = await client.callCount
        XCTAssertEqual(launchCallCount, 6)
        let relaunchedSnapshot = try XCTUnwrap(
            try nativeSnapshot(model: relaunched, account: account)
        )
        XCTAssertEqual(relaunchedSnapshot.savedAccountID, account.accountID)
        XCTAssertTrue(
            relaunchedSnapshot.metrics.contains {
                $0.metricID == "account-credits"
                    && $0.accountContextID == "\(account.accountID)-root"
            }
        )
    }

    func testDebugVerificationCommandUsesDisposableSyntheticStorageOnly() async throws {
        let directory = disposableVerificationDirectory()
        let sawOwnedDirectory = LockedBoolean()
        let command = OpenRouterVerificationCommand(
            storageDirectory: directory,
            postCreationCheckpoint: {
                sawOwnedDirectory.set(
                    FileManager.default.fileExists(atPath: directory.path)
                )
            }
        )

        try await command.run()

        XCTAssertTrue(sawOwnedDirectory.value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDebugVerificationCommandCleansUpAfterFailure() async {
        let directory = disposableVerificationDirectory()
        let command = OpenRouterVerificationCommand(
            storageDirectory: directory,
            postCreationCheckpoint: {
                throw AppIntegrationTestError.injected
            }
        )

        do {
            try await command.run()
            XCTFail("Expected injected failure.")
        } catch AppIntegrationTestError.injected {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDebugVerificationCommandParserRequiresStrictDisposableStorage() throws {
        XCTAssertNil(
            try OpenRouterVerificationCommand.validated(arguments: ["Bairometer"])
        )
        let directory = disposableVerificationDirectory()
        XCTAssertEqual(
            try OpenRouterVerificationCommand.validated(arguments: [
                "Bairometer",
                OpenRouterVerificationCommand.argument,
                AppLaunchOptions.storageDirectoryArgument,
                directory.path
            ])?.storageDirectory.path,
            directory.path
        )
    }

    func testDebugVerificationCommandRejectsUnsafeStorageTargets() throws {
        let validExisting = disposableVerificationDirectory()
        try FileManager.default.createDirectory(
            at: validExisting,
            withIntermediateDirectories: false
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: validExisting)
        }
        let workspace = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let production = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Bairometer",
                isDirectory: true
            )
        for unsafe in [
            URL(fileURLWithPath: "/", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser,
            workspace,
            production,
            validExisting,
            FileManager.default.temporaryDirectory
                .appendingPathComponent("openrouter-verification", isDirectory: true)
        ] {
            XCTAssertThrowsError(
                try OpenRouterVerificationCommand.validated(arguments: [
                    "Bairometer",
                    OpenRouterVerificationCommand.argument,
                    AppLaunchOptions.storageDirectoryArgument,
                    unsafe.path
                ]),
                "Expected rejection for \(unsafe.path)"
            )
        }

        let symlinkParent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bairometer-verification-link-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createSymbolicLink(
            at: symlinkParent,
            withDestinationURL: FileManager.default.temporaryDirectory
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: symlinkParent)
        }
        let symlinkChild = symlinkParent.appendingPathComponent(
            "bairometer-openrouter-verification-abcdef.disposable",
            isDirectory: true
        )
        XCTAssertThrowsError(
            try OpenRouterVerificationCommand.validated(arguments: [
                "Bairometer",
                OpenRouterVerificationCommand.argument,
                AppLaunchOptions.storageDirectoryArgument,
                symlinkChild.path
            ])
        )
    }

    func testDeletingOpenRouterAccountSecurelyDeletesCredentialsAndNativeData() async throws {
        let directory = temporaryDirectory()
        let keychain = AppIntegrationKeychain()
        let client = CountingSyntheticOpenRouterClient()
        let model = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            refreshCoordinator: ProviderRefreshCoordinator(
                retryPolicy: ProviderRetryPolicy(maxAttempts: 1, initialDelay: 0)
            ),
            openRouterAPIClient: client,
            credentialKeychainService: keychain
        )
        let account = try XCTUnwrap(
            model.addAccount(providerID: "openrouter", displayName: "Delete me")
        )
        try configureCredentials(model: model, account: account)
        model.refreshAccount(
            providerID: account.providerID,
            accountID: account.accountID
        )
        await model.waitForRefreshCompletionForTesting()
        XCTAssertEqual(keychain.credentialCount, 2)
        XCTAssertNotNil(try nativeSnapshot(model: model, account: account))

        model.deleteAccount(
            providerID: account.providerID,
            accountID: account.accountID
        )

        XCTAssertEqual(keychain.credentialCount, 0)
        XCTAssertFalse(model.providerAccounts.contains { $0.id == account.id })
        XCTAssertNil(try nativeSnapshot(model: model, account: account))
        XCTAssertTrue(model.snapshots.allSatisfy { $0.id != account.id })
    }

    func testTotalOpenRouterFailurePreservesLegacySnapshotAndLastSuccess() async throws {
        let directory = temporaryDirectory()
        let keychain = AppIntegrationKeychain()
        let client = CountingSyntheticOpenRouterClient()
        let model = AppModel(
            storageDirectory: directory,
            userDefaults: isolatedDefaults(),
            refreshCoordinator: ProviderRefreshCoordinator(
                retryPolicy: ProviderRetryPolicy(maxAttempts: 1, initialDelay: 0)
            ),
            openRouterAPIClient: client,
            credentialKeychainService: keychain
        )
        let account = try XCTUnwrap(
            model.addAccount(providerID: "openrouter", displayName: "Preserve me")
        )
        try configureCredentials(model: model, account: account)
        model.refreshAccount(
            providerID: account.providerID,
            accountID: account.accountID
        )
        await model.waitForRefreshCompletionForTesting()
        let successfulSnapshot = try XCTUnwrap(model.snapshot(for: account))
        let successfulAt = try XCTUnwrap(
            model.sourceRefreshStates[account.id]?.lastSuccessfulRefreshAt
        )

        await client.setFailAllRequests(true)
        model.refreshAccount(
            providerID: account.providerID,
            accountID: account.accountID
        )
        await model.waitForRefreshCompletionForTesting()

        XCTAssertEqual(model.snapshot(for: account), successfulSnapshot)
        XCTAssertEqual(
            model.sourceRefreshStates[account.id]?.lastSuccessfulRefreshAt,
            successfulAt
        )
        XCTAssertNotNil(
            model.sourceRefreshStates[account.id]?.lastFailedRefreshAt
        )
        XCTAssertNotNil(model.accountRefreshIssues[account.id])
    }

    private func configureCredentials(
        model: AppModel,
        account: ProviderAccount
    ) throws {
        let rootContextID = try XCTUnwrap(
            model.accountCredentialStore.loadContexts(
                providerID: account.providerID,
                accountID: account.accountID
            ).first(where: { $0.parentContextID == nil })?.contextID
        )
        let childContextID = "\(account.accountID)-ordinary"
        try model.accountCredentialStore.createContext(
            ProviderAccountContextConfiguration(
                providerID: account.providerID,
                accountID: account.accountID,
                contextID: childContextID,
                kind: .credential,
                displayName: "Local key",
                regionID: "global",
                parentContextID: rootContextID
            )
        )
        try model.accountCredentialStore.createCredential(
            providerID: account.providerID,
            accountID: account.accountID,
            slotID: childContextID,
            contextID: childContextID,
            role: .ordinary,
            credential: CredentialSecret("synthetic-app-ordinary")
        )
        try model.accountCredentialStore.createCredential(
            providerID: account.providerID,
            accountID: account.accountID,
            slotID: "management",
            contextID: rootContextID,
            role: .management,
            credential: CredentialSecret("synthetic-app-management")
        )
    }

    private func nativeSnapshot(
        model: AppModel,
        account: ProviderAccount
    ) throws -> CapacitySnapshot? {
        try model.nativeCapacitySnapshotStore.load(
            providerID: account.providerID,
            accountID: account.accountID,
            surface: OpenRouterProviderContract.surface,
            sources: OpenRouterProviderContract.sources
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func disposableVerificationDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "bairometer-openrouter-verification-\(UUID().uuidString.replacingOccurrences(of: "-", with: "")).disposable",
            isDirectory: true
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "OpenRouterAppIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private actor CountingSyntheticOpenRouterClient: OpenRouterAPIClient {
    private let base = SyntheticOpenRouterVerificationClient(
        failingOrdinarySlotID: "never-fail"
    )
    private(set) var callCount = 0
    private var failAllRequests = false
    private var callWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []

    func waitForCallCount(_ count: Int) async {
        guard callCount < count else {
            return
        }
        await withCheckedContinuation { continuation in
            callWaiters.append((count, continuation))
        }
    }

    func setFailAllRequests(_ shouldFail: Bool) {
        failAllRequests = shouldFail
    }

    func fetchCurrentKeyCapacity(
        credential: OpenRouterOrdinaryCredential
    ) async throws -> OpenRouterCurrentKeyCapacity {
        if failAllRequests {
            recordCall()
            throw OpenRouterAPIClientError.authenticationFailure
        }
        let result = try await base.fetchCurrentKeyCapacity(credential: credential)
        recordCall()
        return result
    }

    func fetchManagementCredits(
        credential: OpenRouterManagementCredential
    ) async throws -> OpenRouterManagementCreditsCapacity {
        if failAllRequests {
            recordCall()
            throw OpenRouterAPIClientError.authenticationFailure
        }
        let result = try await base.fetchManagementCredits(credential: credential)
        recordCall()
        return result
    }

    private func recordCall() {
        callCount += 1
        var remaining: [
            (count: Int, continuation: CheckedContinuation<Void, Never>)
        ] = []
        for waiter in callWaiters {
            if callCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        callWaiters = remaining
    }
}

private final class AppIntegrationKeychain: KeychainService, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: CredentialSecret] = [:]

    var credentialCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return values.count
    }

    func createCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard values[reference] == nil else {
            throw KeychainServiceError.duplicateReference
        }
        values[reference] = credential
    }

    func readCredential(reference: String) throws -> CredentialSecret {
        lock.lock()
        defer { lock.unlock() }
        guard let value = values[reference] else {
            throw KeychainServiceError.credentialNotFound
        }
        return value
    }

    func replaceCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard values[reference] != nil else {
            throw KeychainServiceError.credentialNotFound
        }
        values[reference] = credential
    }

    func deleteCredential(reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: reference)
    }
}

private final class LockedBoolean: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Bool) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}

private enum AppIntegrationTestError: Error {
    case injected
}
#endif
