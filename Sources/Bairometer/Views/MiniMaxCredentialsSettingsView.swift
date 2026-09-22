import BairometerCore
import SwiftUI

enum MiniMaxSettingsAccessibilityID {
    static let boundary = "settings.minimax.boundary"
    static let credential = "settings.minimax.subscription-key"
    static let primaryAction = "settings.minimax.primary-action"
    static let enabledAction = "settings.minimax.enabled-action"
    static let removeAction = "settings.minimax.remove-action"
    static let editorValue = "settings.minimax.credential-value"
    static let editorSave = "settings.minimax.editor-save"
    static let editorError = "settings.minimax.editor-error"
}

struct MiniMaxCredentialRowPresentation: Equatable {
    let stateText: String
    let primaryActionTitle: String
    let canChangeEnabledState: Bool
    let canRemove: Bool
    let accessibilityIdentifier: String

    init(
        credential: ProviderCredentialContext?,
        diagnostic: CredentialContextDiagnostic?,
        locale: Locale
    ) {
        accessibilityIdentifier = MiniMaxSettingsAccessibilityID.credential
        guard let credential else {
            stateText = AppStrings.MiniMax.notAdded.localized(locale: locale)
            primaryActionTitle = AppStrings.MiniMax.addKey.localized(
                locale: locale
            )
            canChangeEnabledState = false
            canRemove = false
            return
        }

        switch credential.slot.lifecycleState {
        case .pendingCreation:
            stateText = AppStrings.MiniMax.recoveryRequired.localized(
                locale: locale
            )
            primaryActionTitle = AppStrings.MiniMax.recoverKey.localized(
                locale: locale
            )
            canChangeEnabledState = false
            canRemove = true
        case .pendingDeletion:
            stateText = AppStrings.MiniMax.deletionPending.localized(
                locale: locale
            )
            primaryActionTitle = AppStrings.MiniMax.replaceKey.localized(
                locale: locale
            )
            canChangeEnabledState = false
            canRemove = true
        case .active where !credential.slot.isEnabled:
            stateText = AppStrings.MiniMax.storedDisabled.localized(
                locale: locale
            )
            primaryActionTitle = AppStrings.MiniMax.replaceKey.localized(
                locale: locale
            )
            canChangeEnabledState = true
            canRemove = true
        case .active:
            stateText = Self.activeStateText(
                diagnostic: diagnostic,
                locale: locale
            )
            primaryActionTitle = AppStrings.MiniMax.replaceKey.localized(
                locale: locale
            )
            canChangeEnabledState = true
            canRemove = true
        }
    }

    private static func activeStateText(
        diagnostic: CredentialContextDiagnostic?,
        locale: Locale
    ) -> String {
        guard let diagnostic else {
            return AppStrings.MiniMax.storedEnabled.localized(locale: locale)
        }
        return switch diagnostic.code {
        case .authentication:
            AppStrings.MiniMax.authenticationFailed.localized(locale: locale)
        case .insufficientPrivilege:
            AppStrings.MiniMax.subscriptionUnavailableCredential.localized(
                locale: locale
            )
        case .throttled:
            AppStrings.MiniMax.throttled.localized(locale: locale)
        case .transientFailure:
            AppStrings.MiniMax.temporaryFailure.localized(locale: locale)
        case .credentialDisabled:
            AppStrings.MiniMax.storedDisabled.localized(locale: locale)
        case .credentialMissing:
            AppStrings.MiniMax.unavailable.localized(locale: locale)
        }
    }
}

