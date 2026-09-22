import BairometerCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsAccountDetailPresentation: Equatable {
    enum ContentKind: Equatable {
        case standard
        case openRouter
        case miniMax
    }

    let providerSubtitle: String?
    let accountExceptionText: String?
    let contentKind: ContentKind

    init(
        account: ProviderAccount,
        providerDisplayName: String,
        refreshStatus: ProviderRefreshStatus,
        refreshIssue: AccountRefreshIssue?,
        diagnosticsAvailability: ProviderSourceAvailability,
        locale: Locale
    ) {
        let isOpenRouter =
            account.providerID == OpenRouterProviderContract.providerID
        let isMiniMax =
            account.providerID == MiniMaxProviderContract.providerID
        providerSubtitle = isOpenRouter ? nil : providerDisplayName
        contentKind = isOpenRouter
            ? .openRouter
            : (isMiniMax ? .miniMax : .standard)

        guard isOpenRouter else {
            accountExceptionText = nil
            return
        }

        let didRefreshFail: Bool
        if case .failed = refreshStatus {
            didRefreshFail = true
        } else {
            didRefreshFail = false
        }

        if refreshIssue != nil
            || didRefreshFail
            || diagnosticsAvailability == .failed {
            accountExceptionText = AppStrings.Dashboard.refreshFailed.localized(
                locale: locale
            )
        } else if diagnosticsAvailability == .unsupported {
            accountExceptionText =
                AppStrings.Dashboard.sourceUnsupported.localized(locale: locale)
        } else if diagnosticsAvailability == .needsConnection {
            accountExceptionText =
                AppStrings.Dashboard.connectBeforeRefresh.localized(locale: locale)
        } else {
            accountExceptionText = nil
        }
    }
}

