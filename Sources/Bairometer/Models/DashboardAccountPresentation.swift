import BairometerCore
import Foundation

enum DashboardAccountState: Equatable {
    case normal
    case refreshing
    case stale
    case failed
    case warning
    case manual
    case unavailable
    case noData
}

struct DashboardLimitWindowPresentation: Identifiable, Equatable {
    let id: String
    let displayName: String
    let displayPercent: Double
    let displayText: String
    let supportingText: String?
    let accessibilityLabel: String
    let toggleHelp: String
    let toggleAccessibilityHint: String
    let resetText: String?

    var accessibilityValue: String {
        [displayText, supportingText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    init?(window: UsageLimitWindow, mode: UsageDisplayMode, now: Date, locale: Locale) {
        guard let usedPercent = window.usedPercent else { return nil }

        id = window.id
        displayName = window.displayName
        let clampedUsedPercent = min(max(usedPercent, 0), 100)
        displayPercent = mode == .used ? clampedUsedPercent : 100 - clampedUsedPercent
        displayText = Self.displayText(for: displayPercent, mode: mode, locale: locale)
        supportingText = window.remainingLabel
        accessibilityLabel = AppStrings.Dashboard.windowUsage.formatted(locale: locale, displayName)
        let nextMode: UsageDisplayMode = mode == .used ? .left : .used
        let nextText = Self.displayText(
            for: nextMode == .used ? clampedUsedPercent : 100 - clampedUsedPercent,
            mode: nextMode,
            locale: locale
        )
        toggleHelp = AppStrings.Dashboard.meterToggleHelp.formatted(
            locale: locale,
            displayName,
            displayText,
            nextText
        )
        toggleAccessibilityHint = AppStrings.Dashboard.meterToggleHint.localized(locale: locale)
        resetText = Self.resetText(for: window.resetAt, now: now, locale: locale)
    }

    init(
        id: String,
        displayName: String,
        displayPercent: Double,
        displayText: String,
        supportingText: String? = nil,
        accessibilityLabel: String,
        toggleHelp: String,
        toggleAccessibilityHint: String,
        resetText: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.displayPercent = displayPercent
        self.displayText = displayText
        self.supportingText = supportingText
        self.accessibilityLabel = accessibilityLabel
        self.toggleHelp = toggleHelp
        self.toggleAccessibilityHint = toggleAccessibilityHint
        self.resetText = resetText
    }

    private static func displayText(for percent: Double, mode: UsageDisplayMode, locale: Locale) -> String {
        let formattedPercent = AppFormatters.percentage(percent, locale: locale)
        return switch mode {
        case .used:
            AppStrings.Dashboard.used.formatted(locale: locale, formattedPercent)
        case .left:
            AppStrings.Dashboard.left.formatted(locale: locale, formattedPercent)
        }
    }

    private static func resetText(for resetAt: Date?, now: Date, locale: Locale) -> String? {
        guard let resetAt else { return nil }

        let relativeText = AppFormatters.relativeDate(resetAt, relativeTo: now, locale: locale)
        return resetAt >= now
            ? AppStrings.Dashboard.resets.formatted(locale: locale, relativeText)
            : AppStrings.Dashboard.reset.formatted(locale: locale, relativeText)
    }
}

struct MiniMaxQuotaWindowPresentation: Identifiable, Equatable {
    let id: String
    let displayName: String
    let capacityText: String
    let percentageText: String?
    let displayPercent: Double?
    let resetText: String?
    let resetAt: Date?
    let accessibilityLabel: String
    let accessibilityValue: String
    let meterPresentation: DashboardLimitWindowPresentation?

    var usageLimitWindow: UsageLimitWindow {
        UsageLimitWindow(
            id: id,
            displayName: displayName,
            usedPercent: displayPercent,
            resetAt: resetAt
        )
    }
}

struct MiniMaxQuotaCategoryPresentation: Identifiable, Equatable {
    let id: String
    let shortDisplayName: String
    let fullDisplayName: String
    let windows: [MiniMaxQuotaWindowPresentation]
    let accessibilityIdentifier: String
    let accessibilityValue: String

    var displayName: String { shortDisplayName }
}

struct MiniMaxCapacityPresentation: Equatable {
    let accountID: String
    let accountName: String
    let categories: [MiniMaxQuotaCategoryPresentation]

    init?(
        account: ProviderAccount,
        snapshot: CapacitySnapshot?,
        displayModeForWindow: (String) -> UsageDisplayMode = { _ in .used },
        now: Date = Date(),
        locale: Locale = Locale(identifier: "en_US")
    ) {
        guard account.providerID == MiniMaxProviderContract.providerID,
              let snapshot,
              snapshot.providerID == MiniMaxProviderContract.providerID,
              snapshot.surfaceID == MiniMaxProviderContract.surfaceID,
              snapshot.savedAccountID == account.accountID else {
            return nil
        }

        accountID = account.accountID
        accountName = account.displayName

        let knownContextIDs = Set(snapshot.accountContexts.map(\.contextID))
        let safeMetrics = snapshot.metrics.filter {
            $0.sourceID == MiniMaxProviderContract.sourceID
                && $0.unit == CapacityUnit(kind: .percent)
                && knownContextIDs.contains($0.accountContextID)
        }
        var metricByID: [String: CapacityMetric] = [:]
        for metric in safeMetrics where metricByID[metric.metricID] == nil {
            metricByID[metric.metricID] = metric
        }

        categories = Self.categoryDescriptors(locale: locale).map { category in
            let windows = Self.windowDescriptors(locale: locale).map { window in
                let metricID = "\(category.id).\(window.idSuffix)"
                return Self.windowPresentation(
                    metric: metricByID[metricID],
                    metricID: metricID,
                    categoryName: category.fullDisplayName,
                    windowName: window.displayName,
                    mode: displayModeForWindow(metricID),
                    now: now,
                    locale: locale
                )
            }
            return MiniMaxQuotaCategoryPresentation(
                id: category.id,
                shortDisplayName: category.shortDisplayName,
                fullDisplayName: category.fullDisplayName,
                windows: windows,
                accessibilityIdentifier: "dashboard.minimax.category.\(account.accountID).\(category.id)",
                accessibilityValue: windows
                    .map { "\($0.accessibilityLabel), \($0.accessibilityValue)" }
                    .joined(separator: "; ")
            )
        }
    }

    private static func categoryDescriptors(
        locale: Locale
    ) -> [(id: String, shortDisplayName: String, fullDisplayName: String)] {
        [
            (
                "quota-category-a",
                AppStrings.MiniMax.quotaCategoryAShort.localized(locale: locale),
                AppStrings.MiniMax.quotaCategoryAFull.localized(locale: locale)
            ),
            (
                "quota-category-b",
                AppStrings.MiniMax.quotaCategoryBShort.localized(locale: locale),
                AppStrings.MiniMax.quotaCategoryBFull.localized(locale: locale)
            ),
        ]
    }

    private static func windowDescriptors(
        locale: Locale
    ) -> [(idSuffix: String, displayName: String)] {
        [
            (
                "current",
                AppStrings.MiniMax.currentWindow.localized(locale: locale)
            ),
            (
                "weekly",
                AppStrings.MiniMax.weeklyWindow.localized(locale: locale)
            ),
        ]
    }

    private static func windowPresentation(
        metric: CapacityMetric?,
        metricID: String,
        categoryName: String,
        windowName: String,
        mode: UsageDisplayMode,
        now: Date,
        locale: Locale
    ) -> MiniMaxQuotaWindowPresentation {
        let resetAt = metric?.window.nextTransition.flatMap {
            $0.kind == .reset ? $0.at : nil
        }
        let resetText = resetAt.map {
            let relative = AppFormatters.relativeDate(
                $0,
                relativeTo: now,
                locale: locale
            )
            return $0 >= now
                ? AppStrings.Dashboard.resets.formatted(locale: locale, relative)
                : AppStrings.Dashboard.reset.formatted(locale: locale, relative)
        }
        let accessibilityLabel = AppStrings.MiniMax.quotaWindowAccessibility
            .formatted(locale: locale, categoryName, windowName)

        guard let metric else {
            let unavailable = AppStrings.Common.unavailable.localized(locale: locale)
            return MiniMaxQuotaWindowPresentation(
                id: metricID,
                displayName: windowName,
                capacityText: unavailable,
                percentageText: nil,
                displayPercent: nil,
                resetText: nil,
                resetAt: nil,
                accessibilityLabel: accessibilityLabel,
                accessibilityValue: unavailable,
                meterPresentation: nil
            )
        }

        let capacityText: String
        let usedPercent: Double?
        switch metric.availability {
        case .known:
            let values = metric.values
            if let remaining = values?.remaining,
               remaining.origin == .reported,
               values?.limit?.value == 100,
               values?.limit?.origin == .reported,
               values?.consumed?.origin == .derived {
                let remainingPercent = NSDecimalNumber(decimal: remaining.value)
                    .doubleValue
                if remainingPercent.isFinite,
                   (0 ... 100).contains(remainingPercent) {
                    let used = 100 - remainingPercent
                    capacityText = ""
                    usedPercent = used
                } else {
                    capacityText = AppStrings.Common.unknown.localized(locale: locale)
                    usedPercent = nil
                }
            } else {
                capacityText = AppStrings.Common.unknown.localized(locale: locale)
                usedPercent = nil
            }
        case .unlimited:
            capacityText = AppStrings.Common.unlimited.localized(locale: locale)
            usedPercent = nil
        case .unavailable:
            capacityText = AppStrings.Common.unavailable.localized(locale: locale)
            usedPercent = nil
        case .unknown:
            capacityText = AppStrings.Common.unknown.localized(locale: locale)
            usedPercent = nil
        case .manual:
            capacityText = AppStrings.Common.manual.localized(locale: locale)
            usedPercent = nil
        }

        let displayPercent = usedPercent.map {
            mode == .used ? $0 : 100 - $0
        }
        let percentageText = displayPercent.map {
            let percentage = AppFormatters.percentage($0, locale: locale)
            return mode == .used
                ? AppStrings.Dashboard.used.formatted(locale: locale, percentage)
                : AppStrings.Dashboard.left.formatted(locale: locale, percentage)
        }
        let accessibilityValue = [percentageText, capacityText, resetText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let meterPresentation = displayPercent.flatMap { displayPercent in
            percentageText.map { percentageText in
                let nextMode: UsageDisplayMode = mode == .used ? .left : .used
                let nextPercent = nextMode == .used
                    ? usedPercent ?? displayPercent
                    : 100 - (usedPercent ?? displayPercent)
                let nextFormatted = AppFormatters.percentage(
                    nextPercent,
                    locale: locale
                )
                let nextText = nextMode == .used
                    ? AppStrings.Dashboard.used.formatted(
                        locale: locale,
                        nextFormatted
                    )
                    : AppStrings.Dashboard.left.formatted(
                        locale: locale,
                        nextFormatted
                    )
                return DashboardLimitWindowPresentation(
                    id: metricID,
                    displayName: windowName,
                    displayPercent: displayPercent,
                    displayText: percentageText,
                    accessibilityLabel: accessibilityLabel,
                    toggleHelp: AppStrings.Dashboard.meterToggleHelp.formatted(
                        locale: locale,
                        accessibilityLabel,
                        percentageText,
                        nextText
                    ),
                    toggleAccessibilityHint: AppStrings.Dashboard
                        .meterToggleHint.localized(locale: locale),
                    resetText: resetText
                )
            }
        }

        return MiniMaxQuotaWindowPresentation(
            id: metricID,
            displayName: windowName,
            capacityText: capacityText,
            percentageText: percentageText,
            displayPercent: usedPercent,
            resetText: resetText,
            resetAt: resetAt,
            accessibilityLabel: accessibilityLabel,
            accessibilityValue: accessibilityValue,
            meterPresentation: meterPresentation
        )
    }
}

struct DashboardAccountPresentation: Equatable {
    let accountName: String
    let state: DashboardAccountState
    let windows: [DashboardLimitWindowPresentation]
    let bodyMessage: String?
    let statusText: String?
    let canRefresh: Bool
    let refreshHelp: String
    let isRefreshing: Bool

    init(
        row: AccountSnapshotRow,
        isStale: Bool,
        isGlobalRefresh: Bool,
        displayModeForWindow: (UsageLimitWindow) -> UsageDisplayMode = { _ in .used },
        now: Date = Date(),
        locale: Locale = Locale(identifier: "en_US")
    ) {
        accountName = row.account.displayName
        isRefreshing = row.refreshStatus == .refreshing
        canRefresh = row.account.isEnabled && !isGlobalRefresh && !isRefreshing
        refreshHelp = Self.refreshHelp(
            accountName: row.account.displayName,
            isEnabled: row.account.isEnabled,
            isGlobalRefresh: isGlobalRefresh,
            isRefreshing: isRefreshing,
            locale: locale
        )

        let snapshot = row.snapshot
        let resolvedState = Self.state(for: row, isStale: isStale)
        let hasUnavailableMiniMaxSubscription = Self.hasUnavailableMiniMaxSubscription(
            row
        )
        let visibleWindows = snapshot?.displayLimitWindows.compactMap {
            DashboardLimitWindowPresentation(
                window: $0,
                mode: displayModeForWindow($0),
                now: now,
                locale: locale
            )
        } ?? []
        state = resolvedState
        windows = switch resolvedState {
        case .manual, .unavailable, .noData:
            []
        case .normal, .refreshing, .stale, .failed, .warning:
            visibleWindows
        }
        statusText = Self.statusText(
            for: resolvedState,
            limitWindows: snapshot?.displayLimitWindows ?? [],
            hasUnavailableMiniMaxSubscription: hasUnavailableMiniMaxSubscription,
            locale: locale
        )
        bodyMessage = Self.bodyMessage(
            for: resolvedState,
            snapshot: snapshot,
            hasVisibleWindows: !windows.isEmpty,
            hasUnavailableMiniMaxSubscription: hasUnavailableMiniMaxSubscription,
            locale: locale
        )
    }

    private static func state(for row: AccountSnapshotRow, isStale: Bool) -> DashboardAccountState {
        if row.refreshIssue != nil || row.snapshot?.status == .error {
            return .failed
        }
        if (row.account.sourceMode == .manual && row.account.providerID != "mock") ||
            row.snapshot?.confidence == .manual {
            return .manual
        }
        if row.snapshot?.status == .unavailable {
            return .unavailable
        }
        if row.snapshot == nil {
            return .noData
        }
        if isStale {
            return .stale
        }
        if row.snapshot?.status == .warning || hasActionableWarnings(for: row) {
            return .warning
        }
        if row.refreshStatus == .refreshing {
            return .refreshing
        }
        return .normal
    }

    private static func hasActionableWarnings(for row: AccountSnapshotRow) -> Bool {
        guard let snapshot = row.snapshot, !snapshot.warnings.isEmpty else {
            return false
        }
        return !(row.account.sourceMode.isExperimental && snapshot.status == .ok)
    }

    private static func statusText(
        for state: DashboardAccountState,
        limitWindows: [UsageLimitWindow],
        hasUnavailableMiniMaxSubscription: Bool,
        locale: Locale
    ) -> String? {
        switch state {
        case .failed:
            hasUnavailableMiniMaxSubscription
                ? AppStrings.MiniMax.subscriptionUnavailable.localized(locale: locale)
                : AppStrings.Dashboard.refreshFailed.localized(locale: locale)
        case .stale:
            AppStrings.Common.stale.localized(locale: locale)
        case .warning:
            limitWindows.contains { ($0.usedPercent ?? 0) >= 85 }
                ? nil
                : AppStrings.Common.warning.localized(locale: locale)
        case .normal, .refreshing, .manual, .unavailable, .noData:
            nil
        }
    }

    private static func bodyMessage(
        for state: DashboardAccountState,
        snapshot: UsageSnapshot?,
        hasVisibleWindows: Bool,
        hasUnavailableMiniMaxSubscription: Bool,
        locale: Locale
    ) -> String? {
        switch state {
        case .manual:
            AppStrings.Dashboard.manualSource.localized(locale: locale)
        case .unavailable:
            snapshot?.remainingLabel ?? AppStrings.Common.usageUnavailable.localized(locale: locale)
        case .noData:
            AppStrings.Dashboard.noData.localized(locale: locale)
        case .failed:
            hasUnavailableMiniMaxSubscription || hasVisibleWindows
                ? nil
                : snapshot?.remainingLabel
                    ?? AppStrings.Dashboard.refreshFailedFallback.localized(locale: locale)
        case .normal, .refreshing, .stale, .warning:
            hasVisibleWindows
                ? nil
                : snapshot?.remainingLabel ?? AppStrings.Common.usageUnavailable.localized(locale: locale)
        }
    }

    private static func hasUnavailableMiniMaxSubscription(
        _ row: AccountSnapshotRow
    ) -> Bool {
        guard row.account.providerID == MiniMaxProviderContract.providerID else {
            return false
        }
        return row.refreshIssue?.warnings.contains(
            MiniMaxProviderContract.unavailableSubscriptionWarning
        ) == true
    }

    private static func refreshHelp(
        accountName: String,
        isEnabled: Bool,
        isGlobalRefresh: Bool,
        isRefreshing: Bool,
        locale: Locale
    ) -> String {
        if !isEnabled {
            return AppStrings.Dashboard.accountDisabled.formatted(locale: locale, accountName)
        }
        if isGlobalRefresh {
            return AppStrings.MenuBar.refreshingAllAccounts.localized(locale: locale)
        }
        if isRefreshing {
            return AppStrings.Dashboard.refreshingAccount.formatted(locale: locale, accountName)
        }
        return AppStrings.Dashboard.refreshAccount.formatted(locale: locale, accountName)
    }
}
