import CryptoKit
import Foundation

public enum ClaudeUsageCLIParserError: Error, LocalizedError, Equatable, Sendable {
    case missingRequiredWindow(String)
    case duplicateWindow(String)
    case invalidWindow(String)
    case invalidPercentage(String)
    case invalidReset(String)
    case noUsablePlanLimits

    public var errorDescription: String? {
        switch self {
        case let .missingRequiredWindow(window):
            "Claude Code /usage did not provide the required \(window) limit."
        case let .duplicateWindow(window):
            "Claude Code /usage returned duplicate \(window) limits."
        case let .invalidWindow(window):
            "Claude Code /usage returned an incomplete \(window) limit."
        case let .invalidPercentage(window):
            "Claude Code /usage returned an invalid \(window) percentage."
        case let .invalidReset(window):
            "Claude Code /usage returned an invalid \(window) reset time."
        case .noUsablePlanLimits:
            "Claude Code /usage did not provide usable subscription plan limits."
        }
    }

    public var recoverySuggestion: String? {
        "Update Claude Code CLI or switch this account to Manual or managed statusLine."
    }
}

public enum ClaudeUsageCLIParser {
    private struct WindowDraft {
        enum Kind {
            case session
            case weeklyAll
            case weeklyModel(String)
        }

        let kind: Kind
        let displayName: String
        let usedPercent: Double
        let resetAt: Date?
    }

    private struct RecognizedHeader {
        let kind: WindowDraft.Kind
        let displayName: String
        let inlineValue: String
    }

    public static func parse(
        _ result: String,
        now: Date = Date()
    ) throws -> [UsageLimitWindow] {
        let lines = normalizedLines(result)
        var drafts: [WindowDraft] = []
        var seenHeaders = Set<String>()

        for (index, line) in lines.enumerated() {
            guard let header = recognizedHeader(for: line) else { continue }
            let canonicalHeader = header.displayName.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard seenHeaders.insert(canonicalHeader).inserted else {
                throw ClaudeUsageCLIParserError.duplicateWindow(header.displayName)
            }

            var block: [String] = header.inlineValue.isEmpty ? [] : [header.inlineValue]
            for candidate in lines[(index + 1)...] {
                if recognizedHeader(for: candidate) != nil || candidate.hasPrefix("Current ") {
                    break
                }
                if candidate.isEmpty {
                    if !block.isEmpty { break }
                    continue
                }
                block.append(candidate)
                if block.count == 12 { break }
            }
            drafts.append(try makeDraft(
                kind: header.kind,
                displayName: header.displayName,
                block: block,
                now: now
            ))
        }

        guard !drafts.isEmpty else {
            throw ClaudeUsageCLIParserError.noUsablePlanLimits
        }
        guard drafts.contains(where: { if case .session = $0.kind { true } else { false } }) else {
            throw ClaudeUsageCLIParserError.missingRequiredWindow("Current session")
        }
        guard drafts.contains(where: { if case .weeklyAll = $0.kind { true } else { false } }) else {
            throw ClaudeUsageCLIParserError.missingRequiredWindow("Current week (all models)")
        }

        let modelSlugs = drafts.compactMap { draft -> (label: String, slug: String)? in
            guard case let .weeklyModel(label) = draft.kind else { return nil }
            return (label, normalizedModelSlug(label))
        }
        let slugCounts = Dictionary(grouping: modelSlugs, by: \.slug).mapValues(\.count)

        return drafts.map { draft in
            let id: String
            switch draft.kind {
            case .session:
                id = "session"
            case .weeklyAll:
                id = "weekly-all"
            case let .weeklyModel(label):
                let slug = normalizedModelSlug(label)
                if slugCounts[slug, default: 0] > 1 {
                    id = "weekly-\(slug)-\(stableSuffix(label))"
                } else {
                    id = "weekly-\(slug)"
                }
            }
            return UsageLimitWindow(
                id: id,
                displayName: draft.displayName,
                usedPercent: draft.usedPercent,
                resetAt: draft.resetAt
            )
        }
    }

    private static func makeDraft(
        kind: WindowDraft.Kind,
        displayName: String,
        block: [String],
        now: Date
    ) throws -> WindowDraft {
        let percentages = block.compactMap(percentage)
        guard percentages.count == 1 else {
            if percentages.isEmpty {
                throw ClaudeUsageCLIParserError.invalidWindow(displayName)
            }
            throw ClaudeUsageCLIParserError.duplicateWindow(displayName)
        }
        guard (0...100).contains(percentages[0]) else {
            throw ClaudeUsageCLIParserError.invalidPercentage(displayName)
        }

        let resetValues = block.compactMap(resetValue)
        guard resetValues.count <= 1 else {
            throw ClaudeUsageCLIParserError.duplicateWindow(displayName)
        }

        let resetAt: Date?
        if let resetValue = resetValues.first {
            guard let parsedReset = parseReset(resetValue, now: now) else {
                throw ClaudeUsageCLIParserError.invalidReset(displayName)
            }
            resetAt = parsedReset
        } else {
            resetAt = nil
        }

        return WindowDraft(
            kind: kind,
            displayName: displayName,
            usedPercent: percentages[0],
            resetAt: resetAt
        )
    }

