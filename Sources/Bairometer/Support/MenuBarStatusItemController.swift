import AppKit
import Combine
import SwiftUI

@MainActor
protocol MenuBarPopoverPresenting: AnyObject {
    var isShown: Bool { get }

    func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge
    )

    func performClose(_ sender: Any?)
}

extension NSPopover: MenuBarPopoverPresenting {}

@MainActor
protocol MenuBarPopoverAnchorHosting: AnyObject {
    var screenRect: NSRect { get }
    var positioningView: NSView { get }
    var positioningRect: NSRect { get }

    func tearDown()
}

@MainActor
protocol MenuBarPopoverAnchorHostFactory {
    func makeAnchorHost(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView
    ) -> (any MenuBarPopoverAnchorHosting)?
}

@MainActor
enum MenuBarPopoverAnchorGeometry {
    static func screenRect(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView
    ) -> NSRect? {
        guard let window = positioningView.window else { return nil }
        let windowRect = positioningView.convert(positioningRect, to: nil)
        let screenRect = window.convertToScreen(windowRect)
        guard screenRect.origin.x.isFinite,
              screenRect.origin.y.isFinite,
              screenRect.width.isFinite,
              screenRect.height.isFinite,
              screenRect.width > 0,
              screenRect.height > 0 else {
            return nil
        }
        return screenRect
    }
}

@MainActor
struct SystemMenuBarPopoverAnchorHostFactory:
    MenuBarPopoverAnchorHostFactory
{
    func makeAnchorHost(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView
    ) -> (any MenuBarPopoverAnchorHosting)? {
        guard let screenRect = MenuBarPopoverAnchorGeometry.screenRect(
            relativeTo: positioningRect,
            of: positioningView
        ) else {
            return nil
        }
        return MenuBarPopoverAnchorHost(screenRect: screenRect)
    }
}

@MainActor
final class MenuBarPopoverAnchorHost: MenuBarPopoverAnchorHosting {
    let screenRect: NSRect
    let positioningView: NSView
    private var panel: MenuBarPopoverAnchorPanel?

    var positioningRect: NSRect {
        positioningView.bounds
    }

    init(screenRect: NSRect) {
        self.screenRect = screenRect
        positioningView = NSView(
            frame: NSRect(origin: .zero, size: screenRect.size)
        )

        let panel = MenuBarPopoverAnchorPanel(
            contentRect: screenRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isMovable = false
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.contentView = positioningView
        panel.setFrame(screenRect, display: false)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func tearDown() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
    }

    isolated deinit {
        panel?.orderOut(nil)
    }

#if DEBUG
    var panelForTesting: NSPanel? {
        panel
    }
#endif
}

@MainActor
private final class MenuBarPopoverAnchorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MenuBarStatusItemController: NSObject, ObservableObject, NSPopoverDelegate {
    static let actionEventMask: NSEvent.EventTypeMask = [.leftMouseDown]

    private let appModel: AppModel
    private let appLanguagePreference: AppLanguagePreference
    private let retainedStatusItem: NSStatusItem?
    private let statusButton: NSStatusBarButton
    private let popover: NSPopover
    private let popoverPresenter: any MenuBarPopoverPresenting
    private let popoverAnchorFactory: any MenuBarPopoverAnchorHostFactory
    private let panelPresentation: MenuBarPanelPresentationState
    private let hostingController: NSHostingController<AppLocaleScope<MenuBarPanelView>>
    private var modelObservation: AnyCancellable?
    private var languageObservation: AnyCancellable?
    private var appearanceObservation: NSKeyValueObservation?
    private var preDismissMouseDownMonitor: MenuBarPreDismissMouseDownMonitor?
    private var preDismissVisibilityLatch = MenuBarPreDismissVisibilityLatch()
    private var activePopoverAnchor: (any MenuBarPopoverAnchorHosting)?
    private var isPopoverClosePending = false

