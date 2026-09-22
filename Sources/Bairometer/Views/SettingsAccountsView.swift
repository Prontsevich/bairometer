import BairometerCore
import SwiftUI

struct AccountsSettingsPane: View {
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    @Binding var editorSession: AccountEditorSession
    let onRequestAccountSelection: (String?) -> Void

    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                accountList
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

                detail
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: accountIDs) { _, _ in
            reconcileSelection()
        }
        .alert(AppStrings.Settings.Accounts.deleteTitle.localized(locale: locale), isPresented: $isShowingDeleteConfirmation) {
            Button(
                AppStrings.Common.delete.localized(locale: locale),
                role: .destructive,
                action: deleteSelectedAccount
            )
            Button(AppStrings.Common.cancel.localized(locale: locale), role: .cancel) {}
        } message: {
            Text(
                deleteMessage.formatted(
                    locale: locale,
                    selectedAccount?.displayName
                        ?? AppStrings.Common.selectedAccount.localized(locale: locale)
                )
            )
        }
    }

    private var deleteMessage: AppString {
        selectedAccount?.providerID == OpenRouterProviderContract.providerID
            ? AppStrings.Settings.Accounts.deleteOpenRouterMessage
            : AppStrings.Settings.Accounts.deleteMessage
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(AppStrings.Settings.Accounts.title.resource(locale: locale))
                    .font(TerminalTheme.legendFont)
                    .foregroundStyle(TerminalTheme.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            List {
                ForEach(appModel.providerAccounts) { account in
                    Button {
                        onRequestAccountSelection(account.id)
                    } label: {
                        AccountListRow(
                            account: account,
                            providerName: appModel.providerDisplayName(for: account.providerID),
                            isSelected: editorSession.selectedAccountID == account.id
                        )
                    }
                    .buttonStyle(TerminalListRowButtonStyle(
                        isSelected: editorSession.selectedAccountID == account.id
                    ))
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        Button(AppStrings.Settings.Accounts.moveUp.localized(locale: locale)) {
                            appModel.moveAccountUp(providerID: account.providerID, accountID: account.accountID)
                        }
                        .disabled(editorSession.isDirty || !appModel.canMoveAccountUp(
                            providerID: account.providerID,
                            accountID: account.accountID
                        ))

                        Button(AppStrings.Settings.Accounts.moveDown.localized(locale: locale)) {
                            appModel.moveAccountDown(providerID: account.providerID, accountID: account.accountID)
                        }
                        .disabled(editorSession.isDirty || !appModel.canMoveAccountDown(
                            providerID: account.providerID,
                            accountID: account.accountID
                        ))
                    }
                }
                .onMove { offsets, destination in
                    guard !editorSession.isDirty else { return }
                    appModel.moveAccounts(fromOffsets: offsets, toOffset: destination)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .tint(TerminalTheme.primary)

            Divider()

            HStack(spacing: 10) {
                Button(action: beginAdding) {
                    SettingsActionIcon(systemName: "plus")
                }
                .settingsIconButton(help: AppStrings.Settings.Accounts.addAccount.localized(locale: locale))
                .accessibilityLabel(AppStrings.Settings.Accounts.addAccount.localized(locale: locale))
                .disabled(editorSession.isDirty || !hasAvailableProvider)

                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    SettingsActionIcon(systemName: "minus")
                }
                .settingsIconButton(
                    help: AppStrings.Settings.Accounts.deleteSelectedAccount.localized(locale: locale)
                )
                .accessibilityLabel(
                    AppStrings.Settings.Accounts.deleteSelectedAccount.localized(locale: locale)
                )
                .disabled(selectedAccount == nil || editorSession.isDirty)

                Spacer()

                Button {
                    appModel.refresh()
                } label: {
                    SettingsActionIcon(systemName: "arrow.clockwise")
                }
                .settingsIconButton(
                    help: appModel.isRefreshing
                        ? AppStrings.MenuBar.refreshingAllAccounts.localized(locale: locale)
                        : AppStrings.MenuBar.refreshAllAccounts.localized(locale: locale)
                )
                .accessibilityLabel(
                    appModel.isRefreshing
                        ? AppStrings.MenuBar.refreshingAllAccounts.localized(locale: locale)
                        : AppStrings.MenuBar.refreshAllAccounts.localized(locale: locale)
                )
                .disabled(appModel.isRefreshing || appModel.hasActiveProviderRefresh || !appModel.hasEnabledAccounts)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if editorSession.mode == .creating {
            AccountEditorView(
                appModel: appModel,
                account: nil,
                isDirty: $editorSession.isDirty,
                onCancel: discardEditor,
                onCreate: { accountID in
                    editorSession.selectedAccountID = accountID
                    finishEditor()
                },
                onSave: { finishEditor() }
            )
            .id("new-account")
        } else if let account = selectedAccount {
            if editorSession.mode == .editing {
                AccountEditorView(
                    appModel: appModel,
                    account: account,
                    isDirty: $editorSession.isDirty,
                    onCancel: discardEditor,
                    onCreate: { _ in },
                    onSave: { finishEditor() }
                )
                .id(account.id)
            } else {
                AccountDetailView(
                    appModel: appModel,
                    account: account,
                    onEdit: beginEditing
                )
            }
        } else {
            ContentUnavailableView(
                AppStrings.Settings.Accounts.noAccountSelected.localized(locale: locale),
                systemImage: "person.crop.square",
                description: Text(AppStrings.Settings.Accounts.selectOrAdd.resource(locale: locale))
            )
        }
    }

    private var selectedAccount: ProviderAccount? {
        guard let selectedAccountID = editorSession.selectedAccountID else { return nil }
        return appModel.providerAccounts.first { $0.id == selectedAccountID }
    }

    private var accountIDs: [String] {
        appModel.providerAccounts.map(\.id)
    }

    private var hasAvailableProvider: Bool {
        appModel.providerIDs.contains(where: appModel.canAddAccount)
    }

    private func beginAdding() {
        guard !editorSession.isDirty, hasAvailableProvider else { return }
        editorSession.selectedAccountID = nil
        editorSession.mode = .creating
        editorSession.isDirty = false
    }

    private func beginEditing() {
        guard selectedAccount != nil else { return }
        editorSession.mode = .editing
        editorSession.isDirty = false
    }

    private func requestAccountSelection(_ accountID: String?) {
        guard accountID != editorSession.selectedAccountID else { return }
        onRequestAccountSelection(accountID)
    }

    private func finishEditor() {
        editorSession.discardEditor()
        reconcileSelection()
    }

    private func discardEditor() {
        editorSession.discardEditor()
        if editorSession.selectedAccountID == nil {
            editorSession.selectedAccountID = appModel.providerAccounts.first?.id
        }
    }

    private func deleteSelectedAccount() {
        guard let account = selectedAccount,
              let index = appModel.providerAccounts.firstIndex(where: { $0.id == account.id })
        else { return }

        let nextSelection = appModel.providerAccounts.dropFirst(index + 1).first?.id
            ?? appModel.providerAccounts.prefix(index).last?.id
        appModel.deleteAccount(providerID: account.providerID, accountID: account.accountID)
        editorSession.selectedAccountID = nextSelection
        reconcileSelection()
    }

    private func reconcileSelection() {
        guard editorSession.mode != .creating else { return }
        guard let selectedAccountID = editorSession.selectedAccountID,
              appModel.providerAccounts.contains(where: { $0.id == selectedAccountID })
        else {
            editorSession.selectedAccountID = appModel.providerAccounts.first?.id
            return
        }
    }
}

private struct AccountListRow: View {
    let account: ProviderAccount
    let providerName: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.square")
                .foregroundStyle(TerminalTheme.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(TerminalTheme.emphasizedBodyFont)
                    .foregroundStyle(TerminalTheme.primary)
                    .lineLimit(1)

                Text(providerName)
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(isSelected ? TerminalTheme.primary.opacity(0.82) : TerminalTheme.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
