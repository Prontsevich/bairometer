import BairometerCore
import SwiftUI

enum OpenRouterSettingsAccessibilityID {
    static let accountException = "settings.openrouter.account-exception"
    static let addKey = "settings.openrouter.add-key"
    static let addManagement = "settings.openrouter.add-management"
    static let missingManagement = "settings.openrouter.management-missing"

    static func credential(contextID: String) -> String {
        "settings.openrouter.credential.\(contextID)"
    }

    static func actions(contextID: String) -> String {
        "settings.openrouter.actions.\(contextID)"
    }
}

enum OpenRouterSettingsLayout {
    static let actionControlSize = TerminalIconControlLayout.hitTargetSize
    static let headerActionTrailingAdjustment: CGFloat = 6
    static let fieldsetActionControlConfiguration =
        TerminalIconButtonConfiguration.fieldset(
            hitTargetSize: actionControlSize
        )
}

struct OpenRouterSettingsCredentialRowPresentation: Equatable {
    let displayName: String
    let visibleStatusText: String?
    let statusState: OpenRouterCapacityState
    let accessibilityValue: String
    let accessibilityIdentifier: String
    let actionsAccessibilityIdentifier: String

    init(
        credential: ProviderCredentialContext,
        capacityPresentation: OpenRouterCapacityPresentation?,
        diagnostic: CredentialContextDiagnostic?,
        locale: Locale
    ) {
        displayName = credential.slot.role == .management
            ? AppStrings.OpenRouter.managementCredential.localized(locale: locale)
            : credential.context.displayName
                ?? AppStrings.OpenRouter.unnamedKey.localized(locale: locale)
        accessibilityIdentifier = OpenRouterSettingsAccessibilityID.credential(
            contextID: credential.context.contextID
        )
        actionsAccessibilityIdentifier = OpenRouterSettingsAccessibilityID.actions(
            contextID: credential.context.contextID
        )

        let visibleStatus: String?
        let state: OpenRouterCapacityState
        switch credential.slot.lifecycleState {
        case .pendingCreation:
            state = .recoveryRequired
            visibleStatus = state.localizedStatusText(locale: locale)
        case .pendingDeletion:
            state = .deletionPending
            visibleStatus = state.localizedStatusText(locale: locale)
        case .active where !credential.slot.isEnabled:
            state = .disabled
            visibleStatus = state.localizedStatusText(locale: locale)
        case .active:
            if let diagnostic {
                state = .credentialError
                visibleStatus = Self.diagnosticText(
                    diagnostic.code,
                    locale: locale
                )
            } else if credential.slot.role == .ordinary,
                      let credentialPresentation =
                          capacityPresentation?.credentials.first(where: {
                              $0.slotID == credential.slot.slotID
                          }) {
                state = credentialPresentation.state
                switch state {
                case .current, .unlimited:
                    visibleStatus = nil
                case .partial, .stale, .unavailable, .unknown,
                     .credentialError, .disabled, .recoveryRequired,
                     .deletionPending:
                    visibleStatus = credentialPresentation.statusText
                }
            } else if credential.slot.role == .management {
                state = capacityPresentation?.sharedCredits.state ?? .unavailable
                visibleStatus = state == .current
                    ? nil
                    : state.localizedStatusText(locale: locale)
            } else {
                state = .current
                visibleStatus = nil
            }
        }

        statusState = state
        visibleStatusText = visibleStatus
        accessibilityValue = visibleStatus
            ?? AppStrings.Common.enabled.localized(locale: locale)
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
}

struct OpenRouterCredentialsSettingsView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    let account: ProviderAccount

    @State private var editor: OpenRouterCredentialEditorConfiguration?
    @State private var pendingDeletion: ProviderCredentialContext?
    @State private var presentedError: OpenRouterSettingsError?

    var body: some View {
        credentialsFieldset
        .sheet(item: $editor) { configuration in
            OpenRouterCredentialEditorSheet(
                appModel: appModel,
                account: currentAccount,
                configuration: configuration
            )
            .environment(\.locale, locale)
        }
        .alert(
            AppStrings.OpenRouter.deleteCredentialTitle.localized(locale: locale),
            isPresented: deletionConfirmationBinding,
            presenting: pendingDeletion
        ) { credential in
            Button(
                AppStrings.Common.delete.localized(locale: locale),
                role: .destructive
            ) {
                deleteCredential(credential)
            }
            Button(AppStrings.Common.cancel.localized(locale: locale), role: .cancel) {
                pendingDeletion = nil
            }
        } message: { credential in
            Text(
                AppStrings.OpenRouter.deleteCredentialMessage.formatted(
                    locale: locale,
                    displayName(for: credential)
                )
            )
        }
        .alert(
            AppStrings.OpenRouter.errorTitle.localized(locale: locale),
            isPresented: errorBinding
        ) {
            Button(AppStrings.Common.ok.localized(locale: locale), role: .cancel) {}
        } message: {
            Text(errorText)
        }
    }

