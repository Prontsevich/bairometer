import BairometerCore
import Foundation

enum MenuBarIndicatorState: Equatable {
    case normal
    case warning
    case error
}

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshots: [UsageSnapshot] = []
    @Published var providerAccounts: [ProviderAccount] = []
    @Published var providerRefreshStatuses: [String: ProviderRefreshStatus] = [:]
    @Published var accountRefreshIssues: [String: AccountRefreshIssue] = [:]
    @Published var sourceDiagnostics: [SourceDiagnostic] = []
    @Published var sourceRefreshStates: [String: SourceRefreshState] = [:]
    @Published var nativeCapacitySnapshots: [String: CapacitySnapshot] = [:]
    @Published var credentialContextsByAccount: [String: [ProviderCredentialContext]] = [:]
    @Published var credentialRefreshStatesByAccount: [String: [CredentialContextRefreshState]] = [:]
    @Published var credentialDiagnosticsByAccount: [String: [CredentialContextDiagnostic]] = [:]
    @Published var refreshSettings = RefreshSettings()
    @Published var usageDisplayMode: UsageDisplayMode = .used
    @Published var usageDisplayOverrides: [UsageDisplayOverrideKey: UsageDisplayMode] = [:]
    @Published var isRefreshing = false
    @Published var storageWarning: String?
    @Published private(set) var ollamaConnectionAccount: ProviderAccount?

    let registry: ProviderRegistry
    let snapshotStore: any CurrentSnapshotStore
    let configurationStore: any ProviderAccountStore
    let refreshSettingsStore: any RefreshSettingsStoreProtocol
    let usageDisplayOverrideStore: any UsageDisplayOverrideStore
    let diagnosticStore: any SourceDiagnosticStore
    let accountCredentialStore: AccountCredentialStore
    let nativeCapacitySnapshotStore: any NativeCapacitySnapshotStore
    let userDefaults: UserDefaults
    let refreshCoordinator: ProviderRefreshCoordinator
    let ollamaWebPageClient: OllamaWebPageClientController?
    var scheduledRefreshTimer: Timer?
    var hasStartedLaunchRefresh = false
    var globalRefreshTask: Task<Void, Never>?
    var accountRefreshTasks: [String: Task<Void, Never>] = [:]
    var accountRefreshTaskIDs: [String: UUID] = [:]
    var openRouterRefreshGenerations: [String: UInt64] = [:]

    init(
        registry: ProviderRegistry? = nil,
        ollamaWebPageClient: OllamaWebPageClientController? = nil,
        directoryResolver: ApplicationSupportDirectoryResolver = ApplicationSupportDirectoryResolver(),
        storageDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard,
        refreshCoordinator: ProviderRefreshCoordinator = ProviderRefreshCoordinator(),
        openRouterAPIClient: any OpenRouterAPIClient = URLSessionOpenRouterAPIClient(),
        miniMaxAPIClient: any MiniMaxAPIClient = URLSessionMiniMaxAPIClient(
            reviewedCategories: MiniMaxProviderContract.reviewedQuotaCategories
        ),
        credentialKeychainService: any KeychainService = MacOSKeychainService(),
        openRouterRefreshPolicy: OpenRouterRefreshPolicy = OpenRouterRefreshPolicy(),
        miniMaxRefreshPolicy: MiniMaxRefreshPolicy = MiniMaxRefreshPolicy()
    ) {
        self.ollamaWebPageClient = ollamaWebPageClient
        let resolvedClient: any OllamaWebPageClient = ollamaWebPageClient ?? UnavailableOllamaWebPageClient()
        self.refreshCoordinator = refreshCoordinator
        self.userDefaults = userDefaults

        let directory: URL
        var initialStorageWarning: String?
        if let storageDirectory {
            directory = storageDirectory
        } else {
            do {
                directory = try directoryResolver.resolve()
            } catch {
                let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("Bairometer")
                try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
                directory = fallback
                initialStorageWarning = "Application Support is unavailable. Temporary storage is active."
            }
        }

        let database: AppDatabase?
        do {
            database = try AppDatabase(directory: directory)
        } catch {
            database = nil
            initialStorageWarning = "Bairometer storage is unavailable. Changes cannot be saved."
        }
        let snapshotStore = DatabaseSnapshotStore(database: database)
        self.snapshotStore = snapshotStore
        self.configurationStore = DatabaseProviderConfigurationStore(database: database)
        self.refreshSettingsStore = DatabaseRefreshSettingsStore(database: database)
        self.usageDisplayOverrideStore = DatabaseUsageDisplayOverrideStore(database: database)
        let diagnosticStore = DatabaseSourceDiagnosticStore(database: database)
        self.diagnosticStore = diagnosticStore
        let accountCredentialStore = AccountCredentialStore(
            database: database,
            keychainService: credentialKeychainService
        )
        let nativeCapacitySnapshotStore = DatabaseCapacitySnapshotStore(
            database: database
        )
        self.accountCredentialStore = accountCredentialStore
        self.nativeCapacitySnapshotStore = nativeCapacitySnapshotStore
        self.storageWarning = initialStorageWarning
        self.registry = registry ?? ProviderRegistry(
            ollamaWebPageClient: resolvedClient,
            claudeSnapshotStore: snapshotStore,
            openRouterRefreshCoordinator: OpenRouterRefreshCoordinator(
                credentialStore: accountCredentialStore,
                capacityStore: nativeCapacitySnapshotStore,
                client: openRouterAPIClient,
                policy: openRouterRefreshPolicy
            ),
            miniMaxRefreshCoordinator: MiniMaxRefreshCoordinator(
                credentialStore: accountCredentialStore,
                capacityStore: nativeCapacitySnapshotStore,
                diagnosticStore: diagnosticStore,
                client: miniMaxAPIClient,
                policy: miniMaxRefreshPolicy
            )
        )

        if let database {
            do {
                try LegacyStorageImporter(
                    directory: directory,
                    database: database,
                    knownProviderIDs: Set(self.registry.adapters.map(\.id))
                ).runIfNeeded()
            } catch {
                self.storageWarning = "Legacy JSON data could not be migrated. Existing database data remains available."
            }
        }
        loadConfiguration()
        loadRefreshSettings()
        loadUsageDisplayPreferences()
        loadSnapshots()
        loadDiagnostics()
        loadOpenRouterPresentationData()
        configureScheduledRefresh()
    }

    isolated deinit {
        scheduledRefreshTimer?.invalidate()
        globalRefreshTask?.cancel()
        accountRefreshTasks.values.forEach { $0.cancel() }
    }

    var enabledSnapshots: [UsageSnapshot] {
        providerAccounts
            .filter(\.isEnabled)
            .compactMap { snapshot(for: $0) }
    }

    var enabledAccountRows: [AccountSnapshotRow] {
        providerAccounts
            .filter(\.isEnabled)
            .filter { registry.adaptersByID[$0.providerID] != nil }
            .map { account in
                AccountSnapshotRow(
                    account: account,
                    providerDisplayName: providerDisplayName(for: account.providerID),
                    snapshot: snapshot(for: account),
                    refreshStatus: refreshStatus(for: account),
                    refreshIssue: accountRefreshIssues[account.id]
                )
            }
    }

    var hasEnabledAccounts: Bool {
        providerAccounts.contains(where: \.isEnabled)
    }

    var hasActiveProviderRefresh: Bool {
        providerRefreshStatuses.values.contains(.refreshing)
    }

    func presentOllamaConnection(for account: ProviderAccount) {
        ollamaConnectionAccount = account
    }

    func clearOllamaConnection(for account: ProviderAccount) {
        guard ollamaConnectionAccount?.id == account.id else { return }
        ollamaConnectionAccount = nil
    }

    var menuBarIndicatorState: MenuBarIndicatorState {
        let enabledAccounts = providerAccounts.filter(\.isEnabled)

        if enabledAccounts.contains(where: { account in
            accountRefreshIssues[account.id] != nil || snapshot(for: account)?.status == .error
        }) {
            return .error
        }
        if enabledAccounts.contains(where: { snapshot(for: $0)?.status == .warning }) {
            return .warning
        }
        return .normal
    }

    var menuBarAccessibilityValue: String {
        menuBarAccessibilityValue(locale: Locale(identifier: "en_US"))
    }

    func menuBarAccessibilityValue(locale: Locale) -> String {
        let highestUsage = enabledSnapshots
            .flatMap(\.displayLimitWindows)
            .compactMap(\.usedPercent)
            .max()

        let usageText: String
        if let highestUsage {
            usageText = AppStrings.Dashboard.highestUsage.formatted(
                locale: locale,
                AppFormatters.percentage(highestUsage, locale: locale)
            )
        } else {
            usageText = hasEnabledAccounts
                ? AppStrings.Dashboard.noUsageAvailable.localized(locale: locale)
                : AppStrings.Dashboard.noEnabledAccounts.localized(locale: locale)
        }

        switch menuBarIndicatorState {
        case .normal:
            return usageText
        case .warning:
            return AppStrings.Dashboard.warningSummary.formatted(locale: locale, usageText)
        case .error:
            return AppStrings.Dashboard.errorSummary.formatted(locale: locale, usageText)
        }
    }

    func localizedStorageWarning(locale: Locale) -> String? {
        guard let storageWarning else { return nil }

        return switch storageWarning {
        case "Provider settings could not be saved.":
            AppStrings.Storage.providerSettingsSave.localized(locale: locale)
        case "Refresh settings could not be saved.":
            AppStrings.Storage.refreshSettingsSave.localized(locale: locale)
        case "Usage display preferences could not be loaded.":
            AppStrings.Storage.usageDisplayPreferencesLoad.localized(locale: locale)
        case "Usage display preferences could not be saved.":
            AppStrings.Storage.usageDisplayPreferencesSave.localized(locale: locale)
        case "Snapshots could not be saved.":
            AppStrings.Storage.snapshotsSave.localized(locale: locale)
        case "Provider diagnostics could not be saved.":
            AppStrings.Storage.diagnosticsSave.localized(locale: locale)
        case "Provider refresh state could not be saved.":
            AppStrings.Storage.refreshStateSave.localized(locale: locale)
        case "Legacy JSON data could not be migrated. Existing database data remains available.":
            AppStrings.Storage.legacyMigration.localized(locale: locale)
        case "Application Support is unavailable. Temporary storage is active.":
            AppStrings.Storage.temporaryStorage.localized(locale: locale)
        case "Bairometer storage is unavailable. Changes cannot be saved.":
            AppStrings.Storage.storageUnavailable.localized(locale: locale)
        case "OpenRouter credential metadata could not be loaded.":
            AppStrings.Storage.openRouterCredentials.localized(locale: locale)
        default:
            storageWarning
        }
    }

    func adapter(for providerID: String) -> (any ProviderAdapter)? {
        registry.adaptersByID[providerID]
    }

    var providerIDs: [String] {
        registry.adapters.map(\.id)
    }

    func providerDisplayName(for providerID: String) -> String {
        adapter(for: providerID)?.displayName ?? providerID
    }

    func providerCapabilities(for providerID: String) -> ProviderCapabilities {
        adapter(for: providerID)?.capabilities ?? .manualOnly
    }

    func sourceCapability(for account: ProviderAccount) -> ProviderSourceCapability? {
        providerCapabilities(for: account.providerID).capability(for: account.sourceMode)
    }

    func accountDiagnostics(for account: ProviderAccount) -> ProviderAccountDiagnostics {
        let capability = sourceCapability(for: account)
        let state = sourceRefreshStates[account.id]
        let snapshot = snapshot(for: account)
        let issue = accountRefreshIssues[account.id]

        let availability: ProviderSourceAvailability
        let message: String
        let messages: [String]

        if capability == nil {
            availability = .unsupported
            message = "This source mode is not supported by the provider adapter."
            messages = [message]
        } else if issue != nil || snapshot?.status == .error {
            availability = .failed
            messages = issue?.warnings ?? snapshot?.warnings ?? ["The last refresh failed."]
            message = messages.first ?? "The last refresh failed."
        } else if account.sourceMode == .ollamaWebPage && account.webDataStoreID == nil {
            availability = .needsConnection
            message = "Connect this account through Bairometer before refreshing."
            messages = [message]
        } else if snapshot == nil || snapshot?.status == .unavailable {
            availability = .noData
            message = noDataMessage(for: account)
            if let snapshot, !snapshot.warnings.isEmpty {
                messages = snapshot.warnings
            } else {
                messages = [message]
            }
        } else {
            availability = .supported
            message = capability?.summary ?? "The configured source is supported."
            messages = []
        }

        return ProviderAccountDiagnostics(
            providerID: account.providerID,
            accountID: account.accountID,
            sourceMode: account.sourceMode,
            sourceKind: capability?.kind,
            availability: availability,
            message: message,
            lastAttemptAt: state?.lastAttemptAt,
            lastSuccessfulRefreshAt: state?.lastSuccessfulRefreshAt,
            lastFailedRefreshAt: state?.lastFailedRefreshAt,
            messages: messages
        )
    }

    func localizedAccountDiagnosticsMessage(for account: ProviderAccount, locale: Locale) -> String {
        let diagnostics = accountDiagnostics(for: account)

        switch diagnostics.availability {
        case .unsupported:
            return AppStrings.Dashboard.sourceUnsupported.localized(locale: locale)
        case .failed:
            return AppStrings.Dashboard.refreshFailed.localized(locale: locale)
        case .needsConnection:
            return AppStrings.Dashboard.connectBeforeRefresh.localized(locale: locale)
        case .noData:
            return localizedNoDataMessage(for: account, locale: locale)
        case .supported:
            return localizedSourceSummary(
                providerID: account.providerID,
                sourceMode: account.sourceMode,
                fallback: diagnostics.message,
                locale: locale
            )
        }
    }

    func accounts(for providerID: String) -> [ProviderAccount] {
        providerAccounts
            .filter { $0.providerID == providerID }
    }

    func account(providerID: String, accountID: String) -> ProviderAccount? {
        providerAccounts.first {
            $0.providerID == providerID && $0.accountID == accountID
        }
    }

    func refreshStatus(for account: ProviderAccount) -> ProviderRefreshStatus {
        providerRefreshStatuses[account.id] ?? .idle
    }

    func snapshot(for account: ProviderAccount) -> UsageSnapshot? {
        snapshots.first { $0.id == account.id }
    }

    func migrationDiagnostics(for account: ProviderAccount) -> [SourceDiagnostic] {
        sourceDiagnostics.filter {
            $0.providerID == account.providerID &&
                $0.accountID == account.accountID &&
                !$0.code.hasPrefix("refresh-")
        }
    }

    func isSnapshotStale(_ snapshot: UsageSnapshot, now: Date = Date()) -> Bool {
        now.timeIntervalSince(snapshot.lastUpdatedAt) > refreshSettings.interval.staleAfter
    }

    func usageURL(providerID: String, accountID: String? = nil) -> URL? {
        guard let url = adapter(for: providerID)?.usageURL else { return nil }
        if let accountID {
            guard account(providerID: providerID, accountID: accountID) != nil else { return nil }
        }
        return url
    }

    private func noDataMessage(for account: ProviderAccount) -> String {
        switch account.sourceMode {
        case .ollamaWebPage:
            "Connect Ollama to load the experimental settings-page source."
        case .appServer:
            "Refresh this account to read the experimental local Codex app-server source."
        case .claudeUsageCLI:
            "Refresh this account to read the experimental local Claude /usage source."
        case .manual, .claudeStatusLine, .openRouterAPI, .miniMaxTokenPlan:
            "Refresh or test this account to load a snapshot."
        }
    }

    private func localizedNoDataMessage(for account: ProviderAccount, locale: Locale) -> String {
        switch account.sourceMode {
        case .ollamaWebPage:
            AppStrings.AccountDetails.ollamaConnectFirst.localized(locale: locale)
        case .appServer:
            AppStrings.AccountDetails.codexRefreshFirst.localized(locale: locale)
        case .claudeUsageCLI:
            AppStrings.AccountDetails.claudeUsageRefreshFirst.localized(locale: locale)
        case .manual, .claudeStatusLine, .openRouterAPI, .miniMaxTokenPlan:
            AppStrings.AccountDetails.refreshOrTestFirst.localized(locale: locale)
        }
    }

    private func localizedSourceSummary(
        providerID: String,
        sourceMode: ProviderSourceMode,
        fallback: String,
        locale: Locale
    ) -> String {
        switch (providerID, sourceMode) {
        case ("ollama-cloud", .ollamaWebPage):
            AppStrings.Dashboard.ollamaSourceSummary.localized(locale: locale)
        case ("claude-code", .claudeStatusLine):
            AppStrings.Dashboard.claudeStatusLineSummary.localized(locale: locale)
        case ("claude-code", .claudeUsageCLI):
            AppStrings.Dashboard.claudeUsageSummary.localized(locale: locale)
        case ("openai-codex", .appServer):
            AppStrings.Dashboard.codexSourceSummary.localized(locale: locale)
        default:
            fallback
        }
    }
}
