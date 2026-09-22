import BairometerCore
import Foundation

enum MiniMaxSettingsError: Error, Equatable {
    case invalidAccount
    case credentialExists
    case emptyCredential
    case pendingDeletion
    case credentialUnavailable
    case keychainUnavailable
    case storageUnavailable
}

extension AppModel {
    nonisolated static let miniMaxRootContextSuffix = "minimax-default-team"
    nonisolated static let miniMaxCredentialContextSuffix =
        "minimax-subscription-key"
    nonisolated static let miniMaxSubscriptionSlotID = "subscription-key"

    func initializeMiniMaxAccount(_ account: ProviderAccount) throws {
        _ = try ensureMiniMaxRootContext(for: account)
        reloadMiniMaxPresentationData(for: account)
    }

    func reloadMiniMaxPresentationData(for account: ProviderAccount) {
        guard account.providerID == MiniMaxProviderContract.providerID else {
            return
        }

        do {
            credentialContextsByAccount[account.id] = try accountCredentialStore
                .loadCredentialContexts(
                    providerID: account.providerID,
                    accountID: account.accountID
                )
            credentialRefreshStatesByAccount[account.id] = try accountCredentialStore
                .loadRefreshStates(
                    providerID: account.providerID,
                    accountID: account.accountID
                )
            credentialDiagnosticsByAccount[account.id] = try accountCredentialStore
                .loadDiagnostics(
                    providerID: account.providerID,
                    accountID: account.accountID
                )
#if DEBUG
            if let syntheticAdapter = adapter(for: account.providerID)
                as? UITestScriptedProviderAdapter,
               syntheticAdapter.preservesNativePresentationFixture {
                return
            }
#endif
            if let snapshot = try nativeCapacitySnapshotStore.load(
                providerID: account.providerID,
                accountID: account.accountID,
                surface: MiniMaxProviderContract.surface,
                sources: MiniMaxProviderContract.sources
            ) {
                nativeCapacitySnapshots[account.id] = snapshot
            } else {
                nativeCapacitySnapshots.removeValue(forKey: account.id)
            }
        } catch {
            credentialContextsByAccount.removeValue(forKey: account.id)
            credentialRefreshStatesByAccount.removeValue(forKey: account.id)
            credentialDiagnosticsByAccount.removeValue(forKey: account.id)
            storageWarning = "Provider settings could not be saved."
        }
    }

    func miniMaxCredentialContexts(
        for account: ProviderAccount
    ) -> [ProviderCredentialContext] {
        credentialContextsByAccount[account.id] ?? []
    }

    func miniMaxCredentialRefreshStates(
        for account: ProviderAccount
    ) -> [CredentialContextRefreshState] {
        credentialRefreshStatesByAccount[account.id] ?? []
    }

    func miniMaxCredentialDiagnostics(
        for account: ProviderAccount
    ) -> [CredentialContextDiagnostic] {
        credentialDiagnosticsByAccount[account.id] ?? []
    }

    @discardableResult
    func createMiniMaxSubscriptionKey(
        for account: ProviderAccount,
        credentialValue: String
    ) throws -> ProviderCredentialContext {
        let account = try requireMiniMaxAccount(account)
        let existingCredentials: [ProviderCredentialContext]
        do {
            existingCredentials = try accountCredentialStore
                .loadCredentialContexts(
                    providerID: account.providerID,
                    accountID: account.accountID
                )
        } catch {
            throw mapMiniMaxSettingsError(error)
        }
        guard existingCredentials.isEmpty else {
            throw MiniMaxSettingsError.credentialExists
        }
        let credential = try makeMiniMaxCredentialSecret(credentialValue)
        let root = try ensureMiniMaxRootContext(for: account)
        let contextID = miniMaxCredentialContextID(for: account)
        let context = ProviderAccountContextConfiguration(
            providerID: account.providerID,
            accountID: account.accountID,
            contextID: contextID,
            kind: .credential,
            displayName: "Subscription Key",
            regionID: "global",
            parentContextID: root.contextID
        )

        invalidateMiniMaxAccount(account)
        do {
            let existingContexts = try accountCredentialStore.loadContexts(
                providerID: account.providerID,
                accountID: account.accountID
            )
            if let existingContext = existingContexts.first(where: {
                $0.contextID == contextID
            }) {
                guard existingContext == context else {
                    throw MiniMaxSettingsError.storageUnavailable
                }
            } else {
                try accountCredentialStore.createContext(context)
            }
            _ = try accountCredentialStore.createCredential(
                providerID: account.providerID,
                accountID: account.accountID,
                slotID: Self.miniMaxSubscriptionSlotID,
                contextID: contextID,
                role: .ordinary,
                credential: credential
            )
            reloadMiniMaxPresentationData(for: account)
            guard let created = miniMaxCredentialContexts(for: account).first,
                  miniMaxCredentialContexts(for: account).count == 1 else {
                throw MiniMaxSettingsError.storageUnavailable
            }
            return created
        } catch {
            reloadMiniMaxPresentationData(for: account)
            throw mapMiniMaxSettingsError(error)
        }
    }

