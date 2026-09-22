#if DEBUG
import BairometerCore
import AppKit
import Foundation
import SwiftUI

enum UITestHostScenario: String, CaseIterable {
    case dashboardEmpty = "dashboard-empty"
    case dashboardHealthy = "dashboard-healthy"
    case dashboardMixed = "dashboard-mixed"
    case dashboardOpenRouter = "dashboard-openrouter"
    case dashboardMiniMax = "dashboard-minimax"
    case settings
    case settingsDirtyEditor = "settings-dirty-editor"
    case settingsOpenRouter = "settings-openrouter"
    case settingsOpenRouterMissingManagement =
        "settings-openrouter-missing-management"

    var initialSurface: UITestHostSurface {
        switch self {
        case .dashboardEmpty, .dashboardHealthy, .dashboardMixed,
             .dashboardOpenRouter, .dashboardMiniMax:
            .dashboard
        case .settings, .settingsDirtyEditor, .settingsOpenRouter,
             .settingsOpenRouterMissingManagement:
            .settings
        }
    }

    func initialSettingsWorkspace(firstAccountID: String?) -> SettingsWorkspaceState {
        guard self == .settingsDirtyEditor, let firstAccountID else {
            return SettingsWorkspaceState()
        }
        return SettingsWorkspaceState(
            selection: .accounts,
            editorSession: AccountEditorSession(
                selectedAccountID: firstAccountID,
                mode: .editing,
                isDirty: false
            )
        )
    }
}

enum UITestHostSurface {
    case dashboard
    case settings
}

enum UITestHostLanguage: String, CaseIterable {
    case english = "en"
    case russian = "ru"

    var appLanguage: AppLanguage {
        switch self {
        case .english: .english
        case .russian: .russian
        }
    }
}

enum UITestHostAppearance: String, CaseIterable {
    case light
    case dark

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    var appKitName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

struct UITestHostConfiguration: Equatable {
    static let bundleIdentifier = "io.github.Prontsevich.Bairometer.UITestHost"
    static let windowID = "ui-test-host"
    static let modeArgument = "--ui-test-host"
    static let languageArgument = "--ui-test-language"
    static let appearanceArgument = "--ui-test-appearance"
    static let heightArgument = "--ui-test-height"

    static let defaultConfiguration = UITestHostConfiguration(
        scenario: .dashboardHealthy,
        language: .english,
        appearance: .dark,
        dashboardHeight: .standard
    )

    let scenario: UITestHostScenario
    let language: UITestHostLanguage
    let appearance: UITestHostAppearance
    let dashboardHeight: DashboardHeightPreset

    static func parse(
        arguments: [String],
        bundleIdentifier: String?
    ) throws -> UITestHostConfiguration? {
        let isHostBundle = bundleIdentifier == Self.bundleIdentifier
        let hasModeArgument = arguments.contains(Self.modeArgument)
        let hasVariantArgument = arguments.contains {
            [languageArgument, appearanceArgument, heightArgument].contains($0)
        }

        guard isHostBundle || hasModeArgument else {
            if hasVariantArgument {
                throw UITestHostConfigurationError.hostModeRequired
            }
            return nil
        }

        var configuration = Self.defaultConfiguration
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
            case modeArgument:
                let value = try value(after: index, in: arguments, for: argument)
                guard let scenario = UITestHostScenario(rawValue: value) else {
                    throw UITestHostConfigurationError.invalidValue(argument: argument, value: value)
                }
                configuration = UITestHostConfiguration(
                    scenario: scenario,
                    language: configuration.language,
                    appearance: configuration.appearance,
                    dashboardHeight: configuration.dashboardHeight
                )
                index += 1
            case languageArgument:
                let value = try value(after: index, in: arguments, for: argument)
                guard let language = UITestHostLanguage(rawValue: value) else {
                    throw UITestHostConfigurationError.invalidValue(argument: argument, value: value)
                }
                configuration = UITestHostConfiguration(
                    scenario: configuration.scenario,
                    language: language,
                    appearance: configuration.appearance,
                    dashboardHeight: configuration.dashboardHeight
                )
                index += 1
            case appearanceArgument:
                let value = try value(after: index, in: arguments, for: argument)
                guard let appearance = UITestHostAppearance(rawValue: value) else {
                    throw UITestHostConfigurationError.invalidValue(argument: argument, value: value)
                }
                configuration = UITestHostConfiguration(
                    scenario: configuration.scenario,
                    language: configuration.language,
                    appearance: appearance,
                    dashboardHeight: configuration.dashboardHeight
                )
                index += 1
            case heightArgument:
                let value = try value(after: index, in: arguments, for: argument)
                guard let height = DashboardHeightPreset(rawValue: value) else {
                    throw UITestHostConfigurationError.invalidValue(argument: argument, value: value)
                }
                configuration = UITestHostConfiguration(
                    scenario: configuration.scenario,
                    language: configuration.language,
                    appearance: configuration.appearance,
                    dashboardHeight: height
                )
                index += 1
            case AppLaunchOptions.storageDirectoryArgument:
                _ = try value(after: index, in: arguments, for: argument)
                index += 1
            default:
                if argument.hasPrefix("--ui-test-") {
                    throw UITestHostConfigurationError.unsupportedArgument(argument)
                }
            }
            index += 1
        }
        return configuration
    }

    private static func value(
        after index: Int,
        in arguments: [String],
        for argument: String
    ) throws -> String {
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex,
              !arguments[valueIndex].hasPrefix("--")
        else {
            throw UITestHostConfigurationError.missingValue(argument)
        }
        return arguments[valueIndex]
    }
}

