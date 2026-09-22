import BairometerCore
import Foundation

extension AppModel {
    func loadConfiguration() {
        let result = configurationStore.load(knownProviderIDs: Set(providerIDs))
        providerAccounts = result.accounts
        storageWarning = storageWarning ?? result.warning
    }

    @discardableResult
    func saveConfiguration() -> Bool {
        do {
            try configurationStore.save(providerAccounts)
            clearStorageWarning("Provider settings could not be saved.")
            return true
        } catch {
            storageWarning = "Provider settings could not be saved."
            AppTelemetry.storage.error("Provider settings could not be saved")
            return false
        }
    }

    func loadRefreshSettings() {
        let result = refreshSettingsStore.load(defaults: RefreshSettings())
        refreshSettings = result.settings
        storageWarning = storageWarning ?? result.warning
    }

    func loadUsageDisplayPreferences() {
        usageDisplayMode = UsageDisplayMode(
            rawValue: userDefaults.string(forKey: UsageDisplayMode.storageKey) ?? ""
        ) ?? .used

        let result = usageDisplayOverrideStore.load()
        usageDisplayOverrides = Dictionary(
            uniqueKeysWithValues: result.overrides.map { ($0.key, $0.mode) }
        )
        storageWarning = storageWarning ?? result.warning
    }

    func setUsageDisplayMode(_ mode: UsageDisplayMode) {
        usageDisplayMode = mode
        userDefaults.set(mode.rawValue, forKey: UsageDisplayMode.storageKey)
    }

    func usageDisplayMode(for account: ProviderAccount, windowID: String) -> UsageDisplayMode {
        usageDisplayMode(for: UsageDisplayOverrideKey(
            providerID: account.providerID,
            accountID: account.accountID,
            windowID: windowID
        ))
    }

    func usageDisplayOverrideSelection(
        for account: ProviderAccount,
        windowID: String
    ) -> UsageDisplayOverrideSelection {
        UsageDisplayOverrideSelection(mode: usageDisplayOverrides[UsageDisplayOverrideKey(
            providerID: account.providerID,
            accountID: account.accountID,
            windowID: windowID
        )])
    }

    @discardableResult
    func setUsageDisplayOverride(
        _ selection: UsageDisplayOverrideSelection,
        for account: ProviderAccount,
        windowID: String
    ) -> Bool {
        let key = UsageDisplayOverrideKey(
            providerID: account.providerID,
            accountID: account.accountID,
            windowID: windowID
        )
        let mode = selection.overrideMode

        do {
            try usageDisplayOverrideStore.set(mode, for: key)
            if let mode {
                usageDisplayOverrides[key] = mode
            } else {
                usageDisplayOverrides.removeValue(forKey: key)
            }
            clearStorageWarning("Usage display preferences could not be saved.")
            return true
        } catch {
            storageWarning = "Usage display preferences could not be saved."
            AppTelemetry.storage.error("Usage display preferences could not be saved")
            return false
        }
    }

    @discardableResult
    func toggleUsageDisplayMode(for account: ProviderAccount, windowID: String) -> Bool {
        let effectiveMode = usageDisplayMode(for: account, windowID: windowID)
        let targetMode: UsageDisplayMode = effectiveMode == .used ? .left : .used
        let selection = targetMode == usageDisplayMode
            ? UsageDisplayOverrideSelection.global
            : UsageDisplayOverrideSelection(mode: targetMode)
        return setUsageDisplayOverride(selection, for: account, windowID: windowID)
    }

    private func usageDisplayMode(for key: UsageDisplayOverrideKey) -> UsageDisplayMode {
        usageDisplayOverrides[key] ?? usageDisplayMode
    }

    @discardableResult
    func saveRefreshSettings() -> Bool {
        do {
            try refreshSettingsStore.save(refreshSettings)
            clearStorageWarning("Refresh settings could not be saved.")
            return true
        } catch {
            storageWarning = "Refresh settings could not be saved."
            AppTelemetry.storage.error("Refresh settings could not be saved")
            return false
        }
    }

    func loadSnapshots() {
        let result = snapshotStore.load()
        snapshots = result.snapshots
        storageWarning = storageWarning ?? result.warning
    }

    @discardableResult
    func saveSnapshots() -> Bool {
        do {
            try snapshotStore.save(snapshots)
            clearStorageWarning("Snapshots could not be saved.")
            return true
        } catch {
            storageWarning = "Snapshots could not be saved."
            AppTelemetry.storage.error("Snapshots could not be saved")
            return false
        }
    }