struct AccountDetailView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    let account: ProviderAccount
    let onEdit: () -> Void

    @State private var connectionError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isOpenRouter {
                        if let exceptionText =
                            detailPresentation.accountExceptionText {
                            Label(
                                exceptionText,
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(TerminalTheme.bodyFont)
                            .foregroundStyle(TerminalTheme.error)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                AppStrings.Settings.Detail.accountStatus
                                    .localized(locale: locale)
                            )
                            .accessibilityValue(exceptionText)
                            .accessibilityIdentifier(
                                OpenRouterSettingsAccessibilityID.accountException
                            )
                        }

                        OpenRouterCredentialsSettingsView(
                            appModel: appModel,
                            account: currentAccount
                        )
                    } else if isMiniMax {
                        standardAccountDetails
                        MiniMaxCredentialsSettingsView(
                            appModel: appModel,
                            account: currentAccount
                        )
                    } else {
                        standardAccountDetails
                    }

                    if !appModel.migrationDiagnostics(for: currentAccount).isEmpty {
                        TerminalFieldset(title: AppStrings.Settings.Detail.migration.localized(locale: locale)) {
                            EmptyView()
                        } content: {
                            ForEach(appModel.migrationDiagnostics(for: currentAccount)) { diagnostic in
                                Label(diagnostic.message, systemImage: "exclamationmark.triangle")
                                    .font(TerminalTheme.bodyFont)
                                    .foregroundStyle(TerminalTheme.warning)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .alert(AppStrings.Ollama.connectionTitle.localized(locale: locale), isPresented: connectionErrorBinding) {
            Button(AppStrings.Common.ok.localized(locale: locale), role: .cancel) {}
        } message: {
            Text(connectionError ?? AppStrings.Ollama.unavailable.localized(locale: locale))
        }
    }

    @ViewBuilder
    private var standardAccountDetails: some View {
        TerminalFieldset(title: AppStrings.Settings.Detail.status.localized(locale: locale)) {
            EmptyView()
        } content: {
            SettingsDetailValueRow(
                label: AppStrings.Settings.Detail.source.localized(locale: locale),
                value: currentAccount.sourceMode.localizedDisplayName(locale: locale),
                isTechnical: true
            )
            SettingsDetailValueRow(
                label: AppStrings.Settings.Detail.refresh.localized(locale: locale),
                value: appModel.refreshStatus(for: currentAccount)
                    .localizedDisplayName(locale: locale)
            )
            SettingsDetailValueRow(
                label: AppStrings.Settings.Detail.lastUpdated.localized(locale: locale),
                value: lastUpdatedText,
                isTechnical: true
            )
        }

        TerminalFieldset(
            title: AppStrings.Settings.Detail.configuration.localized(locale: locale)
        ) {
            EmptyView()
        } content: {
            SettingsDetailValueRow(
                label: AppStrings.Settings.Detail.provider.localized(locale: locale),
                value: appModel.providerDisplayName(for: currentAccount.providerID)
            )
            if let executableLabel,
               let executablePath = currentAccount.executablePath,
               !executablePath.isEmpty {
                SettingsDetailValueRow(
                    label: executableLabel,
                    value: executablePath,
                    isTechnical: true
                )
            }
        }
    }

    private var isOpenRouter: Bool {
        currentAccount.providerID == OpenRouterProviderContract.providerID
    }

    private var isMiniMax: Bool {
        currentAccount.providerID == MiniMaxProviderContract.providerID
    }

    private var detailPresentation: SettingsAccountDetailPresentation {
        SettingsAccountDetailPresentation(
            account: currentAccount,
            providerDisplayName: appModel.providerDisplayName(
                for: currentAccount.providerID
            ),
            refreshStatus: appModel.refreshStatus(for: currentAccount),
            refreshIssue: appModel.accountRefreshIssues[currentAccount.id],
            diagnosticsAvailability: appModel.accountDiagnostics(
                for: currentAccount
            ).availability,
            locale: locale
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentAccount.displayName)
                    .font(TerminalTheme.titleFont)
                    .foregroundStyle(TerminalTheme.primary)
                if let providerSubtitle = detailPresentation.providerSubtitle {
                    Text(providerSubtitle)
                        .font(TerminalTheme.bodyFont)
                        .foregroundStyle(TerminalTheme.secondary)
                }
            }

            Spacer()

            Toggle(AppStrings.Common.enabled.resource(locale: locale), isOn: enabledBinding)
                .toggleStyle(TerminalToggleStyle())

            Button(action: onEdit) {
                SettingsActionIcon(systemName: "square.and.pencil", verticalOffset: -1)
            }
            .settingsIconButton(help: AppStrings.Settings.Detail.editAccount.localized(locale: locale))
            .frame(
                width: TerminalIconControlLayout.hitTargetSize,
                height: TerminalIconControlLayout.hitTargetSize
            )

            if currentAccount.providerID == "ollama-cloud",
               currentAccount.sourceMode == .ollamaWebPage {
                Button(action: beginOllamaConnection) {
                    SettingsActionIcon(systemName: "person.crop.circle.badge.checkmark")
                }
                .disabled(appModel.ollamaWebPageClient == nil)
                .settingsIconButton(help: ollamaConnectionTitle)
                .frame(
                    width: TerminalIconControlLayout.hitTargetSize,
                    height: TerminalIconControlLayout.hitTargetSize
                )
            }

            Button {
                appModel.refreshAccount(
                    providerID: currentAccount.providerID,
                    accountID: currentAccount.accountID
                )
            } label: {
                SettingsActionIcon(systemName: "arrow.clockwise")
            }
            .disabled(isAccountActionDisabled)
            .settingsIconButton(help: refreshButtonTitle)
            .frame(
                width: TerminalIconControlLayout.hitTargetSize,
                height: TerminalIconControlLayout.hitTargetSize
            )

            NativeActionsMenuButton(
                isTestEnabled: !isAccountActionDisabled,
                isUsageEnabled: usageURL != nil,
                onTest: {
                    appModel.testConnection(
                        providerID: currentAccount.providerID,
                        accountID: currentAccount.accountID
                    )
                },
                onOpenUsage: {
                    if let usageURL {
                        openURL(usageURL)
                    }
                }
            )
            .frame(
                width: TerminalIconControlLayout.hitTargetSize,
                height: TerminalIconControlLayout.hitTargetSize
            )
        }
    }

    private var currentAccount: ProviderAccount {
        appModel.account(providerID: account.providerID, accountID: account.accountID) ?? account
    }

    private var isAccountActionDisabled: Bool {
        !currentAccount.isEnabled ||
            appModel.isRefreshing ||
            appModel.refreshStatus(for: currentAccount) == .refreshing
    }

    private var refreshButtonTitle: String {
        appModel.refreshStatus(for: currentAccount) == .refreshing
            ? AppStrings.Settings.Detail.refreshing.localized(locale: locale)
            : AppStrings.Common.refresh.localized(locale: locale)
    }

    private var usageURL: URL? {
        appModel.usageURL(providerID: currentAccount.providerID, accountID: currentAccount.accountID)
    }

    private var executableLabel: String? {
        switch (currentAccount.providerID, currentAccount.sourceMode) {
        case ("openai-codex", .appServer):
            AppStrings.Settings.Detail.codexExecutable.localized(locale: locale)
        case ("claude-code", .claudeUsageCLI):
            AppStrings.Settings.Detail.claudeExecutable.localized(locale: locale)
        default:
            nil
        }
    }

    private var lastUpdatedText: String {
        guard let snapshot = appModel.snapshot(for: currentAccount) else {
            return AppStrings.Common.noUsageData.localized(locale: locale)
        }
        return AppFormatters.shortDate(snapshot.lastUpdatedAt, locale: locale)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { currentAccount.isEnabled },
            set: {
                appModel.setAccount(
                    currentAccount.providerID,
                    accountID: currentAccount.accountID,
                    enabled: $0
                )
            }
        )
    }

    private var ollamaConnectionTitle: String {
        currentAccount.webDataStoreID == nil
            ? AppStrings.Settings.Detail.connectOllama.localized(locale: locale)
            : AppStrings.Settings.Detail.reconnectOllama.localized(locale: locale)
    }

    private func beginOllamaConnection() {
        guard appModel.ollamaWebPageClient != nil,
              let connectedAccount = appModel.prepareOllamaWebPageConnection(
                  providerID: account.providerID,
                  accountID: account.accountID
              )
        else {
            connectionError = AppStrings.Ollama.saveBeforeConnecting.localized(locale: locale)
            return
        }
        appModel.presentOllamaConnection(for: connectedAccount)
        ApplicationLifecycle.openOllamaConnection(using: openWindow)
    }

    private var connectionErrorBinding: Binding<Bool> {
        Binding(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )
    }
}

