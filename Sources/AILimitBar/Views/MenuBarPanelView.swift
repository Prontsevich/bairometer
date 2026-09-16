@preconcurrency import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    let onOpenSettings: () -> Void
    let onOpenAbout: () -> Void
    let onOpenOllamaConnection: () -> Void
    let onCloseDashboard: () -> Void
    @ObservedObject var panelPresentation: MenuBarPanelPresentationState
    @AppStorage(DashboardHeightPreset.storageKey)
    private var dashboardHeightPresetRawValue = DashboardHeightPreset.standard.rawValue
    @State private var focusedLimitWindow: DashboardLimitWindowFocusTarget?
    @State private var showsKeyboardFocus = false

    private let contentInset: CGFloat = 12
    private let accountPanelSpacing: CGFloat = 14
    private let legendClearance: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let warning = appModel.localizedStorageWarning(locale: locale) {
                Text(warning)
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appModel.hasEnabledAccounts {
                dashboard
            } else {
                emptyAccountsPanel
            }

            TerminalRule()

            footerControls
        }
        .padding(contentInset)
        .frame(width: 390)
        .background(TerminalTheme.surface)
        .background {
            MenuBarKeyboardMonitor(
                handleEvent: handleLimitWindowKeyboardEvent,
                handleCancel: handleLimitWindowEscape,
                panelPresentation: panelPresentation
            )
        }
        .onAppear {
            AppTelemetry.lifecycle.info("Menu bar panel appeared")
            clearLimitWindowFocus()
            if appModel.enabledSnapshots.isEmpty {
                appModel.refresh()
            }
        }
        .onChange(of: panelPresentation.isVisible) { _, isVisible in
            guard !isVisible else { return }
            clearLimitWindowFocus()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(">_ Bairometer")
                .font(TerminalTheme.titleFont)
                .foregroundStyle(TerminalTheme.primary)

            Spacer()

            Button {
                appModel.refresh()
            } label: {
                Group {
                    if appModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(TerminalTheme.secondary)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 14, height: 14)
            }
            .buttonStyle(TerminalIconButtonStyle())
            .disabled(!canRefreshAll)
            .help(refreshAllHelp)
            .accessibilityLabel(AppStrings.MenuBar.refreshAllAccounts.resource(locale: locale))
            .accessibilityValue(
                appModel.isRefreshing
                    ? AppStrings.MenuBar.refreshing.localized(locale: locale)
                    : AppStrings.MenuBar.ready.localized(locale: locale)
            )
            .accessibilityIdentifier("dashboard.refresh-all")
        }
    }

    private var emptyAccountsPanel: some View {
        TerminalFieldset(title: AppStrings.MenuBar.accountsTitle.localized(locale: locale)) {
            EmptyView()
        } content: {
            Text(AppStrings.MenuBar.noEnabledAccounts.resource(locale: locale))
                .font(TerminalTheme.emphasizedBodyFont)
                .foregroundStyle(TerminalTheme.primary)
            Text(AppStrings.MenuBar.createAccountInSettings.resource(locale: locale))
                .font(TerminalTheme.captionFont)
                .foregroundStyle(TerminalTheme.secondary)
        }
    }

    private var footerControls: some View {
        HStack(spacing: 8) {
            Button {
                onOpenSettings()
            } label: {
                Text(AppStrings.MenuBar.settings.resource(locale: locale))
            }
            .buttonStyle(TerminalTextButtonStyle())
            .accessibilityIdentifier("dashboard.open-settings")

            Button {
                onOpenAbout()
            } label: {
                Text(AppStrings.MenuBar.about.resource(locale: locale))
            }
            .buttonStyle(TerminalTextButtonStyle())
            .help(AppStrings.MenuBar.aboutAILimitbar.localized(locale: locale))
            .accessibilityLabel(AppStrings.MenuBar.aboutAILimitbar.resource(locale: locale))

            Spacer()

            Button(role: .destructive) {
                ApplicationLifecycle.terminate()
            } label: {
                Text(AppStrings.MenuBar.quit.resource(locale: locale))
            }
            .buttonStyle(TerminalTextButtonStyle())
        }
    }

    private var dashboard: some View {
        let rows = appModel.enabledAccountRows
        return ScrollView {
            accountRows(rows)
                .padding(.top, legendClearance)
                .padding(.trailing, contentInset)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.visible)
        .padding(.trailing, -contentInset)
        .frame(height: dashboardHeightPreset.viewportHeight)
    }

    private func accountRows(_ rows: [AccountSnapshotRow]) -> some View {
        VStack(alignment: .leading, spacing: accountPanelSpacing) {
            ForEach(rows) { row in
                DashboardAccountRowView(
                    appModel: appModel,
                    row: row,
                    isStale: row.snapshot.map { appModel.isSnapshotStale($0) } ?? false,
                    onOpenOllamaConnection: onOpenOllamaConnection,
                    focusedLimitWindow: $focusedLimitWindow,
                    showsKeyboardFocus: $showsKeyboardFocus,
                    onClearLimitWindowFocus: clearLimitWindowFocus
                )
            }
        }
    }

    private var dashboardHeightPreset: DashboardHeightPreset {
        DashboardHeightPreset(rawValue: dashboardHeightPresetRawValue)
            ?? .standard
    }

    private var canRefreshAll: Bool {
        appModel.hasEnabledAccounts && !appModel.isRefreshing && !appModel.hasActiveProviderRefresh
    }

    private var refreshAllHelp: String {
        if !appModel.hasEnabledAccounts {
            return AppStrings.MenuBar.noEnabledAccountsToRefresh.localized(locale: locale)
        }
        if appModel.isRefreshing {
            return AppStrings.MenuBar.refreshingAllAccounts.localized(locale: locale)
        }
        if appModel.hasActiveProviderRefresh {
            return AppStrings.MenuBar.waitForCurrentRefresh.localized(locale: locale)
        }
        return AppStrings.MenuBar.refreshAllAccounts.localized(locale: locale)
    }

    private func clearLimitWindowFocus() {
        focusedLimitWindow = nil
        showsKeyboardFocus = false
    }

    private func moveLimitWindowFocus(backward: Bool) {
        let targets = limitWindowFocusTargets
        guard !targets.isEmpty else { return }

        let target: DashboardLimitWindowFocusTarget
        if showsKeyboardFocus,
           let currentIndex = focusedLimitWindow.flatMap({ targets.firstIndex(of: $0) }) {
            let nextIndex = backward
                ? (currentIndex - 1 + targets.count) % targets.count
                : (currentIndex + 1) % targets.count
            target = targets[nextIndex]
        } else {
            target = backward ? targets[targets.count - 1] : targets[0]
        }

        showsKeyboardFocus = true
        focusedLimitWindow = target
    }

    private func handleLimitWindowKeyboardEvent(_ event: NSEvent) -> Bool {
        guard panelPresentation.isVisible else { return false }

        switch event.keyCode {
        case 48:
            moveLimitWindowFocus(backward: event.modifierFlags.contains(.shift))
            return !limitWindowFocusTargets.isEmpty

        case 53:
            return handleLimitWindowEscape()

        case 36, 49, 76:
            guard let target = focusedLimitWindow else { return false }
            guard let row = appModel.enabledAccountRows.first(where: {
                $0.account.providerID == target.providerID && $0.account.accountID == target.accountID
            }) else {
                clearLimitWindowFocus()
                return true
            }
            appModel.toggleUsageDisplayMode(for: row.account, windowID: target.windowID)
            return true

        default:
            return false
        }
    }

    private func handleLimitWindowEscape() -> Bool {
        guard panelPresentation.isVisible else { return false }

        if focusedLimitWindow != nil {
            clearLimitWindowFocus()
            AppTelemetry.menuBar.info("Dashboard Escape cleared usage-meter focus")
        } else {
            AppTelemetry.menuBar.info("Dashboard Escape closed neutral panel")
            onCloseDashboard()
        }
        return true
    }

    private var limitWindowFocusTargets: [DashboardLimitWindowFocusTarget] {
        appModel.enabledAccountRows.flatMap { row in
            (row.snapshot?.limitWindows ?? []).map {
                DashboardLimitWindowFocusTarget(
                    providerID: row.account.providerID,
                    accountID: row.account.accountID,
                    windowID: $0.id
                )
            }
        }
    }
}

