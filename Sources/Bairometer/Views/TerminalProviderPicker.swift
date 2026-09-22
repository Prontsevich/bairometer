import SwiftUI

struct TerminalProviderPicker: View {
    @Environment(\.locale) private var locale
    private enum FocusTarget: Hashable {
        case trigger
        case option(String)
    }

    @Binding var selection: String
    let options: [TerminalSegmentedOption<String>]

    @State private var isExpanded = false
    @FocusState private var focusedTarget: FocusTarget?

    init(selection: Binding<String>, options: [TerminalSegmentedOption<String>]) {
        _selection = selection
        self.options = options
    }

    var body: some View {
        trigger
            .overlay(alignment: .topLeading) {
                if isExpanded {
                    pickerList
                        .offset(y: 34)
                        .zIndex(1)
                }
            }
            .zIndex(isExpanded ? 1 : 0)
    }

    private var trigger: some View {
        Button(action: togglePicker) {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(TerminalActionButtonStyle())
        .focusable()
        .focused($focusedTarget, equals: .trigger)
        .focusEffectDisabled()
        .overlay {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(
                    focusedTarget == .trigger ? TerminalTheme.primary : .clear,
                    lineWidth: 2
                )
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            openPicker()
            return .handled
        }
        .onKeyPress(.tab) {
            guard isExpanded else { return .ignored }
            focusOption(options.first?.value ?? selection)
            return .handled
        }
        .onMoveCommand { direction in
            switch direction {
            case .up, .down:
                openPicker(focusing: optionID(after: direction))
            default:
                break
            }
        }
        .accessibilityLabel(AppStrings.Settings.Editor.providerAccessibility.localized(locale: locale))
        .accessibilityValue(selectedTitle)
        .accessibilityHint(AppStrings.Settings.Editor.providerHint.localized(locale: locale))
    }

    private var pickerList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(options) { option in
                        Button {
                            select(option.value)
                        } label: {
                            HStack(spacing: 8) {
                                Text(option.title)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if selection == option.value {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .id(option.value)
                        .buttonStyle(TerminalChoiceButtonStyle(isSelected: selection == option.value))
                        .focusable()
                        .focused($focusedTarget, equals: .option(option.value))
                        .focusEffectDisabled()
                        .overlay {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(
                                    focusedTarget == .option(option.value) ? TerminalTheme.primary : .clear,
                                    lineWidth: 2
                                )
                        }
                        .onKeyPress(keys: [.space, .return]) { _ in
                            select(option.value)
                            return .handled
                        }
                        .onKeyPress(.tab) {
                            guard let nextProviderID = nextOptionID(after: option.value) else {
                                isExpanded = false
                                return .ignored
                            }
                            focusOption(nextProviderID)
                            return .handled
                        }
                        .onMoveCommand { direction in
                            moveFocus(direction)
                        }
                        .accessibilityValue(
                            selection == option.value
                                ? AppStrings.Common.selected.localized(locale: locale)
                                : AppStrings.Common.notSelected.localized(locale: locale)
                        )
                    }
                }
            }
            .frame(height: listViewportHeight)
            .onChange(of: focusedTarget) { _, focusedTarget in
                guard case let .option(providerID) = focusedTarget else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(providerID, anchor: .center)
                }
            }
        }
        .padding(6)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, alignment: .leading)
        .background(TerminalTheme.surface)
        .overlay {
            Rectangle()
                .strokeBorder(TerminalTheme.border.opacity(0.92), lineWidth: 1)
        }
        .onExitCommand {
            closePicker()
        }
    }

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title
            ?? AppStrings.Settings.Editor.selectProvider.localized(locale: locale)
    }

    private var listViewportHeight: CGFloat {
        min(max(CGFloat(options.count) * 30, 30), 216)
    }

    private func openPicker() {
        guard !options.isEmpty else { return }
        isExpanded = true
        focusedTarget = .trigger
    }

    private func togglePicker() {
        if isExpanded {
            closePicker()
        } else {
            openPicker()
        }
    }

    private func openPicker(focusing providerID: String?) {
        guard !options.isEmpty else { return }
        isExpanded = true
        focusOption(providerID ?? selection)
    }

    private func select(_ providerID: String) {
        selection = providerID
        closePicker()
    }

    private func closePicker() {
        isExpanded = false
        focusedTarget = .trigger
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        guard let providerID = optionID(after: direction) else { return }
        focusOption(providerID)
    }

    private func nextOptionID(after providerID: String) -> String? {
        guard let currentIndex = options.firstIndex(where: { $0.value == providerID }) else {
            return nil
        }
        let nextIndex = options.index(after: currentIndex)
        guard options.indices.contains(nextIndex) else { return nil }
        return options[nextIndex].value
    }

    private func optionID(after direction: MoveCommandDirection) -> String? {
        let currentProviderID: String
        if case let .option(providerID) = focusedTarget {
            currentProviderID = providerID
        } else {
            currentProviderID = selection
        }

        guard let currentIndex = options.firstIndex(where: { $0.value == currentProviderID }) else {
            return options.first?.value
        }

        let offset: Int
        switch direction {
        case .up, .left:
            offset = -1
        case .down, .right:
            offset = 1
        @unknown default:
            return currentProviderID
        }

        let nextIndex = min(max(currentIndex + offset, 0), options.count - 1)
        return options[nextIndex].value
    }

    private func focusOption(_ providerID: String) {
        guard options.contains(where: { $0.value == providerID }) else { return }
        Task { @MainActor in
            focusedTarget = .option(providerID)
        }
    }
}
