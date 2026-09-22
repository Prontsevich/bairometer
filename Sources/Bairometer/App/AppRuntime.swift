import BairometerCore
import Foundation

@MainActor
final class AppRuntime: ObservableObject {
    let appModel: AppModel
    let appLanguagePreference: AppLanguagePreference

    private let menuBarStatusItemController: MenuBarStatusItemController?

    var ownsMenuBarStatusItemController: Bool {
        menuBarStatusItemController != nil
    }

#if DEBUG
    let uiTestHostConfiguration: UITestHostConfiguration?
    let uiTestHostSession: UITestHostSession?
#endif

    init(launchOptions: AppLaunchOptions = AppLaunchOptions()) {
#if DEBUG
        if let configuration = launchOptions.uiTestHostConfiguration {
            do {
                let session = try UITestHostSession(
                    storageDirectory: launchOptions.storageDirectory
                )
                let fixture = UITestHostFixture.make(
                    scenario: configuration.scenario,
                    anchor: Date()
                )
                session.userDefaults.set(
                    configuration.dashboardHeight.rawValue,
                    forKey: DashboardHeightPreset.storageKey
                )

                let languagePreference = AppLanguagePreference(
                    userDefaults: session.userDefaults,
                    systemLocaleProvider: { Locale(identifier: "en") }
                )
                languagePreference.select(configuration.language.appLanguage)

                let model = AppModel(
                    registry: ProviderRegistry(adapters: fixture.adapters),
                    storageDirectory: session.storageDirectory,
                    userDefaults: session.userDefaults,
                    refreshCoordinator: ProviderRefreshCoordinator(
                        retryPolicy: ProviderRetryPolicy(maxAttempts: 1, initialDelay: 0)
                    )
                )
                fixture.apply(to: model)

                appModel = model
                appLanguagePreference = languagePreference
                menuBarStatusItemController = nil
                uiTestHostConfiguration = configuration
                uiTestHostSession = session
                return
            } catch {
                fatalError("Unable to create UI test host session: \(error)")
            }
        }
#endif

        let ollamaClient = OllamaWebPageClientController()
        let languagePreference = AppLanguagePreference()
        let model = AppModel(
            ollamaWebPageClient: ollamaClient,
            storageDirectory: launchOptions.storageDirectory
        )
        appModel = model
        appLanguagePreference = languagePreference
        menuBarStatusItemController = MenuBarStatusItemController(
            appModel: model,
            appLanguagePreference: languagePreference
        )
#if DEBUG
        uiTestHostConfiguration = nil
        uiTestHostSession = nil
#endif
    }

#if DEBUG
    init(appModelForTesting appModel: AppModel) {
        self.appModel = appModel
        appLanguagePreference = AppLanguagePreference(
            userDefaults: appModel.userDefaults
        )
        menuBarStatusItemController = nil
        uiTestHostConfiguration = nil
        uiTestHostSession = nil
    }
#endif

    func start() {
#if DEBUG
        guard uiTestHostConfiguration == nil else { return }
#endif
        appModel.startLaunchRefresh()
    }
}
