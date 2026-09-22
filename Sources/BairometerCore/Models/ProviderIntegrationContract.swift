import Foundation

public struct ContractVersion: Codable, Equatable, Hashable, Sendable {
    public static let v1 = ContractVersion(major: 1, minor: 0)

    public let major: UInt
    public let minor: UInt

    public init(major: UInt, minor: UInt) {
        self.major = major
        self.minor = minor
    }

    public func isCompatible(
        with supportedVersion: ContractVersion = .v1,
        allowsNewerMinorVersion: Bool = true
    ) -> Bool {
        guard major == supportedVersion.major else {
            return false
        }
        return allowsNewerMinorVersion || minor <= supportedVersion.minor
    }
}

public enum InteractionModel: String, Codable, CaseIterable, Sendable {
    case subscription
    case api
    case enterprise
    case local
    case manual
}

public struct RegionDescriptor: Codable, Equatable, Sendable {
    public let regionID: String
    public let displayName: String

    public init(regionID: String, displayName: String) {
        self.regionID = regionID
        self.displayName = displayName
    }
}

public enum AccountContextKind: String, Codable, CaseIterable, Sendable {
    case personal
    case organization
    case workspace
    case project
    case team
    case credential
    case localIdentity = "local-identity"
}

public struct ProviderSurface: Codable, Equatable, Sendable {
    public let providerID: String
    public let surfaceID: String
    public let displayName: String
    public let interactionModel: InteractionModel
    public let regions: [RegionDescriptor]
    public let accountContextKinds: [AccountContextKind]
    public let capabilities: [String]

    public init(
        providerID: String,
        surfaceID: String,
        displayName: String,
        interactionModel: InteractionModel,
        regions: [RegionDescriptor],
        accountContextKinds: [AccountContextKind],
        capabilities: [String]
    ) {
        self.providerID = providerID
        self.surfaceID = surfaceID
        self.displayName = displayName
        self.interactionModel = interactionModel
        self.regions = regions
        self.accountContextKinds = accountContextKinds
        self.capabilities = capabilities
    }
}

public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case documentedRemoteAPI = "documented-remote-api"
    case documentedLocalInterface = "documented-local-interface"
    case standardProtocol = "standard-protocol"
    case isolatedAuthenticatedWeb = "isolated-authenticated-web"
    case localEstimate = "local-estimate"
    case manualProviderPage = "manual-provider-page"
    case manualInput = "manual-input"
}

public enum SourceAuthority: String, Codable, CaseIterable, Sendable {
    case providerReported = "provider-reported"
    case providerDocumented = "provider-documented"
    case locallyObserved = "locally-observed"
    case estimated
    case manual
}

public enum SourceMaturity: String, Codable, CaseIterable, Sendable {
    case stable
    case experimental
}

public enum FreshnessPolicyKind: String, Codable, CaseIterable, Sendable {
    case maximumAge = "maximum-age"
    case sourceExpiry = "source-expiry"
    case manual
    case unknown
}

public struct FreshnessPolicy: Codable, Equatable, Sendable {
    public let kind: FreshnessPolicyKind
    public let maxAgeSeconds: UInt?

    public init(kind: FreshnessPolicyKind, maxAgeSeconds: UInt? = nil) {
        self.kind = kind
        self.maxAgeSeconds = maxAgeSeconds
    }
}

public enum AuthCategory: String, Codable, CaseIterable, Sendable {
    case none
    case apiKey = "api-key"
    case subscriptionKey = "subscription-key"
    case oauth
    case externalCLISession = "external-cli-session"
    case isolatedBrowserSession = "isolated-browser-session"
    case other
}

public enum AuthPrivilege: String, Codable, CaseIterable, Sendable {
    case none
    case leastPrivilege = "least-privilege"
    case elevated
}

public enum CredentialStorageBoundary: String, Codable, CaseIterable, Sendable {
    case none
    case keychain
    case providerManagedCLI = "provider-managed-cli"
    case isolatedWebDataStore = "isolated-web-data-store"
}