private struct SettingsDetailValueRow: View {
    let label: String
    let value: String
    var isTechnical = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(TerminalTheme.detailLabelFont)
                .foregroundStyle(TerminalTheme.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(isTechnical ? TerminalTheme.bodyFont : TerminalTheme.detailValueFont)
                .foregroundStyle(TerminalTheme.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsActionIcon: View {
    let systemName: String
    var verticalOffset: CGFloat = 0

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 20, height: 20)
            .offset(y: verticalOffset)
    }
}

extension View {
    func settingsIconButton(help: String) -> some View {
        buttonStyle(TerminalIconButtonStyle())
            .help(help)
    }
}

struct AccountEditorDraft: Equatable {
    var providerID: String
    var displayName: String
    var isEnabled: Bool
    var sourceMode: ProviderSourceMode
    var executablePath: String

    init(
        providerID: String,
        displayName: String = "",
        isEnabled: Bool = true,
        sourceMode: ProviderSourceMode? = nil,
        executablePath: String = ""
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.sourceMode = ProviderSourceMode.resolvedMode(sourceMode, for: providerID)
        self.executablePath = executablePath
    }

    init(account: ProviderAccount?, defaultProviderID: String) {
        let providerID = account?.providerID ?? defaultProviderID
        self.init(
            providerID: providerID,
            displayName: account?.displayName ?? "",
            isEnabled: account?.isEnabled ?? true,
            sourceMode: account?.sourceMode,
            executablePath: account?.executablePath ?? ""
        )
    }

    var normalizedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ProviderAccount.defaultDisplayName : trimmed
    }

    var normalizedExecutablePath: String? {
        let trimmed = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func hasChanges(comparedTo original: AccountEditorDraft) -> Bool {
        providerID != original.providerID ||
            normalizedDisplayName != original.normalizedDisplayName ||
            isEnabled != original.isEnabled ||
            sourceMode != original.sourceMode ||
            normalizedExecutablePath != original.normalizedExecutablePath
    }
}

struct AccountEditorView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    let account: ProviderAccount?
    @Binding var isDirty: Bool
    let onCancel: () -> Void
    let onCreate: (String) -> Void
    let onSave: () -> Void

    private let initialDraft: AccountEditorDraft
    @State private var draft: AccountEditorDraft
    @State private var helperInstallation: HelperInstallation?
    @State private var helperSetupError: HelperSetupError?
    @State private var isSelectingExecutable = false

