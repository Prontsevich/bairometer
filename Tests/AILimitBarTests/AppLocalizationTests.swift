import Foundation
import XCTest
@testable import AILimitBar

final class AppLocalizationTests: XCTestCase {
    func testLocalizationCatalogsHaveMatchingKeysValuesAndFormatSpecifiers() throws {
        let english = try localizationTable(for: "en")
        let russian = try localizationTable(for: "ru")

        XCTAssertFalse(english.isEmpty)
        XCTAssertFalse(russian.isEmpty)
        XCTAssertEqual(Set(english.keys), Set(russian.keys))

        for key in english.keys.sorted() {
            let englishValue = try XCTUnwrap(english[key])
            let russianValue = try XCTUnwrap(russian[key])

            XCTAssertFalse(key.isEmpty, "Localization key must not be empty")
            XCTAssertFalse(englishValue.isEmpty, "English value for \(key) must not be empty")
            XCTAssertFalse(russianValue.isEmpty, "Russian value for \(key) must not be empty")
            XCTAssertEqual(
                formatSpecifiers(in: englishValue),
                formatSpecifiers(in: russianValue),
                "Format specifiers for \(key) must match"
            )
        }
    }

    func testUnsupportedLocaleUsesEnglishCatalogForEveryKey() throws {
        let english = try localizationTable(for: "en")
        let fallbackBundle = AppLocalization.bundle(for: Locale(identifier: "de_DE"))

        for key in english.keys.sorted() {
            XCTAssertEqual(
                fallbackBundle.localizedString(
                    forKey: key,
                    value: nil,
                    table: AppLocalization.tableName
                ),
                english[key],
                "Unsupported locale must use the English value for \(key)"
            )
        }
    }

    func testMenuBarResourcesResolveInEnglishAndRussian() {
        XCTAssertEqual(
            AppStrings.MenuBar.noEnabledAccounts.localized(locale: Locale(identifier: "en")),
            "No enabled accounts."
        )
        XCTAssertEqual(
            AppStrings.MenuBar.noEnabledAccounts.localized(locale: Locale(identifier: "ru")),
            "Нет включённых аккаунтов."
        )
    }

    func testMissingRussianTranslationUsesReadableEnglishDefault() {
        let string = AppString(
            "localization.test.missing_russian_translation",
            defaultValue: "Readable English fallback",
            comment: "Test-only missing Russian translation"
        )

        XCTAssertEqual(
            string.localized(locale: Locale(identifier: "ru")),
            "Readable English fallback"
        )
    }

    func testResourceBundleDeclaresBothSupportedLocalizations() {
        XCTAssertTrue(AppLocalization.resourceBundle.localizations.contains("en"))
        XCTAssertTrue(AppLocalization.resourceBundle.localizations.contains("ru"))
    }

    func testPercentageFormatterKeepsOneProviderFractionDigit() {
        XCTAssertEqual(
            AppFormatters.percentage(35.4, locale: Locale(identifier: "en_US")),
            "35.4%"
        )
        XCTAssertEqual(
            AppFormatters.percentage(42, locale: Locale(identifier: "en_US")),
            "42%"
        )

        let russianPercentage = AppFormatters.percentage(35.4, locale: Locale(identifier: "ru_RU"))
        XCTAssertTrue(russianPercentage.contains("35,4"))
        XCTAssertTrue(russianPercentage.contains("%"))
    }

    func testCurrencyFormatterUsesUpToTwoLocalizedDecimalPlaces() {
        XCTAssertEqual(
            AppFormatters.currency(
                Decimal(string: "12.19938")!,
                code: "usd",
                locale: Locale(identifier: "en_US")
            ),
            "$12.2"
        )
        XCTAssertEqual(
            AppFormatters.currency(
                Decimal(55),
                code: "USD",
                locale: Locale(identifier: "en_US")
            ),
            "$55"
        )
        XCTAssertEqual(
            AppFormatters.currency(
                Decimal(string: "12.2")!,
                code: "USD",
                locale: Locale(identifier: "ru_RU")
            ),
            "$12,2"
        )
        XCTAssertEqual(
            AppFormatters.currency(
                Decimal(string: "1.25")!,
                code: "usd",
                locale: Locale(identifier: "en_US")
            ),
            "$1.25"
        )
        XCTAssertEqual(
            AppFormatters.currency(
                Decimal(string: "1.25")!,
                code: "EUR",
                locale: Locale(identifier: "en_US")
            ),
            "EUR 1.25"
        )
    }

