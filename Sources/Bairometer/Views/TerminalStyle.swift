import AppKit
import SwiftUI

enum TerminalTheme {
    static let surface = adaptiveColor(
        light: NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.91, alpha: 1),
        dark: NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.13, alpha: 1)
    )
    static let primary = adaptiveColor(
        light: NSColor(calibratedRed: 0.18, green: 0.16, blue: 0.11, alpha: 1),
        dark: NSColor(calibratedRed: 0.91, green: 0.87, blue: 0.74, alpha: 1)
    )
    static let secondary = adaptiveColor(
        light: NSColor(calibratedRed: 0.43, green: 0.39, blue: 0.29, alpha: 1),
        dark: NSColor(calibratedRed: 0.63, green: 0.59, blue: 0.48, alpha: 1)
    )
    static let border = adaptiveColor(
        light: NSColor(calibratedRed: 0.48, green: 0.43, blue: 0.30, alpha: 1),
        dark: NSColor(calibratedRed: 0.67, green: 0.61, blue: 0.43, alpha: 1)
    )
    static let healthy = adaptiveColor(
        light: NSColor(calibratedRed: 0.18, green: 0.47, blue: 0.24, alpha: 1),
        dark: NSColor(calibratedRed: 0.40, green: 0.70, blue: 0.40, alpha: 1)
    )
    static let warningNSColor = adaptiveNSColor(
        light: NSColor(calibratedRed: 0.67, green: 0.36, blue: 0.04, alpha: 1),
        dark: NSColor(calibratedRed: 0.91, green: 0.59, blue: 0.11, alpha: 1)
    )
    static let warning = Color(nsColor: warningNSColor)
    static let errorNSColor = adaptiveNSColor(
        light: NSColor(calibratedRed: 0.65, green: 0.16, blue: 0.14, alpha: 1),
        dark: NSColor(calibratedRed: 0.91, green: 0.39, blue: 0.35, alpha: 1)
    )
    static let error = Color(nsColor: errorNSColor)

    static let titleFont = Font.system(size: 14, weight: .bold, design: .monospaced)
    static let legendFont = Font.system(size: 12, weight: .semibold, design: .monospaced)
    static let bodyFont = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let emphasizedBodyFont = Font.system(size: 12, weight: .semibold, design: .monospaced)
    static let captionFont = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let detailLabelFont = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let detailValueFont = Font.system(size: 13, weight: .medium, design: .monospaced)

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: adaptiveNSColor(light: light, dark: dark))
    }

    private static func adaptiveNSColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

struct TerminalRule: View {
    var body: some View {
        Rectangle()
            .fill(TerminalTheme.border.opacity(0.62))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

struct TerminalStatusMeter: View {
    let value: Double
    let tint: Color

    private var normalizedValue: Double {
        min(max(value, 0), 100) / 100
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .strokeBorder(TerminalTheme.border, lineWidth: 1)

            GeometryReader { proxy in
                Rectangle()
                    .fill(tint)
                    .frame(
                        width: max(0, (proxy.size.width - 2) * normalizedValue),
                        height: max(0, proxy.size.height - 2)
                    )
                    .padding(1)
            }
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }
}

enum TerminalIconControlLayout {
    static let hitTargetSize: CGFloat = 32
}

enum TerminalIconControlIdleBackground: Equatable {
    case transparent
    case fieldsetSurface

    var color: Color {
        switch self {
        case .transparent:
            .clear
        case .fieldsetSurface:
            TerminalTheme.surface
        }
    }
}

struct TerminalIconButtonConfiguration: Equatable {
    let idleBackground: TerminalIconControlIdleBackground
    let fixedHitTargetSize: CGFloat?

    static let transparent = TerminalIconButtonConfiguration(
        idleBackground: .transparent,
        fixedHitTargetSize: nil
    )

    static func fieldset(hitTargetSize: CGFloat) -> Self {
        TerminalIconButtonConfiguration(
            idleBackground: .fieldsetSurface,
            fixedHitTargetSize: hitTargetSize
        )
    }
}

struct TerminalIconButtonStyle: ButtonStyle {
    let controlConfiguration: TerminalIconButtonConfiguration

    init(
        controlConfiguration: TerminalIconButtonConfiguration = .transparent
    ) {
        self.controlConfiguration = controlConfiguration
    }

    func makeBody(configuration: Configuration) -> some View {
        TerminalIconControlSurface(
            label: configuration.label,
            isPressed: configuration.isPressed,
            controlConfiguration: controlConfiguration
        )
    }
}

private struct TerminalIconControlSurface<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let controlConfiguration: TerminalIconButtonConfiguration

    var body: some View {
        TerminalInteractiveSurface(
            label: label,
            isPressed: isPressed,
            isSelected: false,
            showsBorder: false,
            showsHoverBorder: true,
            horizontalPadding: 4,
            verticalPadding: 4,
            minimumWidth: 22,
            minimumHeight: nil,
            expandsHorizontally: false,
            idleBackground: controlConfiguration.idleBackground.color,
            fixedSize: controlConfiguration.fixedHitTargetSize
        )
    }
}

struct TerminalTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TerminalInteractiveSurface(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: false,
            showsBorder: true,
            showsHoverBorder: false,
            horizontalPadding: 4,
            verticalPadding: 3,
            minimumWidth: nil,
            minimumHeight: nil,
            expandsHorizontally: false
        )
    }
}