    func replaceMiniMaxSubscriptionKey(
        for account: ProviderAccount,
        credentialValue: String
    ) throws {
        let account = try requireMiniMaxAccount(account)
        let credential = try makeMiniMaxCredentialSecret(credentialValue)
        let existing = try requireOnlyMiniMaxCredential(for: account)

        invalidateMiniMaxAccount(account)
        do {
            switch existing.slot.lifecycleState {
            case .active:
                try accountCredentialStore.replaceCredential(
                    credential,
                    providerID: account.providerID,
                    accountID: account.accountID,
                    slotID: existing.slot.slotID
                )
            case .pendingCreation:
                _ = try accountCredentialStore.recoverPendingCreation(
                    providerID: account.providerID,
                    accountID: account.accountID,
                    slotID: existing.slot.slotID,
                    credential: credential
                )
            case .pendingDeletion:
                throw MiniMaxSettingsError.pendingDeletion
            }
            reloadMiniMaxPresentationData(for: account)
        } catch {
            reloadMiniMaxPresentationData(for: account)
            throw mapMiniMaxSettingsError(error)
        }
    }

    func setMiniMaxSubscriptionKeyEnabled(
        _ isEnabled: Bool,
        for account: ProviderAccount
    ) throws {
        let account = try requireMiniMaxAccount(account)
        let existing = try requireOnlyMiniMaxCredential(for: account)

        invalidateMiniMaxAccount(account)
        do {
            try accountCredentialStore.setCredentialEnabled(
                isEnabled,
                providerID: account.providerID,
                accountID: account.accountID,
                slotID: existing.slot.slotID
            )
            reloadMiniMaxPresentationData(for: account)
        } catch {
            reloadMiniMaxPresentationData(for: account)
            throw mapMiniMaxSettingsError(error)
        }
    }

    func deleteMiniMaxSubscriptionKey(
        for account: ProviderAccount
    ) throws {
        let account = try requireMiniMaxAccount(account)
        let existing = try requireOnlyMiniMaxCredential(for: account)

        invalidateMiniMaxAccount(account)
        do {
            try accountCredentialStore.deleteCredential(
                providerID: account.providerID,
                accountID: account.accountID,
                slotID: existing.slot.slotID
            )
            reloadMiniMaxPresentationData(for: account)
        } catch {
            reloadMiniMaxPresentationData(for: account)
            throw mapMiniMaxSettingsError(error)
        }
    }

    private func requireMiniMaxAccount(
        _ requested: ProviderAccount
    ) throws -> ProviderAccount {
        guard requested.providerID == MiniMaxProviderContract.providerID,
              requested.sourceMode == .miniMaxTokenPlan,
              let account = account(
                  providerID: requested.providerID,
                  accountID: requested.accountID
              ) else {
            throw MiniMaxSettingsError.invalidAccount
        }
        return account
    }