    func testDateFormattersUseTheRequestedLocaleAndFixedTimeZone() {
        let date = Date(timeIntervalSince1970: 978_307_445)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let english = Locale(identifier: "en")
        let russian = Locale(identifier: "ru")

        XCTAssertEqual(
            AppFormatters.preciseDate(date, locale: english, timeZone: timeZone),
            formattedDate(date, locale: english, timeZone: timeZone, timeStyle: .medium)
        )
        XCTAssertEqual(
            AppFormatters.preciseDate(date, locale: russian, timeZone: timeZone),
            formattedDate(date, locale: russian, timeZone: timeZone, timeStyle: .medium)
        )
        XCTAssertEqual(
            AppFormatters.shortDate(date, locale: english, timeZone: timeZone),
            formattedDate(date, locale: english, timeZone: timeZone, timeStyle: .short)
        )
        XCTAssertEqual(
            AppFormatters.shortDate(date, locale: russian, timeZone: timeZone),
            formattedDate(date, locale: russian, timeZone: timeZone, timeStyle: .short)
        )
    }

    func testRelativeDateFormatterUsesTheRequestedLocale() {
        let referenceDate = Date(timeIntervalSince1970: 1_000_000)
        let futureDate = referenceDate.addingTimeInterval(7_200)
        let english = Locale(identifier: "en")
        let russian = Locale(identifier: "ru")

        XCTAssertEqual(
            AppFormatters.relativeDate(futureDate, relativeTo: referenceDate, locale: english),
            formattedRelativeDate(futureDate, relativeTo: referenceDate, locale: english)
        )
        XCTAssertEqual(
            AppFormatters.relativeDate(futureDate, relativeTo: referenceDate, locale: russian),
            formattedRelativeDate(futureDate, relativeTo: referenceDate, locale: russian)
        )
    }

    func testPresentationStringsResolveInRussian() {
        let locale = Locale(identifier: "ru")
        XCTAssertEqual(AppStrings.Settings.Navigation.general.localized(locale: locale), "Основные")
        XCTAssertEqual(AppStrings.Dashboard.used.formatted(locale: locale, "35,4 %"), "Ушло 35,4 %")
        XCTAssertEqual(AppStrings.Dashboard.left.formatted(locale: locale, "35,4 %"), "Ещё 35,4 %")
        XCTAssertEqual(AppStrings.DisplayMode.useGlobal.localized(locale: locale), "Как в общих")
        XCTAssertEqual(AppStrings.Window.settingsTitle.localized(locale: locale), "Настройки Биирометра")
    }

