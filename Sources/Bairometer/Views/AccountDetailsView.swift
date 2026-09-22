import BairometerCore
import AppKit
import SwiftUI

struct AccountDetailsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    let row: AccountSnapshotRow
    let onOpenOllamaConnection: (() -> Void)?

    @State private var connectionError: String?

    private var dashboardPresentation: DashboardAccountPresentation {
        DashboardAccountPresentation(
            row: row,
            isStale: row.snapshot.map { appModel.isSnapshotStale($0) } ?? false,
            isGlobalRefresh: appModel.isRefreshing,
            locale: locale
        )
    }

    private var miniMaxPresentation: MiniMaxCapacityPresentation? {
        MiniMaxCapacityPresentation(
            account: currentAccount,
            snapshot: appModel.nativeCapacitySnapshot(for: currentAccount),
            displayModeForWindow: {
                appModel.usageDisplayMode(for: currentAccount, windowID: $0)
            },
            locale: locale
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                inspector
                    .padding(12)
                    .background {
                        AccountDetailsScrollViewConfigurator()
                    }
            }
            .scrollBounceBehavior(.basedOnSize)

            TerminalRule()

            actionBar
                .padding(12)
        }
        .frame(maxHeight: 520)
        .background(TerminalTheme.surface)
        .alert(AppStrings.Ollama.connectionTitle.localized(locale: locale), isPresented: connectionErrorBinding) {
            Button(AppStrings.Common.ok.localized(locale: locale), role: .cancel) {}
        } message: {
            Text(connectionError ?? AppStrings.Ollama.unavailable.localized(locale: locale))
        }
    }

    private var inspector: some View {
        TerminalFieldset(
            title: AppStrings.AccountDetails.title.formatted(locale: locale, row.account.displayName)
        ) {
            EmptyView()
        } content: {
            inspectorRows
        }
    }

    @ViewBuilder
    private var inspectorRows: some View {
        let diagnostics = appModel.accountDiagnostics(for: currentAccount)

        TerminalInspectorRow(
            label: AppStrings.AccountDetails.refresh.localized(locale: locale),
            value: refreshText,
            valueColor: refreshStatusColor
        )
        TerminalRule()

        TerminalInspectorRow(
            label: AppStrings.AccountDetails.sourceState.localized(locale: locale),
            value: sourceStateMessage,
            valueColor: sourceAvailabilityColor(diagnostics.availability)
        )

        if diagnostics.availability == .failed,
           let lastSuccessfulRefreshAt = diagnostics.lastSuccessfulRefreshAt {
            TerminalRule()
            TerminalInspectorRow(
                label: AppStrings.AccountDetails.lastSuccess.localized(locale: locale),
                value: preciseDate(lastSuccessfulRefreshAt),
                valueColor: TerminalTheme.secondary
            )
        }
        TerminalRule()

        if let openRouterPresentation = appModel.openRouterCapacityPresentation(
            for: currentAccount,
            locale: locale
        ) {
            TerminalInspectorRow(
                label: AppStrings.AccountDetails.source.localized(locale: locale),
                value: currentAccount.sourceMode.localizedDisplayName(locale: locale),
                valueColor: TerminalTheme.secondary
            )
            TerminalRule()
            OpenRouterCapacityDetailsContent(
                presentation: openRouterPresentation
            )
        } else if let miniMaxPresentation {
            TerminalInspectorRow(
                label: AppStrings.AccountDetails.source.localized(locale: locale),
                value: currentAccount.sourceMode.localizedDisplayName(locale: locale),
                valueColor: TerminalTheme.secondary
            )
            miniMaxDetailsContent(miniMaxPresentation)
        } else if let snapshot = row.snapshot {
            TerminalInspectorRow(
                label: AppStrings.AccountDetails.source.localized(locale: locale),
                value: snapshot.source,
                valueColor: TerminalTheme.secondary
            )
            TerminalRule()
            TerminalInspectorRow(
                label: AppStrings.AccountDetails.confidence.localized(locale: locale),
                value: snapshot.confidence.localizedDisplayName(locale: locale),
                valueColor: TerminalTheme.secondary
            )

            if let planName = snapshot.planName {
                TerminalRule()
                TerminalInspectorRow(label: AppStrings.AccountDetails.plan.localized(locale: locale), value: planName)
            }

            if snapshot.displayLimitWindows.isEmpty {
                TerminalRule()
                TerminalInspectorRow(
                    label: AppStrings.AccountDetails.usage.localized(locale: locale),
                    value: snapshot.remainingLabel ?? snapshot.status.localizedDisplayName(locale: locale),
                    valueColor: currentStateColor
                )
            }

            ForEach(snapshot.displayLimitWindows) { window in
                if window.usedPercent != nil {
                    TerminalRule()
                    usageDisplayControl(for: window)
                }

                if let remainingLabel = window.remainingLabel, !remainingLabel.isEmpty {
                    TerminalRule()
                    TerminalInspectorRow(
                        label: AppStrings.AccountDetails.usage.localized(locale: locale),
                        value: remainingLabel,
                        valueColor: TerminalTheme.primary
                    )
                }

                if let resetAt = window.resetAt {
                    TerminalRule()
                    TerminalInspectorRow(
                        label: AppStrings.AccountDetails.reset.formatted(
                            locale: locale,
                            window.displayName.uppercased(with: locale)
                        ),
                        value: preciseDate(resetAt),
                        valueColor: TerminalTheme.secondary
                    )
                }
            }
        } else {
            TerminalInspectorRow(
                label: AppStrings.AccountDetails.source.localized(locale: locale),
                value: currentAccount.sourceMode.localizedDisplayName(locale: locale),
                valueColor: TerminalTheme.secondary
            )
            TerminalRule()
            TerminalInspectorRow(
                label: AppStrings.AccountDetails.usage.localized(locale: locale),
                value: emptyStateMessage,
                valueColor: TerminalTheme.secondary
            )
        }

        if hasDiagnostics {
            TerminalRule()
            TerminalNoteBox(title: AppStrings.AccountDetails.diagnostics.localized(locale: locale)) {
                diagnosticsContent
            }
        }
    }

    private func usageDisplayControl(for window: UsageLimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                AppStrings.AccountDetails.displayMode.formatted(
                    locale: locale,
                    window.displayName.uppercased(with: locale)
                )
            )
            .font(TerminalTheme.legendFont)
            .foregroundStyle(TerminalTheme.primary)

            TerminalSegmentedControl(
                AppStrings.AccountDetails.displayModeAccessibility.formatted(
                    locale: locale,
                    window.displayName
                ),
                selection: usageDisplayOverrideBinding(for: window),
                options: UsageDisplayOverrideSelection.allCases.map {
                    TerminalSegmentedOption(
                        value: $0,
                        title: $0.localizedDisplayName(locale: locale)
                    )
                }
            )
        }
    }

    @ViewBuilder
    private func miniMaxDetailsContent(
        _ presentation: MiniMaxCapacityPresentation
    ) -> some View {
        ForEach(presentation.categories) { category in
            TerminalRule()
            VStack(alignment: .leading, spacing: 8) {
                Text(category.fullDisplayName)
                    .font(TerminalTheme.legendFont)
                    .foregroundStyle(TerminalTheme.primary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(category.windows) { window in
                    TerminalInspectorRow(
                        label: window.displayName.uppercased(with: locale),
                        value: [window.percentageText, window.capacityText]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n"),
                        valueColor: TerminalTheme.primary
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(window.accessibilityLabel)
                    .accessibilityValue(window.accessibilityValue)
                    .accessibilityIdentifier(
                        "details.minimax.window.\(presentation.accountID).\(window.id)"
                    )

                    if window.displayPercent != nil {
                        usageDisplayControl(for: window.usageLimitWindow)
                    }

                    if let resetAt = window.resetAt {
                        TerminalInspectorRow(
                            label: AppStrings.AccountDetails.reset.formatted(
                                locale: locale,
                                window.displayName.uppercased(with: locale)
                            ),
                            value: preciseDate(resetAt),
                            valueColor: TerminalTheme.secondary
                        )
                    }
                }
            }
            .accessibilityIdentifier(
                "details.minimax.category.\(presentation.accountID).\(category.id)"
            )
        }
    }

    @ViewBuilder
    private var diagnosticsContent: some View {
        if let issue = row.refreshIssue,
           let messages = refreshIssueDiagnosticMessages {
            diagnosticItem(
                title: AppStrings.AccountDetails.lastRefreshFailed.localized(locale: locale),
                messages: messages,
                date: issue.occurredAt,
                color: TerminalTheme.error
            )
        }

        if let snapshot = row.snapshot, appModel.isSnapshotStale(snapshot) {
            if hasRefreshIssueDiagnostics {
                TerminalRule()
            }
            diagnosticItem(
                title: AppStrings.AccountDetails.staleData.localized(locale: locale),
                messages: [AppStrings.AccountDetails.staleDetail.localized(locale: locale)],
                date: nil,
                color: TerminalTheme.warning
            )
        }

        if let snapshot = row.snapshot, !diagnosticWarnings.isEmpty {
            if hasRefreshIssueDiagnostics || appModel.isSnapshotStale(snapshot) {
                TerminalRule()
            }
            diagnosticItem(
                title: AppStrings.AccountDetails.warnings.localized(locale: locale),
                messages: diagnosticWarnings,
                date: nil,
                color: snapshot.status == .error ? TerminalTheme.error : TerminalTheme.warning
            )
        }
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            if currentAccount.sourceMode == .ollamaWebPage {
                Button(ollamaConnectionTitle, action: beginOllamaConnection)
                    .disabled(appModel.ollamaWebPageClient == nil || actionsDisabled)
            }

            Button(AppStrings.AccountDetails.testConnection.localized(locale: locale)) {
                appModel.testConnection(providerID: row.account.providerID, accountID: row.account.accountID)
            }
            .disabled(actionsDisabled)

            Button(AppStrings.AccountDetails.openUsage.localized(locale: locale)) {
                if let url = usageURL {
                    openURL(url)
                }
            }
            .disabled(usageURL == nil)
        }
        .buttonStyle(TerminalTextButtonStyle())
    }

    private var usageURL: URL? {
        appModel.usageURL(providerID: row.account.providerID, accountID: row.account.accountID)
    }

    private var currentAccount: ProviderAccount {
        appModel.account(providerID: row.account.providerID, accountID: row.account.accountID) ?? row.account
    }

    private func usageDisplayOverrideBinding(
        for window: UsageLimitWindow
    ) -> Binding<UsageDisplayOverrideSelection> {
        Binding(
            get: { appModel.usageDisplayOverrideSelection(for: currentAccount, windowID: window.id) },
            set: { _ = appModel.setUsageDisplayOverride($0, for: currentAccount, windowID: window.id) }
        )
    }

    private var ollamaConnectionTitle: String {
        currentAccount.webDataStoreID == nil
            ? AppStrings.AccountDetails.connect.localized(locale: locale)
            : AppStrings.AccountDetails.reconnect.localized(locale: locale)
    }

    private var emptyStateMessage: String {
        switch currentAccount.sourceMode {
        case .ollamaWebPage:
            AppStrings.AccountDetails.ollamaConnectFirst.localized(locale: locale)
        case .appServer:
            AppStrings.AccountDetails.codexRefreshFirst.localized(locale: locale)
        case .claudeUsageCLI:
            AppStrings.AccountDetails.claudeUsageRefreshFirst.localized(locale: locale)
        case .manual, .claudeStatusLine, .openRouterAPI, .miniMaxTokenPlan:
            AppStrings.AccountDetails.refreshOrTestFirst.localized(locale: locale)
        }
    }

    private var hasDiagnostics: Bool {
        hasRefreshIssueDiagnostics ||
            row.snapshot.map { appModel.isSnapshotStale($0) } == true ||
            !diagnosticWarnings.isEmpty
    }

    private var refreshIssueDiagnosticMessages: [String]? {
        guard let issue = row.refreshIssue else { return nil }
        return AccountDetailsRefreshIssuePresentation.diagnosticMessages(
            for: currentAccount,
            issue: issue,
            locale: locale
        )
    }

    private var hasRefreshIssueDiagnostics: Bool {
        refreshIssueDiagnosticMessages != nil
    }

    private var diagnosticWarnings: [String] {
        guard let snapshot = row.snapshot else { return [] }
        if row.account.sourceMode.isExperimental && snapshot.status == .ok {
            return []
        }
        return localizedDiagnosticMessages(
            AccountDetailsRefreshIssuePresentation.snapshotWarnings(
                for: currentAccount,
                warnings: snapshot.warnings
            )
        )
    }

    private var sourceStateMessage: String {
        hasUnavailableMiniMaxSubscription
            ? AppStrings.MiniMax.subscriptionUnavailable.localized(locale: locale)
            : appModel.localizedAccountDiagnosticsMessage(
                for: currentAccount,
                locale: locale
            )
    }

    private var hasUnavailableMiniMaxSubscription: Bool {
        AccountDetailsRefreshIssuePresentation.hasUnavailableSubscription(
            for: currentAccount,
            issue: row.refreshIssue
        )
    }

    private func localizedDiagnosticMessages(_ messages: [String]) -> [String] {
        guard currentAccount.providerID == MiniMaxProviderContract.providerID else {
            return messages
        }
        return messages.map {
            $0 == MiniMaxProviderContract.unavailableSubscriptionWarning
                ? AppStrings.MiniMax.subscriptionUnavailable.localized(locale: locale)
                : $0
        }
    }

    private var actionsDisabled: Bool {
        appModel.isRefreshing || row.refreshStatus == .refreshing || !row.account.isEnabled
    }

    private var currentStateColor: Color {
        switch dashboardPresentation.state {
        case .failed:
            TerminalTheme.error
        case .stale, .warning:
            TerminalTheme.warning
        case .normal:
            TerminalTheme.healthy
        case .refreshing, .manual, .unavailable, .noData:
            TerminalTheme.primary
        }
    }

    private var refreshStatusColor: Color {
        switch row.refreshStatus {
        case .succeeded:
            TerminalTheme.healthy
        case .failed:
            TerminalTheme.error
        case .idle:
            persistedRefreshStatusColor
        case .refreshing:
            TerminalTheme.primary
        }
    }

    private func sourceAvailabilityColor(_ availability: ProviderSourceAvailability) -> Color {
        switch availability {
        case .supported:
            TerminalTheme.healthy
        case .needsConnection, .noData:
            TerminalTheme.warning
        case .failed, .unsupported:
            TerminalTheme.error
        }
    }

    private var persistedRefreshStatusColor: Color {
        if row.refreshIssue != nil || row.snapshot?.status == .error {
            return TerminalTheme.error
        }
        if row.snapshot != nil {
            return TerminalTheme.healthy
        }
        return currentStateColor
    }

    private var refreshText: String {
        switch row.refreshStatus {
        case .idle:
            persistedRefreshText
        case .refreshing:
            AppStrings.Common.refreshing.localized(locale: locale)
        case let .succeeded(date):
            AppStrings.AccountDetails.succeededAt.formatted(locale: locale, preciseDate(date))
        case let .failed(date):
            AppStrings.AccountDetails.failedAt.formatted(locale: locale, preciseDate(date))
        }
    }

    private var persistedRefreshText: String {
        if let issue = row.refreshIssue {
            return AppStrings.AccountDetails.failedAt.formatted(locale: locale, preciseDate(issue.occurredAt))
        }
        if let date = appModel.accountDiagnostics(for: currentAccount).lastSuccessfulRefreshAt {
            return AppStrings.AccountDetails.succeededAt.formatted(locale: locale, preciseDate(date))
        }
        if let snapshot = row.snapshot, snapshot.status != .error {
            return AppStrings.AccountDetails.succeededAt.formatted(locale: locale, preciseDate(snapshot.lastUpdatedAt))
        }
        return currentStateText
    }

    private var currentStateText: String {
        switch dashboardPresentation.state {
        case .normal:
            row.snapshot?.status.localizedDisplayName(locale: locale)
                ?? AppStrings.Common.noUsageData.localized(locale: locale)
        case .refreshing:
            AppStrings.Common.refreshing.localized(locale: locale)
        case .stale:
            AppStrings.Common.stale.localized(locale: locale)
        case .failed:
            AppStrings.Common.failed.localized(locale: locale)
        case .warning:
            AppStrings.Common.warning.localized(locale: locale)
        case .manual:
            AppStrings.Common.manual.localized(locale: locale)
        case .unavailable:
            AppStrings.Common.unavailable.localized(locale: locale)
        case .noData:
            AppStrings.Common.noUsageData.localized(locale: locale)
        }
    }

    private func beginOllamaConnection() {
        guard currentAccount.providerID == "ollama-cloud",
              appModel.ollamaWebPageClient != nil,
              let connectedAccount = appModel.prepareOllamaWebPageConnection(
                  providerID: currentAccount.providerID,
                  accountID: currentAccount.accountID
              )
        else {
            connectionError = AppStrings.Ollama.saveBeforeConnecting.localized(locale: locale)
            return
        }
        appModel.presentOllamaConnection(for: connectedAccount)
        if let onOpenOllamaConnection {
            onOpenOllamaConnection()
        } else {
            ApplicationLifecycle.openOllamaConnection(using: openWindow)
        }
    }

    private var connectionErrorBinding: Binding<Bool> {
        Binding(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )
    }

    private func diagnosticItem(title: String, messages: [String], date: Date?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(TerminalTheme.detailLabelFont)
                Spacer()
                if let date {
                    Text(preciseDate(date))
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(TerminalTheme.secondary)
                }
            }

            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                Text(message)
                    .font(TerminalTheme.captionFont)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(color)
    }

    private func preciseDate(_ date: Date) -> String {
        AppFormatters.preciseDate(date, locale: locale)
    }
}

