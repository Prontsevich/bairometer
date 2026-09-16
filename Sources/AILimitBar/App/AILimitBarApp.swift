import SwiftUI

@main
struct AILimitBarApp: App {
    @StateObject private var runtime: AppRuntime

    init() {
#if DEBUG
        if let verification = KeychainVerificationCommand.parse() {
            verification.runAndExit()
        }
        if let verification = OpenRouterVerificationCommand.parse() {
            verification.runAndExit()
        }
#endif
        let runtime = AppRuntime()
        _runtime = StateObject(wrappedValue: runtime)
        runtime.start()
    }

    @SceneBuilder
    var body: some Scene {
#if DEBUG
        Window(
            "Bairometer UI Test Host — \(runtime.uiTestHostConfiguration?.scenario.rawValue ?? "disabled")",
            id: UITestHostConfiguration.windowID
        ) {
            if let configuration = runtime.uiTestHostConfiguration,
               let session = runtime.uiTestHostSession {
                UITestHostRootView(
                    appModel: runtime.appModel,
                    appLanguagePreference: runtime.appLanguagePreference,
                    configuration: configuration,
                    userDefaults: session.userDefaults
                )
            } else {
                EmptyView()
            }
        }
        .defaultLaunchBehavior(
            runtime.uiTestHostConfiguration == nil ? .suppressed : .presented
        )
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
#endif
        productionScenes
    }

    @SceneBuilder
    private var productionScenes: some Scene {
        Window(
            AppStrings.Window.settingsTitle.localized(
                locale: runtime.appLanguagePreference.effectiveLocale
            ),
            id: SettingsWindowConfiguration.id
        ) {
            AppLocaleScope(languagePreference: runtime.appLanguagePreference) {
                SettingsView(
                    appModel: runtime.appModel,
                    appLanguagePreference: runtime.appLanguagePreference
                )
            }
                .windowMinimizeBehavior(.disabled)
                .windowResizeBehavior(.disabled)
                .windowFullScreenBehavior(.disabled)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
        .defaultWindowPlacement { content, context in
            let contentSize = content.sizeThatFits(.unspecified)
            let placement = SettingsWindowConfiguration.defaultPlacement(
                contentSize: contentSize,
                visibleRect: context.defaultDisplay.visibleRect
            )
            return WindowPlacement(placement.position, size: placement.size)
        }

        Window(
            AppStrings.Window.ollamaTitle.localized(
                locale: runtime.appLanguagePreference.effectiveLocale
            ),
            id: OllamaConnectionWindowConfiguration.id
        ) {
            AppLocaleScope(languagePreference: runtime.appLanguagePreference) {
                OllamaWebPageConnectionWindow(appModel: runtime.appModel)
            }
                .windowMinimizeBehavior(.disabled)
                .windowResizeBehavior(.disabled)
                .windowFullScreenBehavior(.disabled)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
        .defaultWindowPlacement { content, context in
            let size = OllamaConnectionWindowConfiguration.defaultSize(
                contentSize: content.sizeThatFits(.unspecified),
                visibleRect: context.defaultDisplay.visibleRect
            )
            return WindowPlacement(size: size)
        }
    }
}