enum UITestHostConfigurationError: Error, Equatable, CustomStringConvertible {
    case hostModeRequired
    case missingValue(String)
    case invalidValue(argument: String, value: String)
    case unsupportedArgument(String)

    var description: String {
        switch self {
        case .hostModeRequired:
            "UI test variants require --ui-test-host."
        case let .missingValue(argument):
            "Missing value for \(argument)."
        case let .invalidValue(argument, value):
            "Unsupported value '\(value)' for \(argument)."
        case let .unsupportedArgument(argument):
            "Unsupported UI test host argument \(argument)."
        }
    }
}

@MainActor
final class UITestHostSession {
    let storageDirectory: URL
    let userDefaults: UserDefaults

    let userDefaultsSuiteName: String
    private var terminationObservation: NSObjectProtocol?
    private var hasCleanedUp = false

    init(
        storageDirectory requestedStorageDirectory: URL?,
        fileManager: FileManager = .default
    ) throws {
        let sessionID = UUID().uuidString
        let storageDirectory = requestedStorageDirectory
            ?? fileManager.temporaryDirectory.appendingPathComponent(
                "bairometer-ui-test-\(sessionID)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )

        let suiteName = "\(UITestHostConfiguration.bundleIdentifier).\(sessionID)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            throw UITestHostSessionError.userDefaultsUnavailable
        }
        userDefaults.removePersistentDomain(forName: suiteName)

        self.storageDirectory = storageDirectory
        self.userDefaults = userDefaults
        userDefaultsSuiteName = suiteName
        terminationObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cleanup()
            }
        }
    }

    func cleanup(fileManager: FileManager = .default) {
        guard !hasCleanedUp else { return }
        hasCleanedUp = true
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        try? fileManager.removeItem(at: storageDirectory)
        if let terminationObservation {
            NotificationCenter.default.removeObserver(terminationObservation)
            self.terminationObservation = nil
        }
    }

    isolated deinit {
        MainActor.assumeIsolated {
            cleanup()
        }
    }
}

enum UITestHostSessionError: Error {
    case userDefaultsUnavailable
}

struct UITestHostFixture {
    let adapters: [any ProviderAdapter]
    let accounts: [ProviderAccount]
    let snapshots: [UsageSnapshot]
    let refreshIssues: [String: AccountRefreshIssue]
    let nativeCapacitySnapshots: [String: CapacitySnapshot]
    let credentialContexts: [String: [ProviderCredentialContext]]
    let credentialRefreshStates: [String: [CredentialContextRefreshState]]
    let credentialDiagnostics: [String: [CredentialContextDiagnostic]]

