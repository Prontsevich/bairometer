import Foundation

struct AboutBuildInformation: Equatable {
    static let developmentText = "Development build"

    let shortVersion: String?
    let buildNumber: String?

    init(shortVersion: String?, buildNumber: String?) {
        self.shortVersion = Self.normalized(shortVersion)
        self.buildNumber = Self.normalized(buildNumber)
    }

    init(bundle: Bundle) {
        self.init(
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    static var current: Self {
        Self(bundle: .main)
    }

    var displayText: String {
        guard let shortVersion, let buildNumber else {
            return Self.developmentText
        }
        return "Version \(shortVersion) (build \(buildNumber))"
    }

    func displayText(locale: Locale) -> String {
        guard let shortVersion, let buildNumber else {
            return AppStrings.About.developmentBuild.localized(locale: locale)
        }
        return AppStrings.About.version.formatted(locale: locale, shortVersion, buildNumber)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

enum AboutLinks {
    static let github = URL(string: "https://github.com/Prontsevich/bairometer")!
    static let issue = URL(string: "https://github.com/Prontsevich/bairometer/issues/new")!
    static let email = URL(string: "mailto:prontsevich@gmail.com")!
    static let telegram = URL(string: "https://t.me/s_prontsevich")!
    static let boosty = URL(string: "https://boosty.to/sergey.pro")!
}
