import BairometerCore
import Foundation

extension UsageStatus {
    func localizedDisplayName(locale: Locale) -> String {
        switch self {
        case .ok:
            "OK"
        case .warning:
            AppStrings.Common.warning.localized(locale: locale)
        case .error:
            AppStrings.Common.error.localized(locale: locale)
        case .unavailable:
            AppStrings.Common.unavailable.localized(locale: locale)
        }
    }
}

extension ConfidenceLevel {
    func localizedDisplayName(locale: Locale) -> String {
        switch self {
        case .live:
            AppStrings.Common.live.localized(locale: locale)
        case .delayed:
            AppStrings.Common.delayed.localized(locale: locale)
        case .localEstimate:
            AppStrings.Common.localEstimate.localized(locale: locale)
        case .manual:
            AppStrings.Common.manual.localized(locale: locale)
        case .unknown:
            AppStrings.Common.unknown.localized(locale: locale)
        }
    }
}

extension ProviderSourceMode {
    func localizedDisplayName(locale: Locale) -> String {
        switch self {
        case .manual:
            AppStrings.Common.manual.localized(locale: locale)
        case .claudeStatusLine:
            AppStrings.Common.managedStatusLine.localized(locale: locale)
        case .claudeUsageCLI:
            AppStrings.Common.usageCLIExperimental.localized(locale: locale)
        case .ollamaWebPage:
            AppStrings.Common.webPageExperimental.localized(locale: locale)
        case .appServer:
            AppStrings.Common.appServerExperimental.localized(locale: locale)
        case .openRouterAPI, .miniMaxTokenPlan:
            displayName
        }
    }
}

extension ProviderSourceKind {
    func localizedDisplayName(locale: Locale) -> String {
        switch self {
        case .manual:
            AppStrings.Common.manual.localized(locale: locale)
        case .localSnapshot:
            AppStrings.Common.localSnapshot.localized(locale: locale)
        case .live:
            AppStrings.Common.live.localized(locale: locale)
        case .delayed:
            AppStrings.Common.delayed.localized(locale: locale)
        }
    }
}

extension ProviderRefreshStatus {
    func localizedDisplayName(locale: Locale) -> String {
        switch self {
        case .idle:
            AppStrings.Common.idle.localized(locale: locale)
        case .refreshing:
            AppStrings.Common.refreshing.localized(locale: locale)
        case .succeeded:
            AppStrings.Common.updated.localized(locale: locale)
        case .failed:
            AppStrings.Common.failed.localized(locale: locale)
        }
    }
}

extension RefreshInterval {
    func localizedDisplayName(locale: Locale) -> String {
        switch self {
        case .manualOnly:
            AppStrings.Common.intervalManual.localized(locale: locale)
        case .oneMinute:
            AppStrings.Common.intervalOneMinute.localized(locale: locale)
        case .fiveMinutes:
            AppStrings.Common.intervalFiveMinutes.localized(locale: locale)
        case .tenMinutes:
            AppStrings.Common.intervalTenMinutes.localized(locale: locale)
        case .fifteenMinutes:
            AppStrings.Common.intervalFifteenMinutes.localized(locale: locale)
        case .thirtyMinutes:
            AppStrings.Common.intervalThirtyMinutes.localized(locale: locale)
        case .oneHour:
            AppStrings.Common.intervalOneHour.localized(locale: locale)
        }
    }
}

extension DashboardHeightPreset {
    func localizedDisplayName(locale: Locale) -> String {
        switch self {
        case .compact:
            AppStrings.Common.heightCompact.localized(locale: locale)
        case .standard:
            AppStrings.Common.heightStandard.localized(locale: locale)
        case .tall:
            AppStrings.Common.heightTall.localized(locale: locale)
        }
    }
}

extension UsageDisplayMode {
    func localizedDisplayName(locale: Locale) -> String {
        switch self {
        case .used:
            AppStrings.DisplayMode.used.localized(locale: locale)
        case .left:
            AppStrings.DisplayMode.left.localized(locale: locale)
        }
    }
}

extension UsageDisplayOverrideSelection {
    func localizedDisplayName(locale: Locale) -> String {
        switch self {
        case .global:
            AppStrings.DisplayMode.useGlobal.localized(locale: locale)
        case .used:
            AppStrings.DisplayMode.used.localized(locale: locale)
        case .left:
            AppStrings.DisplayMode.left.localized(locale: locale)
        }
    }
}

extension SettingsSection {
    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .general:
            AppStrings.Settings.Navigation.general.localized(locale: locale)
        case .accounts:
            AppStrings.Settings.Navigation.accounts.localized(locale: locale)
        case .providerSetup:
            AppStrings.Settings.Navigation.providerSetup.localized(locale: locale)
        }
    }
}