    init(
        adapters: [any ProviderAdapter],
        accounts: [ProviderAccount],
        snapshots: [UsageSnapshot],
        refreshIssues: [String: AccountRefreshIssue],
        nativeCapacitySnapshots: [String: CapacitySnapshot] = [:],
        credentialContexts: [String: [ProviderCredentialContext]] = [:],
        credentialRefreshStates: [String: [CredentialContextRefreshState]] = [:],
        credentialDiagnostics: [String: [CredentialContextDiagnostic]] = [:]
    ) {
        self.adapters = adapters
        self.accounts = accounts
        self.snapshots = snapshots
        self.refreshIssues = refreshIssues
        self.nativeCapacitySnapshots = nativeCapacitySnapshots
        self.credentialContexts = credentialContexts
        self.credentialRefreshStates = credentialRefreshStates
        self.credentialDiagnostics = credentialDiagnostics
    }

    @MainActor
    func apply(to appModel: AppModel) {
        appModel.providerAccounts = accounts
        appModel.snapshots = snapshots
        appModel.accountRefreshIssues = refreshIssues
        appModel.providerRefreshStatuses = [:]
        appModel.refreshSettings = RefreshSettings(interval: .manualOnly)
        _ = appModel.saveConfiguration()
        _ = appModel.saveSnapshots()
        _ = appModel.saveRefreshSettings()
        appModel.nativeCapacitySnapshots = nativeCapacitySnapshots
        appModel.credentialContextsByAccount = credentialContexts
        appModel.credentialRefreshStatesByAccount = credentialRefreshStates
        appModel.credentialDiagnosticsByAccount = credentialDiagnostics
    }

    static func make(scenario: UITestHostScenario, anchor: Date) -> UITestHostFixture {
        let anchor = Date(timeIntervalSince1970: floor(anchor.timeIntervalSince1970 / 60) * 60)
        switch scenario {
        case .dashboardEmpty:
            return UITestHostFixture(adapters: [], accounts: [], snapshots: [], refreshIssues: [:])
        case .dashboardHealthy, .settings, .settingsDirtyEditor:
            return healthyFixture(anchor: anchor)
        case .dashboardMixed:
            return mixedFixture(anchor: anchor)
        case .dashboardOpenRouter:
            return openRouterFixture(anchor: anchor, managementState: .active)
        case .dashboardMiniMax:
            return miniMaxFixture(anchor: anchor)
        case .settingsOpenRouter:
            return openRouterFixture(anchor: anchor, managementState: .disabled)
        case .settingsOpenRouterMissingManagement:
            return openRouterFixture(anchor: anchor, managementState: .missing)
        }
    }

    private static func healthyFixture(anchor: Date) -> UITestHostFixture {
        let accounts = [
            account(providerID: "ui-test-live", accountID: "primary", displayName: "Synthetic Primary"),
            account(providerID: "ui-test-live", accountID: "secondary", displayName: "Synthetic Secondary")
        ]
        let snapshots = [
            snapshot(for: accounts[0], usedPercent: 42, anchor: anchor),
            snapshot(for: accounts[1], usedPercent: 17, anchor: anchor)
        ]
        return UITestHostFixture(
            adapters: [liveAdapter(snapshots: snapshots)],
            accounts: accounts,
            snapshots: snapshots,
            refreshIssues: [:]
        )
    }

    private static func mixedFixture(anchor: Date) -> UITestHostFixture {
        let accounts = [
            account(providerID: "ui-test-live", accountID: "healthy", displayName: "Healthy Synthetic"),
            account(providerID: "ui-test-live", accountID: "warning", displayName: "Warning Synthetic"),
            account(providerID: "ui-test-live", accountID: "stale", displayName: "Stale Synthetic"),
            account(providerID: "ui-test-live", accountID: "failed", displayName: "Failed Synthetic"),
            ProviderAccount(
                providerID: "ui-test-manual",
                accountID: "manual",
                displayName: "Manual Synthetic",
                isEnabled: true,
                sourceMode: .manual
            ),
            account(providerID: "ui-test-empty", accountID: "no-data", displayName: "No Data Synthetic"),
            account(
                providerID: "ui-test-live",
                accountID: "long-name",
                displayName: "Synthetic Account With A Deliberately Long Display Name"
            )
        ]
        let healthy = snapshot(for: accounts[0], usedPercent: 36, anchor: anchor)
        let warning = snapshot(
            for: accounts[1],
            status: .warning,
            usedPercent: 91,
            anchor: anchor
        )
        let stale = snapshot(
            for: accounts[2],
            usedPercent: 54,
            anchor: anchor,
            lastUpdatedAt: anchor.addingTimeInterval(-30 * 60 * 60)
        )
        let failed = snapshot(for: accounts[3], usedPercent: 63, anchor: anchor)
        let longName = snapshot(for: accounts[6], usedPercent: 28, anchor: anchor)
        let snapshots = [healthy, warning, stale, failed, longName]
        let failedIssue = AccountRefreshIssue(
            occurredAt: anchor.addingTimeInterval(-5 * 60),
            warnings: ["Synthetic refresh failure for UI verification."]
        )
        return UITestHostFixture(
            adapters: [
                liveAdapter(
                    snapshots: snapshots,
                    failures: [accounts[3].accountID: failedIssue.warnings[0]]
                ),
                UITestScriptedProviderAdapter(
                    id: "ui-test-manual",
                    displayName: "Synthetic Manual Provider",
                    capabilities: .manualOnly,
                    responses: [:]
                ),
                UITestScriptedProviderAdapter(
                    id: "ui-test-empty",
                    displayName: "Synthetic Empty Provider",
                    capabilities: liveCapabilities,
                    responses: [
                        accounts[5].accountID: .failure(
                            message: "Synthetic source has no data.",
                            delayNanoseconds: 0
                        )
                    ]
                )
            ],
            accounts: accounts,
            snapshots: snapshots,
            refreshIssues: [accounts[3].id: failedIssue]
        )
    }