struct TerminalDisclosureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TerminalInteractiveSurface(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: false,
            showsBorder: false,
            showsHoverBorder: true,
            horizontalPadding: 3,
            verticalPadding: 3,
            minimumWidth: nil,
            minimumHeight: 24,
            expandsHorizontally: true
        )
    }
}

struct TerminalActionButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        TerminalInteractiveSurface(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: isProminent,
            showsBorder: true,
            showsHoverBorder: false,
            horizontalPadding: 9,
            verticalPadding: 5,
            minimumWidth: nil,
            minimumHeight: nil,
            expandsHorizontally: false
        )
    }
}

struct TerminalSegmentedOption<Selection: Hashable>: Identifiable {
    let value: Selection
    let title: String
    let accessibilityIdentifier: String?

    init(
        value: Selection,
        title: String,
        accessibilityIdentifier: String? = nil
    ) {
        self.value = value
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var id: Selection { value }
}

struct TerminalSegmentedControl<Selection: Hashable>: View {
    @Environment(\.locale) private var locale
    let accessibilityLabel: String
    @Binding var selection: Selection
    let options: [TerminalSegmentedOption<Selection>]

    init(
        _ accessibilityLabel: String,
        selection: Binding<Selection>,
        options: [TerminalSegmentedOption<Selection>]
    ) {
        self.accessibilityLabel = accessibilityLabel
        _selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(TerminalSegmentButtonStyle(isSelected: selection == option.value))
                .accessibilityValue(
                    selection == option.value
                        ? AppStrings.Common.selected.localized(locale: locale)
                        : AppStrings.Common.notSelected.localized(locale: locale)
                )
                .modifier(OptionalAccessibilityIdentifier(option.accessibilityIdentifier))

                if index < options.count - 1 {
                    Rectangle()
                        .fill(TerminalTheme.border.opacity(0.62))
                        .frame(width: 1, height: 22)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(2)
        .background(TerminalTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(TerminalTheme.border.opacity(0.8), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) {
        self.identifier = identifier
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

struct TerminalToggleStyle: ToggleStyle {
    @Environment(\.locale) private var locale

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                configuration.label
                Text(
                    configuration.isOn
                        ? AppStrings.Common.on.resource(locale: locale)
                        : AppStrings.Common.off.resource(locale: locale)
                )
                    .font(TerminalTheme.captionFont)
            }
        }
        .buttonStyle(TerminalToggleButtonStyle(isOn: configuration.isOn))
        .accessibilityValue(
            configuration.isOn
                ? AppStrings.Common.onAccessibility.localized(locale: locale)
                : AppStrings.Common.offAccessibility.localized(locale: locale)
        )
    }
}

private struct TerminalSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TerminalInteractiveSurface(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: isSelected,
            showsBorder: false,
            showsHoverBorder: false,
            horizontalPadding: 10,
            verticalPadding: 0,
            minimumWidth: nil,
            minimumHeight: 28,
            expandsHorizontally: true
        )
    }
}

private struct TerminalToggleButtonStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        TerminalInteractiveSurface(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: isOn,
            showsBorder: true,
            showsHoverBorder: false,
            horizontalPadding: 8,
            verticalPadding: 5,
            minimumWidth: nil,
            minimumHeight: nil,
            expandsHorizontally: false
        )
    }
}

