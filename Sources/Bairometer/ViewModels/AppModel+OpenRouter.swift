import BairometerCore
import Foundation

enum OpenRouterSettingsError: Error, Equatable {
    case invalidAccount
    case invalidName
    case duplicateName
    case emptyCredential
    case managementCredentialExists
    case pendingDeletion
    case credentialUnavailable
    case keychainUnavailable
    case storageUnavailable
}

extension AppModel {
    func initializeOpenRouterAccount(_ account: ProviderAccount) throws {
        _ = try ensureOpenRouterRootContext(for: account)
        reloadOpenRouterPresentationData(for: account)
    }

    func loadOpenRouterPresentationData() {
        let configuredKeys = Set(
            providerAccounts
                .filter { $0.providerID == OpenRouterProviderContract.providerID }
                .map(\.id)
        )
        nativeCapacitySnapshots = nativeCapacitySnapshots.filter {
            configuredKeys.contains($0.key)
        }
        credentialContextsByAccount = credentialContextsByAccount.filter {
            configuredKeys.contains($0.key)
        }
        credentialRefreshStatesByAccount = credentialRefreshStatesByAccount.filter {
            configuredKeys.contains($0.key)
        }
        credentialDiagnosticsByAccount = credentialDiagnosticsByAccount.filter {
            configuredKeys.contains($0.key)
        }

        for account in providerAccounts where
            account.providerID == OpenRouterProviderContract.providerID {
            reloadOpenRouterPresentationData(for: account)
        }
    }

    func reloadOpenRouterPresentationData(for account: ProviderAccount) {
        guard account.providerID == OpenRouterProviderContract.providerID else {
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
            if let snapshot = try nativeCapacitySnapshotStore.load(
                providerID: account.providerID,
                accountID: account.accountID,
                surface: OpenRouterProviderContract.surface,
                sources: OpenRouterProviderContract.sources
            ) {
                nativeCapacitySnapshots[account.id] = snapshot
            } else {
                nativeCapacitySnapshots.removeValue(forKey: account.id)
            }
            clearOpenRouterStorageWarning()
        } catch {
            storageWarning = "OpenRouter credential metadata could not be loaded."
        }
    }

    func openRouterCredentialContexts(
        for account: ProviderAccount
    ) -> [ProviderCredentialContext] {
        credentialContextsByAccount[account.id] ?? []
    }

    func openRouterCredentialRefreshStates(
        for account: ProviderAccount
    ) -> [CredentialContextRefreshState] {
        credentialRefreshStatesByAccount[account.id] ?? []
    }

    func openRouterCredentialDiagnostics(
        for account: ProviderAccount
    ) -> [CredentialContextDiagnostic] {
        credentialDiagnosticsByAccount[account.id] ?? []
    }

    func nativeCapacitySnapshot(for account: ProviderAccount) -> CapacitySnapshot? {
        nativeCapacitySnapshots[account.id]
    }

    func openRouterCapacityPresentation(
        for account: ProviderAccount,
        now: Date = Date(),
        locale: Locale
    ) -> OpenRouterCapacityPresentation? {
        guard account.providerID == OpenRouterProviderContract.providerID else {
            return nil
        }
        return OpenRouterCapacityPresentation(
            account: account,
            snapshot: nativeCapacitySnapshot(for: account),
            credentialContexts: openRouterCredentialContexts(for: account),
            refreshStates: openRouterCredentialRefreshStates(for: account),
            diagnostics: openRouterCredentialDiagnostics(for: account),
            now: now,
            locale: locale
        )
    }

    @discardableResult
    func createOpenRouterOrdinaryCredential(
        for account: ProviderAccount,
        displayName: String,
        credentialValue: String
    ) throws -> ProviderCredentialContext {
        let account = try requireOpenRouterAccount(account)
        let name = try normalizedOpenRouterCredentialName(
            displayName,
            account: account,
            excludingContextID: nil
        )
        let credential = try makeCredentialSecret(credentialValue)
        let root = try ensureOpenRouterRootContext(for: account)
        let contextID = "credential-\(UUID().uuidString.lowercased())"
        let context = ProviderAccountContextConfiguration(
            providerID: account.providerID,
            accountID: account.accountID,
            contextID: contextID,
            kind: .credential,
            displayName: name,
            regionID: "global",
            parentContextID: root.contextID
        )

        invalidateOpenRouterAccount(account)
        do {
            try accountCredentialStore.createContext(context)
            _ = try accountCredentialStore.createCredential(
                providerID: account.providerID,
                accountID: account.accountID,
                slotID: contextID,
                contextID: contextID,
                role: .ordinary,
                credential: credential
            )
            reloadOpenRouterPresentationData(for: account)
            guard let created = openRouterCredentialContexts(for: account)
                .first(where: { $0.context.contextID == contextID }) else {
                throw OpenRouterSettingsError.storageUnavailable
            }
            return created
        } catch {
            reloadOpenRouterPresentationData(for: account)
            throw mapOpenRouterSettingsError(error)
        }
    }