    private enum OpenRouterManagementFixtureState: Equatable {
        case active
        case disabled
        case missing
    }

    private static func miniMaxFixture(anchor: Date) -> UITestHostFixture {
        let account = ProviderAccount(
            providerID: MiniMaxProviderContract.providerID,
            accountID: "synthetic-minimax",
            displayName: "Synthetic MiniMax",
            isEnabled: true,
            sourceMode: .miniMaxTokenPlan
        )
        let rootContext = AccountContext(
            contextID: "synthetic-minimax-team",
            kind: .team,
            displayName: "Synthetic Default Team",
            regionID: "global"
        )
        let nativeSnapshot = CapacitySnapshot(
            providerID: account.providerID,
            surfaceID: MiniMaxProviderContract.surfaceID,
            savedAccountID: account.accountID,
            accountContexts: [rootContext],
            observedAt: anchor,
            metrics: [
                miniMaxMetric(
                    id: "quota-category-a.current",
                    contextID: rootContext.contextID,
                    remainingPercent: 60,
                    resetAt: anchor.addingTimeInterval(2 * 3_600),
                    observedAt: anchor
                ),
                miniMaxMetric(
                    id: "quota-category-a.weekly",
                    contextID: rootContext.contextID,
                    remainingPercent: 76,
                    resetAt: anchor.addingTimeInterval(3 * 24 * 3_600),
                    observedAt: anchor
                ),
                miniMaxMetric(
                    id: "quota-category-b.current",
                    contextID: rootContext.contextID,
                    remainingPercent: 85,
                    resetAt: anchor.addingTimeInterval(4 * 3_600),
                    observedAt: anchor
                ),
                miniMaxMetric(
                    id: "quota-category-b.weekly",
                    contextID: rootContext.contextID,
                    remainingPercent: 77.5,
                    resetAt: anchor.addingTimeInterval(5 * 24 * 3_600),
                    observedAt: anchor
                ),
            ]
        )
        let compatibilitySnapshot = UsageSnapshot(
            providerID: account.providerID,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: "MiniMax",
            status: .ok,
            remainingLabel: "Synthetic Token Plan capacity",
            lastUpdatedAt: anchor,
            confidence: .live,
            source: "Synthetic UI test fixture"
        )
        let adapter = UITestScriptedProviderAdapter(
            id: MiniMaxProviderContract.providerID,
            displayName: "MiniMax",
            capabilities: ProviderCapabilities(sources: [
                ProviderSourceCapability(
                    mode: .miniMaxTokenPlan,
                    kind: .live,
                    summary: "Synthetic MiniMax data for UI verification."
                )
            ]),
            responses: [
                account.accountID: .snapshot(
                    compatibilitySnapshot,
                    delayNanoseconds: 150_000_000
                )
            ],
            preservesNativePresentationFixture: true
        )
        return UITestHostFixture(
            adapters: [adapter],
            accounts: [account],
            snapshots: [compatibilitySnapshot],
            refreshIssues: [:],
            nativeCapacitySnapshots: [account.id: nativeSnapshot]
        )
    }

