import SwiftUI

struct OpenRouterCapacityDashboardContent: View {
    @Environment(\.locale) private var locale
    let presentation: OpenRouterCapacityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if presentation.state != .current {
                Label(presentation.statusText, systemImage: statusSymbol)
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(statusColor)
                    .accessibilityLabel(presentation.statusText)
            }

            sharedCredits

            TerminalRule()
                .padding(.vertical, 1)

            capacitySectionTitle(
                AppStrings.OpenRouter.apiKeys.localized(locale: locale)
            )
            if presentation.credentials.isEmpty {
                Text(AppStrings.OpenRouter.noOrdinaryKeys.resource(locale: locale))
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(presentation.credentials.enumerated()), id: \.element.id) {
                    index,
                    credential in
                    if index > 0 {
                        TerminalRule()
                            .padding(.vertical, 1)
                    }
                    OpenRouterDashboardCredentialRow(credential: credential)
                }
            }
        }
    }

    @ViewBuilder
    private var sharedCredits: some View {
        if presentation.sharedCredits.state == .unavailable
            || presentation.sharedCredits.state == .unknown {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(presentation.sharedCredits.displayName)
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.secondary)

                Spacer(minLength: 8)

                Text(presentation.sharedCredits.dashboardValueText)
                    .font(TerminalTheme.emphasizedBodyFont)
                    .foregroundStyle(
                        OpenRouterCapacityColors.color(
                            for: presentation.sharedCredits.state
                        )
                    )
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.sharedCredits.displayName)
            .accessibilityValue(
                presentation.sharedCredits.dashboardAccessibilityValue
            )
            .accessibilityIdentifier(
                "dashboard.openrouter.shared.\(presentation.accountID)"
            )
        } else {
            Text(presentation.sharedCredits.dashboardValueText)
                .font(TerminalTheme.emphasizedBodyFont)
                .foregroundStyle(
                    OpenRouterCapacityColors.color(
                        for: presentation.sharedCredits.state
                    )
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(presentation.sharedCredits.displayName)
                .accessibilityValue(
                    presentation.sharedCredits.dashboardAccessibilityValue
                )
                .accessibilityIdentifier(
                    "dashboard.openrouter.shared.\(presentation.accountID)"
                )
        }
    }

    private func capacitySectionTitle(_ title: String) -> some View {
        Text(title)
            .font(TerminalTheme.legendFont)
            .foregroundStyle(TerminalTheme.primary)
            .accessibilityAddTraits(.isHeader)
    }

    private var statusColor: Color {
        OpenRouterCapacityColors.color(for: presentation.state)
    }

    private var statusSymbol: String {
        OpenRouterCapacityColors.symbol(for: presentation.state)
    }
}