    private var credentialsFieldset: some View {
        TerminalFieldset(
            title: AppStrings.OpenRouter.credentialsTitle.localized(locale: locale)
        ) {
            Button {
                editor = OpenRouterCredentialEditorConfiguration(
                    mode: .addOrdinary
                )
            } label: {
                SettingsActionIcon(systemName: "plus")
            }
            .buttonStyle(
                TerminalIconButtonStyle(
                    controlConfiguration:
                        OpenRouterSettingsLayout
                        .fieldsetActionControlConfiguration
                )
            )
            .help(
                AppStrings.OpenRouter.addKey.localized(locale: locale)
            )
            .accessibilityLabel(
                AppStrings.OpenRouter.addKey.localized(locale: locale)
            )
            .accessibilityIdentifier(OpenRouterSettingsAccessibilityID.addKey)
            .frame(
                width: OpenRouterSettingsLayout.actionControlSize,
                height: OpenRouterSettingsLayout.actionControlSize
            )
            .padding(
                .trailing,
                OpenRouterSettingsLayout.headerActionTrailingAdjustment
            )
        } content: {
            credentialSectionTitle(
                AppStrings.OpenRouter.apiKeys.localized(locale: locale)
            )

            if ordinaryCredentials.isEmpty {
                Text(AppStrings.OpenRouter.noOrdinaryKeys.resource(locale: locale))
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.secondary)
            } else {
                ForEach(Array(ordinaryCredentials.enumerated()), id: \.element.id) {
                    index,
                    credential in
                    if index > 0 {
                        TerminalRule()
                    }
                    credentialRow(credential)
                }
            }

            TerminalRule()

            managementSectionTitle
            if let managementCredential {
                credentialRow(managementCredential)
            } else {
                Text(AppStrings.OpenRouter.notConfigured.resource(locale: locale))
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        AppStrings.OpenRouter.sharedCredits.localized(locale: locale)
                    )
                    .accessibilityValue(
                        AppStrings.OpenRouter.notConfigured.localized(locale: locale)
                    )
                    .accessibilityIdentifier(
                        OpenRouterSettingsAccessibilityID.missingManagement
                    )
            }
        }
    }

    private func credentialSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(TerminalTheme.detailLabelFont)
            .foregroundStyle(TerminalTheme.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var managementSectionTitle: some View {
        HStack(spacing: 8) {
            credentialSectionTitle(
                AppStrings.OpenRouter.sharedCredits.localized(locale: locale)
            )

            Spacer()

            if managementCredential == nil {
                Button {
                    editor = OpenRouterCredentialEditorConfiguration(
                        mode: .addManagement
                    )
                } label: {
                    SettingsActionIcon(systemName: "plus")
                }
                .settingsIconButton(
                    help: AppStrings.OpenRouter.addManagement.localized(
                        locale: locale
                    )
                )
                .accessibilityLabel(
                    AppStrings.OpenRouter.addManagement.localized(locale: locale)
                )
                .accessibilityIdentifier(
                    OpenRouterSettingsAccessibilityID.addManagement
                )
                .frame(
                    width: OpenRouterSettingsLayout.actionControlSize,
                    height: OpenRouterSettingsLayout.actionControlSize
                )
            }
        }
    }

    private func credentialRow(
        _ credential: ProviderCredentialContext
    ) -> some View {
        let presentation = rowPresentation(for: credential)

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.displayName)
                    .font(TerminalTheme.emphasizedBodyFont)
                    .foregroundStyle(TerminalTheme.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let visibleStatus = presentation.visibleStatusText {
                    Text(visibleStatus)
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(
                            OpenRouterCapacityColors.color(
                                for: presentation.statusState
                            )
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.displayName)
            .accessibilityValue(presentation.accessibilityValue)
            .accessibilityIdentifier(presentation.accessibilityIdentifier)

            Spacer(minLength: 8)

            NativeMenuButton(
                accessibilityLabel:
                    AppStrings.OpenRouter.credentialActions.formatted(
                        locale: locale,
                        presentation.displayName
                    ),
                actions: credentialMenuActions(credential)
            )
            .frame(
                width: OpenRouterSettingsLayout.actionControlSize,
                height: OpenRouterSettingsLayout.actionControlSize
            )
            .help(
                AppStrings.OpenRouter.credentialActions.formatted(
                    locale: locale,
                    presentation.displayName
                )
            )
            .accessibilityLabel(
                AppStrings.OpenRouter.credentialActions.formatted(
                    locale: locale,
                    presentation.displayName
                )
            )
            .accessibilityIdentifier(presentation.actionsAccessibilityIdentifier)
        }
    }

    private func credentialMenuActions(
        _ credential: ProviderCredentialContext
    ) -> [NativeMenuAction] {
        var actions: [NativeMenuAction] = []
        if credential.slot.role == .ordinary {
            actions.append(
                NativeMenuAction(
                    id: "rename",
                    title: AppStrings.OpenRouter.rename.localized(locale: locale),
                    systemImage: "pencil"
                ) {
                    editor = OpenRouterCredentialEditorConfiguration(
                        mode: .rename(
                            contextID: credential.context.contextID,
                            currentName: displayName(for: credential)
                        )
                    )
                }
            )
        }

        actions.append(
            NativeMenuAction(
                id: "replace",
                title: credential.slot.lifecycleState == .pendingCreation
                    ? AppStrings.OpenRouter.recover.localized(locale: locale)
                    : AppStrings.OpenRouter.replace.localized(locale: locale),
                systemImage: "key",
                isEnabled: credential.slot.lifecycleState != .pendingDeletion
            ) {
                editor = OpenRouterCredentialEditorConfiguration(
                    mode: .replace(
                        slotID: credential.slot.slotID,
                        displayName: displayName(for: credential),
                        isManagement: credential.slot.role == .management,
                        isRecovery: credential.slot.lifecycleState
                            == .pendingCreation
                    )
                )
            }
        )
        actions.append(
            NativeMenuAction(
                id: "enabled",
                title: credential.slot.isEnabled
                    ? AppStrings.OpenRouter.disableCredential.localized(
                        locale: locale
                    )
                    : AppStrings.OpenRouter.enableCredential.localized(
                        locale: locale
                    ),
                systemImage: credential.slot.isEnabled
                    ? "pause.circle"
                    : "play.circle",
                isEnabled: credential.slot.lifecycleState == .active
            ) {
                setCredentialEnabled(
                    !credential.slot.isEnabled,
                    credential: credential
                )
            }
        )
        actions.append(.separator(id: "destructive-separator"))
        actions.append(
            NativeMenuAction(
                id: "remove",
                title: AppStrings.OpenRouter.removeCredential.localized(
                    locale: locale
                ),
                systemImage: "trash",
                role: .destructive
            ) {
                pendingDeletion = credential
            }
        )
        return actions
    }

    private var currentAccount: ProviderAccount {
        appModel.account(
            providerID: account.providerID,
            accountID: account.accountID
        ) ?? account
    }

    private var credentialContexts: [ProviderCredentialContext] {
        appModel.openRouterCredentialContexts(for: currentAccount)
    }

    private var ordinaryCredentials: [ProviderCredentialContext] {
        credentialContexts
            .filter { $0.slot.role == .ordinary }
            .sorted {
                displayName(for: $0).localizedCaseInsensitiveCompare(
                    displayName(for: $1)
                ) == .orderedAscending
            }
    }

    private var managementCredential: ProviderCredentialContext? {
        credentialContexts.first { $0.slot.role == .management }
    }

    private var capacityPresentation: OpenRouterCapacityPresentation? {
        appModel.openRouterCapacityPresentation(
            for: currentAccount,
            locale: locale
        )
    }

    private func displayName(
        for credential: ProviderCredentialContext
    ) -> String {
        if credential.slot.role == .management {
            return AppStrings.OpenRouter.managementCredential.localized(
                locale: locale
            )
        }
        return credential.context.displayName
            ?? AppStrings.OpenRouter.unnamedKey.localized(locale: locale)
    }

    private func rowPresentation(
        for credential: ProviderCredentialContext
    ) -> OpenRouterSettingsCredentialRowPresentation {
        OpenRouterSettingsCredentialRowPresentation(
            credential: credential,
            capacityPresentation: capacityPresentation,
            diagnostic: appModel
                .openRouterCredentialDiagnostics(for: currentAccount)
                .first(where: { $0.slotID == credential.slot.slotID }),
            locale: locale
        )
    }

    private func setCredentialEnabled(
        _ isEnabled: Bool,
        credential: ProviderCredentialContext
    ) {
        do {
            try appModel.setOpenRouterCredentialEnabled(
                isEnabled,
                for: currentAccount,
                slotID: credential.slot.slotID
            )
        } catch {
            presentedError = error as? OpenRouterSettingsError
                ?? .storageUnavailable
        }
    }

    private func deleteCredential(_ credential: ProviderCredentialContext) {
        defer { pendingDeletion = nil }
        do {
            try appModel.deleteOpenRouterCredential(
                for: currentAccount,
                slotID: credential.slot.slotID
            )
        } catch {
            presentedError = error as? OpenRouterSettingsError
                ?? .storageUnavailable
        }
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: {
                if !$0 {
                    pendingDeletion = nil
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: {
                if !$0 {
                    presentedError = nil
                }
            }
        )
    }

    private var errorText: String {
        (presentedError ?? .storageUnavailable)
            .localizedDescription(locale: locale)
    }
}

struct OpenRouterCredentialEditorConfiguration: Identifiable {
    enum Mode {
        case addOrdinary
        case addManagement
        case rename(contextID: String, currentName: String)
        case replace(
            slotID: String,
            displayName: String,
            isManagement: Bool,
            isRecovery: Bool
        )
    }

    let id = UUID()
    let mode: Mode
}

struct OpenRouterCredentialEditorPresentation: Equatable {
    let title: String
    let fieldsetTitle: String
    let nameLabel: String?
    let keyLabel: String?
    let keyPlaceholder: String?
    let cancelButtonTitle: String
    let saveButtonTitle: String

    init(
        mode: OpenRouterCredentialEditorConfiguration.Mode,
        locale: Locale
    ) {
        let needsName: Bool
        let needsKey: Bool

        switch mode {
        case .addOrdinary:
            title = AppStrings.OpenRouter.addKeyTitle.localized(locale: locale)
            needsName = true
            needsKey = true
        case .addManagement:
            title = AppStrings.OpenRouter.addManagementTitle.localized(
                locale: locale
            )
            needsName = false
            needsKey = true
        case .rename:
            title = AppStrings.OpenRouter.renameKeyTitle.localized(locale: locale)
            needsName = true
            needsKey = false
        case let .replace(_, _, _, isRecovery):
            title = isRecovery
                ? AppStrings.OpenRouter.recoverCredentialTitle.localized(
                    locale: locale
                )
                : AppStrings.OpenRouter.replaceCredentialTitle.localized(
                    locale: locale
                )
            needsName = false
            needsKey = true
        }

        fieldsetTitle = AppStrings.OpenRouter.keyDetails.localized(locale: locale)
        nameLabel = needsName
            ? AppStrings.OpenRouter.keyName.localized(locale: locale)
            : nil
        keyLabel = needsKey
            ? AppStrings.OpenRouter.credential.localized(locale: locale)
            : nil
        keyPlaceholder = needsKey
            ? AppStrings.OpenRouter.credentialPlaceholder.localized(
                locale: locale
            )
            : nil
        cancelButtonTitle = AppStrings.Common.cancel.localized(locale: locale)
        saveButtonTitle = AppStrings.Common.save.localized(locale: locale)
    }
}

private struct OpenRouterCredentialEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    let account: ProviderAccount
    let configuration: OpenRouterCredentialEditorConfiguration

    @State private var name: String
    @State private var credentialValue = ""
    @State private var presentedError: OpenRouterSettingsError?

    private var presentation: OpenRouterCredentialEditorPresentation {
        OpenRouterCredentialEditorPresentation(
            mode: configuration.mode,
            locale: locale
        )
    }

    init(
        appModel: AppModel,
        account: ProviderAccount,
        configuration: OpenRouterCredentialEditorConfiguration
    ) {
        self.appModel = appModel
        self.account = account
        self.configuration = configuration
        let initialName: String
        switch configuration.mode {
        case let .rename(_, currentName):
            initialName = currentName
        case .addOrdinary, .addManagement, .replace:
            initialName = ""
        }
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(presentation.title)
                .font(TerminalTheme.titleFont)
                .foregroundStyle(TerminalTheme.primary)

            TerminalFieldset(title: presentation.fieldsetTitle) {
                EmptyView()
            } content: {
                if let nameLabel = presentation.nameLabel {
                    SettingsCredentialEditorRow(
                        title: nameLabel
                    ) {
                        TerminalTextField(
                            nameLabel,
                            text: $name
                        )
                        .accessibilityIdentifier("settings.openrouter.key-name")
                    }
                }

                if let keyLabel = presentation.keyLabel,
                   let keyPlaceholder = presentation.keyPlaceholder {
                    SettingsCredentialEditorRow(
                        title: keyLabel
                    ) {
                        TerminalSecureField(
                            keyPlaceholder,
                            text: $credentialValue
                        )
                        .accessibilityIdentifier("settings.openrouter.credential-value")
                    }

                    Text(
                        AppStrings.OpenRouter.saveWithoutReadback.resource(
                            locale: locale
                        )
                    )
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if needsCredential, !isManagement {
                    Text(
                        AppStrings.OpenRouter.ordinaryDisclosure.resource(
                            locale: locale
                        )
                    )
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if isManagement {
                    Text(
                        AppStrings.OpenRouter.managementDisclosure.resource(
                            locale: locale
                        )
                    )
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let presentedError {
                    Text(presentedError.localizedDescription(locale: locale))
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(TerminalTheme.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.openrouter.editor-error")
                }
            }

            HStack {
                Spacer()
                Button(presentation.cancelButtonTitle) {
                    clearSecret()
                    dismiss()
                }
                .buttonStyle(TerminalActionButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(presentation.saveButtonTitle, action: submit)
                    .buttonStyle(TerminalActionButtonStyle(isProminent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        (needsName && name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty)
                            || (needsCredential && credentialValue.isEmpty)
                    )
                    .accessibilityIdentifier("settings.openrouter.editor-save")
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(TerminalTheme.surface)
        .onDisappear(perform: clearSecret)
    }

    private var needsName: Bool {
        switch configuration.mode {
        case .addOrdinary, .rename:
            true
        case .addManagement, .replace:
            false
        }
    }

    private var needsCredential: Bool {
        switch configuration.mode {
        case .addOrdinary, .addManagement, .replace:
            true
        case .rename:
            false
        }
    }

    private var isManagement: Bool {
        if case .addManagement = configuration.mode {
            return true
        }
        if case let .replace(_, _, isManagement, _) = configuration.mode {
            return isManagement
        }
        return false
    }

    private func submit() {
        do {
            switch configuration.mode {
            case .addOrdinary:
                _ = try appModel.createOpenRouterOrdinaryCredential(
                    for: account,
                    displayName: name,
                    credentialValue: credentialValue
                )
            case .addManagement:
                _ = try appModel.createOpenRouterManagementCredential(
                    for: account,
                    credentialValue: credentialValue
                )
            case let .rename(contextID, _):
                try appModel.renameOpenRouterOrdinaryCredential(
                    for: account,
                    contextID: contextID,
                    displayName: name
                )
            case let .replace(slotID, _, _, _):
                try appModel.replaceOpenRouterCredential(
                    for: account,
                    slotID: slotID,
                    credentialValue: credentialValue
                )
            }
            clearSecret()
            dismiss()
        } catch {
            presentedError = error as? OpenRouterSettingsError
                ?? .storageUnavailable
            clearSecret()
        }
    }

    private func clearSecret() {
        credentialValue.removeAll(keepingCapacity: false)
    }
}

private struct SettingsCredentialEditorRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

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

private extension OpenRouterSettingsError {
    func localizedDescription(locale: Locale) -> String {
        switch self {
        case .invalidAccount:
            AppStrings.OpenRouter.invalidAccountError.localized(locale: locale)
        case .invalidName:
            AppStrings.OpenRouter.invalidNameError.localized(locale: locale)
        case .duplicateName:
            AppStrings.OpenRouter.duplicateNameError.localized(locale: locale)
        case .emptyCredential:
            AppStrings.OpenRouter.emptyCredentialError.localized(locale: locale)
        case .managementCredentialExists:
            AppStrings.OpenRouter.managementExistsError.localized(locale: locale)
        case .pendingDeletion:
            AppStrings.OpenRouter.pendingDeletionError.localized(locale: locale)
        case .credentialUnavailable:
            AppStrings.OpenRouter.unavailableCredentialError.localized(locale: locale)
        case .keychainUnavailable:
            AppStrings.OpenRouter.keychainError.localized(locale: locale)
        case .storageUnavailable:
            AppStrings.OpenRouter.storageError.localized(locale: locale)
        }
    }
}
