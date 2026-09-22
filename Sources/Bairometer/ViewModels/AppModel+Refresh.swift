import BairometerCore
import Foundation

extension AppModel {
    func acceptOllamaUsagePayload(_ payload: OllamaUsagePagePayload, for account: ProviderAccount) {
        guard let adapter = adapter(for: account.providerID) as? OllamaCloudProviderAdapter else { return }

        do {
            let snapshot = try adapter.makeSnapshot(account: account, payload: payload)
            if handleRefreshedSnapshot(snapshot) {
                saveSnapshots()
            }
        } catch {
            let snapshot = refreshCoordinator.errorSnapshot(
                account: account,
                providerDisplayName: adapter.displayName,
                error: error
            )
            if handleRefreshedSnapshot(snapshot) {
                saveSnapshots()
            }
        }
    }

    func setRefreshInterval(_ interval: RefreshInterval) {
        let previousSettings = refreshSettings
        refreshSettings.interval = interval
        guard saveRefreshSettings() else {
            refreshSettings = previousSettings
            return
        }
        configureScheduledRefresh()
    }

    func startLaunchRefresh() {
        guard !hasStartedLaunchRefresh else { return }
        hasStartedLaunchRefresh = true
        refresh()
    }

    func refresh() {
        guard globalRefreshTask == nil, !isRefreshing, !hasActiveProviderRefresh else { return }
        isRefreshing = true
        AppTelemetry.refresh.info("Refreshing all enabled accounts")

        globalRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer { finishGlobalRefresh() }
            await refreshEnabledProviders()
        }
    }

    func refreshAccount(providerID: String, accountID: String) {
        guard let adapter = adapter(for: providerID) else { return }
        guard let account = account(providerID: providerID, accountID: accountID), account.isEnabled else { return }
        guard !isRefreshing, refreshStatus(for: account) != .refreshing else { return }
        setRefreshStatus(.refreshing, for: account.id)
        AppTelemetry.refresh.info("Refreshing one account")
        let taskID = UUID()
        let openRouterGeneration = account.providerID
            == OpenRouterProviderContract.providerID
            ? openRouterRefreshGeneration(for: account.id)
            : nil
        let miniMaxGeneration = account.providerID
            == MiniMaxProviderContract.providerID
            ? miniMaxRefreshGeneration(for: account.id)
            : nil
        accountRefreshTaskIDs[account.id] = taskID

        accountRefreshTasks[account.id] = Task { [weak self] in
            guard let self else { return }
            defer { finishAccountRefresh(for: account.id, taskID: taskID) }
            let snapshot = await refreshCoordinator.refresh(
                ProviderRefreshRequest(adapter: adapter, account: account)
            )
            guard !Task.isCancelled, self.account(providerID: providerID, accountID: accountID) != nil else {
                return
            }
            if handleRefreshedSnapshot(
                snapshot,
                expectedOpenRouterGeneration: openRouterGeneration,
                expectedMiniMaxGeneration: miniMaxGeneration
            ) {
                saveSnapshots()
            }
        }
    }

    func testConnection(providerID: String, accountID: String) {
        guard let adapter = adapter(for: providerID) else { return }
        guard let account = account(providerID: providerID, accountID: accountID) else { return }
        guard !isRefreshing, refreshStatus(for: account) != .refreshing else { return }
        setRefreshStatus(.refreshing, for: account.id)
        AppTelemetry.refresh.info("Testing one account connection")
        let taskID = UUID()
        let openRouterGeneration = account.providerID
            == OpenRouterProviderContract.providerID
            ? openRouterRefreshGeneration(for: account.id)
            : nil
        let miniMaxGeneration = account.providerID
            == MiniMaxProviderContract.providerID
            ? miniMaxRefreshGeneration(for: account.id)
            : nil
        accountRefreshTaskIDs[account.id] = taskID

        accountRefreshTasks[account.id] = Task { [weak self] in
            guard let self else { return }
            defer { finishAccountRefresh(for: account.id, taskID: taskID) }
            let snapshot = await refreshCoordinator.refresh(
                ProviderRefreshRequest(adapter: adapter, account: account)
            )
            guard !Task.isCancelled, self.account(providerID: providerID, accountID: accountID) != nil else {
                return
            }
            if handleRefreshedSnapshot(
                snapshot,
                expectedOpenRouterGeneration: openRouterGeneration,
                expectedMiniMaxGeneration: miniMaxGeneration
            ) {
                saveSnapshots()
            }
        }
    }

    func refreshEnabledProviders() async {
        let enabledAccounts = providerAccounts
            .filter(\.isEnabled)
            .filter { registry.adaptersByID[$0.providerID] != nil }
        guard !enabledAccounts.isEmpty else { return }

        for account in enabledAccounts {
            setRefreshStatus(.refreshing, for: account.id)
        }
        let requests = enabledAccounts.compactMap { account -> ProviderRefreshRequest? in
            guard let adapter = registry.adaptersByID[account.providerID] else { return nil }
            return ProviderRefreshRequest(adapter: adapter, account: account)
        }
        let openRouterGenerations = Dictionary(
            uniqueKeysWithValues: enabledAccounts.compactMap { account in
                account.providerID == OpenRouterProviderContract.providerID
                    ? (
                        account.id,
                        openRouterRefreshGeneration(for: account.id)
                    )
                    : nil
            }
        )
        let miniMaxGenerations = Dictionary(
            uniqueKeysWithValues: enabledAccounts.compactMap { account in
                account.providerID == MiniMaxProviderContract.providerID
                    ? (
                        account.id,
                        miniMaxRefreshGeneration(for: account.id)
                    )
                    : nil
            }
        )
        let refreshedSnapshots = await refreshCoordinator.refresh(requests)
        guard !Task.isCancelled else { return }

        var didChangeSnapshots = false
        for snapshot in refreshedSnapshots {
            didChangeSnapshots = handleRefreshedSnapshot(
                snapshot,
                expectedOpenRouterGeneration: openRouterGenerations[snapshot.id],
                expectedMiniMaxGeneration: miniMaxGenerations[snapshot.id]
            ) || didChangeSnapshots
        }
        if didChangeSnapshots {
            saveSnapshots()
        }
    }

    @discardableResult
    func handleRefreshedSnapshot(
        _ snapshot: UsageSnapshot,
        expectedOpenRouterGeneration: UInt64? = nil,
        expectedMiniMaxGeneration: UInt64? = nil
    ) -> Bool {
        if snapshot.providerID == OpenRouterProviderContract.providerID,
           let expectedOpenRouterGeneration,
           openRouterRefreshGeneration(for: snapshot.id)
               != expectedOpenRouterGeneration {
            return false
        }
        if snapshot.providerID == MiniMaxProviderContract.providerID,
           let expectedMiniMaxGeneration,
           miniMaxRefreshGeneration(for: snapshot.id)
               != expectedMiniMaxGeneration {
            return false
        }
        guard account(
            providerID: snapshot.providerID,
            accountID: snapshot.accountID
        )?.isEnabled == true else {
            return false
        }
        if snapshot.status == .error {
            recordRefreshFailure(for: snapshot)
            handleFailedSnapshot(snapshot)
        } else {
            if snapshot.status == .ok || snapshot.status == .warning {
                recordRefreshSuccess(for: snapshot)
            } else {
                recordRefreshAttempt(for: snapshot)
            }
            upsert(snapshot)
            accountRefreshIssues.removeValue(forKey: snapshot.id)
            clearPersistedRefreshIssue(for: snapshot)
            setRefreshStatus(.succeeded(snapshot.lastUpdatedAt), for: snapshot.id)
        }
        if snapshot.providerID == OpenRouterProviderContract.providerID,
           let account = account(
               providerID: snapshot.providerID,
               accountID: snapshot.accountID
           ) {
#if DEBUG
            if let syntheticAdapter = adapter(for: snapshot.providerID)
                as? UITestScriptedProviderAdapter,
               syntheticAdapter.preservesNativePresentationFixture {
                return true
            }
#endif
            reloadOpenRouterPresentationData(for: account)
        }
        if snapshot.providerID == MiniMaxProviderContract.providerID,
           let account = account(
               providerID: snapshot.providerID,
               accountID: snapshot.accountID
           ) {
            reloadMiniMaxPresentationData(for: account)
        }
        return true
    }

    func openRouterRefreshGeneration(for accountKey: String) -> UInt64 {
        openRouterRefreshGenerations[accountKey, default: 0]
    }

    func handleFailedSnapshot(_ snapshot: UsageSnapshot) {
        guard account(
            providerID: snapshot.providerID,
            accountID: snapshot.accountID
        )?.isEnabled == true else {
            return
        }
        if existingSnapshot(matching: snapshot) == nil {
            upsert(snapshot)
        }
        let issue = AccountRefreshIssue(
            occurredAt: snapshot.lastUpdatedAt,
            warnings: snapshot.warnings
        )
        accountRefreshIssues[snapshot.id] = issue
        persistRefreshIssue(issue, for: snapshot)
        setRefreshStatus(.failed(snapshot.lastUpdatedAt), for: snapshot.id)
    }

    func setRefreshStatus(_ status: ProviderRefreshStatus, for accountKey: String) {
        providerRefreshStatuses[accountKey] = status
    }

    func cancelAccountRefresh(for accountKey: String) {
        accountRefreshTasks.removeValue(forKey: accountKey)?.cancel()
        accountRefreshTaskIDs.removeValue(forKey: accountKey)
        providerRefreshStatuses.removeValue(forKey: accountKey)
    }

    private func finishAccountRefresh(for accountKey: String, taskID: UUID) {
        guard accountRefreshTaskIDs[accountKey] == taskID else { return }
        accountRefreshTasks.removeValue(forKey: accountKey)
        accountRefreshTaskIDs.removeValue(forKey: accountKey)
    }

    private func finishGlobalRefresh() {
        isRefreshing = false
        globalRefreshTask = nil
        AppTelemetry.refresh.info("Finished refreshing enabled accounts")
    }

    func configureScheduledRefresh() {
        scheduledRefreshTimer?.invalidate()
        scheduledRefreshTimer = nil
        guard let timeInterval = refreshSettings.interval.timeInterval else { return }

        scheduledRefreshTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

#if DEBUG
    func waitForRefreshCompletionForTesting() async {
        if let task = globalRefreshTask {
            await task.value
        }
        let tasks = Array(accountRefreshTasks.values)
        for task in tasks {
            await task.value
        }
    }
#endif
}
