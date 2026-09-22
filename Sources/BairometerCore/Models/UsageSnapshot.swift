import Foundation

public enum UsageStatus: String, Codable, CaseIterable, Sendable {
    case ok
    case warning
    case error
    case unavailable

    public var displayName: String {
        switch self {
        case .ok: "OK"
        case .warning: "Warning"
        case .error: "Error"
        case .unavailable: "Unavailable"
        }
    }
}

public enum ConfidenceLevel: String, Codable, CaseIterable, Sendable {
    case live
    case delayed
    case localEstimate = "local-estimate"
    case manual
    case unknown

    public var displayName: String {
        switch self {
        case .live: "Live"
        case .delayed: "Delayed"
        case .localEstimate: "Local estimate"
        case .manual: "Manual"
        case .unknown: "Unknown"
        }
    }
}

public struct UsageLimitWindow: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let usedPercent: Double?
    public let remainingLabel: String?
    public let resetAt: Date?

    public init(
        id: String,
        displayName: String,
        usedPercent: Double? = nil,
        remainingLabel: String? = nil,
        resetAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.usedPercent = usedPercent
        self.remainingLabel = remainingLabel
        self.resetAt = resetAt
    }
}

public struct UsageSnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(providerID):\(accountID)" }

    public let providerID: String
    public let accountID: String
    public let accountDisplayName: String
    public let displayName: String
    public let status: UsageStatus
    public let planName: String?
    public let periodLabel: String?
    public let usedPercent: Double?
    public let remainingLabel: String?
    public let resetAt: Date?
    public let limitWindows: [UsageLimitWindow]
    public let lastUpdatedAt: Date
    public let confidence: ConfidenceLevel
    public let source: String
    public let warnings: [String]

    public var displayLimitWindows: [UsageLimitWindow] {
        if !limitWindows.isEmpty {
            return limitWindows
        }

        guard periodLabel != nil || usedPercent != nil || remainingLabel != nil || resetAt != nil else {
            return []
        }

        return [
            UsageLimitWindow(
                id: "primary",
                displayName: periodLabel ?? "Usage",
                usedPercent: usedPercent,
                remainingLabel: remainingLabel,
                resetAt: resetAt
            )
        ]
    }

    public init(
        providerID: String,
        accountID: String = ProviderAccount.defaultAccountID,
        accountDisplayName: String = ProviderAccount.defaultDisplayName,
        displayName: String,
        status: UsageStatus,
        planName: String? = nil,
        periodLabel: String? = nil,
        usedPercent: Double? = nil,
        remainingLabel: String? = nil,
        resetAt: Date? = nil,
        limitWindows: [UsageLimitWindow] = [],
        lastUpdatedAt: Date,
        confidence: ConfidenceLevel,
        source: String,
        warnings: [String] = []
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.accountDisplayName = accountDisplayName
        self.displayName = displayName
        self.status = status
        self.planName = planName
        self.periodLabel = periodLabel
        self.usedPercent = usedPercent
        self.remainingLabel = remainingLabel
        self.resetAt = resetAt
        self.limitWindows = limitWindows
        self.lastUpdatedAt = lastUpdatedAt
        self.confidence = confidence
        self.source = source
        self.warnings = warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(String.self, forKey: .providerID)
        accountID = try container.decode(String.self, forKey: .accountID)
        accountDisplayName = try container.decode(String.self, forKey: .accountDisplayName)
        displayName = try container.decode(String.self, forKey: .displayName)
        status = try container.decode(UsageStatus.self, forKey: .status)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
        periodLabel = try container.decodeIfPresent(String.self, forKey: .periodLabel)
        usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
        remainingLabel = try container.decodeIfPresent(String.self, forKey: .remainingLabel)
        resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
        limitWindows = try container.decodeIfPresent([UsageLimitWindow].self, forKey: .limitWindows) ?? []
        lastUpdatedAt = try container.decode(Date.self, forKey: .lastUpdatedAt)
        confidence = try container.decode(ConfidenceLevel.self, forKey: .confidence)
        source = try container.decode(String.self, forKey: .source)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}