    @discardableResult
    func createOpenRouterManagementCredential(
        for account: ProviderAccount,
        credentialValue: String
    ) throws -> ProviderCredentialContext {
        let account = try requireOpenRouterAccount(account)
        guard !openRouterCredentialContexts(for: account).contains(where: {
            $0.slot.role == .management
        }) else {
            throw OpenRouterSettingsError.managementCredentialExists
        }
        let credential = try makeCredentialSecret(credentialValue)
        let root = try ensureOpenRouterRootContext(for: account)
        let slotID = "management-\(UUID().uuidString.lowercased())"

        invalidateOpenRouterAccount(account)
        do {
            _ = try accountCredentialStore.createCredential(
                providerID: account.providerID,
                accountID: account.accountID,
                slotID: slotID,
                contextID: root.contextID,
                role: .management,
                credential: credential
            )
            reloadOpenRouterPresentationData(for: account)
            guard let created = openRouterCredentialContexts(for: account)
                .first(where: { $0.slot.slotID == slotID }) else {
                throw OpenRouterSettingsError.storageUnavailable
            }
            return created
        } catch {
            reloadOpenRouterPresentationData(for: account)
            throw mapOpenRouterSettingsError(error)
        }
    }

    func renameOpenRouterOrdinaryCredential(
        for account: ProviderAccount,
        contextID: String,
        displayName: String
    ) throws {
        let account = try requireOpenRouterAccount(account)
        guard let existing = openRouterCredentialContexts(for: account)
            .first(where: {
                $0.context.contextID == contextID && $0.slot.role == .ordinary
            }) else {
            throw OpenRouterSettingsError.credentialUnavailable
        }
        let name = try normalizedOpenRouterCredentialName(
            displayName,
            account: account,
            excludingContextID: contextID
        )
        let updated = ProviderAccountContextConfiguration(
            providerID: existing.context.providerID,
            accountID: existing.context.accountID,
            contextID: existing.context.contextID,
            kind: existing.context.kind,
            displayName: name,
            regionID: existing.context.regionID,
            parentContextID: existing.context.parentContextID
        )
        do {
            invalidateOpenRouterAccount(account)
            try accountCredentialStore.updateContext(updated)
            reloadOpenRouterPresentationData(for: account)
        } catch {
            reloadOpenRouterPresentationData(for: account)
            throw mapOpenRouterSettingsError(error)
        }
    }

    func replaceOpenRouterCredential(
        for account: ProviderAccount,
        slotID: String,
        credentialValue: String
    ) throws {
        let account = try requireOpenRouterAccount(account)
        let credential = try makeCredentialSecret(credentialValue)
        guard let context = openRouterCredentialContexts(for: account)
            .first(where: { $0.slot.slotID == slotID }) else {
            throw OpenRouterSettingsError.credentialUnavailable
        }

        invalidateOpenRouterAccount(account)
        do {
            switch context.slot.lifecycleState {
            case .active:
                try accountCredentialStore.replaceCredential(
                    credential,
                    providerID: account.providerID,
                    accountID: account.accountID,
                    slotID: slotID
                )
            case .pendingCreation:
                _ = try accountCredentialStore.recoverPendingCreation(
                    providerID: account.providerID,
                    accountID: account.accountID,
                    slotID: slotID,
                    credential: credential
                )
            case .pendingDeletion:
                throw OpenRouterSettingsError.pendingDeletion
            }
            reloadOpenRouterPresentationData(for: account)
        } catch {
            reloadOpenRouterPresentationData(for: account)
            throw mapOpenRouterSettingsError(error)
        }
    }

    func setOpenRouterCredentialEnabled(
        _ isEnabled: Bool,
        for account: ProviderAccount,
        slotID: String
    ) throws {
        let account = try requireOpenRouterAccount(account)
        guard let context = openRouterCredentialContexts(for: account)
            .first(where: { $0.slot.slotID == slotID }) else {
            throw OpenRouterSettingsError.credentialUnavailable
        }
        invalidateOpenRouterAccount(account)
        do {
            try accountCredentialStore.setCredentialEnabled(
                isEnabled,
                providerID: account.providerID,
                accountID: account.accountID,
                slotID: slotID
            )
            if context.slot.role == .management && !isEnabled {
                try markOpenRouterSharedCreditsUnavailable(for: account)
            }
            reloadOpenRouterPresentationData(for: account)
        } catch {
            reloadOpenRouterPresentationData(for: account)
            throw mapOpenRouterSettingsError(error)
        }
    }

    func deleteOpenRouterCredential(
        for account: ProviderAccount,
        slotID: String
    ) throws {
        let account = try requireOpenRouterAccount(account)
        guard let context = openRouterCredentialContexts(for: account)
            .first(where: { $0.slot.slotID == slotID }) else {
            throw OpenRouterSettingsError.credentialUnavailable
        }
        invalidateOpenRouterAccount(account)
        do {
            try accountCredentialStore.deleteCredential(
                providerID: account.providerID,
                accountID: account.accountID,
                slotID: slotID
            )
            if context.slot.role == .management {
                try markOpenRouterSharedCreditsUnavailable(for: account)
            }
            reloadOpenRouterPresentationData(for: account)
        } catch {
            reloadOpenRouterPresentationData(for: account)
            throw mapOpenRouterSettingsError(error)
        }
    }