    convenience init(
        appModel: AppModel,
        appLanguagePreference: AppLanguagePreference
    ) {
        let statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        guard let statusButton = statusItem.button else {
            preconditionFailure("NSStatusItem did not provide a status bar button")
        }
        self.init(
            appModel: appModel,
            appLanguagePreference: appLanguagePreference,
            retainedStatusItem: statusItem,
            statusButton: statusButton,
            popover: NSPopover(),
            popoverPresenter: nil,
            popoverAnchorFactory: SystemMenuBarPopoverAnchorHostFactory(),
            panelPresentation: MenuBarPanelPresentationState(),
            observesExternalState: true
        )
    }

    private init(
        appModel: AppModel,
        appLanguagePreference: AppLanguagePreference,
        retainedStatusItem: NSStatusItem?,
        statusButton: NSStatusBarButton,
        popover: NSPopover,
        popoverPresenter: (any MenuBarPopoverPresenting)?,
        popoverAnchorFactory: any MenuBarPopoverAnchorHostFactory,
        panelPresentation: MenuBarPanelPresentationState,
        observesExternalState: Bool
    ) {
        self.appModel = appModel
        self.appLanguagePreference = appLanguagePreference
        self.retainedStatusItem = retainedStatusItem
        self.statusButton = statusButton
        self.popover = popover
        if let popoverPresenter {
            self.popoverPresenter = popoverPresenter
        } else {
            self.popoverPresenter = popover
        }
        self.popoverAnchorFactory = popoverAnchorFactory
        self.panelPresentation = panelPresentation
        hostingController = NSHostingController(
            rootView: AppLocaleScope(languagePreference: appLanguagePreference) {
                MenuBarPanelView(
                    appModel: appModel,
                    onOpenSettings: { [weak appModel, weak appLanguagePreference] in
                        guard let appModel, let appLanguagePreference else { return }
                        ApplicationLifecycle.openSettings(
                            appModel: appModel,
                            appLanguagePreference: appLanguagePreference
                        )
                    },
                    onOpenAbout: { [weak appLanguagePreference] in
                        guard let appLanguagePreference else { return }
                        ApplicationLifecycle.openAbout(appLanguagePreference: appLanguagePreference)
                    },
                    onOpenOllamaConnection: { [weak appModel, weak appLanguagePreference] in
                        guard let appModel, let appLanguagePreference else { return }
                        ApplicationLifecycle.openOllamaConnection(
                            appModel: appModel,
                            appLanguagePreference: appLanguagePreference
                        )
                    },
                    onCloseDashboard: { [weak popover] in
                        popover?.performClose(nil)
                    },
                    panelPresentation: panelPresentation
                )
            }
        )
        super.init()
        configureStatusItem()
        configurePopover()
        if observesExternalState {
            observeModel()
            observeAppearance()
            observePreDismissMouseDown()
        }
        refresh()
    }

#if DEBUG
    convenience init(
        appModelForTesting appModel: AppModel,
        appLanguagePreference: AppLanguagePreference,
        statusButton: NSStatusBarButton,
        popoverPresenter: any MenuBarPopoverPresenting,
        popoverAnchorFactory: any MenuBarPopoverAnchorHostFactory,
        panelPresentation: MenuBarPanelPresentationState
    ) {
        self.init(
            appModel: appModel,
            appLanguagePreference: appLanguagePreference,
            retainedStatusItem: nil,
            statusButton: statusButton,
            popover: NSPopover(),
            popoverPresenter: popoverPresenter,
            popoverAnchorFactory: popoverAnchorFactory,
            panelPresentation: panelPresentation,
            observesExternalState: false
        )
    }

    var popoverBehaviorForTesting: NSPopover.Behavior {
        popover.behavior
    }
#endif

    private func configureStatusItem() {
        statusButton.imagePosition = .imageOnly
        statusButton.imageScaling = .scaleProportionallyDown
        statusButton.title = ""
        statusButton.target = self
        statusButton.action = #selector(togglePopover(_:))
        statusButton.sendAction(on: Self.actionEventMask)
        statusButton.setAccessibilityLabel("Bairometer")
        statusButton.toolTip = "Bairometer"
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hostingController
    }