private struct MenuBarKeyboardMonitor: NSViewRepresentable {
    let handleEvent: (NSEvent) -> Bool
    let handleCancel: () -> Bool
    @ObservedObject var panelPresentation: MenuBarPanelPresentationState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.handleEvent = handleEvent
        context.coordinator.handleCancel = handleCancel
        context.coordinator.installMonitorIfNeeded()
        let responderView = MenuBarKeyboardResponderView()
        responderView.handleEvent = handleEvent
        responderView.handleCancel = handleCancel
        panelPresentation.keyboardResponder = responderView
        return responderView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handleEvent = handleEvent
        context.coordinator.handleCancel = handleCancel
        if let responderView = nsView as? MenuBarKeyboardResponderView {
            responderView.handleEvent = handleEvent
            responderView.handleCancel = handleCancel
            panelPresentation.keyboardResponder = responderView
        }
        context.coordinator.installMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var handleEvent: ((NSEvent) -> Bool)?
        var handleCancel: (() -> Bool)?
        private var localMonitor: Any?

        deinit {
            removeMonitor()
        }

        func installMonitorIfNeeded() {
            guard localMonitor == nil else { return }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard self?.handleEvent?(event) == true else { return event }
                return nil
            }
        }

        func removeMonitor() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
        }
    }
}

private final class MenuBarKeyboardResponderView: NSView {
    var handleEvent: ((NSEvent) -> Bool)?
    var handleCancel: (() -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard handleEvent?(event) != true else { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        AppTelemetry.menuBar.info("Dashboard responder received cancel operation")
        guard handleCancel?() != true else { return }
        super.cancelOperation(sender)
    }
}
