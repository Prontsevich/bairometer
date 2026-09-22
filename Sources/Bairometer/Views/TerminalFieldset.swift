import SwiftUI

enum TerminalFieldsetLayout {
    static let controlsHeight = TerminalIconControlLayout.hitTargetSize
    static let controlsVerticalOffset = -controlsHeight / 2
    static let controlsTrailingInset: CGFloat = 9
}

struct TerminalFieldset<Controls: View, Content: View>: View {
    let title: String
    let titleAccessibilityLabel: String
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        titleAccessibilityLabel: String? = nil,
        @ViewBuilder controls: @escaping () -> Controls,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.titleAccessibilityLabel = titleAccessibilityLabel ?? title
        self.controls = controls
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(TerminalTheme.border.opacity(0.9), lineWidth: 1)
                .background(TerminalTheme.surface, in: RoundedRectangle(cornerRadius: 3, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(.horizontal, 9)
            .padding(.top, 23)
            .padding(.bottom, 8)

            Text(title)
                .font(TerminalTheme.legendFont)
                .foregroundStyle(TerminalTheme.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(title)
                .accessibilityLabel(titleAccessibilityLabel)
                .padding(.horizontal, 4)
                .background(TerminalTheme.surface)
                .frame(maxWidth: 280, alignment: .leading)
                .padding(.leading, 8)
                .offset(y: -8)

            controls()
                .frame(
                    minHeight: TerminalFieldsetLayout.controlsHeight,
                    maxHeight: TerminalFieldsetLayout.controlsHeight,
                    alignment: .center
                )
                .padding(.leading, 4)
                .padding(.trailing, TerminalFieldsetLayout.controlsTrailingInset)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(y: TerminalFieldsetLayout.controlsVerticalOffset)
        }
    }
}