struct MiniMaxCredentialsSettingsView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    let account: ProviderAccount

    @State private var editorMode: MiniMaxCredentialEditorMode?
    @State private var isShowingRemovalConfirmation = false
    @State private var presentedError: MiniMaxSettingsError?

    var body: some View {
        TerminalFieldset(
            title: AppStrings.MiniMax.credentialsTitle.localized(locale: locale)
        ) {
            EmptyView()
        } content: {
            Text(AppStrings.MiniMax.boundaryDescription.localized(locale: locale))
                .font(TerminalTheme.captionFont)
                .foregroundStyle(TerminalTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    AppStrings.MiniMax.boundaryLabel.localized(locale: locale)
                )
                .accessibilityValue(
                    AppStrings.MiniMax.boundaryDescription.localized(
                        locale: locale
                    )
                )
                .accessibilityIdentifier(MiniMaxSettingsAccessibilityID.boundary)

            TerminalRule()

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(AppStrings.MiniMax.keyLabel.localized(locale: locale))
                    .font(TerminalTheme.detailLabelFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .frame(width: 120, alignment: .leading)

                Text(rowPresentation.stateText)
                    .font(TerminalTheme.emphasizedBodyFont)
                    .foregroundStyle(TerminalTheme.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        AppStrings.MiniMax.keyLabel.localized(locale: locale)
                    )
                    .accessibilityValue(rowPresentation.stateText)
                    .accessibilityIdentifier(
                        rowPresentation.accessibilityIdentifier
                    )
            }

            HStack(spacing: 8) {
                Button(rowPresentation.primaryActionTitle) {
                    editorMode = resolvedEditorMode
                }
                .buttonStyle(TerminalActionButtonStyle(isProminent: true))
                .disabled(credential?.slot.lifecycleState == .pendingDeletion)
                .accessibilityIdentifier(
                    MiniMaxSettingsAccessibilityID.primaryAction
                )

                if let credential {
                    Button(
                        credential.slot.isEnabled
                            ? AppStrings.MiniMax.disableKey.localized(
                                locale: locale
                            )
                            : AppStrings.MiniMax.enableKey.localized(
                                locale: locale
                            )
                    ) {
                        setCredentialEnabled(!credential.slot.isEnabled)
                    }
                    .buttonStyle(TerminalActionButtonStyle())
                    .disabled(!rowPresentation.canChangeEnabledState)
                    .accessibilityIdentifier(
                        MiniMaxSettingsAccessibilityID.enabledAction
                    )

                    Button(
                        AppStrings.MiniMax.removeKey.localized(locale: locale),
                        role: .destructive
                    ) {
                        isShowingRemovalConfirmation = true
                    }
                    .buttonStyle(TerminalActionButtonStyle())
                    .disabled(!rowPresentation.canRemove)
                    .accessibilityIdentifier(
                        MiniMaxSettingsAccessibilityID.removeAction
                    )
                }
            }
        }
        .task(id: currentAccount.id) {
            appModel.reloadMiniMaxPresentationData(for: currentAccount)
        }
        .sheet(item: $editorMode) { mode in
            MiniMaxCredentialEditorSheet(
                appModel: appModel,
                account: currentAccount,
                mode: mode
            )
            .environment(\.locale, locale)
        }
        .alert(
            AppStrings.MiniMax.removeTitle.localized(locale: locale),
            isPresented: $isShowingRemovalConfirmation
        ) {
            Button(
                AppStrings.MiniMax.removeKey.localized(locale: locale),
                role: .destructive,
                action: deleteCredential
            )
            Button(AppStrings.Common.cancel.localized(locale: locale), role: .cancel) {}
        } message: {
            Text(AppStrings.MiniMax.removeMessage.localized(locale: locale))
        }
        .alert(
            AppStrings.MiniMax.errorTitle.localized(locale: locale),
            isPresented: errorBinding
        ) {
            Button(AppStrings.Common.ok.localized(locale: locale), role: .cancel) {}
        } message: {
            Text(localizedError)
        }
    }

    private var currentAccount: ProviderAccount {
        appModel.account(
            providerID: account.providerID,
            accountID: account.accountID
        ) ?? account
    }

    private var credential: ProviderCredentialContext? {
        let credentials = appModel.miniMaxCredentialContexts(
            for: currentAccount
        )
        return credentials.count == 1 ? credentials.first : nil
    }

    private var rowPresentation: MiniMaxCredentialRowPresentation {
        MiniMaxCredentialRowPresentation(
            credential: credential,
            diagnostic: credential.flatMap { credential in
                appModel.miniMaxCredentialDiagnostics(for: currentAccount)
                    .first(where: { $0.slotID == credential.slot.slotID })
            },
            locale: locale
        )
    }

    private var resolvedEditorMode: MiniMaxCredentialEditorMode {
        guard let credential else { return .add }
        return credential.slot.lifecycleState == .pendingCreation
            ? .recover
            : .replace
    }

    private func setCredentialEnabled(_ isEnabled: Bool) {
        do {
            try appModel.setMiniMaxSubscriptionKeyEnabled(
                isEnabled,
                for: currentAccount
            )
        } catch {
            presentedError = error as? MiniMaxSettingsError
                ?? .storageUnavailable
        }
    }

    private func deleteCredential() {
        do {
            try appModel.deleteMiniMaxSubscriptionKey(for: currentAccount)
        } catch {
            presentedError = error as? MiniMaxSettingsError
                ?? .storageUnavailable
        }
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

    private var localizedError: String {
        (presentedError ?? .storageUnavailable)
            .localizedDescription(locale: locale)
    }
}

