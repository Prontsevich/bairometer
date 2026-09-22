import Foundation

public enum ContractValidationCode: String, Codable, Equatable, Sendable {
    case incompatibleVersion = "incompatible-version"
    case emptyRequiredField = "empty-required-field"
    case duplicateIdentifier = "duplicate-identifier"
    case invalidFreshnessPolicy = "invalid-freshness-policy"
    case invalidAuthRequirement = "invalid-auth-requirement"
    case providerMismatch = "provider-mismatch"
    case surfaceMismatch = "surface-mismatch"
    case missingSurface = "missing-surface"
    case missingSource = "missing-source"
    case missingAccountContext = "missing-account-context"
    case unsupportedCapability = "unsupported-capability"
    case unsupportedContextKind = "unsupported-context-kind"
    case missingRegion = "missing-region"
    case missingRootContext = "missing-root-context"
    case multipleRootContexts = "multiple-root-contexts"
    case missingParentContext = "missing-parent-context"
    case contextCycle = "context-cycle"
    case invalidUnit = "invalid-unit"
    case invalidAvailability = "invalid-availability"
    case invalidWindow = "invalid-window"
    case invalidFreshness = "invalid-freshness"
    case invalidDerivation = "invalid-derivation"
    case observationAfterSnapshot = "observation-after-snapshot"
}

public struct ContractValidationIssue: Codable, Equatable, Sendable {
    public let code: ContractValidationCode
    public let field: String

    public init(code: ContractValidationCode, field: String) {
        self.code = code
        self.field = field
    }
}

public struct ContractValidationFailure: Error, LocalizedError, Equatable, Sendable {
    public let issues: [ContractValidationIssue]

    public var errorDescription: String? {
        guard let first = issues.first else {
            return "Provider contract validation failed."
        }
        return "Provider contract validation failed at \(first.field) (\(first.code.rawValue))."
    }

    public init(issues: [ContractValidationIssue]) {
        self.issues = issues
    }
}

public enum ProviderContractValidator {
    public static func validate(
        contractVersion: ContractVersion,
        surfaces: [ProviderSurface],
        sources: [SourceDescriptor],
        snapshots: [CapacitySnapshot],
        supportedVersion: ContractVersion = .v1,
        allowsNewerMinorVersion: Bool = true
    ) throws {
        let issues = issues(
            contractVersion: contractVersion,
            surfaces: surfaces,
            sources: sources,
            snapshots: snapshots,
            supportedVersion: supportedVersion,
            allowsNewerMinorVersion: allowsNewerMinorVersion
        )
        guard issues.isEmpty else {
            throw ContractValidationFailure(issues: issues)
        }
    }

    public static func issues(
        contractVersion: ContractVersion,
        surfaces: [ProviderSurface],
        sources: [SourceDescriptor],
        snapshots: [CapacitySnapshot],
        supportedVersion: ContractVersion = .v1,
        allowsNewerMinorVersion: Bool = true
    ) -> [ContractValidationIssue] {
        var result: [ContractValidationIssue] = []

        if !contractVersion.isCompatible(
            with: supportedVersion,
            allowsNewerMinorVersion: allowsNewerMinorVersion
        ) {
            result.append(.init(code: .incompatibleVersion, field: "contractVersion"))
        }

        var surfaceKeys = Set<String>()
        for (index, surface) in surfaces.enumerated() {
            let field = "surfaces[\(index)]"
            validateSurface(surface, field: field, issues: &result)
            if !surfaceKeys.insert(surfaceKey(surface.providerID, surface.surfaceID)).inserted {
                result.append(.init(code: .duplicateIdentifier, field: "\(field).surfaceID"))
            }
        }

        var sourceKeys = Set<String>()
        for (index, source) in sources.enumerated() {
            let field = "sources[\(index)]"
            validateSource(source, field: field, issues: &result)
            let key = sourceKey(source.providerID, source.surfaceID, source.sourceID)
            if !sourceKeys.insert(key).inserted {
                result.append(.init(code: .duplicateIdentifier, field: "\(field).sourceID"))
            }

            guard let surface = surfaces.first(where: {
                $0.providerID == source.providerID && $0.surfaceID == source.surfaceID
            }) else {
                result.append(.init(code: .missingSurface, field: field))
                continue
            }
            for capability in source.capabilities where !surface.capabilities.contains(capability) {
                result.append(.init(code: .unsupportedCapability, field: "\(field).capabilities"))
            }
        }

        for (index, snapshot) in snapshots.enumerated() {
            let field = "snapshots[\(index)]"
            if snapshot.contractVersion != contractVersion {
                result.append(.init(code: .incompatibleVersion, field: "\(field).contractVersion"))
            }
            guard let surface = surfaces.first(where: {
                $0.providerID == snapshot.providerID && $0.surfaceID == snapshot.surfaceID
            }) else {
                result.append(.init(code: .missingSurface, field: field))
                continue
            }
            let matchingSources = sources.filter {
                $0.providerID == snapshot.providerID && $0.surfaceID == snapshot.surfaceID
            }
            validateSnapshot(
                snapshot,
                surface: surface,
                sources: matchingSources,
                field: field,
                issues: &result
            )
        }

        return result
    }