    private func requireOpenRouterAccount(
        _ requested: ProviderAccount
    ) throws -> ProviderAccount {
        guard requested.providerID == OpenRouterProviderContract.providerID,
              let account = account(
                  providerID: requested.providerID,
                  accountID: requested.accountID
              ) else {
            throw OpenRouterSettingsError.invalidAccount
        }
        return account
    }

    private func ensureOpenRouterRootContext(
        for account: ProviderAccount
    ) throws -> ProviderAccountContextConfiguration {
        let contexts: [ProviderAccountContextConfiguration]
        do {
            contexts = try accountCredentialStore.loadContexts(
                providerID: account.providerID,
                accountID: account.accountID
            )
        } catch {
            throw mapOpenRouterSettingsError(error)
        }
        if let root = contexts.first(where: { $0.parentContextID == nil }) {
            return root
        }
        let root = ProviderAccountContextConfiguration(
            providerID: account.providerID,
            accountID: account.accountID,
            contextID: "\(account.accountID)-root",
            kind: .personal,
            regionID: "global"
        )
        do {
            try accountCredentialStore.createContext(root)
            return root
        } catch {
            throw mapOpenRouterSettingsError(error)
        }
    }

    private func normalizedOpenRouterCredentialName(
        _ displayName: String,
        account: ProviderAccount,
        excludingContextID: String?
    ) throws -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw OpenRouterSettingsError.invalidName
        }
        let key = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let hasConflict = openRouterCredentialContexts(for: account).contains {
            guard $0.slot.role == .ordinary,
                  $0.context.contextID != excludingContextID,
                  let existingName = $0.context.displayName else {
                return false
            }
            return existingName.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            ) == key
        }
        guard !hasConflict else {
            throw OpenRouterSettingsError.duplicateName
        }
        return name
    }

    private func makeCredentialSecret(
        _ credentialValue: String
    ) throws -> CredentialSecret {
        guard !credentialValue.isEmpty else {
            throw OpenRouterSettingsError.emptyCredential
        }
        do {
            return try CredentialSecret(credentialValue)
        } catch {
            throw OpenRouterSettingsError.emptyCredential
        }
    }

    private func invalidateOpenRouterAccount(_ account: ProviderAccount) {
        openRouterRefreshGenerations[account.id, default: 0] &+= 1
        cancelAccountRefresh(for: account.id)
        (adapter(for: account.providerID) as? OpenRouterProviderAdapter)?
            .invalidateAccount(accountID: account.accountID)
    }

    private func markOpenRouterSharedCreditsUnavailable(
        for account: ProviderAccount
    ) throws {
        let contexts = try accountCredentialStore.loadContexts(
            providerID: account.providerID,
            accountID: account.accountID
        )
        guard let root = contexts.first(where: { $0.parentContextID == nil }) else {
            return
        }
        let observedAt = Date()
        _ = try nativeCapacitySnapshotStore
            .replaceManagementMetricsWithUnavailableIfAbsent(
                CapacitySourceMutation(
                    providerID: account.providerID,
                    accountID: account.accountID,
                    contextID: root.contextID,
                    sourceID: OpenRouterProviderContract.managementSourceID,
                    accountContexts: contexts.map(\.contractContext),
                    metrics: [
                        CapacityMetric(
                            metricID: "account-credits",
                            accountContextID: root.contextID,
                            sourceID: OpenRouterProviderContract.managementSourceID,
                            capability: "credits",
                            displayName: "Account credits",
                            availability: .unavailable,
                            unit: CapacityUnit(
                                kind: .currency,
                                currencyCode: "USD"
                            ),
                            window: CapacityWindow(kind: .none),
                            freshness: ObservationFreshness(
                                observedAt: observedAt
                            ),
                            confidence: .unknown
                        )
                    ],
                    completedAt: observedAt,
                    identityExpectation: .noEnabledManagementSlot
                ),
                surface: OpenRouterProviderContract.surface,
                sources: OpenRouterProviderContract.sources
            )
    }

    private func mapOpenRouterSettingsError(_ error: Error) -> OpenRouterSettingsError {
        if let error = error as? OpenRouterSettingsError {
            return error
        }
        guard let error = error as? CredentialStoreError else {
            return .storageUnavailable
        }
        return switch error {
        case .managementCredentialAlreadyExists:
            .managementCredentialExists
        case .credentialPendingDeletion:
            .pendingDeletion
        case .credentialMissing, .slotNotFound, .contextNotFound:
            .credentialUnavailable
        case let .keychain(keychainError):
            keychainError == .invalidCredential
                ? .emptyCredential
                : .keychainUnavailable
        case .invalidContextTree,
             .invalidCredentialRole,
             .contextAlreadyHasCredential,
             .credentialDisabled,
             .credentialPendingCreation,
             .accountNotFound,
             .storageUnavailable:
            .storageUnavailable
        }
    }

    private func clearOpenRouterStorageWarning() {
        if storageWarning == "OpenRouter credential metadata could not be loaded." {
            storageWarning = nil
        }
    }
}
