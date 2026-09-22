import SwiftUI

struct SettingsView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    @ObservedObject var appLanguagePreference: AppLanguagePreference
    @State private var workspace: SettingsWorkspaceState
    @State private var workspaceGeneration = UUID()

    init(
        appModel: AppModel,
        appLanguagePreference: AppLanguagePreference,
        initialWorkspace: SettingsWorkspaceState = SettingsWorkspaceState()
    ) {
        self.appModel = appModel
        self.appLanguagePreference = appLanguagePreference
        _workspace = State(initialValue: initialWorkspace)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let warning = appModel.localizedStorageWarning(locale: locale) {
                Label(warning, systemImage: "externaldrive.badge.exclamationmark")
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)

                Divider()
            }

            sectionNavigation
            Divider()
            sectionContent
                .id(workspaceGeneration)
        }
        .frame(minWidth: 760, idealWidth: 840, minHeight: 500, idealHeight: 560)
        .font(TerminalTheme.bodyFont)
        .tint(TerminalTheme.primary)
        .alert(AppStrings.Settings.Accounts.discardTitle.localized(locale: locale), isPresented: $workspace.isShowingDiscardConfirmation) {
            Button(AppStrings.Settings.Accounts.discard.localized(locale: locale), role: .destructive) {
                guard let pendingNavigation = workspace.pendingNavigation else { return }
                applyNavigation(pendingNavigation)
                workspace.pendingNavigation = nil
            }
            .accessibilityIdentifier("settings.discard")
            Button(AppStrings.Settings.Accounts.keepEditing.localized(locale: locale), role: .cancel) {
                workspace.pendingNavigation = nil
            }
            .accessibilityIdentifier("settings.keep-editing")
        } message: {
            Text(AppStrings.Settings.Accounts.discardMessage.resource(locale: locale))
        }
        .onAppear {
            AppTelemetry.lifecycle.info("Settings appeared")
        }
        .onDisappear {
            resetWorkspace()
        }
    }

    private var sectionNavigation: some View {
        TerminalSegmentedControl(
            AppStrings.Settings.Navigation.label.localized(locale: locale),
            selection: $workspace.selection,
            options: SettingsSection.allCases.map {
                TerminalSegmentedOption(
                    value: $0,
                    title: $0.localizedTitle(locale: locale),
                    accessibilityIdentifier: "settings.navigation.\($0.rawValue)"
                )
            }
        )
        .labelsHidden()
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .onChange(of: workspace.selection) { oldSelection, newSelection in
            guard oldSelection != newSelection else { return }
            guard workspace.editorSession.isDirty else {
                workspace.editorSession.discardEditor()
                return
            }

            workspace.selection = oldSelection
            workspace.pendingNavigation = .section(newSelection)
            workspace.isShowingDiscardConfirmation = true
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch workspace.selection {
        case .general:
            GeneralSettingsPane(
                appModel: appModel,
                appLanguagePreference: appLanguagePreference
            )
        case .accounts:
            AccountsSettingsPane(
                appModel: appModel,
                editorSession: $workspace.editorSession,
                onRequestAccountSelection: requestAccountSelection
            )
        case .providerSetup:
            ProviderSetupSettingsPane(appModel: appModel)
        }
    }

    private func requestAccountSelection(_ accountID: String?) {
        guard accountID != workspace.editorSession.selectedAccountID else { return }
        requestNavigation(.account(accountID))
    }

    private func requestNavigation(_ destination: SettingsNavigationDestination) {
        guard workspace.editorSession.isDirty else {
            applyNavigation(destination)
            return
        }

        workspace.pendingNavigation = destination
        workspace.isShowingDiscardConfirmation = true
    }

    private func applyNavigation(_ destination: SettingsNavigationDestination) {
        workspace.editorSession.discardEditor()

        switch destination {
        case let .section(section):
            workspace.selection = section
        case let .account(accountID):
            workspace.editorSession.selectedAccountID = accountID
        }
    }

    private func resetWorkspace() {
        workspace.reset()
        workspaceGeneration = UUID()
    }
}

enum SettingsNavigationDestination: Equatable {
    case section(SettingsSection)
    case account(String?)
}

struct SettingsWorkspaceState: Equatable {
    var selection: SettingsSection = .accounts
    var editorSession = AccountEditorSession()
    var pendingNavigation: SettingsNavigationDestination?
    var isShowingDiscardConfirmation = false

    mutating func reset() {
        selection = .accounts
        editorSession.reset()
        pendingNavigation = nil
        isShowingDiscardConfirmation = false
    }
}

struct AccountEditorSession: Equatable {
    var selectedAccountID: String?
    var mode: AccountEditorMode?
    var isDirty: Bool

    init(
        selectedAccountID: String? = nil,
        mode: AccountEditorMode? = nil,
        isDirty: Bool = false
    ) {
        self.selectedAccountID = selectedAccountID
        self.mode = mode
        self.isDirty = isDirty
    }

    mutating func discardEditor() {
        mode = nil
        isDirty = false
    }

    mutating func reset() {
        selectedAccountID = nil
        mode = nil
        isDirty = false
    }
}

enum AccountEditorMode: Equatable {
    case creating
    case editing
}

enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case general
    case accounts
    case providerSetup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .accounts: "Accounts"
        case .providerSetup: "Providers"
        }
    }
}