    public static func validate(
        snapshot: CapacitySnapshot,
        surface: ProviderSurface,
        sources: [SourceDescriptor],
        supportedVersion: ContractVersion = .v1,
        allowsNewerMinorVersion: Bool = true
    ) throws {
        var result: [ContractValidationIssue] = []
        if !snapshot.contractVersion.isCompatible(
            with: supportedVersion,
            allowsNewerMinorVersion: allowsNewerMinorVersion
        ) {
            result.append(.init(code: .incompatibleVersion, field: "contractVersion"))
        }
        validateSurface(surface, field: "surface", issues: &result)
        var sourceIDs = Set<String>()
        for (index, source) in sources.enumerated() {
            let field = "sources[\(index)]"
            validateSource(source, field: field, issues: &result)
            if !sourceIDs.insert(source.sourceID).inserted {
                result.append(.init(code: .duplicateIdentifier, field: "\(field).sourceID"))
            }
            if source.providerID != surface.providerID {
                result.append(.init(code: .providerMismatch, field: "\(field).providerID"))
            }
            if source.surfaceID != surface.surfaceID {
                result.append(.init(code: .surfaceMismatch, field: "\(field).surfaceID"))
            }
            for capability in source.capabilities where !surface.capabilities.contains(capability) {
                result.append(.init(code: .unsupportedCapability, field: "\(field).capabilities"))
            }
        }
        let matchingSources = sources.filter {
            $0.providerID == snapshot.providerID && $0.surfaceID == snapshot.surfaceID
        }
        validateSnapshot(
            snapshot,
            surface: surface,
            sources: matchingSources,
            field: "snapshot",
            issues: &result
        )
        guard result.isEmpty else {
            throw ContractValidationFailure(issues: result)
        }
    }

    private static func validateSurface(
        _ surface: ProviderSurface,
        field: String,
        issues: inout [ContractValidationIssue]
    ) {
        requireText(surface.providerID, field: "\(field).providerID", issues: &issues)
        requireText(surface.surfaceID, field: "\(field).surfaceID", issues: &issues)
        requireText(surface.displayName, field: "\(field).displayName", issues: &issues)
        requireNonemptyUnique(
            surface.regions.map(\.regionID),
            field: "\(field).regions",
            issues: &issues
        )
        for (index, region) in surface.regions.enumerated() {
            requireText(region.displayName, field: "\(field).regions[\(index)].displayName", issues: &issues)
        }
        requireNonemptyUnique(
            surface.accountContextKinds.map(\.rawValue),
            field: "\(field).accountContextKinds",
            issues: &issues
        )
        requireNonemptyUnique(
            surface.capabilities,
            field: "\(field).capabilities",
            issues: &issues
        )
    }