    init(
        appModel: AppModel,
        account: ProviderAccount?,
        isDirty: Binding<Bool>,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (String) -> Void,
        onSave: @escaping () -> Void
    ) {
        self.appModel = appModel
        self.account = account
        self._isDirty = isDirty
        self.onCancel = onCancel
        self.onCreate = onCreate
        self.onSave = onSave

        let initialDraft = AccountEditorDraft(
            account: account,
            defaultProviderID: appModel.providerIDs.first(where: appModel.canAddAccount) ?? ""
        )
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    accountFieldset
                    if hasSourceConfiguration {
                        sourceFieldset
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            HStack {
                Spacer()

                Button(AppStrings.Common.cancel.localized(locale: locale), action: onCancel)
                    .buttonStyle(TerminalActionButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button(
                    account == nil
                        ? AppStrings.Common.create.localized(locale: locale)
                        : AppStrings.Common.save.localized(locale: locale),
                    action: save
                )
                    .buttonStyle(TerminalActionButtonStyle(isProminent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        draft.providerID.isEmpty ||
                        (account != nil && !isDirty) ||
                            displayNameConflict != nil ||
                            codexAppServerConflict != nil ||
                            claudeUsageCLIConflict != nil
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .onAppear {
                updateDirtyState()
            }
            .onChange(of: draft) { _, _ in
                updateDirtyState()
            }
            .onChange(of: draft.providerID) { previousProviderID, providerID in
                guard account == nil, previousProviderID != providerID else { return }
                draft.sourceMode = ProviderSourceMode.defaultMode(for: providerID)
            }
            .onChange(of: draft.sourceMode) { _, sourceMode in
                if sourceMode != .claudeStatusLine {
                    helperInstallation = nil
                    helperSetupError = nil
                }
            }
            .fileImporter(
                isPresented: $isSelectingExecutable,
                allowedContentTypes: [.executable],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    draft.executablePath = url.path
                }
            }
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    account == nil
                        ? AppStrings.Settings.Editor.newAccount.resource(locale: locale)
                        : AppStrings.Settings.Editor.editAccount.resource(locale: locale)
                )
                    .font(TerminalTheme.titleFont)
                    .foregroundStyle(TerminalTheme.primary)

                Text(
                    account == nil
                        ? AppStrings.Settings.Editor.newDescription.resource(locale: locale)
                        : AppStrings.Settings.Editor.editDescription.resource(locale: locale)
                )
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var accountFieldset: some View {
        TerminalFieldset(title: AppStrings.Settings.Editor.account.localized(locale: locale)) {
            EmptyView()
        } content: {
            SettingsEditorValueRow(AppStrings.Settings.Editor.provider.localized(locale: locale)) {
                if account == nil {
                    TerminalProviderPicker(
                        selection: $draft.providerID,
                        options: availableProviderIDs.map {
                            TerminalSegmentedOption(
                                value: $0,
                                title: appModel.providerDisplayName(for: $0)
                            )
                        }
                    )
                } else {
                    Text(appModel.providerDisplayName(for: draft.providerID))
                        .font(TerminalTheme.detailValueFont)
                        .foregroundStyle(TerminalTheme.primary)
                }
            }
            .zIndex(1)

            SettingsEditorValueRow(AppStrings.Settings.Editor.accountName.localized(locale: locale)) {
                TerminalTextField(
                    AppStrings.Settings.Editor.accountName.localized(locale: locale),
                    text: $draft.displayName
                )
                .accessibilityIdentifier("settings.account-name")
            }

            if let displayNameConflict {
                Text(displayNameConflict)
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if account == nil {
                SettingsEditorValueRow(AppStrings.Common.enabled.localized(locale: locale)) {
                    Toggle(AppStrings.Common.enabled.resource(locale: locale), isOn: $draft.isEnabled)
                        .labelsHidden()
                        .toggleStyle(TerminalToggleStyle())
                        .accessibilityLabel(AppStrings.Common.enabled.localized(locale: locale))
                }
            }
        }
        .zIndex(1)
    }

    private var sourceFieldset: some View {
        TerminalFieldset(title: AppStrings.Settings.Editor.source.localized(locale: locale)) {
            EmptyView()
        } content: {
            sourceSelector
            sourceDetails
        }
    }

    @ViewBuilder
    private var sourceSelector: some View {
        if draft.providerID == "claude-code" {
            SettingsEditorValueRow(AppStrings.Settings.Editor.mode.localized(locale: locale)) {
                TerminalSegmentedControl(
                    AppStrings.Settings.Editor.claudeSourceAccessibility.localized(locale: locale),
                    selection: $draft.sourceMode,
                    options: [
                        TerminalSegmentedOption(
                            value: .manual,
                            title: AppStrings.Common.manual.localized(locale: locale)
                        ),
                        TerminalSegmentedOption(value: .claudeStatusLine, title: "statusLine"),
                        TerminalSegmentedOption(value: .claudeUsageCLI, title: "/usage CLI")
                    ]
                )
                .labelsHidden()
            }
        } else if let sourceMode = configuredSourceMode {
            SettingsEditorValueRow(AppStrings.Settings.Editor.mode.localized(locale: locale)) {
                Text(sourceMode.localizedDisplayName(locale: locale))
                    .font(TerminalTheme.detailValueFont)
                    .foregroundStyle(TerminalTheme.primary)
            }
        }
    }

    @ViewBuilder
    private var sourceDetails: some View {
        if draft.providerID == "claude-code" {
            switch draft.sourceMode {
            case .manual:
                Text(AppStrings.Settings.Editor.manualSourceDescription.resource(locale: locale))
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            case .claudeStatusLine:
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.Settings.Editor.statusLineTitle.resource(locale: locale))
                        .font(TerminalTheme.emphasizedBodyFont)
                        .foregroundStyle(TerminalTheme.primary)

                    Text(AppStrings.Settings.Editor.statusLineDescription.resource(locale: locale))
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(TerminalTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(AppStrings.Settings.Editor.installHelper.localized(locale: locale), action: installHelper)
                        .buttonStyle(TerminalActionButtonStyle())
                        .disabled(account == nil)

                    if account == nil {
                        Text(AppStrings.Settings.Editor.saveFirst.resource(locale: locale))
                            .font(TerminalTheme.captionFont)
                            .foregroundStyle(TerminalTheme.secondary)
                    }

                    if let helperInstallation {
                        Text(helperInstallation.text(locale: locale))
                            .font(TerminalTheme.captionFont)
                            .foregroundStyle(TerminalTheme.secondary)
                            .textSelection(.enabled)
                    }

                    if let helperSetupError {
                        Text(helperSetupError.text(locale: locale))
                            .font(TerminalTheme.captionFont)
                            .foregroundStyle(TerminalTheme.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
            case .claudeUsageCLI:
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.Settings.Editor.usageCLI.resource(locale: locale))
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(TerminalTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SettingsEditorValueRow(AppStrings.Settings.Editor.claudePath.localized(locale: locale)) {
                        TerminalTextField(
                            AppStrings.Settings.Editor.claudeExecutablePlaceholder.localized(locale: locale),
                            text: $draft.executablePath
                        )
                    }

                    HStack {
                        Text(AppStrings.Settings.Editor.leaveBlankForClaude.resource(locale: locale))
                            .font(TerminalTheme.captionFont)
                            .foregroundStyle(TerminalTheme.secondary)
                        Spacer()
                        Button(AppStrings.Settings.Editor.browse.localized(locale: locale)) {
                            isSelectingExecutable = true
                        }
                        .buttonStyle(TerminalActionButtonStyle())
                    }

                    if let claudeUsageCLIConflict {
                        Text(claudeUsageCLIConflict)
                            .font(TerminalTheme.captionFont)
                            .foregroundStyle(TerminalTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
            case .ollamaWebPage, .appServer, .openRouterAPI, .miniMaxTokenPlan:
                EmptyView()
            }
        } else if draft.providerID == "ollama-cloud" {
            Text(AppStrings.Settings.Editor.ollamaSource.resource(locale: locale))
                .font(TerminalTheme.captionFont)
                .foregroundStyle(TerminalTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        } else if draft.providerID == "openai-codex" {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.Settings.Editor.codexSource.resource(locale: locale))
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SettingsEditorValueRow(AppStrings.Settings.Editor.codexPath.localized(locale: locale)) {
                    TerminalTextField(
                        AppStrings.Settings.Editor.codexExecutablePlaceholder.localized(locale: locale),
                        text: $draft.executablePath
                    )
                }

                HStack {
                    Text(AppStrings.Settings.Editor.leaveBlankForCodex.resource(locale: locale))
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(TerminalTheme.secondary)
                    Spacer()
                    Button(AppStrings.Settings.Editor.browse.localized(locale: locale)) {
                        isSelectingExecutable = true
                    }
                    .buttonStyle(TerminalActionButtonStyle())
                }

                if let codexAppServerConflict {
                    Text(codexAppServerConflict)
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(TerminalTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
        } else if draft.providerID == OpenRouterProviderContract.providerID {
            Text(AppStrings.OpenRouter.sourceDescription.resource(locale: locale))
                .font(TerminalTheme.captionFont)
                .foregroundStyle(TerminalTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func save() {
        if let account {
            guard appModel.updateAccount(
                providerID: account.providerID,
                accountID: account.accountID,
                displayName: draft.normalizedDisplayName,
                sourceMode: persistedSourceMode,
                executablePath: persistedExecutablePath
            ) else { return }
            onSave()
            return
        }

        guard let createdAccount = appModel.addAccount(
            providerID: draft.providerID,
            displayName: draft.normalizedDisplayName,
            isEnabled: draft.isEnabled,
            sourceMode: persistedSourceMode,
            executablePath: persistedExecutablePath
        ) else { return }
        onCreate(createdAccount.id)
    }

    private func updateDirtyState() {
        isDirty = draft.hasChanges(comparedTo: initialDraft)
    }

    private var persistedSourceMode: ProviderSourceMode {
        ProviderSourceMode.resolvedMode(draft.sourceMode, for: draft.providerID)
    }

    private var availableProviderIDs: [String] {
        appModel.providerIDs.filter(appModel.canAddAccount)
    }

    private var hasSourceConfiguration: Bool {
        configuredSourceMode != nil
    }

    private var configuredSourceMode: ProviderSourceMode? {
        switch draft.providerID {
        case "claude-code", "ollama-cloud", "openai-codex":
            ProviderSourceMode.defaultMode(for: draft.providerID)
        default:
            nil
        }
    }

    private var persistedExecutablePath: String? {
        switch draft.providerID {
        case "openai-codex", "claude-code":
            draft.normalizedExecutablePath
        default:
            nil
        }
    }

    private var codexAppServerConflict: String? {
        guard draft.providerID == "openai-codex",
              persistedSourceMode == .appServer,
              appModel.hasCodexAppServerConflict(
                  providerID: draft.providerID,
                  accountID: account?.accountID,
                  sourceMode: persistedSourceMode
              )
        else { return nil }

        return AppStrings.Settings.Editor.appServerConflict.localized(locale: locale)
    }

    private var claudeUsageCLIConflict: String? {
        guard draft.providerID == "claude-code",
              persistedSourceMode == .claudeUsageCLI,
              appModel.hasClaudeUsageCLIConflict(
                  providerID: draft.providerID,
                  accountID: account?.accountID,
                  sourceMode: persistedSourceMode
              )
        else { return nil }

        return AppStrings.Settings.Editor.usageCLIConflict.localized(locale: locale)
    }

    private var displayNameConflict: String? {
        guard appModel.hasDisplayNameConflict(
            accountID: account?.accountID,
            displayName: draft.normalizedDisplayName
        ) else { return nil }
        return AppStrings.Settings.Editor.displayNameConflict.localized(locale: locale)
    }

    private func installHelper() {
        guard let account else {
            helperSetupError = .saveAccountFirst
            return
        }
        do {
            let installer = ClaudeCodeStatusLineInstaller()
            let helperURL = try installer.install()
            draft.sourceMode = .claudeStatusLine
            helperSetupError = nil
            helperInstallation = HelperInstallation(
                path: helperURL.path,
                snippet: installer.settingsSnippet(helperURL: helperURL, accountID: account.accountID)
            )
        } catch {
            helperInstallation = nil
            helperSetupError = .technical(error.localizedDescription)
        }
    }
}

private struct HelperInstallation {
    let path: String
    let snippet: String

    func text(locale: Locale) -> String {
        AppStrings.Settings.Editor.helperInstalled.formatted(locale: locale, path, snippet)
    }
}

private enum HelperSetupError {
    case saveAccountFirst
    case technical(String)

    func text(locale: Locale) -> String {
        switch self {
        case .saveAccountFirst:
            AppStrings.Settings.Editor.saveBeforeHelper.localized(locale: locale)
        case let .technical(message):
            message
        }
    }
}

private struct SettingsEditorValueRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(TerminalTheme.detailLabelFont)
                .foregroundStyle(TerminalTheme.secondary)
                .frame(width: 120, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
