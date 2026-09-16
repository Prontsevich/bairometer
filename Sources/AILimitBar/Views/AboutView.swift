import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.locale) private var locale
    private let buildInformation: AboutBuildInformation

    init(buildInformation: AboutBuildInformation = .current) {
        self.buildInformation = buildInformation
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Bairometer")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(TerminalTheme.primary)

                Text(buildInformation.displayText(locale: locale))
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .accessibilityLabel(AppStrings.About.buildInformation.localized(locale: locale))
                    .accessibilityValue(buildInformation.displayText(locale: locale))
            }

            VStack(spacing: 8) {
                externalLink(
                    AppStrings.About.openGitHub.localized(locale: locale),
                    destination: AboutLinks.github,
                    accessibilityLabel: AppStrings.About.openGitHubAccessibility.localized(locale: locale)
                )

                Text(AppStrings.About.feedback.resource(locale: locale))
                    .font(TerminalTheme.detailLabelFont)
                    .foregroundStyle(TerminalTheme.secondary)

                HStack(spacing: 8) {
                    externalLink(
                        AppStrings.About.reportIssue.localized(locale: locale),
                        destination: AboutLinks.issue,
                        accessibilityLabel: AppStrings.About.reportIssueAccessibility.localized(locale: locale)
                    )

                    externalLink(
                        AppStrings.About.email.localized(locale: locale),
                        destination: AboutLinks.email,
                        accessibilityLabel: AppStrings.About.emailAccessibility.localized(locale: locale)
                    )

                    externalLink(
                        AppStrings.About.telegram.localized(locale: locale),
                        destination: AboutLinks.telegram,
                        accessibilityLabel: AppStrings.About.telegramAccessibility.localized(locale: locale)
                    )
                }

                Text(AppStrings.About.supportText.resource(locale: locale))
                    .font(TerminalTheme.captionFont)
                    .foregroundStyle(TerminalTheme.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                externalLink(
                    AppStrings.About.supportBoosty.localized(locale: locale),
                    destination: AboutLinks.boosty,
                    accessibilityLabel: AppStrings.About.supportBoostyAccessibility.localized(locale: locale)
                )
            }
        }
        .padding(24)
        .frame(
            width: AboutWindowConfiguration.preferredSize.width,
            height: AboutWindowConfiguration.preferredSize.height
        )
        .background(TerminalTheme.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppStrings.About.accessibilityLabel.localized(locale: locale))
    }

    private func externalLink(
        _ title: String,
        destination: URL,
        accessibilityLabel: String
    ) -> some View {
        Link(destination: destination) {
            Text(title)
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(TerminalTheme.border.opacity(0.8), lineWidth: 1)
                }
        }
        .accessibilityLabel(accessibilityLabel)
    }
}