public struct AuthRequirement: Codable, Equatable, Sendable {
    public let category: AuthCategory
    public let privilege: AuthPrivilege
    public let requiredScopes: [String]
    public let storageBoundary: CredentialStorageBoundary

    public init(
        category: AuthCategory,
        privilege: AuthPrivilege,
        requiredScopes: [String] = [],
        storageBoundary: CredentialStorageBoundary
    ) {
        self.category = category
        self.privilege = privilege
        self.requiredScopes = requiredScopes
        self.storageBoundary = storageBoundary
    }
}

public struct SourceDescriptor: Codable, Equatable, Sendable {
    public let providerID: String
    public let surfaceID: String
    public let sourceID: String
    public let displayName: String
    public let kind: SourceKind
    public let authority: SourceAuthority
    public let maturity: SourceMaturity
    public let defaultConfidence: ConfidenceLevel
    public let freshnessPolicy: FreshnessPolicy
    public let capabilities: [String]
    public let authRequirement: AuthRequirement

    public init(
        providerID: String,
        surfaceID: String,
        sourceID: String,
        displayName: String,
        kind: SourceKind,
        authority: SourceAuthority,
        maturity: SourceMaturity,
        defaultConfidence: ConfidenceLevel,
        freshnessPolicy: FreshnessPolicy,
        capabilities: [String],
        authRequirement: AuthRequirement
    ) {
        self.providerID = providerID
        self.surfaceID = surfaceID
        self.sourceID = sourceID
        self.displayName = displayName
        self.kind = kind
        self.authority = authority
        self.maturity = maturity
        self.defaultConfidence = defaultConfidence
        self.freshnessPolicy = freshnessPolicy
        self.capabilities = capabilities
        self.authRequirement = authRequirement
    }
}

public struct AccountContext: Codable, Equatable, Sendable {
    public let contextID: String
    public let kind: AccountContextKind
    public let displayName: String?
    public let regionID: String
    public let parentContextID: String?

    public init(
        contextID: String,
        kind: AccountContextKind,
        displayName: String? = nil,
        regionID: String,
        parentContextID: String? = nil
    ) {
        self.contextID = contextID
        self.kind = kind
        self.displayName = displayName
        self.regionID = regionID
        self.parentContextID = parentContextID
    }
}

public enum CapacityAvailability: String, Codable, CaseIterable, Sendable {
    case known
    case unlimited
    case unavailable
    case manual
    case unknown
}

public enum CapacityCondition: String, Codable, CaseIterable, Sendable {
    case overage
    case boost
}

public enum CapacityUnitKind: String, Codable, CaseIterable, Sendable {
    case percent
    case currency
    case credits
    case tokens
    case requests
    case characters
    case generations
    case images
    case mediaMinutes = "media-minutes"
    case computeUnits = "compute-units"
    case time
    case providerDefined = "provider-defined"
}

public enum CapacityTimeUnit: String, Codable, CaseIterable, Sendable {
    case seconds
    case minutes
}

public struct CapacityUnit: Codable, Equatable, Sendable {
    public let kind: CapacityUnitKind
    public let currencyCode: String?
    public let timeUnit: CapacityTimeUnit?
    public let providerUnitID: String?

    public init(
        kind: CapacityUnitKind,
        currencyCode: String? = nil,
        timeUnit: CapacityTimeUnit? = nil,
        providerUnitID: String? = nil
    ) {
        self.kind = kind
        self.currencyCode = currencyCode
        self.timeUnit = timeUnit
        self.providerUnitID = providerUnitID
    }
}

public enum CapacityValueOrigin: String, Codable, CaseIterable, Sendable {
    case reported
    case derived
}

public struct CapacityValue: Codable, Equatable, Sendable {
    public let value: Decimal
    public let origin: CapacityValueOrigin