enum AccountDetailsRefreshIssuePresentation {
    static func hasUnavailableSubscription(
        for account: ProviderAccount,
        issue: AccountRefreshIssue?
    ) -> Bool {
        guard account.providerID == MiniMaxProviderContract.providerID else {
            return false
        }
        return issue?.warnings.contains(
            MiniMaxProviderContract.unavailableSubscriptionWarning
        ) == true
    }

    static func diagnosticMessages(
        for account: ProviderAccount,
        issue: AccountRefreshIssue,
        locale: Locale
    ) -> [String]? {
        guard !issue.warnings.isEmpty else {
            return [AppStrings.AccountDetails.noErrorDetails.localized(locale: locale)]
        }

        let messages = issue.warnings.compactMap { warning -> String? in
            guard account.providerID == MiniMaxProviderContract.providerID,
                  warning == MiniMaxProviderContract.unavailableSubscriptionWarning else {
                return warning
            }
            return nil
        }
        return messages.isEmpty ? nil : messages
    }

    static func snapshotWarnings(
        for account: ProviderAccount,
        warnings: [String]
    ) -> [String] {
        guard account.providerID == MiniMaxProviderContract.providerID else {
            return warnings
        }
        return warnings.filter {
            $0 != MiniMaxProviderContract.unavailableSubscriptionWarning
        }
    }
}

struct AccountDetailsScrollViewConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.configureAfterMount(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.configureAfterMount(from: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @discardableResult
    static func configureEnclosingScrollView(from view: NSView) -> Bool {
        guard let scrollView = view.enclosingScrollView else { return false }
        configure(scrollView)
        return true
    }

    static func configure(_ scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.verticalScroller?.controlSize = .mini
    }

    @MainActor
    final class Coordinator {
        private weak var scrollView: NSScrollView?
        private var styleObservation: NSKeyValueObservation?
        private var mountGeneration: UInt = 0

        func configureAfterMount(from view: NSView) {
            mountGeneration &+= 1
            let generation = mountGeneration
            configureAndObserve(from: view)
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self,
                      let view,
                      self.mountGeneration == generation else {
                    return
                }
                self.configureAndObserve(from: view)
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self,
                          let view,
                          self.mountGeneration == generation else {
                        return
                    }
                    self.configureAndObserve(from: view)
                }
            }
        }

        func detach() {
            mountGeneration &+= 1
            clearBinding()
        }

        @discardableResult
        private func configureAndObserve(from view: NSView) -> Bool {
            guard let enclosingScrollView = view.enclosingScrollView else {
                clearBinding()
                return false
            }
            if scrollView !== enclosingScrollView {
                clearBinding()
                scrollView = enclosingScrollView
                styleObservation = enclosingScrollView.observe(
                    \.scrollerStyle,
                    options: [.new]
                ) { [weak self, weak enclosingScrollView] _, change in
                    guard change.newValue != .overlay else { return }
                    DispatchQueue.main.async { [weak self, weak enclosingScrollView] in
                        guard let self,
                              let enclosingScrollView,
                              self.scrollView === enclosingScrollView else {
                            return
                        }
                        AccountDetailsScrollViewConfigurator.configure(
                            enclosingScrollView
                        )
                    }
                }
            }
            AccountDetailsScrollViewConfigurator.configure(enclosingScrollView)
            return true
        }

        private func clearBinding() {
            styleObservation?.invalidate()
            styleObservation = nil
            scrollView = nil
        }

#if DEBUG
        var observedScrollViewForTesting: NSScrollView? {
            scrollView
        }
#endif
    }
}

private struct TerminalInspectorRow: View {
    let label: String
    let value: String
    var valueColor: Color = TerminalTheme.primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(TerminalTheme.detailLabelFont)
                .foregroundStyle(TerminalTheme.primary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(TerminalTheme.detailValueFont)
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