    private func observeModel() {
        modelObservation = appModel.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        languageObservation = appLanguagePreference.$effectiveLocale.sink { [weak self] _ in
            self?.refresh()
        }
    }

    private func observeAppearance() {
        appearanceObservation = NSApplication.shared.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        statusButton.image = MenuBarStatusItemImageRenderer.image(
            for: appModel.menuBarIndicatorState
        )
        statusButton.setAccessibilityValue(
            appModel.menuBarAccessibilityValue(locale: appLanguagePreference.effectiveLocale)
        )
    }

    @objc private func togglePopover(_ sender: Any?) {
        handleStatusItemAction(
            sender: sender as? NSStatusBarButton,
            eventType: NSApplication.shared.currentEvent?.type
        )
    }

    func handleStatusItemAction(
        sender: NSStatusBarButton?,
        eventType: NSEvent.EventType?
    ) {
        guard Self.handlesActionEvent(eventType) else { return }
        let anchorButton = sender ?? statusButton

        switch MenuBarPopoverToggleCoordinator.decision(
            wasVisibleAtMouseDown: preDismissVisibilityLatch.consume(
                for: eventType
            ),
            isPresentationVisible: panelPresentation.isVisible,
            isPopoverShown: popoverPresenter.isShown
        ) {
        case .closeOnly:
            if popoverPresenter.isShown {
                isPopoverClosePending = true
                popoverPresenter.performClose(sender)
            } else if !isPopoverClosePending {
                panelPresentation.isVisible = false
                releasePopoverAnchor()
            }
            return

        case .open:
            isPopoverClosePending = false
            releasePopoverAnchor()
            guard let anchorHost = popoverAnchorFactory.makeAnchorHost(
                relativeTo: anchorButton.bounds,
                of: anchorButton
            ) else {
                panelPresentation.isVisible = false
                return
            }
            activePopoverAnchor = anchorHost
            AppTelemetry.menuBar.info("Dashboard popover opening")
            popoverPresenter.show(
                relativeTo: anchorHost.positioningRect,
                of: anchorHost.positioningView,
                preferredEdge: .minY
            )
            guard popoverPresenter.isShown else {
                panelPresentation.isVisible = false
                releasePopoverAnchor()
                return
            }
            panelPresentation.isVisible = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.hostingController.view.layoutSubtreeIfNeeded()
                self.popover.contentSize = self.hostingController.view.fittingSize
                self.activatePopoverForKeyboardInput()
            }
        }
    }

    static func handlesActionEvent(_ eventType: NSEvent.EventType?) -> Bool {
        switch eventType {
        case .leftMouseUp, .rightMouseDown, .rightMouseUp:
            false
        default:
            true
        }
    }

    func handlePreDismissEvent(_ eventType: NSEvent.EventType) {
        guard eventType == .leftMouseDown else { return }
        let generation = preDismissVisibilityLatch.beginEvent(
            isVisible: panelPresentation.isVisible || popoverPresenter.isShown
        )
        DispatchQueue.main.async { [weak self] in
            self?.preDismissVisibilityLatch.expire(generation: generation)
        }
    }

    private func observePreDismissMouseDown() {
        preDismissMouseDownMonitor = MenuBarPreDismissMouseDownMonitor {
            [weak self] eventType in
            self?.handlePreDismissEvent(eventType)
        }
    }

    private func releasePopoverAnchor() {
        activePopoverAnchor?.tearDown()
        activePopoverAnchor = nil
    }