struct TerminalListRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TerminalListRowSurface(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: isSelected
        )
    }
}

struct TerminalChoiceButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TerminalInteractiveSurface(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: isSelected,
            showsBorder: true,
            showsHoverBorder: false,
            horizontalPadding: 8,
            verticalPadding: 0,
            minimumWidth: nil,
            minimumHeight: 28,
            expandsHorizontally: true
        )
    }
}

struct TerminalInteractiveSurface<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isSelected: Bool
    let showsBorder: Bool
    let showsHoverBorder: Bool
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minimumWidth: CGFloat?
    let minimumHeight: CGFloat?
    let expandsHorizontally: Bool
    var idleBackground: Color = .clear
    var fixedSize: CGFloat?
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var fill: Color {
        guard isEnabled else { return .clear }
        if isPressed {
            return TerminalTheme.primary.opacity(0.32)
        }
        if isHovering {
            return TerminalTheme.primary.opacity(isSelected ? 0.28 : 0.20)
        }
        if isSelected {
            return TerminalTheme.primary.opacity(0.22)
        }
        return .clear
    }

    private var foreground: Color {
        guard isEnabled else { return TerminalTheme.secondary.opacity(0.42) }
        return isPressed || isSelected || isHovering ? TerminalTheme.primary : TerminalTheme.secondary
    }

    private var borderOpacity: Double {
        guard isEnabled else { return showsBorder ? 0.28 : 0 }
        if showsBorder {
            if isPressed || isSelected { return 0.98 }
            if isHovering { return 0.90 }
            return 0.52
        }
        if showsHoverBorder, isPressed || isHovering {
            return isPressed ? 0.98 : 0.90
        }
        return 0
    }

    var body: some View {
        label
            .font(TerminalTheme.bodyFont)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(
                minWidth: minimumWidth,
                maxWidth: expandsHorizontally ? .infinity : nil,
                minHeight: minimumHeight
            )
            .frame(width: fixedSize, height: fixedSize)
            .contentShape(Rectangle())
            .background(fill)
            .background(idleBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(TerminalTheme.border.opacity(borderOpacity), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .scaleEffect(isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .onHover { isHovering = $0 }
    }
}

private struct TerminalListRowSurface<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isSelected: Bool
    @State private var isHovering = false

    private var fill: Color {
        if isPressed {
            return TerminalTheme.primary.opacity(0.32)
        }
        if isHovering {
            return TerminalTheme.primary.opacity(isSelected ? 0.28 : 0.20)
        }
        if isSelected {
            return TerminalTheme.primary.opacity(0.22)
        }
        return .clear
    }

    var body: some View {
        label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .onHover { isHovering = $0 }
    }
}

struct TerminalTextField: View {
    let title: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(TerminalTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(
                        isFocused ? TerminalTheme.primary : TerminalTheme.border.opacity(0.72),
                        lineWidth: isFocused ? 2 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .focused($isFocused)
            .accessibilityLabel(title)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

struct TerminalSecureField: View {
    let title: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        SecureField(title, text: $text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(TerminalTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(
                        isFocused ? TerminalTheme.primary : TerminalTheme.border.opacity(0.72),
                        lineWidth: isFocused ? 2 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .focused($isFocused)
            .accessibilityLabel(title)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

struct TerminalNoteBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(TerminalTheme.detailLabelFont)
                .foregroundStyle(TerminalTheme.secondary)

            content()
        }
        .padding(8)
        .background(TerminalTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(TerminalTheme.border.opacity(0.8), lineWidth: 1)
        }
    }
}