    private static func validateSource(
        _ source: SourceDescriptor,
        field: String,
        issues: inout [ContractValidationIssue]
    ) {
        requireText(source.providerID, field: "\(field).providerID", issues: &issues)
        requireText(source.surfaceID, field: "\(field).surfaceID", issues: &issues)
        requireText(source.sourceID, field: "\(field).sourceID", issues: &issues)
        requireText(source.displayName, field: "\(field).displayName", issues: &issues)
        requireUnique(source.capabilities, field: "\(field).capabilities", issues: &issues)
        requireUnique(
            source.authRequirement.requiredScopes,
            field: "\(field).authRequirement.requiredScopes",
            issues: &issues
        )

        switch source.freshnessPolicy.kind {
        case .maximumAge:
            if source.freshnessPolicy.maxAgeSeconds == nil || source.freshnessPolicy.maxAgeSeconds == 0 {
                issues.append(.init(
                    code: .invalidFreshnessPolicy,
                    field: "\(field).freshnessPolicy.maxAgeSeconds"
                ))
            }
        case .sourceExpiry, .manual, .unknown:
            if source.freshnessPolicy.maxAgeSeconds != nil {
                issues.append(.init(
                    code: .invalidFreshnessPolicy,
                    field: "\(field).freshnessPolicy.maxAgeSeconds"
                ))
            }
        }

        let auth = source.authRequirement
        if auth.category == .none {
            if auth.privilege != .none
                || auth.storageBoundary != .none
                || !auth.requiredScopes.isEmpty {
                issues.append(.init(code: .invalidAuthRequirement, field: "\(field).authRequirement"))
            }
        } else if auth.privilege == .none {
            issues.append(.init(code: .invalidAuthRequirement, field: "\(field).authRequirement"))
        }
    }

    private static func validateSnapshot(
        _ snapshot: CapacitySnapshot,
        surface: ProviderSurface,
        sources: [SourceDescriptor],
        field: String,
        issues: inout [ContractValidationIssue]
    ) {
        requireText(snapshot.providerID, field: "\(field).providerID", issues: &issues)
        requireText(snapshot.surfaceID, field: "\(field).surfaceID", issues: &issues)
        requireText(snapshot.savedAccountID, field: "\(field).savedAccountID", issues: &issues)

        if snapshot.providerID != surface.providerID {
            issues.append(.init(code: .providerMismatch, field: "\(field).providerID"))
        }
        if snapshot.surfaceID != surface.surfaceID {
            issues.append(.init(code: .surfaceMismatch, field: "\(field).surfaceID"))
        }

        validateContexts(
            snapshot.accountContexts,
            surface: surface,
            field: "\(field).accountContexts",
            issues: &issues
        )

        let contextIDs = Set(snapshot.accountContexts.map(\.contextID))
        var metricKeys = Set<String>()
        for (index, metric) in snapshot.metrics.enumerated() {
            let metricField = "\(field).metrics[\(index)]"
            validateMetric(
                metric,
                snapshot: snapshot,
                surface: surface,
                sources: sources,
                contextIDs: contextIDs,
                field: metricField,
                issues: &issues
            )
            let key = "\(metric.accountContextID)\u{1f}\(metric.sourceID)\u{1f}\(metric.metricID)"
            if !metricKeys.insert(key).inserted {
                issues.append(.init(code: .duplicateIdentifier, field: "\(metricField).metricID"))
            }
        }
    }

