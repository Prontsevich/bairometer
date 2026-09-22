import Foundation

enum AppLocalization {
    static let tableName = "Localizable"

    static let resourceBundle: Bundle = {
        if Bundle.main.url(
            forResource: tableName,
            withExtension: "strings",
            subdirectory: nil,
            localization: "en"
        ) != nil {
            return .main
        }

        return .module
    }()

    static func bundle(for locale: Locale) -> Bundle {
        let localization = supportedLocalization(for: locale)
        if let localizedBundle = localizedBundle(named: localization) {
            return localizedBundle
        }
        if let englishBundle = localizedBundle(named: "en") {
            return englishBundle
        }
        return resourceBundle
    }

    private static func supportedLocalization(for locale: Locale) -> String {
        let language = locale.identifier
            .replacingOccurrences(of: "-", with: "_")
            .split(separator: "_", maxSplits: 1)
            .first
            .map(String.init)

        return language == "ru" ? "ru" : "en"
    }

    private static func localizedBundle(named localization: String) -> Bundle? {
        guard let path = resourceBundle.path(forResource: localization, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}

struct AppString {
    let key: StaticString
    let defaultValue: String.LocalizationValue
    let comment: StaticString

    init(
        _ key: StaticString,
        defaultValue: String.LocalizationValue,
        comment: StaticString
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.comment = comment
    }

    func resource(locale: Locale) -> LocalizedStringResource {
        LocalizedStringResource(
            key,
            defaultValue: defaultValue,
            table: AppLocalization.tableName,
            locale: locale,
            bundle: AppLocalization.bundle(for: locale),
            comment: comment
        )
    }

    func localized(locale: Locale) -> String {
        String(
            localized: key,
            defaultValue: defaultValue,
            table: AppLocalization.tableName,
            bundle: AppLocalization.bundle(for: locale),
            locale: locale,
            comment: comment
        )
    }

    func formatted(locale: Locale, _ arguments: CVarArg...) -> String {
        String(
            format: localized(locale: locale),
            locale: locale,
            arguments: arguments
        )
    }
}

enum AppStrings {
    enum MenuBar {
        static let accountsTitle = AppString(
            "menu_bar.accounts.title",
            defaultValue: "ACCOUNTS",
            comment: "Terminal fieldset title for the account list"
        )
        static let refreshAllAccounts = AppString(
            "menu_bar.refresh_all_accounts",
            defaultValue: "Refresh all accounts",
            comment: "Accessibility label and tooltip for the menu bar refresh button"
        )
        static let refreshing = AppString(
            "menu_bar.refreshing",
            defaultValue: "Refreshing",
            comment: "Accessibility value while the menu bar refresh is active"
        )
        static let ready = AppString(
            "menu_bar.ready",
            defaultValue: "Ready",
            comment: "Accessibility value while the menu bar refresh is idle"
        )
        static let noEnabledAccounts = AppString(
            "menu_bar.empty.no_enabled_accounts",
            defaultValue: "No enabled accounts.",
            comment: "Empty menu bar dashboard message"
        )
        static let createAccountInSettings = AppString(
            "menu_bar.empty.create_account_in_settings",
            defaultValue: "Create an account in Settings.",
            comment: "Empty menu bar dashboard recovery instruction"
        )
        static let settings = AppString(
            "menu_bar.action.settings",
            defaultValue: "Settings",
            comment: "Menu bar footer action"
        )
        static let about = AppString(
            "menu_bar.action.about",
            defaultValue: "About",
            comment: "Menu bar footer action"
        )
        static let aboutBairometer = AppString(
            "menu_bar.action.about_bairometer",
            defaultValue: "About Bairometer",
            comment: "Tooltip and accessibility label for the About action"
        )
        static let quit = AppString(
            "menu_bar.action.quit",
            defaultValue: "Quit",
            comment: "Menu bar footer action"
        )
        static let noEnabledAccountsToRefresh = AppString(
            "menu_bar.refresh_help.no_enabled_accounts",
            defaultValue: "No enabled accounts to refresh.",
            comment: "Tooltip when no enabled accounts can be refreshed"
        )
        static let refreshingAllAccounts = AppString(
            "menu_bar.refresh_help.refreshing_all_accounts",
            defaultValue: "Refreshing all accounts.",
            comment: "Tooltip while the menu bar refresh is active"
        )
        static let waitForCurrentRefresh = AppString(
            "menu_bar.refresh_help.wait_for_current_refresh",
            defaultValue: "Wait for the current account refresh to finish.",
            comment: "Tooltip while an account refresh is active"
        )
    }

    enum Settings {
        enum Language {
            static let title = AppString(
                "settings.language.title",
                defaultValue: "LANGUAGE",
                comment: "Terminal fieldset title for the app language preference"
            )
            static let selection = AppString(
                "settings.language.selection",
                defaultValue: "App language",
                comment: "Accessibility label for the app language selector"
            )
            static let description = AppString(
                "settings.language.description",
                defaultValue: "Choose the language used by Bairometer.",
                comment: "Description below the app language selector"
            )
            static let systemDefault = AppString(
                "settings.language.choice.system_default",
                defaultValue: "System Default",
                comment: "App language option that follows the current system locale"
            )
            static let english = AppString(
                "settings.language.choice.english",
                defaultValue: "English",
                comment: "App language option for English"
            )
            static let russian = AppString(
                "settings.language.choice.russian",
                defaultValue: "Russian",
                comment: "App language option for Russian"
            )

            static func option(for language: AppLanguage) -> AppString {
                switch language {
                case .systemDefault:
                    systemDefault
                case .english:
                    english
                case .russian:
                    russian
                }
            }
        }
    }
}