    private static func miniMaxMetric(
        id: String,
        contextID: String,
        remainingPercent: Decimal,
        resetAt: Date,
        observedAt: Date
    ) -> CapacityMetric {
        CapacityMetric(
            metricID: id,
            accountContextID: contextID,
            sourceID: MiniMaxProviderContract.sourceID,
            capability: "quota-windows",
            displayName: "Synthetic reviewed quota capacity",
            availability: .known,
            unit: CapacityUnit(kind: .percent),
            values: CapacityValues(
                consumed: CapacityValue(
                    value: 100 - remainingPercent,
                    origin: .derived
                ),
                remaining: CapacityValue(
                    value: remainingPercent,
                    origin: .reported
                ),
                limit: CapacityValue(value: 100, origin: .reported)
            ),
            window: CapacityWindow(
                kind: id.hasSuffix(".weekly") ? .fixed : .rolling,
                nextTransition: CapacityTransition(kind: .reset, at: resetAt)
            ),
            freshness: ObservationFreshness(observedAt: observedAt),
            confidence: .live,
            derivations: [
                Derivation(
                    kind: .consumedFromLimitMinusRemaining,
                    target: .consumed,
                    inputs: [.limit, .remaining]
                )
            ]
        )
    }

    private static func openRouterFixture(
        anchor: Date,
        managementState: OpenRouterManagementFixtureState
    ) -> UITestHostFixture {
        let account = ProviderAccount(
            providerID: OpenRouterProviderContract.providerID,
            accountID: "synthetic-openrouter",
            displayName: "Synthetic OpenRouter",
            isEnabled: true,
            sourceMode: .openRouterAPI
        )
        let root = AccountContext(
            contextID: "account",
            kind: .personal,
            regionID: "global"
        )
        let primary = AccountContext(
            contextID: "primary",
            kind: .credential,
            displayName: "Primary",
            regionID: "global",
            parentContextID: root.contextID
        )
        let stale = AccountContext(
            contextID: "stale",
            kind: .credential,
            displayName: "Stale key",
            regionID: "global",
            parentContextID: root.contextID
        )
        let failed = AccountContext(
            contextID: "failed",
            kind: .credential,
            displayName: "Authentication issue",
            regionID: "global",
            parentContextID: root.contextID
        )
        let nativeSnapshot = CapacitySnapshot(
            providerID: account.providerID,
            surfaceID: OpenRouterProviderContract.surfaceID,
            savedAccountID: account.accountID,
            accountContexts: [root, primary, stale, failed],
            observedAt: anchor,
            metrics: [
                openRouterMetric(
                    id: "account-credits",
                    contextID: root.contextID,
                    sourceID: OpenRouterProviderContract.managementSourceID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 12.5, origin: .reported),
                        remaining: CapacityValue(value: 87.5, origin: .derived),
                        limit: CapacityValue(value: 100, origin: .reported)
                    ),
                    observedAt: anchor
                ),
                openRouterMetric(
                    id: "key-credit-limit",
                    contextID: primary.contextID,
                    values: CapacityValues(
                        remaining: CapacityValue(value: 8.75, origin: .reported),
                        limit: CapacityValue(value: 10, origin: .reported)
                    ),
                    observedAt: anchor,
                    window: CapacityWindow(
                        kind: .fixed,
                        nextTransition: CapacityTransition(
                            kind: .reset,
                            at: anchor.addingTimeInterval(3_600)
                        )
                    )
                ),
                openRouterMetric(
                    id: "key-total-usage",
                    contextID: primary.contextID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 1.25, origin: .reported)
                    ),
                    observedAt: anchor
                ),
                openRouterMetric(
                    id: "key-daily-usage",
                    contextID: primary.contextID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 0, origin: .reported)
                    ),
                    observedAt: anchor,
                    window: CapacityWindow(
                        kind: .fixed,
                        nextTransition: CapacityTransition(
                            kind: .reset,
                            at: anchor.addingTimeInterval(2 * 3_600)
                        )
                    )
                ),
                openRouterMetric(
                    id: "key-daily-byok-usage",
                    contextID: primary.contextID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 0, origin: .reported)
                    ),
                    observedAt: anchor,
                    window: CapacityWindow(
                        kind: .fixed,
                        nextTransition: CapacityTransition(
                            kind: .reset,
                            at: anchor.addingTimeInterval(2 * 3_600)
                        )
                    )
                ),
                openRouterMetric(
                    id: "key-weekly-usage",
                    contextID: primary.contextID,
                    availability: .unknown,
                    values: nil,
                    observedAt: anchor,
                    window: CapacityWindow(
                        kind: .fixed,
                        nextTransition: CapacityTransition(
                            kind: .reset,
                            at: anchor.addingTimeInterval(2 * 24 * 3_600)
                        )
                    )
                ),
                openRouterMetric(
                    id: "key-monthly-byok-usage",
                    contextID: primary.contextID,
                    availability: .unlimited,
                    values: nil,
                    observedAt: anchor,
                    window: CapacityWindow(
                        kind: .fixed,
                        nextTransition: CapacityTransition(
                            kind: .reset,
                            at: anchor.addingTimeInterval(7 * 24 * 3_600)
                        )
                    )
                ),
                openRouterMetric(
                    id: "key-total-usage",
                    contextID: stale.contextID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 4.5, origin: .reported)
                    ),
                    observedAt: anchor.addingTimeInterval(-20 * 60)
                ),
                openRouterMetric(
                    id: "key-total-usage",
                    contextID: failed.contextID,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 2, origin: .reported)
                    ),
                    observedAt: anchor
                )
            ]
        )
        var credentials = [
            openRouterCredential(
                account: account,
                context: primary,
                slotID: primary.contextID,
                role: .ordinary
            ),
            openRouterCredential(
                account: account,
                context: stale,
                slotID: stale.contextID,
                role: .ordinary
            ),
            openRouterCredential(
                account: account,
                context: failed,
                slotID: failed.contextID,
                role: .ordinary
            )
        ]
        if managementState != .missing {
            credentials.append(openRouterCredential(
                account: account,
                context: root,
                slotID: "management",
                role: .management,
                isEnabled: managementState == .active
            ))
        }
        let compatibilitySnapshot = UsageSnapshot(
            providerID: account.providerID,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: "OpenRouter",
            status: .warning,
            planName: "API account",
            periodLabel: "Native capacity",
            usedPercent: 0,
            remainingLabel: "Native capacity",
            resetAt: nil,
            limitWindows: [],
            lastUpdatedAt: anchor,
            confidence: .live,
            source: "Synthetic UI test fixture"
        )
        let adapter = UITestScriptedProviderAdapter(
            id: OpenRouterProviderContract.providerID,
            displayName: "OpenRouter",
            capabilities: ProviderCapabilities(sources: [
                ProviderSourceCapability(
                    mode: .openRouterAPI,
                    kind: .live,
                    summary: "Synthetic OpenRouter data for UI verification."
                )
            ]),
            responses: [
                account.accountID: .snapshot(
                    compatibilitySnapshot,
                    delayNanoseconds: 150_000_000
                )
            ],
            preservesNativePresentationFixture: true
        )
        let accountRefreshIssues: [String: AccountRefreshIssue]
        let slotDiagnostics: [CredentialContextDiagnostic]
        if managementState == .missing {
            accountRefreshIssues = [
                account.id: AccountRefreshIssue(
                    occurredAt: anchor,
                    warnings: [
                        "Synthetic account refresh failure before slot diagnostics."
                    ]
                )
            ]
            slotDiagnostics = []
        } else {
            accountRefreshIssues = [:]
            slotDiagnostics = [
                CredentialContextDiagnostic(
                    providerID: account.providerID,
                    accountID: account.accountID,
                    slotID: failed.contextID,
                    code: .authentication,
                    occurredAt: anchor
                )
            ]
        }
        return UITestHostFixture(
            adapters: [adapter],
            accounts: [account],
            snapshots: [compatibilitySnapshot],
            refreshIssues: accountRefreshIssues,
            nativeCapacitySnapshots: [account.id: nativeSnapshot],
            credentialContexts: [account.id: credentials],
            credentialRefreshStates: [
                account.id: [
                    CredentialContextRefreshState(
                        providerID: account.providerID,
                        accountID: account.accountID,
                        slotID: primary.contextID,
                        lastAttemptAt: anchor,
                        lastSuccessfulRefreshAt: anchor,
                        lastFailedRefreshAt: nil
                    ),
                    CredentialContextRefreshState(
                        providerID: account.providerID,
                        accountID: account.accountID,
                        slotID: stale.contextID,
                        lastAttemptAt: anchor.addingTimeInterval(-20 * 60),
                        lastSuccessfulRefreshAt: anchor.addingTimeInterval(-20 * 60),
                        lastFailedRefreshAt: nil
                    )
                ]
            ],
            credentialDiagnostics: [
                account.id: slotDiagnostics
            ]
        )
    }

    private static func openRouterCredential(
        account: ProviderAccount,
        context: AccountContext,
        slotID: String,
        role: ProviderCredentialRole,
        isEnabled: Bool = true
    ) -> ProviderCredentialContext {
        ProviderCredentialContext(
            context: ProviderAccountContextConfiguration(
                providerID: account.providerID,
                accountID: account.accountID,
                contextID: context.contextID,
                kind: context.kind,
                displayName: context.displayName,
                regionID: context.regionID,
                parentContextID: context.parentContextID
            ),
            slot: ProviderCredentialSlot(
                providerID: account.providerID,
                accountID: account.accountID,
                slotID: slotID,
                contextID: context.contextID,
                role: role,
                isEnabled: isEnabled,
                keychainReference: "synthetic-reference-\(slotID)"
            )
        )
    }

    private static func openRouterMetric(
        id: String,
        contextID: String,
        sourceID: String = OpenRouterProviderContract.currentKeySourceID,
        availability: CapacityAvailability = .known,
        values: CapacityValues?,
        observedAt: Date,
        window: CapacityWindow = CapacityWindow(kind: .lifetime)
    ) -> CapacityMetric {
        CapacityMetric(
            metricID: id,
            accountContextID: contextID,
            sourceID: sourceID,
            capability: id.contains("usage") ? "spend" : "credits",
            displayName: "Synthetic",
            availability: availability,
            unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
            values: values,
            window: window,
            freshness: ObservationFreshness(observedAt: observedAt),
            confidence: .live
        )
    }

    private static func account(
        providerID: String,
        accountID: String,
        displayName: String
    ) -> ProviderAccount {
        ProviderAccount(
            providerID: providerID,
            accountID: accountID,
            displayName: displayName,
            isEnabled: true,
            sourceMode: .appServer
        )
    }

    private static func snapshot(
        for account: ProviderAccount,
        status: UsageStatus = .ok,
        usedPercent: Double,
        anchor: Date,
        lastUpdatedAt: Date? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(
            providerID: account.providerID,
            accountID: account.accountID,
            accountDisplayName: account.displayName,
            displayName: "Synthetic Provider",
            status: status,
            planName: "Synthetic Plan",
            periodLabel: "Synthetic window",
            usedPercent: usedPercent,
            remainingLabel: "Synthetic remaining value",
            resetAt: anchor.addingTimeInterval(2 * 60 * 60),
            limitWindows: [
                UsageLimitWindow(
                    id: "weekly",
                    displayName: "Weekly",
                    usedPercent: usedPercent,
                    remainingLabel: "Synthetic remaining value",
                    resetAt: anchor.addingTimeInterval(2 * 60 * 60)
                ),
                UsageLimitWindow(
                    id: "rolling",
                    displayName: "5-hour",
                    usedPercent: max(0, usedPercent - 11),
                    remainingLabel: "Synthetic rolling value",
                    resetAt: anchor.addingTimeInterval(5 * 60 * 60)
                )
            ],
            lastUpdatedAt: lastUpdatedAt ?? anchor.addingTimeInterval(-60),
            confidence: .localEstimate,
            source: "Synthetic UI test fixture"
        )
    }

    private static func liveAdapter(
        snapshots: [UsageSnapshot],
        failures: [String: String] = [:]
    ) -> UITestScriptedProviderAdapter {
        var responses = Dictionary(uniqueKeysWithValues: snapshots.map {
            ($0.accountID, UITestScriptedProviderResponse.snapshot($0, delayNanoseconds: 150_000_000))
        })
        for (accountID, message) in failures {
            responses[accountID] = .failure(message: message, delayNanoseconds: 150_000_000)
        }
        return UITestScriptedProviderAdapter(
            id: "ui-test-live",
            displayName: "Synthetic Live Provider",
            capabilities: liveCapabilities,
            responses: responses
        )
    }

    private static let liveCapabilities = ProviderCapabilities(sources: [
        ProviderSourceCapability(
            mode: .appServer,
            kind: .live,
            summary: "Synthetic live data for UI verification."
        )
    ])
}

