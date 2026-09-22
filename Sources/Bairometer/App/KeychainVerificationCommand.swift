#if DEBUG
import BairometerCore
import Darwin
import Foundation

struct KeychainVerificationCommand {
    static let argument = "--bairometer-keychain-verification"

    enum Operation: String {
        case create
        case replace
        case delete
    }

    let operation: Operation
    let storageDirectory: URL
    let keychainService: any KeychainService

    init(
        operation: Operation,
        storageDirectory: URL,
        keychainService: any KeychainService = MacOSKeychainService()
    ) {
        self.operation = operation
        self.storageDirectory = storageDirectory
        self.keychainService = keychainService
    }

    static func parse(
        arguments: [String] = CommandLine.arguments
    ) -> KeychainVerificationCommand? {
        guard let commandIndex = arguments.firstIndex(of: argument) else {
            return nil
        }
        let operationIndex = arguments.index(after: commandIndex)
        guard operationIndex < arguments.endIndex,
              let operation = Operation(rawValue: arguments[operationIndex]),
              let storageIndex = arguments.firstIndex(
                of: AppLaunchOptions.storageDirectoryArgument
              )
        else {
            failInvalidArguments()
        }
        let pathIndex = arguments.index(after: storageIndex)
        guard pathIndex < arguments.endIndex,
              arguments[pathIndex].hasPrefix("/")
        else {
            failInvalidArguments()
        }
        return KeychainVerificationCommand(
            operation: operation,
            storageDirectory: URL(
                fileURLWithPath: arguments[pathIndex],
                isDirectory: true
            )
        )
    }

    private static func failInvalidArguments() -> Never {
        fputs("Invalid Keychain verification arguments.\n", stderr)
        Darwin.exit(EXIT_FAILURE)
    }

    func runAndExit() -> Never {
        do {
            let reference = try run()
            print("Keychain verification \(operation.rawValue) passed.")
            if let reference {
                print("KEYCHAIN_REFERENCE=\(reference)")
            }
            Darwin.exit(EXIT_SUCCESS)
        } catch {
            fputs(
                "Keychain verification \(operation.rawValue) failed.\n",
                stderr
            )
            Darwin.exit(EXIT_FAILURE)
        }
    }

    func run() throws -> String? {
        let providerID = "keychain-verification"
        let accountID = "temporary"
        let rootContextID = "root"
        let credentialContextID = "credential"
        let slotID = "ordinary"
        let database = try AppDatabase(directory: storageDirectory)
        let accountStore = DatabaseProviderConfigurationStore(database: database)
        let credentialStore = AccountCredentialStore(
            database: database,
            keychainService: keychainService
        )
        let expectedAccount = ProviderAccount(
            providerID: providerID,
            accountID: accountID,
            displayName: "Temporary Keychain Verification",
            isEnabled: false
        )
        let expectedRoot = ProviderAccountContextConfiguration(
            providerID: providerID,
            accountID: accountID,
            contextID: rootContextID,
            kind: .personal,
            regionID: "local"
        )
        let expectedCredentialContext = ProviderAccountContextConfiguration(
            providerID: providerID,
            accountID: accountID,
            contextID: credentialContextID,
            kind: .credential,
            displayName: "Temporary credential",
            regionID: "local",
            parentContextID: rootContextID
        )

        switch operation {
        case .create:
            guard try accountStore.insertIfEmpty(expectedAccount) else {
                throw CredentialStoreError.storageUnavailable
            }
            try credentialStore.createContext(expectedRoot)
            try credentialStore.createContext(expectedCredentialContext)
            let value = "temporary-keychain-verification-\(UUID().uuidString)"
            let slot = try credentialStore.createCredential(
                providerID: providerID,
                accountID: accountID,
                slotID: slotID,
                contextID: credentialContextID,
                role: .ordinary,
                credential: CredentialSecret(value)
            )
            let persisted = try credentialStore.readCredential(
                providerID: providerID,
                accountID: accountID,
                slotID: slotID
            )
            guard try persisted.withUTF8String({ $0 == value }) else {
                throw CredentialStoreError.credentialMissing
            }
            return slot.keychainReference

        case .replace:
            let slot = try requireExpectedState(
                accountStore: accountStore,
                credentialStore: credentialStore,
                expectedAccount: expectedAccount,
                expectedContexts: [expectedRoot, expectedCredentialContext],
                providerID: providerID,
                accountID: accountID,
                slotID: slotID,
                credentialContextID: credentialContextID,
                allowedLifecycleStates: [.active]
            )
            let value = "temporary-keychain-replacement-\(UUID().uuidString)"
            try credentialStore.replaceCredential(
                CredentialSecret(value),
                providerID: providerID,
                accountID: accountID,
                slotID: slotID
            )
            let persisted = try credentialStore.readCredential(
                providerID: providerID,
                accountID: accountID,
                slotID: slotID
            )
            guard try persisted.withUTF8String({ $0 == value }) else {
                throw CredentialStoreError.credentialMissing
            }
            return slot.keychainReference

        case .delete:
            let slot = try requireExpectedState(
                accountStore: accountStore,
                credentialStore: credentialStore,
                expectedAccount: expectedAccount,
                expectedContexts: [expectedRoot, expectedCredentialContext],
                providerID: providerID,
                accountID: accountID,
                slotID: slotID,
                credentialContextID: credentialContextID,
                allowedLifecycleStates: CredentialLifecycleState.allCases
            )
            try credentialStore.deleteCredential(
                providerID: providerID,
                accountID: accountID,
                slotID: slotID
            )
            do {
                _ = try keychainService.readCredential(
                    reference: slot.keychainReference
                )
                throw CredentialStoreError.storageUnavailable
            } catch KeychainServiceError.credentialNotFound {
                return slot.keychainReference
            }
        }
    }

    private func requireExpectedState(
        accountStore: DatabaseProviderConfigurationStore,
        credentialStore: AccountCredentialStore,
        expectedAccount: ProviderAccount,
        expectedContexts: [ProviderAccountContextConfiguration],
        providerID: String,
        accountID: String,
        slotID: String,
        credentialContextID: String,
        allowedLifecycleStates: [CredentialLifecycleState]
    ) throws -> ProviderCredentialSlot {
        guard try accountStore.accountCount() == 1 else {
            throw CredentialStoreError.storageUnavailable
        }
        let accountResult = accountStore.load(knownProviderIDs: [providerID])
        guard accountResult.warning == nil,
              accountResult.accounts == [expectedAccount]
        else {
            throw CredentialStoreError.storageUnavailable
        }
        let contexts = try credentialStore.loadContexts(
            providerID: providerID,
            accountID: accountID
        )
        guard contexts.count == expectedContexts.count,
              contexts.allSatisfy(expectedContexts.contains)
        else {
            throw CredentialStoreError.storageUnavailable
        }
        let credentialContexts = try credentialStore.loadCredentialContexts(
            providerID: providerID,
            accountID: accountID
        )
        guard credentialContexts.count == 1,
              let slot = credentialContexts.first?.slot
        else {
            throw CredentialStoreError.storageUnavailable
        }
        let expectedEnabled = slot.lifecycleState != .pendingDeletion
        guard slot.providerID == providerID,
              slot.accountID == accountID,
              slot.slotID == slotID,
              slot.contextID == credentialContextID,
              slot.role == .ordinary,
              slot.isEnabled == expectedEnabled,
              !slot.keychainReference.isEmpty,
              allowedLifecycleStates.contains(slot.lifecycleState)
        else {
            throw CredentialStoreError.storageUnavailable
        }
        return slot
    }
}
#endif
