import BairometerCore
import Foundation

enum OpenRouterCapacityState: Equatable {
    case current
    case partial
    case stale
    case unavailable
    case unknown
    case unlimited
    case credentialError
    case disabled
    case recoveryRequired
    case deletionPending

    func localizedStatusText(locale: Locale) -> String {
        switch self {
        case .current:
            AppStrings.OpenRouter.current.localized(locale: locale)
        case .partial:
            AppStrings.OpenRouter.partial.localized(locale: locale)
        case .stale:
            AppStrings.Common.stale.localized(locale: locale)
        case .unavailable:
            AppStrings.Common.unavailable.localized(locale: locale)
        case .unknown:
            AppStrings.Common.unknown.localized(locale: locale)
        case .unlimited:
            AppStrings.Common.unlimited.localized(locale: locale)
        case .credentialError:
            AppStrings.Common.error.localized(locale: locale)
        case .disabled:
            AppStrings.OpenRouter.disabled.localized(locale: locale)
        case .recoveryRequired:
            AppStrings.OpenRouter.recoveryRequired.localized(locale: locale)
        case .deletionPending:
            AppStrings.OpenRouter.deletionPending.localized(locale: locale)
        }
    }
}

struct OpenRouterCapacityMetricPresentation: Identifiable, Equatable {
    let id: String
    let metricID: String
    let displayName: String
    let valueText: String
    let displayValueLines: [String]
    let dashboardValueText: String
    let dashboardAccessibilityValue: String
    let tableValueText: String
    let accountCredits: OpenRouterAccountCreditsPresentation?
    let keyCapacity: OpenRouterKeyCapacityPresentation?
    let scopeText: String?
    let usageColumn: OpenRouterUsageColumn?
    let usageQualifierText: String?
    let resetText: String?
    let resetIdentity: String?
    let freshnessText: String?
    let state: OpenRouterCapacityState
    let accessibilityValue: String

