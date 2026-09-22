#if DEBUG
import BairometerCore
import Darwin
import Foundation

struct OpenRouterVerificationCommand {
    static let argument = "--bairometer-openrouter-verification"
    static let basenamePrefix = "bairometer-openrouter-verification-"
    static let basenameSuffix = ".disposable"

    let storageDirectory: URL
    var postCreationCheckpoint: @Sendable () throws -> Void = {}

    static func parse(
        arguments: [String] = CommandLine.arguments
    ) -> OpenRouterVerificationCommand? {
        do {
            return try validated(arguments: arguments)
        } catch {
            failInvalidArguments()
        }
    }

    static func validated(
        arguments: [String]
    ) throws -> OpenRouterVerificationCommand? {
        guard arguments.contains(argument) else {
            return nil
        }
        guard let storageIndex = arguments.firstIndex(
            of: AppLaunchOptions.storageDirectoryArgument
        ) else {
            throw OpenRouterVerificationPathError.invalidArguments
        }
        let pathIndex = arguments.index(after: storageIndex)
        guard pathIndex < arguments.endIndex,
              arguments[pathIndex].hasPrefix("/")
        else {
            throw OpenRouterVerificationPathError.invalidArguments
        }
        let directory = URL(
            fileURLWithPath: arguments[pathIndex],
            isDirectory: true
        )
        try validateDisposableDirectory(directory)
        return OpenRouterVerificationCommand(storageDirectory: directory)
    }

    private static func failInvalidArguments() -> Never {
        fputs("Invalid OpenRouter verification arguments.\n", stderr)
        Darwin.exit(EXIT_FAILURE)
    }

    func runAndExit() -> Never {
        Task.detached {
            do {
                try await run()
                print("OpenRouter synthetic integration verification passed.")
                Darwin.exit(EXIT_SUCCESS)
            } catch {
                fputs(
                    "OpenRouter synthetic integration verification failed.\n",
                    stderr
                )
                Darwin.exit(EXIT_FAILURE)
            }
        }
        dispatchMain()
    }

    func run() async throws {
        try Self.validateDisposableDirectory(storageDirectory)
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: false
        )
        defer {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        try postCreationCheckpoint()

        let providerID = OpenRouterProviderContract.providerID
        let accountID = "synthetic-openrouter-verification"
        let rootContextID = "account-root"
        let healthyContextID = "healthy-key"
        let failingContextID = "failing-key"
        let database = try AppDatabase(directory: storageDirectory)
        let accountStore = DatabaseProviderConfigurationStore(database: database)
        guard try accountStore.accountCount() == 0 else {
            throw NativeCapacityStoreError.accountUnavailable
        }
        let account = ProviderAccount(
            providerID: providerID,
            accountID: accountID,
            displayName: "Synthetic OpenRouter Verification",
            isEnabled: true
        )
        try accountStore.save([account])

        let keychain = OpenRouterVerificationKeychain()
        let credentialStore = AccountCredentialStore(
            database: database,
            keychainService: keychain
        )
        try credentialStore.createContext(
            ProviderAccountContextConfiguration(
                providerID: providerID,
                accountID: accountID,
                contextID: rootContextID,
                kind: .personal,
                regionID: "global"
            )
        )
        for contextID in [healthyContextID, failingContextID] {
            try credentialStore.createContext(
                ProviderAccountContextConfiguration(
                    providerID: providerID,
                    accountID: accountID,
                    contextID: contextID,
                    kind: .credential,
                    displayName: "Synthetic key",
                    regionID: "global",
                    parentContextID: rootContextID
                )
            )
            try credentialStore.createCredential(
                providerID: providerID,
                accountID: accountID,
                slotID: contextID,
                contextID: contextID,
                role: .ordinary,
                credential: CredentialSecret("synthetic-\(contextID)")
            )
        }
        try credentialStore.createCredential(
            providerID: providerID,
            accountID: accountID,
            slotID: "management",
            contextID: rootContextID,
            role: .management,
            credential: CredentialSecret("synthetic-management")
        )

        let capacityStore = DatabaseCapacitySnapshotStore(database: database)
        let observedAt = Date(timeIntervalSince1970: 20_000)
        let adapter = OpenRouterProviderAdapter(
            refreshCoordinator: OpenRouterRefreshCoordinator(
                credentialStore: credentialStore,
                capacityStore: capacityStore,
                client: SyntheticOpenRouterVerificationClient(
                    failingOrdinarySlotID: failingContextID,
                    observedAt: observedAt
                ),
                policy: OpenRouterRefreshPolicy(
                    maximumConcurrentSources: 4,
                    initialBackoff: 30,
                    maximumBackoff: 300
                ),
                now: { observedAt }
            )
        )
        let compatibilitySnapshot = try await adapter.fetchSnapshot(
            account: account
        )
        guard compatibilitySnapshot.status == .warning,
              compatibilitySnapshot.usedPercent == nil,
              compatibilitySnapshot.limitWindows.isEmpty
        else {
            throw NativeCapacityStoreError.invalidSnapshot
        }
        try DatabaseSnapshotStore(database: database).save([
            compatibilitySnapshot
        ])

        guard let snapshot = try capacityStore.load(
            providerID: providerID,
            accountID: accountID,
            surface: OpenRouterProviderContract.surface,
            sources: OpenRouterProviderContract.sources
        ) else {
            throw NativeCapacityStoreError.invalidSnapshot
        }
        try ProviderContractValidator.validate(
            snapshot: snapshot,
            surface: OpenRouterProviderContract.surface,
            sources: OpenRouterProviderContract.sources
        )
        guard snapshot.metrics.contains(where: {
            $0.accountContextID == healthyContextID
                && $0.metricID == "key-total-usage"
        }), !snapshot.metrics.contains(where: {
            $0.accountContextID == failingContextID
        }), snapshot.metrics.filter({
            $0.accountContextID == rootContextID
                && $0.metricID == "account-credits"
        }).count == 1 else {
            throw NativeCapacityStoreError.invalidSnapshot
        }
        let diagnostics = try credentialStore.loadDiagnostics(
            providerID: providerID,
            accountID: accountID
        )
        guard diagnostics.count == 1,
              diagnostics.first?.slotID == failingContextID,
              diagnostics.first?.code == .transientFailure else {
            throw NativeCapacityStoreError.invalidSnapshot
        }
    }

