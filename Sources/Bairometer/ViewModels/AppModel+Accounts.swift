import BairometerCore
import Foundation

extension AppModel {
    func canAddAccount(providerID: String) -> Bool {
        guard adapter(for: providerID) != nil else { return false }
        return !hasExclusiveLocalSourceConflict(
            providerID: providerID,
            accountID: nil,
            sourceMode: ProviderSourceMode.defaultMode(for: providerID)
        )
    }

    func setAccount(_ providerID: String, accountID: String, enabled: Bool) {
        let previousAccounts = providerAccounts
        guard let index = providerAccounts.firstIndex(where: {
            $0.providerID == providerID && $0.accountID == accountID
        }) else { return }

        providerAccounts[index].isEnabled = enabled
        if !enabled {
            cancelAccountRefresh(for: providerAccounts[index].id)
            if let openRouterAdapter = adapter(for: providerID)
                as? OpenRouterProviderAdapter {
                openRouterAdapter.invalidateAccount(accountID: accountID)
            } else if let miniMaxAdapter = adapter(for: providerID)
                as? MiniMaxProviderAdapter {
                miniMaxAdapter.invalidateAccount(accountID: accountID)
            }
        }
        if !saveConfiguration() {
            providerAccounts = previousAccounts
        }
    }

    func setAccountDisplayName(_ providerID: String, accountID: String, displayName: String) {
        let previousAccounts = providerAccounts
        let previousSnapshots = snapshots
        guard let index = providerAccounts.firstIndex(where: {
            $0.providerID == providerID && $0.accountID == accountID
        }) else { return }

        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayName = trimmed.isEmpty ? ProviderAccount.defaultDisplayName : trimmed
        guard !hasDisplayNameConflict(
            accountID: accountID,
            displayName: resolvedDisplayName
        ) else { return }
        providerAccounts[index].displayName = resolvedDisplayName
        updateSnapshotAccountDisplayName(
            providerID: providerID,
            accountID: accountID,
            displayName: resolvedDisplayName
        )
        guard saveConfiguration() else {
            providerAccounts = previousAccounts
            snapshots = previousSnapshots
            return
        }
        saveSnapshots()
    }

    @discardableResult
    func updateAccount(
        providerID: String,
        accountID: String,
        displayName: String,
        sourceMode: ProviderSourceMode,
        executablePath: String? = nil
    ) -> Bool {
        let previousAccounts = providerAccounts
        let previousSnapshots = snapshots
        guard let index = providerAccounts.firstIndex(where: {
            $0.providerID == providerID && $0.accountID == accountID
        }) else { return false }

        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExecutablePath = executablePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedDisplayName = trimmedDisplayName.isEmpty ? ProviderAccount.defaultDisplayName : trimmedDisplayName
        let resolvedSourceMode = ProviderSourceMode.resolvedMode(sourceMode, for: providerID)

        guard !hasDisplayNameConflict(
            accountID: accountID,
            displayName: resolvedDisplayName
        ) else { return false }

        guard !hasExclusiveLocalSourceConflict(
            providerID: providerID,
            accountID: accountID,
            sourceMode: resolvedSourceMode
        ) else { return false }

        providerAccounts[index].displayName = resolvedDisplayName
        providerAccounts[index].sourceMode = resolvedSourceMode
        providerAccounts[index].executablePath = trimmedExecutablePath.isEmpty ? nil : trimmedExecutablePath
        updateSnapshotAccountDisplayName(
            providerID: providerID,
            accountID: accountID,
            displayName: resolvedDisplayName
        )

        guard saveConfiguration() else {
            providerAccounts = previousAccounts
            snapshots = previousSnapshots
            return false
        }
        saveSnapshots()
        return true
    }

    @discardableResult
    func prepareOllamaWebPageConnection(providerID: String, accountID: String) -> ProviderAccount? {
        guard providerID == "ollama-cloud",
              let index = providerAccounts.firstIndex(where: {
                  $0.providerID == providerID && $0.accountID == accountID
              })
        else { return nil }

        if providerAccounts[index].webDataStoreID == nil {
            let previousAccounts = providerAccounts
            providerAccounts[index].webDataStoreID = UUID()
            guard saveConfiguration() else {
                providerAccounts = previousAccounts
                return nil
            }
        }
        return providerAccounts[index]
    }

    func setAccountSourceMode(_ providerID: String, accountID: String, sourceMode: ProviderSourceMode) {
        let previousAccounts = providerAccounts
        let resolvedSourceMode = ProviderSourceMode.resolvedMode(sourceMode, for: providerID)
        guard let index = providerAccounts.firstIndex(where: {
            $0.providerID == providerID && $0.accountID == accountID
        }), !hasExclusiveLocalSourceConflict(
            providerID: providerID,
            accountID: accountID,
            sourceMode: resolvedSourceMode
        ) else { return }

        providerAccounts[index].sourceMode = resolvedSourceMode
        if !saveConfiguration() {
            providerAccounts = previousAccounts
        }
    }

