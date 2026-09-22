import Foundation

enum AppFormatters {
    static func percentage(_ usedPercent: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1

        return formatter.string(from: NSNumber(value: usedPercent / 100))
            ?? "\(usedPercent)%"
    }

    static func currency(
        _ value: Decimal,
        code: String,
        locale: Locale
    ) -> String {
        let amount = decimal(value, locale: locale)
        let normalizedCode = code.uppercased()
        return normalizedCode == "USD"
            ? "$\(amount)"
            : "\(normalizedCode) \(amount)"
    }

    static func decimal(
        _ value: Decimal,
        locale: Locale
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true

        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    static func relativeDate(_ date: Date, relativeTo referenceDate: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    static func preciseDate(
        _ date: Date,
        locale: Locale,
        timeZone: TimeZone? = nil
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        if let timeZone {
            formatter.timeZone = timeZone
        }
        return formatter.string(from: date)
    }

    static func shortDate(
        _ date: Date,
        locale: Locale,
        timeZone: TimeZone? = nil
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if let timeZone {
            formatter.timeZone = timeZone
        }
        return formatter.string(from: date)
    }
}