private struct OpenRouterDashboardCredentialRow: View {
    let credential: OpenRouterCredentialCapacityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(credential.displayName)
                    .font(TerminalTheme.emphasizedBodyFont)
                    .foregroundStyle(TerminalTheme.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                Text(credential.dashboardValueText)
                    .font(TerminalTheme.emphasizedBodyFont)
                    .foregroundStyle(summaryColor)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let resetText = credential.dashboardMetric?.resetText {
                Text(resetText)
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let dashboardStatusText = credential.dashboardStatusText {
                Text(dashboardStatusText)
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(
                        OpenRouterCapacityColors.color(for: credential.state)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(credential.displayName)
        .accessibilityValue(credential.dashboardAccessibilityValue)
        .accessibilityIdentifier("openrouter.key.\(credential.id)")
    }

    private var summaryColor: Color {
        if credential.dashboardMetric != nil {
            return OpenRouterCapacityColors.color(
                for: credential.dashboardMetric?.state ?? credential.state
            )
        }
        return OpenRouterCapacityColors.color(for: credential.state)
    }
}

struct OpenRouterCapacityDetailsContent: View {
    @Environment(\.locale) private var locale
    let presentation: OpenRouterCapacityPresentation
    @State private var expandedCredentialID: String?

    init(
        presentation: OpenRouterCapacityPresentation,
        initiallyExpandedCredentialID: String? = nil
    ) {
        self.presentation = presentation
        _expandedCredentialID = State(
            initialValue: initiallyExpandedCredentialID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OpenRouterAccountCreditsDetails(metric: presentation.sharedCredits)
            .accessibilityIdentifier("details.openrouter.shared")

            if presentation.credentials.isEmpty {
                TerminalRule()
                Text(AppStrings.OpenRouter.noOrdinaryKeys.resource(locale: locale))
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(presentation.credentials) { credential in
                    TerminalRule()
                    OpenRouterCredentialDisclosureRow(
                        presentation: credential.detailsPresentation,
                        isExpanded: expansionBinding(for: credential.id)
                    )
                }
            }
        }
    }

    private func expansionBinding(for credentialID: String) -> Binding<Bool> {
        Binding(
            get: { expandedCredentialID == credentialID },
            set: { isExpanded in
                if isExpanded {
                    expandedCredentialID = credentialID
                } else if expandedCredentialID == credentialID {
                    expandedCredentialID = nil
                }
            }
        )
    }
}

private struct OpenRouterCredentialDisclosureRow: View {
    let presentation: OpenRouterCredentialDetailsPresentation
    @Binding var isExpanded: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if presentation.expandedMetrics.isEmpty {
                summary(showsReset: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(presentation.displayName)
                    .accessibilityValue(
                        presentation.collapsedAccessibilityValue
                    )
                    .accessibilityIdentifier(
                        "details.openrouter.key.\(presentation.id).summary"
                    )
            } else {
                disclosureButton

                if isExpanded {
                    expandedContent
                        .padding(.top, 4)
                        .padding(.leading, 20)
                        .accessibilityIdentifier(
                            "details.openrouter.key.\(presentation.id).expanded"
                        )
                }
            }
        }
    }

    private var disclosureButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12, height: 16, alignment: .center)
                    .foregroundStyle(TerminalTheme.primary)

                summary(showsReset: !isExpanded)
                    .accessibilityIdentifier(
                        "details.openrouter.key.\(presentation.id).summary"
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TerminalDisclosureButtonStyle())
        .help(disclosureHint)
        .accessibilityLabel(presentation.displayName)
        .accessibilityValue(disclosureAccessibilityValue)
        .accessibilityHint(disclosureHint)
        .accessibilityIdentifier(
            "details.openrouter.key.\(presentation.id).disclosure"
        )
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let keyLimitMetric = presentation.keyLimitMetric {
                OpenRouterAvailableCapacityRow(metric: keyLimitMetric)
            }

            if !presentation.usageRows.isEmpty {
                detailsSection(
                    AppStrings.OpenRouter.usageSection.localized(locale: locale)
                ) {
                    OpenRouterUsageTable(rows: presentation.usageRows)
                }
            }

            if !presentation.resetGroups.isEmpty {
                detailsSection(
                    AppStrings.OpenRouter.resetScheduleSection.localized(
                        locale: locale
                    )
                ) {
                    OpenRouterResetTable(
                        credentialID: presentation.id,
                        rows: presentation.resetGroups
                    )
                }
            }

            if let updateText = presentation.updateText {
                Text(updateText)
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(
                        presentation.state == .stale
                            ? TerminalTheme.warning
                            : TerminalTheme.secondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func detailsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(TerminalTheme.legendFont)
                .foregroundStyle(TerminalTheme.primary)
                .accessibilityAddTraits(.isHeader)

            content()
        }
    }

    private func summary(showsReset: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            OpenRouterAdaptiveValueRow(
                label: presentation.displayName,
                values: [presentation.summaryValueText],
                labelFont: TerminalTheme.emphasizedBodyFont,
                valueFont: TerminalTheme.emphasizedBodyFont,
                labelColor: TerminalTheme.primary,
                valueColor: OpenRouterCapacityColors.color(
                    for: presentation.summaryState
                )
            )

            if showsReset, let resetText = presentation.resetText {
                Text(resetText)
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let exceptionText = presentation.exceptionText {
                Text(exceptionText)
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(
                        OpenRouterCapacityColors.color(
                            for: presentation.state
                        )
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var disclosureAccessibilityValue: String {
        [
            isExpanded
                ? presentation.expandedSummaryAccessibilityValue
                : presentation.collapsedAccessibilityValue,
            isExpanded
                ? AppStrings.OpenRouter.detailsExpanded.localized(locale: locale)
                : AppStrings.OpenRouter.detailsCollapsed.localized(locale: locale),
        ]
        .joined(separator: ", ")
    }

    private var disclosureHint: String {
        isExpanded
            ? AppStrings.OpenRouter.hideKeyDetails.localized(locale: locale)
            : AppStrings.OpenRouter.showKeyDetails.localized(locale: locale)
    }
}

private struct OpenRouterAccountCreditsDetails: View {
    @Environment(\.locale) private var locale
    let metric: OpenRouterCapacityMetricPresentation

    @ViewBuilder
    var body: some View {
        if let credits = metric.accountCredits {
            VStack(alignment: .leading, spacing: 5) {
                Text(metric.displayName)
                    .font(TerminalTheme.legendFont)
                    .foregroundStyle(TerminalTheme.primary)
                    .accessibilityAddTraits(.isHeader)

                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 3) {
                        tableHeader(
                            AppStrings.OpenRouter.leftColumn.localized(
                                locale: locale
                            )
                        )
                        tableValue(credits.leftText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        tableHeader(
                            AppStrings.OpenRouter.usedColumn.localized(
                                locale: locale
                            )
                        )
                        tableValue(credits.usedText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let freshnessText = metric.freshnessText {
                    Text(freshnessText)
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(
                            metric.state == .stale
                                ? TerminalTheme.warning
                                : TerminalTheme.secondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(metric.displayName)
            .accessibilityValue(
                [credits.accessibilityValue, metric.freshnessText]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            )
        } else {
            OpenRouterCapacityMetricRow(
                metric: metric,
                showsFreshness: true,
                prefersVerticalLayout: true
            )
        }
    }

    private func tableHeader(_ text: String) -> some View {
        Text(text)
            .font(TerminalTheme.detailLabelFont)
            .foregroundStyle(TerminalTheme.primary)
            .fixedSize(horizontal: true, vertical: true)
    }

    private func tableValue(_ text: String) -> some View {
        Text(text)
            .font(TerminalTheme.emphasizedBodyFont)
            .foregroundStyle(OpenRouterCapacityColors.color(for: metric.state))
            .fixedSize(horizontal: true, vertical: true)
    }
}

private struct OpenRouterUsageTable: View {
    @Environment(\.locale) private var locale
    let rows: [OpenRouterUsageTableRowPresentation]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalTable
            compactTable
        }
    }

    private var horizontalTable: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: 12,
            verticalSpacing: 4
        ) {
            GridRow {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
                header(AppStrings.OpenRouter.usageColumn.localized(locale: locale))
                header(AppStrings.OpenRouter.byokColumn.localized(locale: locale))
            }

            ForEach(rows) { row in
                GridRow {
                    Text(row.scopeText)
                        .font(TerminalTheme.detailLabelFont)
                        .foregroundStyle(TerminalTheme.primary)
                        .fixedSize(horizontal: true, vertical: true)
                    metricValue(row.usageMetric)
                    metricValue(row.byokMetric)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var compactTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.scopeText)
                        .font(TerminalTheme.detailLabelFont)
                        .foregroundStyle(TerminalTheme.primary)

                    HStack(alignment: .top, spacing: 12) {
                        compactColumn(
                            title: AppStrings.OpenRouter.usageColumn.localized(
                                locale: locale
                            ),
                            metric: row.usageMetric
                        )
                        compactColumn(
                            title: AppStrings.OpenRouter.byokColumn.localized(
                                locale: locale
                            ),
                            metric: row.byokMetric
                        )
                    }
                }
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(TerminalTheme.detailLabelFont)
            .foregroundStyle(TerminalTheme.primary)
            .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private func metricValue(
        _ metric: OpenRouterCapacityMetricPresentation?
    ) -> some View {
        if let metric {
            Text(metric.tableValueText)
                .font(TerminalTheme.emphasizedBodyFont)
                .foregroundStyle(OpenRouterCapacityColors.color(for: metric.state))
                .fixedSize(horizontal: true, vertical: true)
                .accessibilityLabel(metric.displayName)
                .accessibilityValue(metric.tableValueText)
                .accessibilityIdentifier("openrouter.metric.\(metric.id)")
        } else {
            Text("—")
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.secondary)
                .accessibilityHidden(true)
        }
    }

    private func compactColumn(
        title: String,
        metric: OpenRouterCapacityMetricPresentation?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            header(title)
            metricValue(metric)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OpenRouterResetTable: View {
    @Environment(\.locale) private var locale
    let credentialID: String
    let rows: [OpenRouterCredentialResetPresentation]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalTable
            compactList
        }
    }

    private var horizontalTable: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: 12,
            verticalSpacing: 4
        ) {
            GridRow {
                header(AppStrings.OpenRouter.scopeColumn.localized(locale: locale))
                header(AppStrings.OpenRouter.resetColumn.localized(locale: locale))
            }

            ForEach(rows) { row in
                GridRow {
                    Text(row.scopeNames.joined(separator: ", "))
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(TerminalTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(row.resetText)
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(TerminalTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityValue(row.accessibilityValue)
                .accessibilityIdentifier(
                    "details.openrouter.key."
                        + "\(credentialID).reset."
                        + "\(row.id)"
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var compactList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    header(
                        AppStrings.OpenRouter.scopeColumn.localized(
                            locale: locale
                        )
                    )
                    Text(row.scopeNames.joined(separator: ", "))
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(TerminalTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    header(
                        AppStrings.OpenRouter.resetColumn.localized(
                            locale: locale
                        )
                    )
                    Text(row.resetText)
                        .font(TerminalTheme.captionFont)
                        .foregroundStyle(TerminalTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityValue(row.accessibilityValue)
                .accessibilityIdentifier(
                    "details.openrouter.key."
                        + "\(credentialID).reset."
                        + "\(row.id)"
                )
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(TerminalTheme.detailLabelFont)
            .foregroundStyle(TerminalTheme.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OpenRouterAvailableCapacityRow: View {
    @Environment(\.locale) private var locale
    let metric: OpenRouterCapacityMetricPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(
                    AppStrings.OpenRouter.available.localized(locale: locale)
                )
                .font(TerminalTheme.detailLabelFont)
                .foregroundStyle(TerminalTheme.primary)

                Spacer(minLength: 12)

                Text(
                    metric.keyCapacity?.visualValueText
                        ?? metric.dashboardValueText
                )
                .font(TerminalTheme.emphasizedBodyFont)
                .foregroundStyle(
                    OpenRouterCapacityColors.color(for: metric.state)
                )
                .multilineTextAlignment(.trailing)
            }

            if let availableFraction = metric.keyCapacity?.availableFraction {
                TerminalStatusMeter(
                    value: availableFraction * 100,
                    tint: TerminalTheme.border
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AppStrings.OpenRouter.available.localized(locale: locale)
        )
        .accessibilityValue(
            metric.keyCapacity?.accessibilityValue
                ?? metric.dashboardAccessibilityValue
        )
        .accessibilityIdentifier("openrouter.metric.\(metric.id)")
    }
}

struct OpenRouterCapacityMetricRow: View {
    let metric: OpenRouterCapacityMetricPresentation
    let showsFreshness: Bool
    var showsReset = true
    var prefersVerticalLayout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            OpenRouterAdaptiveValueRow(
                label: metric.displayName,
                values: metric.displayValueLines,
                labelFont: TerminalTheme.bodyFont,
                valueFont: TerminalTheme.emphasizedBodyFont,
                labelColor: TerminalTheme.secondary,
                valueColor: OpenRouterCapacityColors.color(for: metric.state),
                prefersVerticalLayout: prefersVerticalLayout
            )

            if showsReset, let resetText = metric.resetText {
                Text(resetText)
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsFreshness, let freshnessText = metric.freshnessText {
                Text(freshnessText)
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(
                        metric.state == .stale
                            ? TerminalTheme.warning
                            : TerminalTheme.secondary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.displayName)
        .accessibilityValue(
            metric.visibleAccessibilityValue(
                showsReset: showsReset,
                showsFreshness: showsFreshness
            )
        )
        .accessibilityIdentifier("openrouter.metric.\(metric.id)")
    }
}

private struct OpenRouterAdaptiveValueRow: View {
    let label: String
    let values: [String]
    let labelFont: Font
    let valueFont: Font
    let labelColor: Color
    let valueColor: Color
    var prefersVerticalLayout = false

    @ViewBuilder
    var body: some View {
        if prefersVerticalLayout {
            verticalLayout
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalLayout
                verticalLayout
            }
        }
    }

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(labelFont)
                .foregroundStyle(labelColor)
                .fixedSize(horizontal: true, vertical: true)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text(value)
                        .font(valueFont)
                        .foregroundStyle(valueColor)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: true)
                }
            }
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(labelFont)
                .foregroundStyle(labelColor)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .font(valueFont)
                    .foregroundStyle(valueColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

enum OpenRouterCapacityColors {
    static func color(for state: OpenRouterCapacityState) -> Color {
        switch state {
        case .current, .unlimited:
            TerminalTheme.primary
        case .partial, .stale, .unknown, .recoveryRequired, .deletionPending:
            TerminalTheme.warning
        case .credentialError:
            TerminalTheme.error
        case .unavailable, .disabled:
            TerminalTheme.secondary
        }
    }

    static func symbol(for state: OpenRouterCapacityState) -> String {
        switch state {
        case .current, .unlimited:
            "checkmark.circle"
        case .partial:
            "exclamationmark.circle"
        case .stale:
            "clock.badge.exclamationmark"
        case .credentialError:
            "exclamationmark.triangle"
        case .unavailable, .unknown, .disabled, .recoveryRequired,
             .deletionPending:
            "info.circle"
        }
    }
}