    public init(value: Decimal, origin: CapacityValueOrigin) {
        self.value = value
        self.origin = origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stringValue = try container.decode(String.self, forKey: .value)
        guard let normalizedValue = Self.normalizedPlainDecimal(stringValue),
              let decimal = Decimal(string: stringValue, locale: Locale(identifier: "en_US_POSIX")),
              !decimal.isNaN,
              normalizedValue == NSDecimalNumber(decimal: decimal).stringValue
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "Capacity values must use exactly representable finite base-10 decimal strings without an exponent."
            )
        }
        value = decimal
        origin = try container.decode(CapacityValueOrigin.self, forKey: .origin)
    }

    public func encode(to encoder: Encoder) throws {
        guard !value.isNaN else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Capacity values must be finite."
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            NSDecimalNumber(decimal: value).stringValue,
            forKey: .value
        )
        try container.encode(origin, forKey: .origin)
    }

    private static func normalizedPlainDecimal(_ value: String) -> String? {
        guard value.range(
            of: #"^[+-]?[0-9]+(?:\.[0-9]+)?$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }

        let isNegative = value.hasPrefix("-")
        let hasSign = value.hasPrefix("-") || value.hasPrefix("+")
        let unsignedValue = hasSign ? String(value.dropFirst()) : value
        let components = unsignedValue.split(separator: ".", maxSplits: 1)
        let integerWithoutLeadingZeros = components[0].drop { $0 == "0" }
        let integer = integerWithoutLeadingZeros.isEmpty
            ? "0"
            : String(integerWithoutLeadingZeros)
        var fraction = components.count == 2 ? String(components[1]) : ""
        while fraction.last == "0" {
            fraction.removeLast()
        }

        if integer == "0" && fraction.isEmpty {
            return "0"
        }

        let normalizedUnsignedValue = fraction.isEmpty ? integer : "\(integer).\(fraction)"
        return isNegative ? "-\(normalizedUnsignedValue)" : normalizedUnsignedValue
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case origin
    }
}

public struct CapacityValues: Codable, Equatable, Sendable {
    public let consumed: CapacityValue?
    public let remaining: CapacityValue?
    public let limit: CapacityValue?

    public init(
        consumed: CapacityValue? = nil,
        remaining: CapacityValue? = nil,
        limit: CapacityValue? = nil
    ) {
        self.consumed = consumed
        self.remaining = remaining
        self.limit = limit
    }

    public var isEmpty: Bool {
        consumed == nil && remaining == nil && limit == nil
    }

    public subscript(role: CapacityValueRole) -> CapacityValue? {
        switch role {
        case .consumed:
            consumed
        case .remaining:
            remaining
        case .limit:
            limit
        }
    }
}

public enum CapacityWindowKind: String, Codable, CaseIterable, Sendable {
    case rolling
    case fixed
    case billingCycle = "billing-cycle"
    case lifetime
    case none
    case unknown
}

public enum CapacityTransitionKind: String, Codable, CaseIterable, Sendable {
    case reset
    case renew
    case expire
}

public struct CapacityTransition: Codable, Equatable, Sendable {
    public let kind: CapacityTransitionKind
    public let at: Date

    public init(kind: CapacityTransitionKind, at: Date) {
        self.kind = kind
        self.at = at
    }
}

public struct CapacityWindow: Codable, Equatable, Sendable {
    public let kind: CapacityWindowKind
    public let durationSeconds: UInt?
    public let startsAt: Date?
    public let endsAt: Date?
    public let nextTransition: CapacityTransition?

    public init(
        kind: CapacityWindowKind,
        durationSeconds: UInt? = nil,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        nextTransition: CapacityTransition? = nil
    ) {
        self.kind = kind
        self.durationSeconds = durationSeconds
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.nextTransition = nextTransition
    }
}

public struct ObservationFreshness: Codable, Equatable, Sendable {
    public let observedAt: Date
    public let validUntil: Date?