enum MiniMaxCredentialEditorMode: String, Identifiable {
    case add
    case replace
    case recover

    var id: String { rawValue }
}

struct MiniMaxCredentialEditorPresentation: Equatable {
    let title: String
    let fieldsetTitle: String
    let keyLabel: String
    let keyPlaceholder: String
    let cancelButtonTitle: String
    let saveButtonTitle: String

    init(mode: MiniMaxCredentialEditorMode, locale: Locale) {
        title = switch mode {
        case .add:
            AppStrings.MiniMax.addTitle.localized(locale: locale)
        case .replace:
            AppStrings.MiniMax.replaceTitle.localized(locale: locale)
        case .recover:
            AppStrings.MiniMax.recoverTitle.localized(locale: locale)
        }
        fieldsetTitle = AppStrings.MiniMax.keyDetails.localized(locale: locale)
        keyLabel = AppStrings.MiniMax.keyLabel.localized(locale: locale)
        keyPlaceholder = AppStrings.MiniMax.keyPlaceholder.localized(locale: locale)
        cancelButtonTitle = AppStrings.Common.cancel.localized(locale: locale)
        saveButtonTitle = AppStrings.Common.save.localized(locale: locale)
    }
}

private struct MiniMaxCredentialEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    let account: ProviderAccount
    let mode: MiniMaxCredentialEditorMode

    @State private var credentialValue = ""
    @State private var presentedError: MiniMaxSettingsError?

    private var presentation: MiniMaxCredentialEditorPresentation {
        MiniMaxCredentialEditorPresentation(mode: mode, locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(presentation.title)
                .font(TerminalTheme.titleFont)
                .foregroundStyle(TerminalTheme.primary)

            TerminalFieldset(title: presentation.fieldsetTitle) {
                EmptyView()
            } content: {
                HStack(alignment: .center, spacing: 16) {
                    Text(presentation.keyLabel)
                        .font(TerminalTheme.detailLabelFont)
                        .foregroundStyle(TerminalTheme.secondary)
                        .frame(width: 120, alignment: .leading)

                    TerminalSecureField(
                        presentation.keyPlaceholder,
                        text: $credentialValue
                    )
                    .accessibilityIdentifier(
                        MiniMaxSettingsAccessibilityID.editorValue
                    )
                }

                Text(
                    AppStrings.MiniMax.storageDisclosure.localized(
                        locale: locale
                    )
                )
                .font(TerminalTheme.captionFont)
                .foregroundStyle(TerminalTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if let presentedError {
                    Text(presentedError.localizedDescription(locale: locale))
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(TerminalTheme.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(
                            MiniMaxSettingsAccessibilityID.editorError
                        )
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
                    .disabled(credentialValue.isEmpty)
                    .accessibilityIdentifier(
                        MiniMaxSettingsAccessibilityID.editorSave
                    )
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(TerminalTheme.surface)
        .focusSection()
        .onDisappear(perform: clearSecret)
    }

    private func submit() {
        do {
            switch mode {
            case .add:
                _ = try appModel.createMiniMaxSubscriptionKey(
                    for: account,
                    credentialValue: credentialValue
                )
            case .replace, .recover:
                try appModel.replaceMiniMaxSubscriptionKey(
                    for: account,
                    credentialValue: credentialValue
                )
            }
            clearSecret()
            dismiss()
        } catch {
            presentedError = error as? MiniMaxSettingsError
                ?? .storageUnavailable
            clearSecret()
        }
    }

    private func clearSecret() {
        credentialValue.removeAll(keepingCapacity: false)
    }
}

private extension MiniMaxSettingsError {
    func localizedDescription(locale: Locale) -> String {
        switch self {
        case .invalidAccount:
            AppStrings.MiniMax.invalidAccountError.localized(locale: locale)
        case .credentialExists:
            AppStrings.MiniMax.credentialExistsError.localized(locale: locale)
        case .emptyCredential:
            AppStrings.MiniMax.emptyCredentialError.localized(locale: locale)
        case .pendingDeletion:
            AppStrings.MiniMax.pendingDeletionError.localized(locale: locale)
        case .credentialUnavailable:
            AppStrings.MiniMax.unavailableCredentialError.localized(locale: locale)
        case .keychainUnavailable:
            AppStrings.MiniMax.keychainError.localized(locale: locale)
        case .storageUnavailable:
            AppStrings.MiniMax.storageError.localized(locale: locale)
        }
    }
}
