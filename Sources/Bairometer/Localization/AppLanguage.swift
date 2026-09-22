import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case systemDefault = "system"
    case english = "en"
    case russian = "ru"

    static let storageKey = "app-language"

    var id: String { rawValue }

    func resolvedLocale(systemLocale: Locale) -> Locale {
        switch self {
        case .systemDefault:
            systemLocale
        case .english:
            Locale(identifier: "en")
        case .russian:
            Locale(identifier: "ru")
        }
    }
}

@MainActor
final class AppLanguagePreference: ObservableObject {
    @Published private(set) var language: AppLanguage
    @Published private(set) var effectiveLocale: Locale

    private let userDefaults: UserDefaults
    private let systemLocaleProvider: () -> Locale
    private var localeChangeObservation: AnyCancellable?

    init(
        userDefaults: UserDefaults = .standard,
        systemLocaleProvider: @escaping () -> Locale = { .autoupdatingCurrent }
    ) {
        self.userDefaults = userDefaults
        self.systemLocaleProvider = systemLocaleProvider

        let language = AppLanguage(
            rawValue: userDefaults.string(forKey: AppLanguage.storageKey) ?? ""
        ) ?? .systemDefault
        self.language = language
        self.effectiveLocale = language.resolvedLocale(systemLocale: systemLocaleProvider())

        localeChangeObservation = NotificationCenter.default
            .publisher(for: NSLocale.currentLocaleDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshSystemLocale()
            }
    }

    func select(_ language: AppLanguage) {
        self.language = language
        userDefaults.set(language.rawValue, forKey: AppLanguage.storageKey)
        effectiveLocale = language.resolvedLocale(systemLocale: systemLocaleProvider())
    }

    func refreshSystemLocale() {
        guard language == .systemDefault else { return }
        effectiveLocale = language.resolvedLocale(systemLocale: systemLocaleProvider())
    }
}

struct AppLocaleScope<Content: View>: View {
    @ObservedObject private var languagePreference: AppLanguagePreference
    private let content: Content

    init(
        languagePreference: AppLanguagePreference,
        @ViewBuilder content: () -> Content
    ) {
        _languagePreference = ObservedObject(wrappedValue: languagePreference)
        self.content = content()
    }

    var body: some View {
        content.environment(\.locale, languagePreference.effectiveLocale)
    }
}