    func visibleAccessibilityValue(
        showsReset: Bool,
        showsFreshness: Bool
    ) -> String {
        [
            valueText,
            showsReset ? resetText : nil,
            showsFreshness ? freshnessText : nil,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

struct OpenRouterAccountCreditsPresentation: Equatable {
    let leftText: String
    let usedText: String
    let accessibilityValue: String
}

struct OpenRouterKeyCapacityPresentation: Equatable {
    let availableText: String
    let totalText: String
    let visualValueText: String
    let availableFraction: Double?
    let accessibilityValue: String
}

enum OpenRouterUsageColumn: Equatable {
    case usage
    case byok
}

struct OpenRouterUsageTableRowPresentation: Identifiable, Equatable {
    let id: String
    let scopeText: String
    let usageMetric: OpenRouterCapacityMetricPresentation?
    let byokMetric: OpenRouterCapacityMetricPresentation?
}

struct OpenRouterCredentialCapacityPresentation: Identifiable, Equatable {
    let id: String
    let slotID: String
    let displayName: String
    let isEnabled: Bool
    let lifecycleState: CredentialLifecycleState
    let state: OpenRouterCapacityState
    let statusText: String
    let dashboardValueText: String
    let dashboardStatusText: String?
    let dashboardAccessibilityValue: String
    let metrics: [OpenRouterCapacityMetricPresentation]

    var dashboardMetric: OpenRouterCapacityMetricPresentation? {
        metrics.first { $0.metricID == "key-credit-limit" }
    }

    var detailsPresentation: OpenRouterCredentialDetailsPresentation {
        OpenRouterCredentialDetailsPresentation(credential: self)
    }
}

struct OpenRouterCredentialDetailsPresentation: Identifiable, Equatable {
    let id: String
    let displayName: String
    let summaryValueText: String
    let summaryState: OpenRouterCapacityState
    let state: OpenRouterCapacityState
    let resetText: String?
    let exceptionText: String?
    let updateText: String?
    let collapsedMetrics: [OpenRouterCapacityMetricPresentation]
    let expandedMetrics: [OpenRouterCapacityMetricPresentation]
    let keyLimitMetric: OpenRouterCapacityMetricPresentation?
    let usageRows: [OpenRouterUsageTableRowPresentation]
    let resetGroups: [OpenRouterCredentialResetPresentation]
    let isExpandedByDefault: Bool
    let showsPerMetricFreshness: Bool
    let collapsedAccessibilityValue: String
    let expandedSummaryAccessibilityValue: String

    init(credential: OpenRouterCredentialCapacityPresentation) {
        id = credential.id
        displayName = credential.displayName
        summaryValueText = credential.dashboardValueText
        summaryState = credential.dashboardMetric?.state ?? credential.state
        state = credential.state
        resetText = credential.dashboardMetric?.resetText
        exceptionText = credential.dashboardStatusText
        updateText = credential.metrics.first(where: {
            $0.state == .stale && $0.freshnessText != nil
        })?.freshnessText
            ?? credential.metrics.compactMap(\.freshnessText).first
        collapsedMetrics = []
        expandedMetrics = credential.metrics
        keyLimitMetric = credential.metrics.first {
            $0.metricID == "key-credit-limit"
        }
        var rows: [OpenRouterUsageTableRowPresentation] = []
        for metric in credential.metrics where metric.usageColumn != nil {
            guard let scopeText = metric.scopeText else { continue }
            if let index = rows.firstIndex(where: { $0.id == scopeText }) {
                let existing = rows[index]
                rows[index] = OpenRouterUsageTableRowPresentation(
                    id: existing.id,
                    scopeText: existing.scopeText,
                    usageMetric: metric.usageColumn == .usage
                        ? metric
                        : existing.usageMetric,
                    byokMetric: metric.usageColumn == .byok
                        ? metric
                        : existing.byokMetric
                )
            } else {
                rows.append(
                    OpenRouterUsageTableRowPresentation(
                        id: scopeText,
                        scopeText: scopeText,
                        usageMetric: metric.usageColumn == .usage ? metric : nil,
                        byokMetric: metric.usageColumn == .byok ? metric : nil
                    )
                )
            }
        }
        usageRows = rows.sorted {
            Self.usageScopeOrder($0) < Self.usageScopeOrder($1)
        }
        var groupedResets: [
            (
                resetIdentity: String,
                resetText: String,
                metrics: [OpenRouterCapacityMetricPresentation]
            )
        ] = []
        for metric in credential.metrics {
            guard let metricResetText = metric.resetText,
                  let metricResetIdentity = metric.resetIdentity else {
                continue
            }
            if let index = groupedResets.firstIndex(where: {
                $0.resetIdentity == metricResetIdentity
            }) {
                groupedResets[index].metrics.append(metric)
            } else {
                groupedResets.append(
                    (
                        resetIdentity: metricResetIdentity,
                        resetText: metricResetText,
                        metrics: [metric]
                    )
                )
            }
        }
        resetGroups = groupedResets
            .sorted {
                let leftOrder = Self.resetGroupOrder($0.metrics)
                let rightOrder = Self.resetGroupOrder($1.metrics)
                if leftOrder != rightOrder {
                    return leftOrder < rightOrder
                }
                return $0.resetIdentity < $1.resetIdentity
            }
            .map { group in
                OpenRouterCredentialResetPresentation(
                    id: group.resetIdentity,
                    scopeNames: Self.resetScopeNames(for: group.metrics),
                    resetText: group.resetText
                )
            }
        isExpandedByDefault = false
        showsPerMetricFreshness = false
        collapsedAccessibilityValue = [
            credential.dashboardMetric?.dashboardAccessibilityValue
                ?? summaryValueText,
            resetText,
            exceptionText,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        expandedSummaryAccessibilityValue = [
            credential.dashboardMetric?.dashboardAccessibilityValue
                ?? summaryValueText,
            exceptionText,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private static func resetScopeNames(
        for metrics: [OpenRouterCapacityMetricPresentation]
    ) -> [String] {
        var scopes: [(name: String, metrics: [OpenRouterCapacityMetricPresentation])] = []
        for metric in metrics {
            let name = metric.scopeText ?? metric.displayName
            if let index = scopes.firstIndex(where: { $0.name == name }) {
                scopes[index].metrics.append(metric)
            } else {
                scopes.append((name, [metric]))
            }
        }

        return scopes.map { scope in
            let usageColumns = Set(
                scope.metrics.compactMap(\.usageColumn).map {
                    $0 == .usage ? "usage" : "byok"
                }
            )
            if usageColumns.count != 1 {
                return scope.name
            }
            guard let qualifier = scope.metrics.compactMap(\.usageQualifierText).first else {
                return scope.name
            }
            return "\(scope.name) · \(qualifier)"
        }
    }

    private static func usageScopeOrder(
        _ row: OpenRouterUsageTableRowPresentation
    ) -> Int {
        let metricID = (row.usageMetric ?? row.byokMetric)?.metricID ?? ""
        if metricID.contains("-daily-") { return 0 }
        if metricID.contains("-weekly-") { return 1 }
        if metricID.contains("-monthly-") { return 2 }
        if metricID.contains("-total-") { return 3 }
        return 100
    }

    private static func resetGroupOrder(
        _ metrics: [OpenRouterCapacityMetricPresentation]
    ) -> Int {
        metrics.map {
            if $0.metricID == "key-credit-limit" { return 0 }
            if $0.metricID.contains("-daily-") { return 1 }
            if $0.metricID.contains("-weekly-") { return 2 }
            if $0.metricID.contains("-monthly-") { return 3 }
            if $0.metricID.contains("-total-") { return 4 }
            return 100
        }.min() ?? 100
    }
}

struct OpenRouterCredentialResetPresentation: Identifiable, Equatable {
    let id: String
    let scopeNames: [String]
    let resetText: String

    var accessibilityLabel: String {
        scopeNames.joined(separator: ", ")
    }

    var accessibilityValue: String {
        resetText
    }
}

struct OpenRouterCapacityPresentation: Equatable {
    let accountID: String
    let accountName: String
    let state: OpenRouterCapacityState
    let statusText: String
    let sharedCredits: OpenRouterCapacityMetricPresentation
    let credentials: [OpenRouterCredentialCapacityPresentation]

    init(
        account: ProviderAccount,
        snapshot: CapacitySnapshot?,
        credentialContexts: [ProviderCredentialContext],
        refreshStates: [CredentialContextRefreshState],
        diagnostics: [CredentialContextDiagnostic],
        now: Date = Date(),
        locale: Locale = Locale(identifier: "en_US")
    ) {
        accountID = account.accountID
        accountName = account.displayName
        let ordinaryCredentials = credentialContexts
            .filter { $0.slot.role == .ordinary }
            .sorted {
                ($0.context.displayName ?? "").localizedCaseInsensitiveCompare(
                    $1.context.displayName ?? ""
                ) == .orderedAscending
            }
        let managementCredential = credentialContexts.first {
            $0.slot.role == .management
                && $0.slot.lifecycleState == .active
                && $0.slot.isEnabled
        }
        let refreshStateBySlot = Dictionary(
            uniqueKeysWithValues: refreshStates.map { ($0.slotID, $0) }
        )
        let diagnosticBySlot = Dictionary(
            uniqueKeysWithValues: diagnostics.map { ($0.slotID, $0) }
        )
        let metricsByContext = Dictionary(
            grouping: snapshot?.metrics ?? [],
            by: \.accountContextID
        )

        let rootContextID = snapshot?.accountContexts.first(where: {
            $0.parentContextID == nil
        })?.contextID
        let sharedMetric = managementCredential.flatMap { _ in
            (rootContextID.flatMap { metricsByContext[$0] } ?? [])
                .first(where: {
                    $0.metricID == "account-credits"
                        && $0.sourceID
                            == OpenRouterProviderContract.managementSourceID
                })
        }
        sharedCredits = Self.metricPresentation(
            sharedMetric,
            fallbackID: "account-credits",
            locale: locale,
            now: now
        )

        credentials = ordinaryCredentials.map { credential in
            let diagnostic = diagnosticBySlot[credential.slot.slotID]
            let metrics = (metricsByContext[credential.context.contextID] ?? [])
                .sorted {
                    Self.metricOrder($0.metricID)
                        < Self.metricOrder($1.metricID)
                }
                .map {
                    Self.metricPresentation(
                        $0,
                        fallbackID: $0.metricID,
                        locale: locale,
                        now: now
                    )
                }
            let state = Self.credentialState(
                credential,
                metrics: metrics,
                diagnostic: diagnostic
            )
            let statusText = Self.credentialStatusText(
                state: state,
                diagnostic: diagnostic,
                refreshState: refreshStateBySlot[credential.slot.slotID],
                locale: locale
            )
            let dashboardMetric = metrics.first {
                $0.metricID == "key-credit-limit"
            }
            let dashboardValue = Self.credentialDashboardValue(
                state: state,
                statusText: statusText,
                metric: dashboardMetric,
                locale: locale
            )
            let dashboardStatus = Self.credentialDashboardStatus(
                state: state,
                statusText: statusText,
                hasMetric: dashboardMetric != nil
            )
            return OpenRouterCredentialCapacityPresentation(
                id: credential.context.contextID,
                slotID: credential.slot.slotID,
                displayName: credential.context.displayName
                    ?? AppStrings.OpenRouter.unnamedKey.localized(locale: locale),
                isEnabled: credential.slot.isEnabled,
                lifecycleState: credential.slot.lifecycleState,
                state: state,
                statusText: statusText,
                dashboardValueText: dashboardValue,
                dashboardStatusText: dashboardStatus,
                dashboardAccessibilityValue: [
                    dashboardMetric?.dashboardAccessibilityValue
                        ?? dashboardValue,
                    dashboardMetric?.resetText,
                    dashboardStatus,
                ]
                .compactMap { $0 }
                .joined(separator: ", "),
                metrics: metrics
            )
        }

        let managementDiagnostic = managementCredential.flatMap {
            diagnosticBySlot[$0.slot.slotID]
        }
        let aggregateCredentials = credentials.filter {
            $0.lifecycleState == .active && $0.isEnabled
        }
        state = Self.accountState(
            sharedCredits: sharedCredits,
            credentials: aggregateCredentials,
            managementDiagnostic: managementDiagnostic
        )
        statusText = Self.statusText(for: state, locale: locale)
    }

    private static func accountState(
        sharedCredits: OpenRouterCapacityMetricPresentation,
        credentials: [OpenRouterCredentialCapacityPresentation],
        managementDiagnostic: CredentialContextDiagnostic?
    ) -> OpenRouterCapacityState {
        let visibleMetrics = credentials.flatMap(\.metrics)
        let hasUsableMetrics = visibleMetrics.contains {
            [.current, .stale, .unlimited].contains($0.state)
        } || [.current, .stale, .unlimited].contains(sharedCredits.state)
        let hasUnknownMetrics = sharedCredits.state == .unknown
            || credentials.contains { $0.state == .unknown }
        let hasCredentialError = credentials.contains {
            [.partial, .credentialError, .recoveryRequired, .deletionPending]
                .contains($0.state)
        } || managementDiagnostic != nil
        if hasCredentialError && hasUsableMetrics {
            return .partial
        }
        if hasCredentialError {
            return .credentialError
        }
        if visibleMetrics.contains(where: { $0.state == .stale })
            || sharedCredits.state == .stale {
            return .stale
        }
        if hasUsableMetrics {
            return .current
        }
        if hasUnknownMetrics {
            return .unknown
        }
        return .unavailable
    }

    private static func credentialState(
        _ credential: ProviderCredentialContext,
        metrics: [OpenRouterCapacityMetricPresentation],
        diagnostic: CredentialContextDiagnostic?
    ) -> OpenRouterCapacityState {
        switch credential.slot.lifecycleState {
        case .pendingCreation:
            return .recoveryRequired
        case .pendingDeletion:
            return .deletionPending
        case .active:
            break
        }
        guard credential.slot.isEnabled else {
            return .disabled
        }
        if diagnostic != nil {
            return metrics.isEmpty ? .credentialError : .partial
        }
        if metrics.contains(where: { $0.state == .stale }) {
            return .stale
        }
        if metrics.contains(where: { $0.state == .current }) {
            return .current
        }
        if metrics.contains(where: { $0.state == .unlimited }) {
            return .unlimited
        }
        if metrics.contains(where: { $0.state == .unknown }) {
            return .unknown
        }
        return .unavailable
    }

    private static func credentialStatusText(
        state: OpenRouterCapacityState,
        diagnostic: CredentialContextDiagnostic?,
        refreshState: CredentialContextRefreshState?,
        locale: Locale
    ) -> String {
        if let diagnostic {
            return diagnosticText(diagnostic.code, locale: locale)
        }
        switch state {
        case .current:
            if let date = refreshState?.lastSuccessfulRefreshAt {
                return AppStrings.OpenRouter.updated.formatted(
                    locale: locale,
                    AppFormatters.shortDate(date, locale: locale)
                )
            }
            return AppStrings.OpenRouter.current.localized(locale: locale)
        case .partial:
            return AppStrings.OpenRouter.partial.localized(locale: locale)
        case .stale:
            return AppStrings.Common.stale.localized(locale: locale)
        case .unavailable:
            return AppStrings.Common.unavailable.localized(locale: locale)
        case .unknown:
            return AppStrings.Common.unknown.localized(locale: locale)
        case .unlimited:
            return AppStrings.Common.unlimited.localized(locale: locale)
        case .credentialError:
            return AppStrings.OpenRouter.credentialUnavailable.localized(locale: locale)
        case .disabled:
            return AppStrings.OpenRouter.disabled.localized(locale: locale)
        case .recoveryRequired:
            return AppStrings.OpenRouter.recoveryRequired.localized(locale: locale)
        case .deletionPending:
            return AppStrings.OpenRouter.deletionPending.localized(locale: locale)
        }
    }

    private static func credentialDashboardValue(
        state: OpenRouterCapacityState,
        statusText: String,
        metric: OpenRouterCapacityMetricPresentation?,
        locale: Locale
    ) -> String {
        if let metric {
            return metric.dashboardValueText
        }
        switch state {
        case .current, .unlimited:
            return AppStrings.OpenRouter.noKeyLimit.localized(locale: locale)
        case .partial, .stale, .unavailable, .unknown, .credentialError,
             .disabled, .recoveryRequired, .deletionPending:
            return statusText
        }
    }

    private static func credentialDashboardStatus(
        state: OpenRouterCapacityState,
        statusText: String,
        hasMetric: Bool
    ) -> String? {
        guard hasMetric else { return nil }
        switch state {
        case .partial, .stale, .credentialError, .disabled,
             .recoveryRequired, .deletionPending:
            return statusText
        case .current, .unavailable, .unknown, .unlimited:
            return nil
        }
    }

    private static func statusText(
        for state: OpenRouterCapacityState,
        locale: Locale
    ) -> String {
        state.localizedStatusText(locale: locale)
    }

    private static func metricPresentation(
        _ metric: CapacityMetric?,
        fallbackID: String,
        locale: Locale,
        now: Date
    ) -> OpenRouterCapacityMetricPresentation {
        guard let metric else {
            let value = AppStrings.Common.unavailable.localized(locale: locale)
            return OpenRouterCapacityMetricPresentation(
                id: fallbackID,
                metricID: fallbackID,
                displayName: metricName(fallbackID, locale: locale),
                valueText: value,
                displayValueLines: [value],
                dashboardValueText: value,
                dashboardAccessibilityValue: value,
                tableValueText: value,
                accountCredits: nil,
                keyCapacity: nil,
                scopeText: metricScopeText(fallbackID, locale: locale),
                usageColumn: usageColumn(fallbackID),
                usageQualifierText: usageQualifierText(
                    fallbackID,
                    locale: locale
                ),
                resetText: nil,
                resetIdentity: nil,
                freshnessText: nil,
                state: .unavailable,
                accessibilityValue: value
            )
        }

        let isStale = now.timeIntervalSince(metric.freshness.observedAt)
            > TimeInterval(OpenRouterProviderContract.maximumAgeSeconds)
        let state: OpenRouterCapacityState = switch metric.availability {
        case .known:
            isStale ? .stale : .current
        case .unlimited:
            isStale ? .stale : .unlimited
        case .unavailable:
            .unavailable
        case .unknown:
            .unknown
        case .manual:
            .unknown
        }
        let name = metricName(metric.metricID, locale: locale)
        let value = metricValue(metric, locale: locale)
        let displayValueLines = metricDisplayValueLines(
            metric,
            fallback: value,
            locale: locale
        )
        let dashboardValue = dashboardMetricValue(metric, locale: locale)
        let dashboardAccessibility = dashboardMetricAccessibilityValue(
            metric,
            fallback: dashboardValue,
            locale: locale
        )
        let tableValue = tableMetricValue(metric, fallback: value, locale: locale)
        let accountCredits = accountCreditsPresentation(
            metric,
            locale: locale
        )
        let keyCapacity = keyCapacityPresentation(metric, locale: locale)
        let reset = resetText(metric.window, now: now, locale: locale)
        let freshness: String? = switch metric.availability {
        case .known, .unlimited:
            isStale
                ? AppStrings.OpenRouter.staleUpdated.formatted(
                    locale: locale,
                    AppFormatters.shortDate(metric.freshness.observedAt, locale: locale)
                )
                : AppStrings.OpenRouter.updated.formatted(
                    locale: locale,
                    AppFormatters.shortDate(metric.freshness.observedAt, locale: locale)
                )
        case .unavailable, .manual, .unknown:
            nil
        }
        let accessibility = [value, reset, freshness]
            .compactMap { $0 }
            .joined(separator: ", ")
        return OpenRouterCapacityMetricPresentation(
            id: "\(metric.accountContextID):\(metric.sourceID):\(metric.metricID)",
            metricID: metric.metricID,
            displayName: name,
            valueText: value,
            displayValueLines: displayValueLines,
            dashboardValueText: dashboardValue,
            dashboardAccessibilityValue: dashboardAccessibility,
            tableValueText: tableValue,
            accountCredits: accountCredits,
            keyCapacity: keyCapacity,
            scopeText: metricScopeText(metric.metricID, locale: locale),
            usageColumn: usageColumn(metric.metricID),
            usageQualifierText: usageQualifierText(
                metric.metricID,
                locale: locale
            ),
            resetText: reset,
            resetIdentity: resetIdentity(
                metric.window,
                metricID: metric.metricID
            ),
            freshnessText: freshness,
            state: state,
            accessibilityValue: accessibility
        )
    }

    private static func metricValue(
        _ metric: CapacityMetric,
        locale: Locale
    ) -> String {
        switch metric.availability {
        case .unavailable:
            return AppStrings.Common.unavailable.localized(locale: locale)
        case .unknown:
            return AppStrings.Common.unknown.localized(locale: locale)
        case .unlimited:
            return AppStrings.Common.unlimited.localized(locale: locale)
        case .manual:
            return AppStrings.Common.manual.localized(locale: locale)
        case .known:
            break
        }

        guard metric.unit.kind == .currency,
              let code = metric.unit.currencyCode,
              let values = metric.values else {
            return AppStrings.Common.unknown.localized(locale: locale)
        }
        let consumed = values.consumed.map {
            AppFormatters.currency($0.value, code: code, locale: locale)
        }
        let remaining = values.remaining.map {
            AppFormatters.currency($0.value, code: code, locale: locale)
        }
        let limit = values.limit.map {
            AppFormatters.currency($0.value, code: code, locale: locale)
        }
        if metric.metricID == "account-credits",
           let remaining, let consumed {
            return AppStrings.OpenRouter.creditSummary.formatted(
                locale: locale,
                remaining,
                consumed
            )
        }
        if let remainingValue = values.remaining,
           let limitValue = values.limit {
            return AppStrings.OpenRouter.availableOf.formatted(
                locale: locale,
                AppFormatters.currency(
                    remainingValue.value,
                    code: code,
                    locale: locale
                ),
                AppFormatters.currency(
                    limitValue.value,
                    code: code,
                    locale: locale
                )
            )
        }
        if let remaining {
            return AppStrings.OpenRouter.remaining.formatted(
                locale: locale,
                remaining
            )
        }
        if let limit {
            return AppStrings.OpenRouter.limit.formatted(
                locale: locale,
                limit
            )
        }
        if let consumed {
            return AppStrings.OpenRouter.used.formatted(
                locale: locale,
                consumed
            )
        }
        return AppStrings.Common.unknown.localized(locale: locale)
    }

    private static func metricDisplayValueLines(
        _ metric: CapacityMetric,
        fallback: String,
        locale: Locale
    ) -> [String] {
        guard metric.metricID == "account-credits",
              metric.availability == .known,
              metric.unit.kind == .currency,
              let code = metric.unit.currencyCode,
              let values = metric.values,
              let remaining = values.remaining,
              let consumed = values.consumed else {
            return [fallback]
        }

        return [
            AppStrings.OpenRouter.remaining.formatted(
                locale: locale,
                AppFormatters.currency(
                    remaining.value,
                    code: code,
                    locale: locale
                )
            ),
            AppStrings.OpenRouter.used.formatted(
                locale: locale,
                AppFormatters.currency(
                    consumed.value,
                    code: code,
                    locale: locale
                )
            ),
        ]
    }

    private static func accountCreditsPresentation(
        _ metric: CapacityMetric,
        locale: Locale
    ) -> OpenRouterAccountCreditsPresentation? {
        guard metric.metricID == "account-credits",
              metric.availability == .known,
              metric.unit.kind == .currency,
              let code = metric.unit.currencyCode,
              let remaining = metric.values?.remaining,
              let consumed = metric.values?.consumed else {
            return nil
        }
        let leftText = AppFormatters.currency(
            remaining.value,
            code: code,
            locale: locale
        )
        let usedText = AppFormatters.currency(
            consumed.value,
            code: code,
            locale: locale
        )
        return OpenRouterAccountCreditsPresentation(
            leftText: leftText,
            usedText: usedText,
            accessibilityValue: [
                AppStrings.OpenRouter.leftColumn.localized(locale: locale),
                leftText,
                AppStrings.OpenRouter.usedColumn.localized(locale: locale),
                usedText,
            ].joined(separator: ", ")
        )
    }

    private static func keyCapacityPresentation(
        _ metric: CapacityMetric,
        locale: Locale
    ) -> OpenRouterKeyCapacityPresentation? {
        guard metric.metricID == "key-credit-limit",
              metric.availability == .known,
              metric.unit.kind == .currency,
              let code = metric.unit.currencyCode,
              let available = metric.values?.remaining,
              let total = metric.values?.limit else {
            return nil
        }
        let availableText = AppFormatters.currency(
            available.value,
            code: code,
            locale: locale
        )
        let totalText = AppFormatters.currency(
            total.value,
            code: code,
            locale: locale
        )
        let totalDouble = NSDecimalNumber(decimal: total.value).doubleValue
        let availableDouble = NSDecimalNumber(decimal: available.value).doubleValue
        let fraction = totalDouble > 0
            ? min(max(availableDouble / totalDouble, 0), 1)
            : nil
        return OpenRouterKeyCapacityPresentation(
            availableText: availableText,
            totalText: totalText,
            visualValueText: "\(availableText) / \(totalText)",
            availableFraction: fraction,
            accessibilityValue: AppStrings.OpenRouter.availableOf.formatted(
                locale: locale,
                availableText,
                totalText
            )
        )
    }

    private static func tableMetricValue(
        _ metric: CapacityMetric,
        fallback: String,
        locale: Locale
    ) -> String {
        guard metric.availability == .known,
              metric.unit.kind == .currency,
              let code = metric.unit.currencyCode,
              let values = metric.values else {
            return fallback
        }
        let amount = values.consumed ?? values.remaining ?? values.limit
        guard let amount else { return fallback }
        return AppFormatters.currency(
            amount.value,
            code: code,
            locale: locale
        )
    }

    private static func dashboardMetricValue(
        _ metric: CapacityMetric,
        locale: Locale
    ) -> String {
        switch metric.availability {
        case .unavailable:
            return AppStrings.Common.unavailable.localized(locale: locale)
        case .unknown:
            return AppStrings.Common.unknown.localized(locale: locale)
        case .unlimited:
            return AppStrings.Common.unlimited.localized(locale: locale)
        case .manual:
            return AppStrings.Common.manual.localized(locale: locale)
        case .known:
            break
        }

        guard metric.unit.kind == .currency,
              let code = metric.unit.currencyCode,
              let remaining = metric.values?.remaining else {
            return metricValue(metric, locale: locale)
        }
        return AppFormatters.currency(
            remaining.value,
            code: code,
            locale: locale
        )
    }

    private static func dashboardMetricAccessibilityValue(
        _ metric: CapacityMetric,
        fallback: String,
        locale: Locale
    ) -> String {
        guard metric.availability == .known,
              metric.unit.kind == .currency,
              let code = metric.unit.currencyCode,
              let remaining = metric.values?.remaining else {
            return fallback
        }
        let amount = AppFormatters.currency(
            remaining.value,
            code: code,
            locale: locale
        )
        if metric.metricID == "key-credit-limit",
           let limit = metric.values?.limit {
            return AppStrings.OpenRouter.availableOf.formatted(
                locale: locale,
                amount,
                AppFormatters.currency(
                    limit.value,
                    code: code,
                    locale: locale
                )
            )
        }
        return AppStrings.OpenRouter.remaining.formatted(
            locale: locale,
            amount
        )
    }

    private static func resetText(
        _ window: CapacityWindow,
        now: Date,
        locale: Locale
    ) -> String? {
        if let transition = window.nextTransition {
            let relative = AppFormatters.relativeDate(
                transition.at,
                relativeTo: now,
                locale: locale
            )
            return transition.at >= now
                ? AppStrings.OpenRouter.resets.formatted(
                    locale: locale,
                    relative
                )
                : AppStrings.OpenRouter.reset.formatted(
                    locale: locale,
                    relative
                )
        }
        return switch window.kind {
        case .lifetime:
            AppStrings.OpenRouter.noReset.localized(locale: locale)
        case .fixed, .billingCycle, .rolling, .unknown:
            AppStrings.OpenRouter.resetUnknown.localized(locale: locale)
        case .none:
            nil
        }
    }

    private static func resetIdentity(
        _ window: CapacityWindow,
        metricID: String
    ) -> String? {
        guard window.kind != .none else { return nil }
        return [
            resetSemanticClass(metricID),
            window.kind.rawValue,
            window.durationSeconds.map(String.init) ?? "-",
            dateIdentity(window.startsAt),
            dateIdentity(window.endsAt),
            window.nextTransition?.kind.rawValue ?? "-",
            dateIdentity(window.nextTransition?.at),
        ]
        .joined(separator: ":")
    }

    private static func resetSemanticClass(_ metricID: String) -> String {
        switch metricID {
        case "key-credit-limit":
            "key-limit"
        case "key-daily-usage", "key-daily-byok-usage":
            "usage-day"
        case "key-weekly-usage", "key-weekly-byok-usage":
            "usage-week"
        case "key-monthly-usage", "key-monthly-byok-usage":
            "usage-month"
        case "key-total-usage", "key-total-byok-usage":
            "usage-total"
        default:
            metricID
        }
    }

    private static func dateIdentity(_ date: Date?) -> String {
        date.map {
            String($0.timeIntervalSinceReferenceDate.bitPattern)
        } ?? "-"
    }

    private static func metricName(
        _ metricID: String,
        locale: Locale
    ) -> String {
        switch metricID {
        case "account-credits":
            AppStrings.OpenRouter.accountCredits.localized(locale: locale)
        case "key-credit-limit":
            AppStrings.OpenRouter.keyCreditLimit.localized(locale: locale)
        case "key-total-usage":
            AppStrings.OpenRouter.totalUsage.localized(locale: locale)
        case "key-daily-usage":
            AppStrings.OpenRouter.dailyUsage.localized(locale: locale)
        case "key-weekly-usage":
            AppStrings.OpenRouter.weeklyUsage.localized(locale: locale)
        case "key-monthly-usage":
            AppStrings.OpenRouter.monthlyUsage.localized(locale: locale)
        case "key-total-byok-usage":
            AppStrings.OpenRouter.totalBYOKUsage.localized(locale: locale)
        case "key-daily-byok-usage":
            AppStrings.OpenRouter.dailyBYOKUsage.localized(locale: locale)
        case "key-weekly-byok-usage":
            AppStrings.OpenRouter.weeklyBYOKUsage.localized(locale: locale)
        case "key-monthly-byok-usage":
            AppStrings.OpenRouter.monthlyBYOKUsage.localized(locale: locale)
        default:
            AppStrings.Common.unknown.localized(locale: locale)
        }
    }

    private static func metricScopeText(
        _ metricID: String,
        locale: Locale
    ) -> String? {
        switch metricID {
        case "key-credit-limit":
            AppStrings.OpenRouter.limitScope.localized(locale: locale)
        case "key-daily-usage", "key-daily-byok-usage":
            AppStrings.OpenRouter.dayScope.localized(locale: locale)
        case "key-weekly-usage", "key-weekly-byok-usage":
            AppStrings.OpenRouter.weekScope.localized(locale: locale)
        case "key-monthly-usage", "key-monthly-byok-usage":
            AppStrings.OpenRouter.monthScope.localized(locale: locale)
        case "key-total-usage", "key-total-byok-usage":
            AppStrings.OpenRouter.totalScope.localized(locale: locale)
        default:
            nil
        }
    }

    private static func usageColumn(
        _ metricID: String
    ) -> OpenRouterUsageColumn? {
        if metricID.hasSuffix("-byok-usage") {
            return .byok
        }
        if metricID.hasSuffix("-usage") {
            return .usage
        }
        return nil
    }

    private static func usageQualifierText(
        _ metricID: String,
        locale: Locale
    ) -> String? {
        switch usageColumn(metricID) {
        case .usage:
            AppStrings.OpenRouter.usageColumn.localized(locale: locale)
        case .byok:
            AppStrings.OpenRouter.byokColumn.localized(locale: locale)
        case nil:
            nil
        }
    }

    private static func diagnosticText(
        _ code: CredentialContextDiagnosticCode,
        locale: Locale
    ) -> String {
        switch code {
        case .authentication:
            AppStrings.OpenRouter.authenticationFailed.localized(locale: locale)
        case .insufficientPrivilege:
            AppStrings.OpenRouter.privilegeInsufficient.localized(locale: locale)
        case .throttled:
            AppStrings.OpenRouter.throttled.localized(locale: locale)
        case .transientFailure:
            AppStrings.OpenRouter.temporaryFailure.localized(locale: locale)
        case .credentialDisabled:
            AppStrings.OpenRouter.disabled.localized(locale: locale)
        case .credentialMissing:
            AppStrings.OpenRouter.credentialUnavailable.localized(locale: locale)
        }
    }

    private static func metricOrder(_ metricID: String) -> Int {
        switch metricID {
        case "key-credit-limit": 0
        case "key-daily-usage": 1
        case "key-weekly-usage": 2
        case "key-monthly-usage": 3
        case "key-total-usage": 4
        case "key-daily-byok-usage": 5
        case "key-weekly-byok-usage": 6
        case "key-monthly-byok-usage": 7
        case "key-total-byok-usage": 8
        default: 100
        }
    }
}