    private static func recognizedHeader(for line: String) -> RecognizedHeader? {
        if let captures = captures(
            pattern: #"^Current session(?::\s*(.*))?$"#,
            in: line,
            caseInsensitive: true
        ) {
            return RecognizedHeader(
                kind: .session,
                displayName: "Current session",
                inlineValue: captures.first ?? ""
            )
        }
        guard let captures = captures(
            pattern: #"^Current week \(([^)]+)\)(?::\s*(.*))?$"#,
            in: line,
            caseInsensitive: true
        ), let label = captures.first?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            return nil
        }
        if label.caseInsensitiveCompare("all models") == .orderedSame {
            return RecognizedHeader(
                kind: .weeklyAll,
                displayName: "Current week (all models)",
                inlineValue: captures.count > 1 ? captures[1] : ""
            )
        }
        return RecognizedHeader(
            kind: .weeklyModel(label),
            displayName: "Current week (\(label))",
            inlineValue: captures.count > 1 ? captures[1] : ""
        )
    }

    private static func percentage(in line: String) -> Double? {
        guard let value = captures(
            pattern: #"([0-9]+(?:\.[0-9]+)?)\s*%\s*used"#,
            in: line,
            caseInsensitive: true
        )?.first else { return nil }
        return Double(value)
    }

    private static func resetValue(in line: String) -> String? {
        captures(
            pattern: #"\bresets\s+(.+)$"#,
            in: line,
            caseInsensitive: true
        )?.first
    }

    private static func normalizedLines(_ result: String) -> [String] {
        let normalizedNewlines = result
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let withoutANSI = normalizedNewlines.replacingOccurrences(
            of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        return withoutANSI
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func parseReset(_ value: String, now: Date) -> Date? {
        let normalized = value
            .replacingOccurrences(
                of: #"\s*\(UTC\)\s*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let time = parseTime(normalized) {
            return nextTime(hour: time.hour, minute: time.minute, now: now)
        }

        guard let dateCaptures = captures(
            pattern: #"^([A-Za-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?(?:\s+at\s+|,\s*)(.+)$"#,
            in: normalized,
            caseInsensitive: true
        ), dateCaptures.count == 4,
           let month = monthNumber(dateCaptures[0]),
           let day = Int(dateCaptures[1]),
           let time = parseTime(dateCaptures[3])
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let explicitYear = Int(dateCaptures[2])
        let currentYear = calendar.component(.year, from: now)
        var components = DateComponents(
            timeZone: calendar.timeZone,
            year: explicitYear ?? currentYear,
            month: month,
            day: day,
            hour: time.hour,
            minute: time.minute
        )
        guard var date = calendar.date(from: components) else { return nil }

        if explicitYear == nil, date <= now {
            components.year = currentYear + 1
            guard let nextYearDate = calendar.date(from: components) else { return nil }
            date = nextYearDate
        }
        return date > now ? date : nil
    }

    private static func parseTime(_ value: String) -> (hour: Int, minute: Int)? {
        guard let captures = captures(
            pattern: #"^(\d{1,2})(?::(\d{2}))?\s*([ap]m)$"#,
           in: value.trimmingCharacters(in: .whitespacesAndNewlines),
           caseInsensitive: true
        ), captures.count == 3,
           let rawHour = Int(captures[0]),
           let minute = captures[1].isEmpty ? 0 : Int(captures[1]),
           (1...12).contains(rawHour),
           (0...59).contains(minute)
        else { return nil }

        let marker = captures[2].lowercased()
        let hour = (rawHour % 12) + (marker == "pm" ? 12 : 0)
        return (hour, minute)
    }

    private static func nextTime(hour: Int, minute: Int, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.timeZone = calendar.timeZone
        components.hour = hour
        components.minute = minute
        guard var date = calendar.date(from: components) else { return nil }
        if date <= now {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            date = nextDay
        }
        return date
    }

    private static func monthNumber(_ value: String) -> Int? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let normalized = value.lowercased()
        let names = zip(formatter.monthSymbols, formatter.shortMonthSymbols)
        for (index, pair) in names.enumerated() {
            if pair.0.lowercased() == normalized || pair.1.lowercased() == normalized {
                return index + 1
            }
        }
        return nil
    }

    private static func normalizedModelSlug(_ label: String) -> String {
        let folded = label
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        var slug = ""
        var lastWasSeparator = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                slug.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator, !slug.isEmpty {
                slug.append("-")
                lastWasSeparator = true
            }
        }
        while slug.last == "-" {
            slug.removeLast()
        }
        return slug.isEmpty ? "model" : slug
    }

    private static func stableSuffix(_ label: String) -> String {
        let canonical = label.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private static func captures(
        pattern: String,
        in value: String,
        caseInsensitive: Bool
    ) -> [String]? {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            let captureRange = match.range(at: index)
            guard captureRange.location != NSNotFound,
                  let range = Range(captureRange, in: value) else { return "" }
            return String(value[range])
        }
    }
}