    func moveAccountUp(providerID: String, accountID: String) {
        moveAccount(providerID: providerID, accountID: accountID, offset: -1)
    }

    func moveAccountDown(providerID: String, accountID: String) {
        moveAccount(providerID: providerID, accountID: accountID, offset: 1)
    }

    func moveAccounts(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !offsets.isEmpty,
              destination >= 0,
              destination <= providerAccounts.count,
              offsets.allSatisfy(providerAccounts.indices.contains)
        else { return }

        let previousAccounts = providerAccounts
        let movedAccounts = offsets.map { providerAccounts[$0] }
        var remainingAccounts = providerAccounts.enumerated().compactMap { index, account in
            offsets.contains(index) ? nil : account
        }
        let adjustedDestination = destination - offsets.filter { $0 < destination }.count
        remainingAccounts.insert(contentsOf: movedAccounts, at: adjustedDestination)
        providerAccounts = remainingAccounts

        if !saveConfiguration() {
            providerAccounts = previousAccounts
        }
    }

    func canMoveAccountUp(providerID: String, accountID: String) -> Bool {
        guard let index = providerAccounts.firstIndex(where: {
            $0.providerID == providerID && $0.accountID == accountID
        }) else { return false }
        return index > providerAccounts.startIndex
    }

    func canMoveAccountDown(providerID: String, accountID: String) -> Bool {
        guard let index = providerAccounts.firstIndex(where: {
            $0.providerID == providerID && $0.accountID == accountID
        }) else { return false }
        return index < providerAccounts.index(before: providerAccounts.endIndex)
    }

    @discardableResult
    func addAccount(
        providerID: String,
        displayName: String? = nil,
        isEnabled: Bool = true,
        sourceMode: ProviderSourceMode? = nil,
        executablePath: String? = nil
    ) -> ProviderAccount? {
        guard adapter(for: providerID) != nil else { return nil }
        let previousAccounts = providerAccounts
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedExecutablePath = executablePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedSourceMode = ProviderSourceMode.resolvedMode(sourceMode, for: providerID)
        guard !hasExclusiveLocalSourceConflict(
            providerID: providerID,
            accountID: nil,
            sourceMode: resolvedSourceMode
        ) else { return nil }
        let account = ProviderAccount(
            providerID: providerID,
            accountID: "account-\(UUID().uuidString.lowercased())",
            displayName: trimmedDisplayName.isEmpty ? nextAccountDisplayName(for: providerID) : trimmedDisplayName,
            isEnabled: isEnabled,
            sourceMode: resolvedSourceMode,
            executablePath: trimmedExecutablePath.isEmpty ? nil : trimmedExecutablePath
        )
        guard !hasDisplayNameConflict(
            accountID: nil,
            displayName: account.displayName
        ) else { return nil }
        providerAccounts.append(account)
        if !saveConfiguration() {
            providerAccounts = previousAccounts
            return nil
        }
        if providerID == OpenRouterProviderContract.providerID {
            do {
                try initializeOpenRouterAccount(account)
            } catch {
                try? accountCredentialStore.deleteAccount(
                    providerID: providerID,
                    accountID: account.accountID
                )
                providerAccounts = previousAccounts
                storageWarning = "OpenRouter credential metadata could not be loaded."
                return nil
            }
        } else if providerID == MiniMaxProviderContract.providerID {
            do {
                try initializeMiniMaxAccount(account)
            } catch {
                try? accountCredentialStore.deleteAccount(
                    providerID: providerID,
                    accountID: account.accountID
                )
                providerAccounts = previousAccounts
                storageWarning = "Provider settings could not be saved."
                return nil
            }
        }
        return account
    }