    private func ensureMiniMaxRootContext(
        for account: ProviderAccount
    ) throws -> ProviderAccountContextConfiguration {
        let contexts: [ProviderAccountContextConfiguration]
        do {
            contexts = try accountCredentialStore.loadContexts(
                providerID: account.providerID,
                accountID: account.accountID
            )
        } catch {
            throw mapMiniMaxSettingsError(error)
        }

        let roots = contexts.filter { $0.parentContextID == nil }
        if let root = roots.first {
            guard roots.count == 1,
                  root.kind == .team,
                  root.regionID == "global",
                  root.contextID == miniMaxRootContextID(for: account),
                  root.displayName == "Personal Default Team" else {
                throw MiniMaxSettingsError.storageUnavailable
            }
            return root
        }
        guard contexts.isEmpty else {
            throw MiniMaxSettingsError.storageUnavailable
        }

        let root = ProviderAccountContextConfiguration(
            providerID: account.providerID,
            accountID: account.accountID,
            contextID: miniMaxRootContextID(for: account),
            kind: .team,
            displayName: "Personal Default Team",
            regionID: "global"
        )
        do {
            try accountCredentialStore.createContext(root)
            return root
        } catch {
            throw mapMiniMaxSettingsError(error)
        }
    }

    private func requireOnlyMiniMaxCredential(
        for account: ProviderAccount
    ) throws -> ProviderCredentialContext {
        let credentials: [ProviderCredentialContext]
        do {
            credentials = try accountCredentialStore.loadCredentialContexts(
                providerID: account.providerID,
                accountID: account.accountID
            )
        } catch {
            throw mapMiniMaxSettingsError(error)
        }
        guard !credentials.isEmpty else {
            throw MiniMaxSettingsError.credentialUnavailable
        }
        guard credentials.count == 1,
              let credential = credentials.first,
              credential.slot.role == .ordinary,
              credential.slot.slotID == Self.miniMaxSubscriptionSlotID,
              credential.context.kind == .credential,
              credential.context.contextID
                == miniMaxCredentialContextID(for: account),
              credential.context.parentContextID
                == miniMaxRootContextID(for: account),
              credential.context.regionID == "global" else {
            throw MiniMaxSettingsError.storageUnavailable
        }
        return credential
    }

    private func miniMaxRootContextID(for account: ProviderAccount) -> String {
        "\(account.accountID)-\(Self.miniMaxRootContextSuffix)"
    }

    private func miniMaxCredentialContextID(
        for account: ProviderAccount
    ) -> String {
        "\(account.accountID)-\(Self.miniMaxCredentialContextSuffix)"
    }

    private func makeMiniMaxCredentialSecret(
        _ credentialValue: String
    ) throws -> CredentialSecret {
        guard !credentialValue.isEmpty else {
            throw MiniMaxSettingsError.emptyCredential
        }
        do {
            return try CredentialSecret(credentialValue)
        } catch {
            throw MiniMaxSettingsError.emptyCredential
        }
    }

    private func invalidateMiniMaxAccount(_ account: ProviderAccount) {
        openRouterRefreshGenerations[account.id, default: 0] &+= 1
        cancelAccountRefresh(for: account.id)
        (adapter(for: account.providerID) as? MiniMaxProviderAdapter)?
            .invalidateAccount(accountID: account.accountID)
    }

    func miniMaxRefreshGeneration(for accountKey: String) -> UInt64 {
        openRouterRefreshGenerations[accountKey, default: 0]
    }

    private func mapMiniMaxSettingsError(_ error: Error) -> MiniMaxSettingsError {
        if let error = error as? MiniMaxSettingsError {
            return error
        }
        guard let error = error as? CredentialStoreError else {
            return .storageUnavailable
        }
        return switch error {
        case .credentialPendingDeletion:
            .pendingDeletion
        case .credentialMissing, .slotNotFound, .contextNotFound:
            .credentialUnavailable
        case let .keychain(keychainError):
            keychainError == .invalidCredential
                ? .emptyCredential
                : .keychainUnavailable
        case .accountNotFound,
             .invalidContextTree,
             .invalidCredentialRole,
             .managementCredentialAlreadyExists,
             .contextAlreadyHasCredential,
             .credentialDisabled,
             .credentialPendingCreation,
             .storageUnavailable:
            .storageUnavailable
        }
    }
}