    private static func validateContexts(
        _ contexts: [AccountContext],
        surface: ProviderSurface,
        field: String,
        issues: inout [ContractValidationIssue]
    ) {
        var contextsByID: [String: AccountContext] = [:]
        for (index, context) in contexts.enumerated() {
            let contextField = "\(field)[\(index)]"
            requireText(context.contextID, field: "\(contextField).contextID", issues: &issues)
            requireText(context.regionID, field: "\(contextField).regionID", issues: &issues)
            if contextsByID.updateValue(context, forKey: context.contextID) != nil {
                issues.append(.init(code: .duplicateIdentifier, field: "\(contextField).contextID"))
            }
            if !surface.accountContextKinds.contains(context.kind) {
                issues.append(.init(code: .unsupportedContextKind, field: "\(contextField).kind"))
            }
            if !surface.regions.contains(where: { $0.regionID == context.regionID }) {
                issues.append(.init(code: .missingRegion, field: "\(contextField).regionID"))
            }
        }

        let roots = contexts.filter { $0.parentContextID == nil }
        if roots.isEmpty {
            issues.append(.init(code: .missingRootContext, field: field))
        } else if roots.count > 1 {
            issues.append(.init(code: .multipleRootContexts, field: field))
        }

        for (index, context) in contexts.enumerated() {
            guard let parentID = context.parentContextID else {
                continue
            }
            if contextsByID[parentID] == nil {
                issues.append(.init(
                    code: .missingParentContext,
                    field: "\(field)[\(index)].parentContextID"
                ))
            }
        }

        var resolved = Set<String>()
        var visiting = Set<String>()
        func visit(_ contextID: String) -> Bool {
            if resolved.contains(contextID) {
                return false
            }
            if !visiting.insert(contextID).inserted {
                return true
            }
            if let parentID = contextsByID[contextID]?.parentContextID,
               contextsByID[parentID] != nil,
               visit(parentID) {
                return true
            }
            visiting.remove(contextID)
            resolved.insert(contextID)
            return false
        }

        if contexts.contains(where: { visit($0.contextID) }) {
            issues.append(.init(code: .contextCycle, field: field))
        }
    }

    private static func validateMetric(
        _ metric: CapacityMetric,
        snapshot: CapacitySnapshot,
        surface: ProviderSurface,
        sources: [SourceDescriptor],
        contextIDs: Set<String>,
        field: String,
        issues: inout [ContractValidationIssue]
    ) {
        requireText(metric.metricID, field: "\(field).metricID", issues: &issues)
        requireText(metric.accountContextID, field: "\(field).accountContextID", issues: &issues)
        requireText(metric.sourceID, field: "\(field).sourceID", issues: &issues)
        requireText(metric.capability, field: "\(field).capability", issues: &issues)
        requireText(metric.displayName, field: "\(field).displayName", issues: &issues)

        if !contextIDs.contains(metric.accountContextID) {
            issues.append(.init(code: .missingAccountContext, field: "\(field).accountContextID"))
        }

        let source = sources.first { $0.sourceID == metric.sourceID }
        if source == nil {
            issues.append(.init(code: .missingSource, field: "\(field).sourceID"))
        }
        if !surface.capabilities.contains(metric.capability)
            || source.map({ !$0.capabilities.contains(metric.capability) }) == true {
            issues.append(.init(code: .unsupportedCapability, field: "\(field).capability"))
        }

        requireUnique(
            metric.conditions.map(\.rawValue),
            field: "\(field).conditions",
            issues: &issues
        )
        validateUnit(metric.unit, field: "\(field).unit", issues: &issues)
        validateAvailability(metric, field: field, issues: &issues)
        validateWindow(metric.window, field: "\(field).window", issues: &issues)

        if metric.freshness.observedAt > snapshot.observedAt {
            issues.append(.init(code: .observationAfterSnapshot, field: "\(field).freshness.observedAt"))
        }
        if let validUntil = metric.freshness.validUntil,
           validUntil <= metric.freshness.observedAt {
            issues.append(.init(code: .invalidFreshness, field: "\(field).freshness.validUntil"))
        }
        if source?.freshnessPolicy.kind == .sourceExpiry && metric.freshness.validUntil == nil {
            issues.append(.init(code: .invalidFreshness, field: "\(field).freshness.validUntil"))
        }
        if source?.freshnessPolicy.kind == .unknown && metric.freshness.validUntil != nil {
            issues.append(.init(code: .invalidFreshness, field: "\(field).freshness.validUntil"))
        }

        validateDerivations(metric, field: field, issues: &issues)
    }

