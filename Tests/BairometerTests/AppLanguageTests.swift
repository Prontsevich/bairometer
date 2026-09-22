import BairometerCore
import Foundation
import XCTest
@testable import Bairometer

@MainActor
final class AppLanguageTests: XCTestCase {
    func testLanguagesUseStableStorageValues() {
        XCTAssertEqual(AppLanguage.storageKey, "app-language")
        XCTAssertEqual(AppLanguage.systemDefault.rawValue, "system")
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.russian.rawValue, "ru")
    }

    func testSystemDefaultUsesProvidedSystemLocaleAndExplicitChoicesUseTheirLanguage() {
        let systemLocale = Locale(identifier: "ru_BY")

        XCTAssertEqual(
            AppLanguage.systemDefault.resolvedLocale(systemLocale: systemLocale).identifier,
            "ru_BY"
        )
        XCTAssertEqual(
            AppLanguage.english.resolvedLocale(systemLocale: systemLocale).identifier,
            "en"
        )
        XCTAssertEqual(
            AppLanguage.russian.resolvedLocale(systemLocale: systemLocale).identifier,
            "ru"
        )
    }

    func testPreferenceFallsBackToSystemDefaultAndPersistsSelection() {
        let (userDefaults, suiteName) = makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set("unsupported", forKey: AppLanguage.storageKey)
        let preference = AppLanguagePreference(
            userDefaults: userDefaults,
            systemLocaleProvider: { Locale(identifier: "en_US") }
        )
        XCTAssertEqual(preference.language, .systemDefault)
        XCTAssertEqual(preference.effectiveLocale.identifier, "en_US")

        preference.select(.russian)
        let restoredPreference = AppLanguagePreference(
            userDefaults: userDefaults,
            systemLocaleProvider: { Locale(identifier: "en_US") }
        )

        XCTAssertEqual(restoredPreference.language, .russian)
        XCTAssertEqual(restoredPreference.effectiveLocale.identifier, "ru")
    }

    func testEveryLanguageSelectionPersistsAcrossRelaunch() {
        let (userDefaults, suiteName) = makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        for language in AppLanguage.allCases {
            let preference = AppLanguagePreference(
                userDefaults: userDefaults,
                systemLocaleProvider: { Locale(identifier: "ru_BY") }
            )
            preference.select(language)

            XCTAssertEqual(userDefaults.string(forKey: AppLanguage.storageKey), language.rawValue)

            let restoredPreference = AppLanguagePreference(
                userDefaults: userDefaults,
                systemLocaleProvider: { Locale(identifier: "ru_BY") }
            )
            XCTAssertEqual(restoredPreference.language, language)
            XCTAssertEqual(
                restoredPreference.effectiveLocale.identifier,
                language.resolvedLocale(systemLocale: Locale(identifier: "ru_BY")).identifier
            )
        }
    }

    func testSystemDefaultRefreshesItsEffectiveLocale() {
        let (userDefaults, suiteName) = makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        var systemLocale = Locale(identifier: "ru_RU")
        let preference = AppLanguagePreference(
            userDefaults: userDefaults,
            systemLocaleProvider: { systemLocale }
        )

        systemLocale = Locale(identifier: "en_GB")
        preference.refreshSystemLocale()

        XCTAssertEqual(preference.effectiveLocale.identifier, "en_GB")
    }

    func testExplicitLanguageIgnoresSystemLocaleRefresh() {
        let (userDefaults, suiteName) = makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        var systemLocale = Locale(identifier: "en_US")
        let preference = AppLanguagePreference(
            userDefaults: userDefaults,
            systemLocaleProvider: { systemLocale }
        )
        preference.select(.russian)

        systemLocale = Locale(identifier: "en_GB")
        preference.refreshSystemLocale()

        XCTAssertEqual(preference.language, .russian)
        XCTAssertEqual(preference.effectiveLocale.identifier, "ru")
    }

    func testSelectionImmediatelyChangesLocalizedPresentation() {
        let (userDefaults, suiteName) = makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let preference = AppLanguagePreference(
            userDefaults: userDefaults,
            systemLocaleProvider: { Locale(identifier: "en_US") }
        )
        XCTAssertEqual(
            AppStrings.MenuBar.settings.localized(locale: preference.effectiveLocale),
            "Settings"
        )

        preference.select(.russian)

        XCTAssertEqual(
            AppStrings.MenuBar.settings.localized(locale: preference.effectiveLocale),
            "Настройки"
        )
        XCTAssertEqual(
            AppStrings.Settings.Language.title.localized(locale: preference.effectiveLocale),
            "ЯЗЫК"
        )
    }

    func testOpenRouterSheetsAndDetailsUseExplicitAppLanguageAgainstSystemLocale() {
        let (englishDefaults, englishSuiteName) = makeUserDefaults()
        let (russianDefaults, russianSuiteName) = makeUserDefaults()
        defer {
            englishDefaults.removePersistentDomain(forName: englishSuiteName)
            russianDefaults.removePersistentDomain(forName: russianSuiteName)
        }

        let englishPreference = AppLanguagePreference(
            userDefaults: englishDefaults,
            systemLocaleProvider: { Locale(identifier: "ru_RU") }
        )
        englishPreference.select(.english)
        let englishLocale = englishPreference.effectiveLocale
        let englishEditor = OpenRouterCredentialEditorPresentation(
            mode: .addOrdinary,
            locale: englishLocale
        )

        XCTAssertEqual(englishEditor.title, "Add key")
        XCTAssertEqual(englishEditor.fieldsetTitle, "KEY DETAILS")
        XCTAssertEqual(englishEditor.nameLabel, "Name")
        XCTAssertEqual(englishEditor.keyLabel, "Key")
        XCTAssertEqual(englishEditor.keyPlaceholder, "Paste key")
        XCTAssertEqual(englishEditor.cancelButtonTitle, "Cancel")
        XCTAssertEqual(englishEditor.saveButtonTitle, "Save")
        XCTAssertEqual(
            AppStrings.OpenRouter.dailyUsage.localized(locale: englishLocale),
            "Daily usage"
        )
        XCTAssertEqual(
            AppStrings.OpenRouter.remaining.formatted(
                locale: englishLocale,
                "$12.2"
            ),
            "$12.2 left"
        )
        XCTAssertEqual(
            AppStrings.OpenRouter.resets.formatted(
                locale: englishLocale,
                "in 1 hour"
            ),
            "Resets in 1 hour"
        )
        XCTAssertEqual(
            AppStrings.OpenRouter.updated.formatted(
                locale: englishLocale,
                "today"
            ),
            "Updated today"
        )

        let russianPreference = AppLanguagePreference(
            userDefaults: russianDefaults,
            systemLocaleProvider: { Locale(identifier: "en_US") }
        )
        russianPreference.select(.russian)
        let russianLocale = russianPreference.effectiveLocale
        let russianEditor = OpenRouterCredentialEditorPresentation(
            mode: .addManagement,
            locale: russianLocale
        )

        XCTAssertEqual(russianEditor.title, "Добавить management-ключ")
        XCTAssertEqual(russianEditor.fieldsetTitle, "ДАННЫЕ КЛЮЧА")
        XCTAssertNil(russianEditor.nameLabel)
        XCTAssertEqual(russianEditor.keyLabel, "Ключ")
        XCTAssertEqual(russianEditor.keyPlaceholder, "Вставьте ключ")
        XCTAssertEqual(russianEditor.cancelButtonTitle, "Отмена")
        XCTAssertEqual(russianEditor.saveButtonTitle, "Сохранить")
        XCTAssertEqual(
            AppStrings.OpenRouter.dailyUsage.localized(locale: russianLocale),
            "Расход за день"
        )
        XCTAssertEqual(
            AppStrings.OpenRouter.remaining.formatted(
                locale: russianLocale,
                "$12,2"
            ),
            "Осталось $12,2"
        )
        XCTAssertEqual(
            AppStrings.OpenRouter.resets.formatted(
                locale: russianLocale,
                "через 1 час"
            ),
            "Сброс через 1 час"
        )
        XCTAssertEqual(
            AppStrings.OpenRouter.updated.formatted(
                locale: russianLocale,
                "сегодня"
            ),
            "Обновлено сегодня"
        )
    }

    func testLanguageSelectionPreservesDashboardAndRefreshPreferencesAcrossRelaunch() throws {
        let (userDefaults, suiteName) = makeUserDefaults()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLanguageTests.\(UUID().uuidString)", isDirectory: true)
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        userDefaults.set(DashboardHeightPreset.tall.rawValue, forKey: DashboardHeightPreset.storageKey)
        let preference = AppLanguagePreference(
            userDefaults: userDefaults,
            systemLocaleProvider: { Locale(identifier: "en_US") }
        )
        let model = AppModel(storageDirectory: directory)

        model.setRefreshInterval(.thirtyMinutes)
        preference.select(.russian)

        let restoredPreference = AppLanguagePreference(
            userDefaults: userDefaults,
            systemLocaleProvider: { Locale(identifier: "en_US") }
        )
        let restoredModel = AppModel(storageDirectory: directory)

        XCTAssertEqual(restoredPreference.language, .russian)
        XCTAssertEqual(restoredPreference.effectiveLocale.identifier, "ru")
        XCTAssertEqual(
            userDefaults.string(forKey: DashboardHeightPreset.storageKey),
            DashboardHeightPreset.tall.rawValue
        )
        XCTAssertEqual(restoredModel.refreshSettings.interval, .thirtyMinutes)
    }

    private func makeUserDefaults() -> (UserDefaults, String) {
        let suiteName = "AppLanguageTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated test user defaults")
        }
        userDefaults.removePersistentDomain(forName: suiteName)
        return (userDefaults, suiteName)
    }
}