    func testOpenRouterUserFacingTerminologyUsesKeysInBothCatalogs() throws {
        let english = try localizationTable(for: "en")
        let russian = try localizationTable(for: "ru")
        let openRouterKeys = english.keys.filter {
            $0.hasPrefix("openrouter.")
                || $0 == "storage.openrouter_credentials"
                || $0 == "settings.accounts.delete_openrouter_message"
        }

        for key in openRouterKeys {
            let englishValue = try XCTUnwrap(english[key])
            let russianValue = try XCTUnwrap(russian[key])
            XCTAssertFalse(
                englishValue.localizedCaseInsensitiveContains("credential"),
                "English user-facing value for \(key) must use key terminology"
            )
            XCTAssertFalse(
                russianValue.localizedCaseInsensitiveContains("credential"),
                "Russian user-facing value for \(key) must use key terminology"
            )
        }
        for key in english.keys where key.hasPrefix("openrouter.") {
            let englishValue = try XCTUnwrap(english[key])
            XCTAssertFalse(
                englishValue.localizedCaseInsensitiveContains("remaining"),
                "English OpenRouter value for \(key) must use left terminology"
            )
        }

        XCTAssertEqual(english["openrouter.settings.credentials_title"], "KEYS")
        XCTAssertEqual(russian["openrouter.settings.credentials_title"], "КЛЮЧИ")
        XCTAssertEqual(english["openrouter.settings.add_key"], "Add key")
        XCTAssertEqual(russian["openrouter.settings.add_key"], "Добавить ключ")
        XCTAssertEqual(english["openrouter.editor.add_key_title"], "Add key")
        XCTAssertEqual(russian["openrouter.editor.add_key_title"], "Добавить ключ")
        XCTAssertEqual(
            english["openrouter.editor.key_details"],
            "KEY DETAILS"
        )
        XCTAssertEqual(
            russian["openrouter.editor.key_details"],
            "ДАННЫЕ КЛЮЧА"
        )
        XCTAssertEqual(english["openrouter.settings.replace"], "Replace Key")
        XCTAssertEqual(russian["openrouter.settings.replace"], "Заменить ключ")
        XCTAssertEqual(english["openrouter.editor.key_name"], "Name")
        XCTAssertEqual(russian["openrouter.editor.key_name"], "Имя")
        XCTAssertEqual(english["openrouter.editor.credential"], "Key")
        XCTAssertEqual(russian["openrouter.editor.credential"], "Ключ")
        XCTAssertEqual(
            russian["openrouter.value.credit_summary"],
            "Осталось %@ · Использовано %@"
        )
        XCTAssertEqual(
            english["openrouter.value.credit_summary"],
            "%@ left · %@ used"
        )
        XCTAssertFalse(
            try XCTUnwrap(
                english["openrouter.settings.ordinary_disclosure"]
            ).localizedCaseInsensitiveContains("ordinary")
        )
        XCTAssertFalse(
            try XCTUnwrap(
                russian["openrouter.settings.ordinary_disclosure"]
            ).localizedCaseInsensitiveContains("обыч")
        )
    }

    func testLocalAccountRemovalUsesRemoveTerminologyInEnglish() throws {
        let english = try localizationTable(for: "en")

        XCTAssertEqual(english["common.action.delete"], "Remove")
        XCTAssertEqual(
            english["settings.accounts.delete_title"],
            "Remove Account?"
        )
        XCTAssertEqual(
            english["settings.accounts.delete_selected"],
            "Remove selected account"
        )
        XCTAssertEqual(
            english["openrouter.settings.delete_title"],
            "Remove Key?"
        )
    }

    private func localizationTable(for localization: String) throws -> [String: String] {
        let bundle = AppLocalization.bundle(for: Locale(identifier: localization))
        let url = try XCTUnwrap(
            bundle.url(forResource: AppLocalization.tableName, withExtension: "strings"),
            "Missing \(localization) localization table"
        )
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try XCTUnwrap(
            propertyList as? [String: String],
            "\(localization) localization table must contain string values"
        )
    }

    private func formatSpecifiers(in value: String) -> [String] {
        let pattern = "(?<!%)%(?:\\d+\\$)?[-+ #0']*(?:\\d+)?(?:\\.\\d+)?(?:hh|h|ll|l|L|z|j|t|q)?[@a-zA-Z]"
        let expression = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..., in: value)
        return expression
            .matches(in: value, range: range)
            .compactMap { Range($0.range, in: value).flatMap { value[$0].last.map(String.init) } }
            .sorted()
    }

    private func formattedDate(
        _ date: Date,
        locale: Locale,
        timeZone: TimeZone,
        timeStyle: DateFormatter.Style
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    private func formattedRelativeDate(
        _ date: Date,
        relativeTo referenceDate: Date,
        locale: Locale
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}
