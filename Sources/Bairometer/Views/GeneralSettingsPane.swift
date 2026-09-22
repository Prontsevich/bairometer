import BairometerCore
import SwiftUI

struct GeneralSettingsPane: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var appLanguagePreference: AppLanguagePreference
    @Environment(\.locale) private var locale
    @AppStorage(DashboardHeightPreset.storageKey)
    private var dashboardHeightPresetRawValue = DashboardHeightPreset.standard.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.Settings.General.title.resource(locale: locale))
                    .font(TerminalTheme.titleFont)
                    .foregroundStyle(TerminalTheme.primary)
                Text(AppStrings.Settings.General.description.resource(locale: locale))
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.secondary)
            }

            TerminalFieldset(
                title: AppStrings.Settings.Language.title.localized(locale: locale)
            ) {
                EmptyView()
            } content: {
                HStack(alignment: .center, spacing: 14) {
                    Text(AppStrings.Settings.Language.selection.resource(locale: locale))
                        .font(TerminalTheme.bodyFont)
                        .foregroundStyle(TerminalTheme.secondary)
                        .frame(width: 120, alignment: .leading)

                    TerminalSegmentedControl(
                        AppStrings.Settings.Language.selection.localized(locale: locale),
                        selection: appLanguageBinding,
                        options: AppLanguage.allCases.map {
                            TerminalSegmentedOption(
                                value: $0,
                                title: AppStrings.Settings.Language.option(for: $0)
                                    .localized(locale: locale),
                                accessibilityIdentifier: "settings.general.language.\($0.rawValue)"
                            )
                        }
                    )
                }

                Text(AppStrings.Settings.Language.description.resource(locale: locale))
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.secondary)
            }

            TerminalFieldset(title: AppStrings.Settings.General.scheduleTitle.localized(locale: locale)) {
                EmptyView()
            } content: {
                HStack(alignment: .center, spacing: 14) {
                    Text(AppStrings.Settings.General.interval.resource(locale: locale))
                        .font(TerminalTheme.bodyFont)
                        .foregroundStyle(TerminalTheme.secondary)
                        .frame(width: 80, alignment: .leading)

                    TerminalSegmentedControl(
                        AppStrings.Settings.General.refreshInterval.localized(locale: locale),
                        selection: refreshIntervalBinding,
                        options: RefreshInterval.allCases.map {
                            TerminalSegmentedOption(
                                value: $0,
                                title: $0.localizedDisplayName(locale: locale),
                                accessibilityIdentifier: "settings.general.refresh.\($0.rawValue)"
                            )
                        }
                    )
                }

                Text(AppStrings.Settings.General.manualRefreshHelp.resource(locale: locale))
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.secondary)
            }

            TerminalFieldset(title: AppStrings.Settings.General.dashboardTitle.localized(locale: locale)) {
                EmptyView()
            } content: {
                HStack(alignment: .center, spacing: 14) {
                    Text(AppStrings.Settings.General.displayLimits.resource(locale: locale))
                        .font(TerminalTheme.bodyFont)
                        .foregroundStyle(TerminalTheme.secondary)
                        .frame(width: 80, alignment: .leading)

                    TerminalSegmentedControl(
                        AppStrings.Settings.General.displayLimitsAccessibility.localized(locale: locale),
                        selection: usageDisplayModeBinding,
                        options: UsageDisplayMode.allCases.map {
                            TerminalSegmentedOption(
                                value: $0,
                                title: $0.localizedDisplayName(locale: locale),
                                accessibilityIdentifier: "settings.general.limit-display.\($0.rawValue)"
                            )
                        }
                    )
                }

                Text(AppStrings.Settings.General.displayLimitsHelp.resource(locale: locale))
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.secondary)

                HStack(alignment: .center, spacing: 14) {
                    Text(AppStrings.Settings.General.height.resource(locale: locale))
                        .font(TerminalTheme.bodyFont)
                        .foregroundStyle(TerminalTheme.secondary)
                        .frame(width: 80, alignment: .leading)

                    TerminalSegmentedControl(
                        AppStrings.Settings.General.heightAccessibility.localized(locale: locale),
                        selection: dashboardHeightPresetBinding,
                        options: DashboardHeightPreset.allCases.map {
                            TerminalSegmentedOption(
                                value: $0,
                                title: $0.localizedDisplayName(locale: locale),
                                accessibilityIdentifier: "settings.general.height.\($0.rawValue)"
                            )
                        }
                    )
                }

                Text(AppStrings.Settings.General.heightHelp.resource(locale: locale))
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var refreshIntervalBinding: Binding<RefreshInterval> {
        Binding(
            get: { appModel.refreshSettings.interval },
            set: { appModel.setRefreshInterval($0) }
        )
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { appLanguagePreference.language },
            set: { appLanguagePreference.select($0) }
        )
    }

    private var dashboardHeightPresetBinding: Binding<DashboardHeightPreset> {
        Binding(
            get: {
                DashboardHeightPreset(rawValue: dashboardHeightPresetRawValue) ?? .standard
            },
            set: { dashboardHeightPresetRawValue = $0.rawValue }
        )
    }

    private var usageDisplayModeBinding: Binding<UsageDisplayMode> {
        Binding(
            get: { appModel.usageDisplayMode },
            set: { appModel.setUsageDisplayMode($0) }
        )
    }
}