    private static func validateDisposableDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        let standardized = directory.standardizedFileURL
        guard standardized.path == directory.path,
              !fileManager.fileExists(atPath: standardized.path)
        else {
            throw OpenRouterVerificationPathError.existingOrNonCanonical
        }
        let basename = standardized.lastPathComponent
        guard basename.hasPrefix(basenamePrefix),
              basename.hasSuffix(basenameSuffix)
        else {
            throw OpenRouterVerificationPathError.invalidBasename
        }
        let token = basename
            .dropFirst(basenamePrefix.count)
            .dropLast(basenameSuffix.count)
        guard token.count >= 6,
              token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else {
            throw OpenRouterVerificationPathError.invalidBasename
        }
        let parent = standardized.deletingLastPathComponent()
        let canonicalParent = parent.resolvingSymlinksInPath()
        let canonicalSystemTemp = fileManager.temporaryDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard canonicalParent == canonicalSystemTemp,
              try parent.resourceValues(forKeys: [.isSymbolicLinkKey])
                .isSymbolicLink != true
        else {
            throw OpenRouterVerificationPathError.invalidParent
        }
    }
}

enum OpenRouterVerificationPathError: Error, Equatable {
    case invalidArguments
    case invalidBasename
    case invalidParent
    case existingOrNonCanonical
}

private final class OpenRouterVerificationKeychain:
    KeychainService,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var credentials: [String: CredentialSecret] = [:]

    func createCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard credentials[reference] == nil else {
            throw KeychainServiceError.duplicateReference
        }
        credentials[reference] = credential
    }

    func readCredential(reference: String) throws -> CredentialSecret {
        lock.lock()
        defer { lock.unlock() }
        guard let credential = credentials[reference] else {
            throw KeychainServiceError.credentialNotFound
        }
        return credential
    }

    func replaceCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard credentials[reference] != nil else {
            throw KeychainServiceError.credentialNotFound
        }
        credentials[reference] = credential
    }

    func deleteCredential(reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        credentials.removeValue(forKey: reference)
    }
}
#endif