    public init(observedAt: Date, validUntil: Date? = nil) {
        self.observedAt = observedAt
        self.validUntil = validUntil
    }
}

public enum DerivationKind: String, Codable, CaseIterable, Sendable {
    case percentComplement = "percent-complement"
    case consumedFromLimitMinusRemaining = "consumed-from-limit-minus-remaining"
    case remainingFromLimitMinusConsumed = "remaining-from-limit-minus-consumed"
    case utilizationFromConsumedAndLimit = "utilization-from-consumed-and-limit"
}

public enum DerivationTarget: String, Codable, CaseIterable, Sendable {
    case consumed
    case remaining
    case utilization
}

public enum CapacityValueRole: String, Codable, CaseIterable, Sendable {
    case consumed
    case remaining
    case limit
}

public struct Derivation: Codable, Equatable, Sendable {
    public let kind: DerivationKind
    public let target: DerivationTarget
    public let inputs: [CapacityValueRole]

    public init(
        kind: DerivationKind,
        target: DerivationTarget,
        inputs: [CapacityValueRole]
    ) {
        self.kind = kind
        self.target = target
        self.inputs = inputs
    }
}

public struct CapacityMetric: Codable, Equatable, Sendable {
    public let metricID: String
    public let accountContextID: String
    public let sourceID: String
    public let capability: String
    public let displayName: String
    public let availability: CapacityAvailability
    public let conditions: [CapacityCondition]
    public let unit: CapacityUnit
    public let values: CapacityValues?
    public let window: CapacityWindow
    public let freshness: ObservationFreshness
    public let confidence: ConfidenceLevel
    public let derivations: [Derivation]

    public init(
        metricID: String,
        accountContextID: String,
        sourceID: String,
        capability: String,
        displayName: String,
        availability: CapacityAvailability,
        conditions: [CapacityCondition] = [],
        unit: CapacityUnit,
        values: CapacityValues? = nil,
        window: CapacityWindow,
        freshness: ObservationFreshness,
        confidence: ConfidenceLevel,
        derivations: [Derivation] = []
    ) {
        self.metricID = metricID
        self.accountContextID = accountContextID
        self.sourceID = sourceID
        self.capability = capability
        self.displayName = displayName
        self.availability = availability
        self.conditions = conditions
        self.unit = unit
        self.values = values
        self.window = window
        self.freshness = freshness
        self.confidence = confidence
        self.derivations = derivations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metricID = try container.decode(String.self, forKey: .metricID)
        accountContextID = try container.decode(String.self, forKey: .accountContextID)
        sourceID = try container.decode(String.self, forKey: .sourceID)
        capability = try container.decode(String.self, forKey: .capability)
        displayName = try container.decode(String.self, forKey: .displayName)
        availability = try Self.decodeDiscriminator(
            CapacityAvailability.self,
            from: container,
            forKey: .availability
        )
        conditions = try Self.decodeDiscriminator(
            [CapacityCondition].self,
            from: container,
            forKey: .conditions
        )
        unit = try Self.decodeDiscriminator(
            CapacityUnit.self,
            from: container,
            forKey: .unit
        )
        values = try Self.decodeOptionalDiscriminator(
            CapacityValues.self,
            from: container,
            forKey: .values
        )
        window = try Self.decodeDiscriminator(
            CapacityWindow.self,
            from: container,
            forKey: .window
        )
        freshness = try container.decode(ObservationFreshness.self, forKey: .freshness)
        confidence = try Self.decodeDiscriminator(
            ConfidenceLevel.self,
            from: container,
            forKey: .confidence
        )
        derivations = try Self.decodeDiscriminator(
            [Derivation].self,
            from: container,
            forKey: .derivations
        )
    }