    func upsert(_ snapshot: UsageSnapshot) {
        if let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
            snapshots[index] = snapshot
        } else {
            snapshots.append(snapshot)
        }
    }

    func existingSnapshot(matching snapshot: UsageSnapshot) -> UsageSnapshot? {
        snapshots.first { $0.id == snapshot.id }
    }

    func loadDiagnostics() {
        let diagnostics = diagnosticStore.load()
        sourceDiagnostics = diagnostics
        sourceRefreshStates = Dictionary(
            uniqueKeysWithValues: diagnosticStore.loadRefreshStates().map { ($0.providerID + ":" + $0.accountID, $0) }
        )
        let configuredAccountIDs = Set(providerAccounts.map(\.id))
        let accountDiagnostics = Dictionary(grouping: diagnostics.compactMap { diagnostic -> (String, SourceDiagnostic)? in
            guard let providerID = diagnostic.providerID,
                  let accountID = diagnostic.accountID,
                  diagnostic.code.hasPrefix("refresh-")
            else { return nil }
            let accountKey = "\(providerID):\(accountID)"
            guard configuredAccountIDs.contains(accountKey) else { return nil }
            return (accountKey, diagnostic)
        }, by: \.0)
        accountRefreshIssues = Dictionary(uniqueKeysWithValues: accountDiagnostics.map { accountID, entries in
            let diagnostics = entries.map(\.1).sorted { $0.code < $1.code }
            return (
                accountID,
                AccountRefreshIssue(
                    occurredAt: diagnostics.map(\.occurredAt).max() ?? Date(),
                    warnings: diagnostics.map(\.message)
                )
            )
        })

        if storageWarning == nil,
           let globalDiagnostic = diagnostics.first(where: { $0.providerID == nil && $0.accountID == nil }) {
            storageWarning = globalDiagnostic.message
        }
    }

    func persistRefreshIssue(_ issue: AccountRefreshIssue, for snapshot: UsageSnapshot) {
        do {
            try diagnosticStore.replaceRefreshDiagnostics(
                providerID: snapshot.providerID,
                accountID: snapshot.accountID,
                occurredAt: issue.occurredAt,
                messages: issue.warnings
            )
        } catch {
            storageWarning = "Provider diagnostics could not be saved."
        }
    }

    func clearPersistedRefreshIssue(for snapshot: UsageSnapshot) {
        do {
            try diagnosticStore.clearRefreshDiagnostics(
                providerID: snapshot.providerID,
                accountID: snapshot.accountID
            )
        } catch {
            storageWarning = "Provider diagnostics could not be saved."
        }
    }

    func recordRefreshAttempt(for snapshot: UsageSnapshot) {
        do {
            try diagnosticStore.recordRefreshAttempt(
                providerID: snapshot.providerID,
                accountID: snapshot.accountID,
                occurredAt: snapshot.lastUpdatedAt
            )
            updateRefreshState(for: snapshot) { state in
                SourceRefreshState(
                    providerID: state?.providerID ?? snapshot.providerID,
                    accountID: state?.accountID ?? snapshot.accountID,
                    lastAttemptAt: snapshot.lastUpdatedAt,
                    lastSuccessfulRefreshAt: state?.lastSuccessfulRefreshAt,
                    lastFailedRefreshAt: state?.lastFailedRefreshAt
                )
            }
        } catch {
            storageWarning = "Provider refresh state could not be saved."
        }
    }

    func recordRefreshSuccess(for snapshot: UsageSnapshot) {
        do {
            try diagnosticStore.recordRefreshSuccess(
                providerID: snapshot.providerID,
                accountID: snapshot.accountID,
                occurredAt: snapshot.lastUpdatedAt
            )
            updateRefreshState(for: snapshot) { state in
                SourceRefreshState(
                    providerID: state?.providerID ?? snapshot.providerID,
                    accountID: state?.accountID ?? snapshot.accountID,
                    lastAttemptAt: snapshot.lastUpdatedAt,
                    lastSuccessfulRefreshAt: snapshot.lastUpdatedAt,
                    lastFailedRefreshAt: state?.lastFailedRefreshAt
                )
            }
        } catch {
            storageWarning = "Provider refresh state could not be saved."
        }
    }

    func recordRefreshFailure(for snapshot: UsageSnapshot) {
        do {
            try diagnosticStore.recordRefreshFailure(
                providerID: snapshot.providerID,
                accountID: snapshot.accountID,
                occurredAt: snapshot.lastUpdatedAt
            )
            updateRefreshState(for: snapshot) { state in
                SourceRefreshState(
                    providerID: state?.providerID ?? snapshot.providerID,
                    accountID: state?.accountID ?? snapshot.accountID,
                    lastAttemptAt: snapshot.lastUpdatedAt,
                    lastSuccessfulRefreshAt: state?.lastSuccessfulRefreshAt,
                    lastFailedRefreshAt: snapshot.lastUpdatedAt
                )
            }
        } catch {
            storageWarning = "Provider refresh state could not be saved."
        }
    }

    private func updateRefreshState(
        for snapshot: UsageSnapshot,
        update: (SourceRefreshState?) -> SourceRefreshState
    ) {
        sourceRefreshStates[snapshot.id] = update(sourceRefreshStates[snapshot.id])
    }

    private func clearStorageWarning(_ warning: String) {
        if storageWarning == warning {
            storageWarning = nil
        }
    }
}