    private static func validateUnit(
        _ unit: CapacityUnit,
        field: String,
        issues: inout [ContractValidationIssue]
    ) {
        switch unit.kind {
        case .currency:
            guard let currencyCode = unit.currencyCode,
                  isThreeLetterASCIICurrencyCode(currencyCode),
                  unit.timeUnit == nil,
                  unit.providerUnitID == nil else {
                issues.append(.init(code: .invalidUnit, field: field))
                return
            }
        case .time:
            guard unit.currencyCode == nil,
                  unit.timeUnit != nil,
                  unit.providerUnitID == nil else {
                issues.append(.init(code: .invalidUnit, field: field))
                return
            }
        case .providerDefined:
            guard unit.currencyCode == nil,
                  unit.timeUnit == nil,
                  let providerUnitID = unit.providerUnitID,
                  providerUnitID.contains("."),
                  !providerUnitID.hasPrefix("."),
                  !providerUnitID.hasSuffix(".") else {
                issues.append(.init(code: .invalidUnit, field: field))
                return
            }
        default:
            if unit.currencyCode != nil || unit.timeUnit != nil || unit.providerUnitID != nil {
                issues.append(.init(code: .invalidUnit, field: field))
            }
        }
    }

    private static func isThreeLetterASCIICurrencyCode(_ code: String) -> Bool {
        let scalars = code.unicodeScalars
        return scalars.count == 3 && scalars.allSatisfy { (65...90).contains($0.value) }
    }

    private static func validateAvailability(
        _ metric: CapacityMetric,
        field: String,
        issues: inout [ContractValidationIssue]
    ) {
        let values = metric.values
        switch metric.availability {
        case .known:
            if values == nil || values?.isEmpty == true {
                issues.append(.init(code: .invalidAvailability, field: "\(field).values"))
            }
        case .unlimited:
            if values?.isEmpty == true
                || values?.remaining != nil
                || values?.limit != nil
                || values?.consumed?.origin == .derived {
                issues.append(.init(code: .invalidAvailability, field: "\(field).values"))
            }
        case .unavailable, .manual, .unknown:
            if values != nil {
                issues.append(.init(code: .invalidAvailability, field: "\(field).values"))
            }
        }

        for value in [values?.consumed, values?.remaining, values?.limit].compactMap({ $0 })
            where value.value.isNaN {
            issues.append(.init(code: .invalidAvailability, field: "\(field).values"))
        }
    }

    private static func validateWindow(
        _ window: CapacityWindow,
        field: String,
        issues: inout [ContractValidationIssue]
    ) {
        if window.durationSeconds == 0 {
            issues.append(.init(code: .invalidWindow, field: "\(field).durationSeconds"))
        }
        if let startsAt = window.startsAt,
           let endsAt = window.endsAt,
           startsAt >= endsAt {
            issues.append(.init(code: .invalidWindow, field: field))
        }
        if window.kind == .none,
           window.durationSeconds != nil
            || window.startsAt != nil
            || window.endsAt != nil
            || window.nextTransition != nil {
            issues.append(.init(code: .invalidWindow, field: field))
        }
    }