enum UITestScriptedProviderResponse: Sendable {
    case snapshot(UsageSnapshot, delayNanoseconds: UInt64)
    case failure(message: String, delayNanoseconds: UInt64)
}

struct UITestScriptedProviderAdapter: ProviderAdapter {
    let id: String
    let displayName: String
    let usageURL: URL? = nil
    let capabilities: ProviderCapabilities
    let responses: [String: UITestScriptedProviderResponse]
    let preservesNativePresentationFixture: Bool

    init(
        id: String,
        displayName: String,
        capabilities: ProviderCapabilities,
        responses: [String: UITestScriptedProviderResponse],
        preservesNativePresentationFixture: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
        self.responses = responses
        self.preservesNativePresentationFixture =
            preservesNativePresentationFixture
    }

    func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot {
        guard let response = responses[account.accountID] else {
            throw ProviderAdapterError(
                providerID: id,
                message: "No synthetic response is configured for this account."
            )
        }
        switch response {
        case let .snapshot(snapshot, delayNanoseconds):
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            return snapshot
        case let .failure(message, delayNanoseconds):
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            throw ProviderAdapterError(providerID: id, message: message)
        }
    }
}

struct UITestHostRootView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var appLanguagePreference: AppLanguagePreference
    let configuration: UITestHostConfiguration
    let userDefaults: UserDefaults

    @StateObject private var panelPresentation = MenuBarPanelPresentationState()
    @State private var surface: UITestHostSurface

    init(
        appModel: AppModel,
        appLanguagePreference: AppLanguagePreference,
        configuration: UITestHostConfiguration,
        userDefaults: UserDefaults
    ) {
        self.appModel = appModel
        self.appLanguagePreference = appLanguagePreference
        self.configuration = configuration
        self.userDefaults = userDefaults
        _surface = State(initialValue: configuration.scenario.initialSurface)
    }

    var body: some View {
        AppLocaleScope(languagePreference: appLanguagePreference) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .accessibilityElement()
                    .accessibilityLabel("UI test host root")
                    .accessibilityIdentifier(
                        "ui-test-host.root.\(configuration.scenario.rawValue)"
                    )

                Group {
                    switch surface {
                    case .dashboard:
                        dashboard
                    case .settings:
                        SettingsView(
                            appModel: appModel,
                            appLanguagePreference: appLanguagePreference,
                            initialWorkspace: initialSettingsWorkspace
                        )
                    }
                }
            }
        }
        .defaultAppStorage(userDefaults)
        .preferredColorScheme(configuration.appearance.colorScheme)
        .onAppear(perform: activateHost)
        .onChange(of: surface) { _, surface in
            panelPresentation.isVisible = surface == .dashboard
            if surface == .dashboard {
                focusDashboardResponder()
            }
        }
        .onDisappear {
            panelPresentation.isVisible = false
        }
    }

    private var dashboard: some View {
        MenuBarPanelView(
            appModel: appModel,
            onOpenSettings: {
                surface = .settings
            },
            onOpenAbout: {
                ApplicationLifecycle.openAbout(appLanguagePreference: appLanguagePreference)
            },
            onOpenOllamaConnection: {},
            onCloseDashboard: {
                NSApp.keyWindow?.performClose(nil)
            },
            panelPresentation: panelPresentation
        )
    }

    private var initialSettingsWorkspace: SettingsWorkspaceState {
        configuration.scenario.initialSettingsWorkspace(
            firstAccountID: appModel.providerAccounts.first?.id
        )
    }

    private func activateHost() {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: configuration.appearance.appKitName)
        NSApp.activate(ignoringOtherApps: true)
        panelPresentation.isVisible = surface == .dashboard
        if surface == .dashboard {
            focusDashboardResponder()
        }
    }

    private func focusDashboardResponder(attemptsRemaining: Int = 4) {
        DispatchQueue.main.async {
            let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible)
            window?.makeKeyAndOrderFront(nil)
            if let responder = panelPresentation.keyboardResponder,
               window?.makeFirstResponder(responder) == true {
                return
            }
            guard attemptsRemaining > 1 else { return }
            focusDashboardResponder(attemptsRemaining: attemptsRemaining - 1)
        }
    }
}
#endif