    private func activatePopoverForKeyboardInput() {
        guard popover.isShown, let popoverWindow = hostingController.view.window else { return }

        NSApp.activate(ignoringOtherApps: true)
        popoverWindow.makeKey()
        let acceptedResponder = panelPresentation.keyboardResponder.map {
            popoverWindow.makeFirstResponder($0)
        } ?? false
        AppTelemetry.menuBar.info(
            "Dashboard keyboard activated: keyWindow=\(popoverWindow.isKeyWindow), responderAccepted=\(acceptedResponder)"
        )
    }

    func popoverWillClose(_ notification: Notification) {
        isPopoverClosePending = true
    }

    func popoverDidClose(_ notification: Notification) {
        isPopoverClosePending = false
        panelPresentation.isVisible = false
        releasePopoverAnchor()
        AppTelemetry.menuBar.info("Dashboard popover closed")
    }

    isolated deinit {
        activePopoverAnchor?.tearDown()
    }
}

@MainActor
final class MenuBarPanelPresentationState: ObservableObject {
    @Published var isVisible = false
    weak var keyboardResponder: NSView?
}

enum MenuBarPopoverToggleDecision: Equatable {
    case open
    case closeOnly
}

enum MenuBarPopoverToggleCoordinator {
    static func decision(
        wasVisibleAtMouseDown: Bool = false,
        isPresentationVisible: Bool,
        isPopoverShown: Bool
    ) -> MenuBarPopoverToggleDecision {
        wasVisibleAtMouseDown || isPresentationVisible || isPopoverShown
            ? .closeOnly
            : .open
    }
}

struct MenuBarPreDismissVisibilityLatch {
    private var generation: UInt = 0
    private var wasVisibleAtMouseDown = false

    mutating func beginEvent(isVisible: Bool) -> UInt {
        generation &+= 1
        wasVisibleAtMouseDown = isVisible
        return generation
    }

    mutating func consume(for eventType: NSEvent.EventType?) -> Bool {
        guard eventType == .leftMouseDown else { return false }
        defer { wasVisibleAtMouseDown = false }
        return wasVisibleAtMouseDown
    }

    mutating func expire(generation expiredGeneration: UInt) {
        guard generation == expiredGeneration else { return }
        wasVisibleAtMouseDown = false
    }
}

@MainActor
final class MenuBarPreDismissMouseDownMonitor {
    private final class Token: @unchecked Sendable {
        let value: Any

        init(_ value: Any) {
            self.value = value
        }
    }

    private var token: Token?

    init(onMouseDown: @escaping @MainActor (NSEvent.EventType) -> Void) {
        token = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            event in
            MainActor.assumeIsolated {
                onMouseDown(event.type)
            }
            return event
        }.map(Token.init)
    }

    deinit {
        if let token {
            NSEvent.removeMonitor(token.value)
        }
    }
}

enum MenuBarStatusItemImageRenderer {
    static let baseSystemImageName = "gauge.with.dots.needle.33percent"

    private static let canvasSize = NSSize(width: 20, height: 20)

    static func image(for state: MenuBarIndicatorState) -> NSImage {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        drawBaseIcon(in: image)

        switch state {
        case .normal:
            break
        case .warning:
            drawBadge(color: TerminalTheme.warningNSColor)
        case .error:
            drawBadge(color: TerminalTheme.errorNSColor)
        }

        image.isTemplate = false
        return image
    }

    private static func drawBaseIcon(in image: NSImage) {
        guard let symbol = NSImage(systemSymbolName: baseSystemImageName, accessibilityDescription: nil) else {
            return
        }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: 18,
            weight: .regular
        ).applying(
            NSImage.SymbolConfiguration(paletteColors: [NSColor.controlTextColor])
        )
        let configuredSymbol = symbol.withSymbolConfiguration(configuration) ?? symbol
        configuredSymbol.draw(
            in: NSRect(x: 0.5, y: 0.5, width: 19, height: 19),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    private static func drawBadge(color: NSColor) {
        let badgeRect = NSRect(x: 13.5, y: 13.5, width: 6, height: 6)

        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(ovalIn: badgeRect.insetBy(dx: -0.8, dy: -0.8)).fill()

        color.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
    }
}
