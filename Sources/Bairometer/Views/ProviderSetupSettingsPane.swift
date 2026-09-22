import SwiftUI

struct ProviderSetupSettingsPane: View {
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.Settings.ProviderSetup.title.resource(locale: locale))
                    .font(TerminalTheme.titleFont)
                    .foregroundStyle(TerminalTheme.primary)
                Text(AppStrings.Settings.ProviderSetup.description.resource(locale: locale))
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.secondary)
            }

            TerminalFieldset(title: AppStrings.Settings.ProviderSetup.providers.localized(locale: locale)) {
                EmptyView()
            } content: {
                VStack(spacing: 0) {
                    ForEach(appModel.providerIDs, id: \.self) { providerID in
                        ProviderSetupRow(appModel: appModel, providerID: providerID)

                        if providerID != appModel.providerIDs.last {
                            TerminalRule()
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ProviderSetupRow: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    let providerID: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appModel.providerDisplayName(for: providerID))
                    .font(TerminalTheme.emphasizedBodyFont)
                    .foregroundStyle(TerminalTheme.primary)
                Text(sourceSummary)
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.secondary)
            }
            Spacer()
            Button {
                if let usageURL { openURL(usageURL) }
            } label: {
                Label(
                    AppStrings.Settings.ProviderSetup.openUsage.localized(locale: locale),
                    systemImage: "arrow.up.forward.square"
                )
            }
            .buttonStyle(TerminalActionButtonStyle())
            .disabled(usageURL == nil)
        }
    }

    private var usageURL: URL? {
        appModel.usageURL(providerID: providerID)
    }

    private var sourceSummary: String {
        let capabilities = appModel.providerCapabilities(for: providerID)
        guard !capabilities.sources.isEmpty else {
            return AppStrings.Settings.ProviderSetup.noConfiguredSource.localized(locale: locale)
        }
        return capabilities.sources
            .map {
                "\($0.mode.localizedDisplayName(locale: locale)) · \($0.kind.localizedDisplayName(locale: locale))"
            }
            .joined(separator: " · ")
    }
}