    func deleteAccount(providerID: String, accountID: String) {
        let accountKey = "\(providerID):\(accountID)"
        let previousAccounts = providerAccounts
        let previousSnapshots = snapshots
        let previousStatuses = providerRefreshStatuses
        let previousIssues = accountRefreshIssues
        let previousRefreshStates = sourceRefreshStates
        guard let account = providerAccounts.first(where: {
            $0.providerID == providerID && $0.accountID == accountID
        }) else { return }

        cancelAccountRefresh(for: accountKey)
        if let openRouterAdapter = adapter(for: providerID)
            as? OpenRouterProviderAdapter {
            openRouterAdapter.invalidateAccount(accountID: accountID)
        } else if let miniMaxAdapter = adapter(for: providerID)
            as? MiniMaxProviderAdapter {
            miniMaxAdapter.invalidateAccount(accountID: accountID)
        }

        if providerID == OpenRouterProviderContract.providerID
            || providerID == MiniMaxProviderContract.providerID {
            do {
                try accountCredentialStore.deleteAccount(
                    providerID: providerID,
                    accountID: accountID
                )
            } catch {
                storageWarning = "Provider settings could not be saved."
                return
            }
        }
        providerAccounts.removeAll { $0.providerID == providerID && $0.accountID == accountID }
        snapshots.removeAll { $0.id == accountKey }
        providerRefreshStatuses.removeValue(forKey: accountKey)
        accountRefreshIssues.removeValue(forKey: accountKey)
        sourceRefreshStates.removeValue(forKey: accountKey)
        nativeCapacitySnapshots.removeValue(forKey: accountKey)
        credentialContextsByAccount.removeValue(forKey: accountKey)
        credentialRefreshStatesByAccount.removeValue(forKey: accountKey)
        credentialDiagnosticsByAccount.removeValue(forKey: accountKey)
        guard providerID == OpenRouterProviderContract.providerID
                || providerID == MiniMaxProviderContract.providerID
                || saveConfiguration() else {
            providerAccounts = previousAccounts
            snapshots = previousSnapshots
            providerRefreshStatuses = previousStatuses
            accountRefreshIssues = previousIssues
            sourceRefreshStates = previousRefreshStates
            return
        }
        saveSnapshots()
        if account.providerID == "ollama-cloud" {
            clearOllamaConnection(for: account)
            ollamaWebPageClient?.forgetSession(for: account)
        }
    }

    func canDeleteAccount(providerID: String, accountID: String) -> Bool {
        providerAccounts.contains { $0.providerID == providerID && $0.accountID == accountID }
    }

    func updateSnapshotAccountDisplayName(providerID: String, accountID: String, displayName: String) {
        guard let index = snapshots.firstIndex(where: {
            $0.providerID == providerID && $0.accountID == accountID
        }) else { return }

        let snapshot = snapshots[index]
        snapshots[index] = UsageSnapshot(
            providerID: snapshot.providerID,
            accountID: snapshot.accountID,
            accountDisplayName: displayName,
            displayName: snapshot.displayName,
            status: snapshot.status,
            planName: snapshot.planName,
            periodLabel: snapshot.periodLabel,
            usedPercent: snapshot.usedPercent,
            remainingLabel: snapshot.remainingLabel,
            resetAt: snapshot.resetAt,
            limitWindows: snapshot.limitWindows,
            lastUpdatedAt: snapshot.lastUpdatedAt,
            confidence: snapshot.confidence,
            source: snapshot.source,
            warnings: snapshot.warnings
        )
    }

    func hasDisplayNameConflict(
        accountID: String?,
        displayName: String
    ) -> Bool {
        let nameKey = DatabaseProviderConfigurationStore.displayNameKey(for: displayName)
        return providerAccounts.contains {
            $0.accountID != accountID &&
                DatabaseProviderConfigurationStore.displayNameKey(for: $0.displayName) == nameKey
        }
    }

    private func nextAccountDisplayName(for providerID: String) -> String {
        var number = accounts(for: providerID).count + 1
        while hasDisplayNameConflict(
            accountID: nil,
            displayName: "Account \(number)"
        ) {
            number += 1
        }
        return "Account \(number)"
    }

    func hasCodexAppServerConflict(
        providerID: String,
        accountID: String?,
        sourceMode: ProviderSourceMode
    ) -> Bool {
        guard providerID == "openai-codex", sourceMode == .appServer else { return false }
        return providerAccounts.contains {
            $0.providerID == "openai-codex" &&
                $0.sourceMode == .appServer &&
                $0.accountID != accountID
        }
    }

    func hasClaudeUsageCLIConflict(
        providerID: String,
        accountID: String?,
        sourceMode: ProviderSourceMode
    ) -> Bool {
        guard providerID == "claude-code", sourceMode == .claudeUsageCLI else { return false }
        return providerAccounts.contains {
            $0.providerID == "claude-code" &&
                $0.sourceMode == .claudeUsageCLI &&
                $0.accountID != accountID
        }
    }

    private func hasExclusiveLocalSourceConflict(
        providerID: String,
        accountID: String?,
        sourceMode: ProviderSourceMode
    ) -> Bool {
        hasCodexAppServerConflict(
            providerID: providerID,
            accountID: accountID,
            sourceMode: sourceMode
        ) || hasClaudeUsageCLIConflict(
            providerID: providerID,
            accountID: accountID,
            sourceMode: sourceMode
        )
    }

    private func moveAccount(providerID: String, accountID: String, offset: Int) {
        let previousAccounts = providerAccounts
        guard let sourceIndex = providerAccounts.firstIndex(where: {
            $0.providerID == providerID && $0.accountID == accountID
        }) else { return }

        let destinationIndex = sourceIndex + offset
        guard providerAccounts.indices.contains(destinationIndex) else { return }
        providerAccounts.swapAt(sourceIndex, destinationIndex)
        if !saveConfiguration() {
            providerAccounts = previousAccounts
        }
    }
}