    private static func decodeDiscriminator<Value: Decodable>(
        _ type: Value.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Value {
        do {
            return try container.decode(type, forKey: key)
        } catch let error as DecodingError {
            if case .dataCorrupted(let context) = error,
               context.debugDescription.hasPrefix("Cannot initialize") {
                throw UnsupportedMetricDiscriminator()
            }
            throw error
        }
    }

    private static func decodeOptionalDiscriminator<Value: Decodable>(
        _ type: Value.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Value? {
        do {
            return try container.decodeIfPresent(type, forKey: key)
        } catch let error as DecodingError {
            if case .dataCorrupted(let context) = error,
               context.debugDescription.hasPrefix("Cannot initialize") {
                throw UnsupportedMetricDiscriminator()
            }
            throw error
        }
    }

    private enum CodingKeys: String, CodingKey {
        case metricID
        case accountContextID
        case sourceID
        case capability
        case displayName
        case availability
        case conditions
        case unit
        case values
        case window
        case freshness
        case confidence
        case derivations
    }
}

public enum ContractDiagnosticCode: String, Codable, Equatable, Sendable {
    case unsupportedMetricDiscriminator = "unsupported-metric-discriminator"
}

public struct ContractDiagnostic: Codable, Equatable, Sendable {
    public let code: ContractDiagnosticCode
    public let field: String

    public init(code: ContractDiagnosticCode, field: String) {
        self.code = code
        self.field = field
    }
}

public struct CapacitySnapshot: Codable, Equatable, Sendable {
    public let contractVersion: ContractVersion
    public let providerID: String
    public let surfaceID: String
    public let savedAccountID: String
    public let accountContexts: [AccountContext]
    public let observedAt: Date
    public let metrics: [CapacityMetric]

    /// Decode-time diagnostics are local and intentionally excluded from the serialized contract.
    public let decodingDiagnostics: [ContractDiagnostic]

    public init(
        contractVersion: ContractVersion = .v1,
        providerID: String,
        surfaceID: String,
        savedAccountID: String,
        accountContexts: [AccountContext],
        observedAt: Date,
        metrics: [CapacityMetric],
        decodingDiagnostics: [ContractDiagnostic] = []
    ) {
        self.contractVersion = contractVersion
        self.providerID = providerID
        self.surfaceID = surfaceID
        self.savedAccountID = savedAccountID
        self.accountContexts = accountContexts
        self.observedAt = observedAt
        self.metrics = metrics
        self.decodingDiagnostics = decodingDiagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try container.decode(ContractVersion.self, forKey: .contractVersion)
        providerID = try container.decode(String.self, forKey: .providerID)
        surfaceID = try container.decode(String.self, forKey: .surfaceID)
        savedAccountID = try container.decode(String.self, forKey: .savedAccountID)
        accountContexts = try container.decode([AccountContext].self, forKey: .accountContexts)
        observedAt = try container.decode(Date.self, forKey: .observedAt)
        var metricContainer = try container.nestedUnkeyedContainer(forKey: .metrics)
        var decodedMetrics: [CapacityMetric] = []
        var diagnostics: [ContractDiagnostic] = []
        while !metricContainer.isAtEnd {
            let index = metricContainer.currentIndex
            let metricDecoder = try metricContainer.superDecoder()
            do {
                decodedMetrics.append(try CapacityMetric(from: metricDecoder))
            } catch is UnsupportedMetricDiscriminator {
                diagnostics.append(
                    ContractDiagnostic(
                        code: .unsupportedMetricDiscriminator,
                        field: "metrics[\(index)]"
                    )
                )
            }
        }
        metrics = decodedMetrics
        decodingDiagnostics = diagnostics
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contractVersion, forKey: .contractVersion)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(surfaceID, forKey: .surfaceID)
        try container.encode(savedAccountID, forKey: .savedAccountID)
        try container.encode(accountContexts, forKey: .accountContexts)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(metrics, forKey: .metrics)
    }

    private enum CodingKeys: String, CodingKey {
        case contractVersion
        case providerID
        case surfaceID
        case savedAccountID
        case accountContexts
        case observedAt
        case metrics
    }
}

private struct UnsupportedMetricDiscriminator: Error {}
