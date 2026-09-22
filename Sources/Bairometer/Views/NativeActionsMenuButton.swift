import AppKit
import SwiftUI

struct NativeActionsMenuButton: View {
    @Environment(\.locale) private var locale
    let isTestEnabled: Bool
    let isUsageEnabled: Bool
    let onTest: () -> Void
    let onOpenUsage: () -> Void

    var body: some View {
        let accessibilityLabel =
            AppStrings.Settings.Editor.moreActions.localized(locale: locale)
        NativeMenuButton(
            accessibilityLabel: accessibilityLabel,
            actions: [
                NativeMenuAction(
                    id: "test",
                    title: AppStrings.AccountDetails.testConnection.localized(
                        locale: locale
                    ),
                    systemImage: "checkmark.circle",
                    isEnabled: isTestEnabled,
                    action: onTest
                ),
                NativeMenuAction(
                    id: "usage",
                    title: AppStrings.AccountDetails.openUsage.localized(
                        locale: locale
                    ),
                    systemImage: "arrow.up.forward.square",
                    isEnabled: isUsageEnabled,
                    action: onOpenUsage
                ),
            ]
        )
    }
}

enum NativeMenuActionRole: Equatable {
    case standard
    case destructive
}

struct NativeMenuAction {
    let id: String
    let title: String?
    let systemImage: String?
    let isEnabled: Bool
    let role: NativeMenuActionRole
    let action: (() -> Void)?

    init(
        id: String,
        title: String,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        role: NativeMenuActionRole = .standard,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.role = role
        self.action = action
    }

    static func separator(id: String) -> NativeMenuAction {
        NativeMenuAction(
            id: id,
            title: nil,
            systemImage: nil,
            isEnabled: false,
            role: .standard,
            action: nil
        )
    }

    private init(
        id: String,
        title: String?,
        systemImage: String?,
        isEnabled: Bool,
        role: NativeMenuActionRole,
        action: (() -> Void)?
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.role = role
        self.action = action
    }
}

struct NativeMenuButton: View {
    let accessibilityLabel: String
    let actions: [NativeMenuAction]
    @State private var menuRequest: UInt = 0

    var body: some View {
        ZStack {
            Button {
                menuRequest &+= 1
            } label: {
                SettingsActionIcon(systemName: "ellipsis", verticalOffset: -1)
            }
            .settingsIconButton(help: accessibilityLabel)
            .accessibilityLabel(accessibilityLabel)

            NativeMenuAnchor(
                request: $menuRequest,
                actions: actions
            )
            .frame(width: 40, height: 40)
            .allowsHitTesting(false)
        }
    }
}

private struct NativeMenuAnchor: NSViewRepresentable {
    @Binding var request: UInt
    let actions: [NativeMenuAction]

    func makeCoordinator() -> NativeMenuCoordinator {
        NativeMenuCoordinator()
    }

    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        context.coordinator.update(actions: actions)

        guard request != context.coordinator.lastRequest else { return }
        context.coordinator.lastRequest = request
        DispatchQueue.main.async {
            context.coordinator.present(from: nsView)
        }
    }

    final class AnchorView: NSView {
        override var isOpaque: Bool { false }
    }
}

@MainActor
struct NativeMenuPopupRunner {
    let run: (NativeMenuPresentation) -> Void

    static let appKit = NativeMenuPopupRunner { presentation in
        presentation.menu.popUp(
            positioning: nil,
            at: NSEvent.mouseLocation,
            in: nil
        )
    }
}

@MainActor
final class NativeMenuCoordinator: NSObject {
    var lastRequest: UInt = 0
    private var actions: [NativeMenuAction] = []
    private var isPresenting = false

    func update(actions: [NativeMenuAction]) {
        self.actions = actions
    }

    func present(
        from view: NSView,
        using popupRunner: NativeMenuPopupRunner = .appKit
    ) {
        guard !isPresenting else { return }
        isPresenting = true
        defer { isPresenting = false }

        let presentation = NativeMenuPresentation(actions: actions)
        defer { presentation.releaseActionTargets() }
        withExtendedLifetime(presentation) {
            popupRunner.run(presentation)
        }
    }
}

@MainActor
final class NativeMenuPresentation {
    let menu: NSMenu
    private var targets: [String: MenuActionTarget]

    init(actions: [NativeMenuAction]) {
        let targets = Dictionary(
            uniqueKeysWithValues: actions.compactMap { action in
                action.action.map {
                    (
                        action.id,
                        MenuActionTarget(action: $0)
                    )
                }
            }
        )
        let menu = NSMenu()
        menu.autoenablesItems = false

        for action in actions {
            guard let title = action.title else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(
                title: title,
                action: #selector(MenuActionTarget.invoke(_:)),
                keyEquivalent: ""
            )
            item.target = targets[action.id]
            item.isEnabled = action.isEnabled
            item.image = action.systemImage.flatMap {
                NSImage(
                    systemSymbolName: $0,
                    accessibilityDescription: nil
                )
            }
            if action.role == .destructive {
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
            }
            menu.addItem(item)
        }

        self.menu = menu
        self.targets = targets
    }

    fileprivate func releaseActionTargets() {
        for item in menu.items {
            item.target = nil
        }
        targets.removeAll(keepingCapacity: false)
    }
}

@MainActor
final class MenuActionTarget: NSObject {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke(_ sender: Any?) {
        action()
    }
}