    private static func validateDerivations(
        _ metric: CapacityMetric,
        field: String,
        issues: inout [ContractValidationIssue]
    ) {
        let derivations = metric.derivations
        requireUnique(
            derivations.map(\.target.rawValue),
            field: "\(field).derivations",
            issues: &issues
        )

        for (index, derivation) in derivations.enumerated() {
            let derivationField = "\(field).derivations[\(index)]"
            let inputs = Set(derivation.inputs)
            let expectedInputs: Set<CapacityValueRole>
            let expectedTarget: DerivationTarget
            let expectedValue: Decimal?

            switch derivation.kind {
            case .percentComplement:
                expectedInputs = [.consumed]
                expectedTarget = .remaining
                expectedValue = metric.values?.consumed.map { 100 - $0.value }
                if metric.unit.kind != .percent {
                    issues.append(.init(code: .invalidDerivation, field: derivationField))
                }
            case .consumedFromLimitMinusRemaining:
                expectedInputs = [.limit, .remaining]
                expectedTarget = .consumed
                if let limit = metric.values?.limit?.value,
                   let remaining = metric.values?.remaining?.value {
                    expectedValue = limit - remaining
                } else {
                    expectedValue = nil
                }
            case .remainingFromLimitMinusConsumed:
                expectedInputs = [.limit, .consumed]
                expectedTarget = .remaining
                if let limit = metric.values?.limit?.value,
                   let consumed = metric.values?.consumed?.value {
                    expectedValue = limit - consumed
                } else {
                    expectedValue = nil
                }
            case .utilizationFromConsumedAndLimit:
                expectedInputs = [.consumed, .limit]
                expectedTarget = .utilization
                expectedValue = nil
                if metric.values?.limit?.value == Decimal.zero {
                    issues.append(.init(code: .invalidDerivation, field: derivationField))
                }
            }

            if inputs.count != derivation.inputs.count
                || inputs != expectedInputs
                || derivation.target != expectedTarget {
                issues.append(.init(code: .invalidDerivation, field: derivationField))
            }

            for input in inputs where metric.values?[input] == nil {
                issues.append(.init(code: .invalidDerivation, field: "\(derivationField).inputs"))
            }
            switch derivation.target {
            case .consumed:
                if metric.values?.consumed?.origin != .derived {
                    issues.append(.init(code: .invalidDerivation, field: "\(derivationField).target"))
                }
                if let expectedValue,
                   metric.values?.consumed?.value != expectedValue {
                    issues.append(.init(code: .invalidDerivation, field: "\(derivationField).target"))
                }
            case .remaining:
                if metric.values?.remaining?.origin != .derived {
                    issues.append(.init(code: .invalidDerivation, field: "\(derivationField).target"))
                }
                if let expectedValue,
                   metric.values?.remaining?.value != expectedValue {
                    issues.append(.init(code: .invalidDerivation, field: "\(derivationField).target"))
                }
            case .utilization:
                break
            }
        }

        let derivedRoles = CapacityValueRole.allCases.filter {
            metric.values?[$0]?.origin == .derived
        }
        for role in derivedRoles {
            switch role {
            case .consumed:
                if !derivations.contains(where: { $0.target == .consumed }) {
                    issues.append(.init(
                        code: .invalidDerivation,
                        field: "\(field).values.\(role.rawValue)"
                    ))
                }
            case .remaining:
                if !derivations.contains(where: { $0.target == .remaining }) {
                    issues.append(.init(
                        code: .invalidDerivation,
                        field: "\(field).values.\(role.rawValue)"
                    ))
                }
            case .limit:
                issues.append(.init(code: .invalidDerivation, field: "\(field).values.\(role.rawValue)"))
            }
        }
    }

    private static func requireText(
        _ value: String,
        field: String,
        issues: inout [ContractValidationIssue]
    ) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(code: .emptyRequiredField, field: field))
        }
    }

    private static func requireNonemptyUnique(
        _ values: [String],
        field: String,
        issues: inout [ContractValidationIssue]
    ) {
        if values.isEmpty {
            issues.append(.init(code: .emptyRequiredField, field: field))
        }
        requireUnique(values, field: field, issues: &issues)
    }

    private static func requireUnique(
        _ values: [String],
        field: String,
        issues: inout [ContractValidationIssue]
    ) {
        var seen = Set<String>()
        for value in values {
            requireText(value, field: field, issues: &issues)
            if !seen.insert(value).inserted {
                issues.append(.init(code: .duplicateIdentifier, field: field))
            }
        }
    }

    private static func surfaceKey(_ providerID: String, _ surfaceID: String) -> String {
        "\(providerID)\u{1f}\(surfaceID)"
    }

    private static func sourceKey(
        _ providerID: String,
        _ surfaceID: String,
        _ sourceID: String
    ) -> String {
        "\(providerID)\u{1f}\(surfaceID)\u{1f}\(sourceID)"
    }

}
