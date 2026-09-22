import AppKit
import Combine
import SwiftUI

enum ApplicationLifecycle {
    @MainActor
    private static var directSettingsWindowController: NSWindowController?

    @MainActor
    private static var directOllamaWindowController: NSWindowController?

    @MainActor
    private static var directAboutWindowController: NSWindowController?

    @MainActor
    private static var directSettingsWindowTitleObservation: AnyCancellable?

    @MainActor
    private static var directOllamaWindowTitleObservation: AnyCancellable?

    @MainActor
    private static var directAboutWindowTitleObservation: AnyCancellable?

    @MainActor
    static func activate() {
        NSApplication.shared.activate()
    }

    @MainActor
    static func openSettings(using openWindow: OpenWindowAction) {
        if let settingsWindow = visibleSettingsWindow() {
            activate()
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let targetVisibleRect = menuBarPanelVisibleRect()
        activate()
        openWindow(id: SettingsWindowConfiguration.id)

        guard let targetVisibleRect else { return }
        centerNewSettingsWindow(in: targetVisibleRect, attemptsRemaining: 3)
    }

    @MainActor
    static func openSettings(
        appModel: AppModel,
        appLanguagePreference: AppLanguagePreference
    ) {
        if let settingsWindow = visibleSettingsWindow() {
            activate()
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(
            rootView: AppLocaleScope(languagePreference: appLanguagePreference) {
                SettingsView(
                    appModel: appModel,
                    appLanguagePreference: appLanguagePreference
                )
            }
        )
        let window = NSWindow(contentViewController: hostingController)
        observeWindowTitle(
            window,
            preference: appLanguagePreference,
            title: { AppStrings.Window.settingsTitle.localized(locale: $0) },
            storeIn: &directSettingsWindowTitleObservation
        )
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(SettingsWindowConfiguration.preferredSize)
        window.contentMinSize = SettingsWindowConfiguration.preferredSize

        let controller = NSWindowController(window: window)
        directSettingsWindowController = controller

        activate()
        controller.showWindow(nil)
        if let visibleRect = menuBarPanelVisibleRect() {
            window.setFrame(
                SettingsWindowConfiguration.centeredWindowFrame(window.frame, in: visibleRect),
                display: true
            )
        }
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    static func openOllamaConnection(using openWindow: OpenWindowAction) {
        activate()

        if let connectionWindow = visibleOllamaConnectionWindow() {
            connectionWindow.makeKeyAndOrderFront(nil)
            return
        }

        openWindow(id: OllamaConnectionWindowConfiguration.id)
        DispatchQueue.main.async {
            visibleOllamaConnectionWindow()?.makeKeyAndOrderFront(nil)
        }
    }

    @MainActor
    static func openOllamaConnection(
        appModel: AppModel,
        appLanguagePreference: AppLanguagePreference
    ) {
        activate()

        if let connectionWindow = visibleOllamaConnectionWindow() {
            connectionWindow.makeKeyAndOrderFront(nil)
            return
        }

        var controller: NSWindowController?
        let rootView = AppLocaleScope(languagePreference: appLanguagePreference) {
            OllamaWebPageConnectionWindow(
                appModel: appModel,
                dismiss: {
                    controller?.close()
                }
            )
        }
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        observeWindowTitle(
            window,
            preference: appLanguagePreference,
            title: { AppStrings.Window.ollamaTitle.localized(locale: $0) },
            storeIn: &directOllamaWindowTitleObservation
        )
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(OllamaConnectionWindowConfiguration.preferredSize)

        controller = NSWindowController(window: window)
        directOllamaWindowController = controller
        controller?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    static func openAbout(appLanguagePreference: AppLanguagePreference) {
        let targetVisibleRect = menuBarPanelVisibleRect()
        activate()

        if let controller = directAboutWindowController, let window = controller.window {
            let wasVisible = window.isVisible
            controller.showWindow(nil)
            if !wasVisible, let targetVisibleRect {
                window.setFrame(
                    AboutWindowConfiguration.centeredWindowFrame(
                        window.frame,
                        in: targetVisibleRect
                    ),
                    display: true
                )
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(
            rootView: AppLocaleScope(languagePreference: appLanguagePreference) {
                AboutView()
            }
        )
        let window = NSWindow(contentViewController: hostingController)
        observeWindowTitle(
            window,
            preference: appLanguagePreference,
            title: { AppStrings.Window.aboutTitle.localized(locale: $0) },
            storeIn: &directAboutWindowTitleObservation
        )
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.setContentSize(AboutWindowConfiguration.preferredSize)
        window.contentMinSize = AboutWindowConfiguration.preferredSize
        window.contentMaxSize = AboutWindowConfiguration.preferredSize

        let controller = NSWindowController(window: window)
        directAboutWindowController = controller
        controller.showWindow(nil)
        if let targetVisibleRect {
            window.setFrame(
                AboutWindowConfiguration.centeredWindowFrame(window.frame, in: targetVisibleRect),
                display: true
            )
        }
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    static func terminate() {
        NSApplication.shared.terminate(nil)
    }

    @MainActor
    private static func menuBarPanelVisibleRect() -> CGRect? {
        if let screen = NSApplication.shared.keyWindow?.screen ?? NSApplication.shared.mainWindow?.screen {
            return screen.visibleFrame
        }

        let pointerLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(pointerLocation)
        }?.visibleFrame ?? NSScreen.main?.visibleFrame
    }

    @MainActor
    private static func visibleSettingsWindow() -> NSWindow? {
        NSApplication.shared.windows.first { window in
            SettingsWindowConfiguration.matchesTitle(window.title) && window.isVisible
        }
    }

    @MainActor
    private static func visibleOllamaConnectionWindow() -> NSWindow? {
        NSApplication.shared.windows.first { window in
            OllamaConnectionWindowConfiguration.matchesTitle(window.title) && window.isVisible
        }
    }

    @MainActor
    private static func settingsWindow() -> NSWindow? {
        NSApplication.shared.windows.first { window in
            SettingsWindowConfiguration.matchesTitle(window.title)
        }
    }

    @MainActor
    private static func observeWindowTitle(
        _ window: NSWindow,
        preference: AppLanguagePreference,
        title: @escaping (Locale) -> String,
        storeIn observation: inout AnyCancellable?
    ) {
        window.title = title(preference.effectiveLocale)
        observation = preference.$effectiveLocale.sink { [weak window] locale in
            window?.title = title(locale)
        }
    }

    @MainActor
    private static func centerNewSettingsWindow(in visibleRect: CGRect, attemptsRemaining: Int) {
        DispatchQueue.main.async {
            guard let settingsWindow = settingsWindow() else {
                guard attemptsRemaining > 1 else { return }
                centerNewSettingsWindow(
                    in: visibleRect,
                    attemptsRemaining: attemptsRemaining - 1
                )
                return
            }

            let centeredFrame = SettingsWindowConfiguration.centeredWindowFrame(
                settingsWindow.frame,
                in: visibleRect
            )
            settingsWindow.setFrame(centeredFrame, display: true)
            settingsWindow.makeKeyAndOrderFront(nil)
        }
    }
}
