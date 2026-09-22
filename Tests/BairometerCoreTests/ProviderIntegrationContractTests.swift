import Foundation
import XCTest
@testable import BairometerCore

final class ProviderIntegrationContractTests: XCTestCase {
    func testContractVersionCompatibilityAndAdditiveObjectDecoding() throws {
        XCTAssertTrue(ContractVersion(major: 1, minor: 7).isCompatible())
        XCTAssertFalse(
            ContractVersion(major: 1, minor: 7).isCompatible(
                allowsNewerMinorVersion: false
            )
        )
        XCTAssertFalse(ContractVersion(major: 2, minor: 0).isCompatible())

        let data = Data(
            """
            {
              "providerID": "example",
              "surfaceID": "api",
              "displayName": "Example API",
              "interactionModel": "api",
              "regions": [{"regionID": "global", "displayName": "Global"}],
              "accountContextKinds": ["personal"],
              "capabilities": ["quota-windows"],
              "futureMetadata": {"ignored": true}
            }
            """.utf8
        )

        let surface = try JSONDecoder().decode(ProviderSurface.self, from: data)

        XCTAssertEqual(surface.surfaceID, "api")
        XCTAssertEqual(surface.accountContextKinds, [.personal])
    }

    func testCapacityValueUsesLosslessPlainDecimalStrings() throws {
        let original = CapacityValue(
            value: Decimal(string: "-1234567890.0123456789")!,
            origin: .reported
        )
        let encoded = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertEqual(object["value"] as? String, "-1234567890.0123456789")
        XCTAssertEqual(try JSONDecoder().decode(CapacityValue.self, from: encoded), original)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                CapacityValue.self,
                from: Data(#"{"value":"1e3","origin":"reported"}"#.utf8)
            )
        )
    }

    func testCapacityValueRejectsDecimalValuesThatWouldRound() {
        for value in [
            "999999999999999999999999999999999999999999",
            "1.234567890123456789012345678901234567891"
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    CapacityValue.self,
                    from: Data("{\"value\":\"\(value)\",\"origin\":\"reported\"}".utf8)
                ),
                value
            )
        }
    }

    func testCapacityValueRoundTripsExactBoundaryAndNormalizedZeroForms() throws {
        let cases = [
            ("99999999999999999999999999999999999999", "99999999999999999999999999999999999999"),
            ("0.00100", "0.001"),
            ("0001.00", "1"),
            ("-000.000", "0"),
            ("0000.00100", "0.001"),
            ("+00042.500", "42.5"),
            ("-00042.500", "-42.5"),
            ("-123.4500", "-123.45"),
            ("-0.00", "0")
        ]

        for (input, expectedEncodedValue) in cases {
            let decoded = try JSONDecoder().decode(
                CapacityValue.self,
                from: Data("{\"value\":\"\(input)\",\"origin\":\"reported\"}".utf8)
            )
            let encoded = try JSONEncoder().encode(decoded)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            )

            XCTAssertEqual(object["value"] as? String, expectedEncodedValue, input)
        }
    }

    func testAllSanitizedProviderContractFixturesDecodeAndValidate() throws {
        let fixtureDirectory = repositoryRoot
            .appendingPathComponent("docs/providers/contract-fixtures", isDirectory: true)
        let fixtureURLs = try FileManager.default.contentsOfDirectory(
            at: fixtureDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertEqual(
            fixtureURLs.map(\.lastPathComponent),
            ["claude.json", "codex.json", "minimax.json", "openrouter.json"]
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var fixturesByName: [String: ContractFixture] = [:]
        for fixtureURL in fixtureURLs {
            let fixture = try decoder.decode(
                ContractFixture.self,
                from: Data(contentsOf: fixtureURL)
            )
            XCTAssertEqual(fixture.fixtureVersion, 1, fixtureURL.lastPathComponent)
            let snapshots = fixture.snapshots.map {
                $0.capacitySnapshot(contractVersion: fixture.contractVersion)
            }
            XCTAssertNoThrow(
                try ProviderContractValidator.validate(
                    contractVersion: fixture.contractVersion,
                    surfaces: fixture.surfaces,
                    sources: fixture.sources,
                    snapshots: snapshots
                ),
                fixtureURL.lastPathComponent
            )
            fixturesByName[fixtureURL.lastPathComponent] = fixture
        }

        let openRouter = try XCTUnwrap(fixturesByName["openrouter.json"])
        XCTAssertTrue(
            openRouter.snapshots
                .flatMap(\.metrics)
                .contains { $0.unit == CapacityUnit(kind: .currency, currencyCode: "USD") }
        )
        XCTAssertTrue(
            openRouter.snapshots
                .flatMap(\.accountContexts)
                .contains { $0.kind == .credential }
        )

        let minimax = try XCTUnwrap(fixturesByName["minimax.json"])
        XCTAssertTrue(
            minimax.snapshots
                .flatMap(\.metrics)
                .contains {
                    $0.unit
                        == CapacityUnit(
                            kind: .providerDefined,
                            providerUnitID: "minimax.included-usage"
                        )
                }
        )
    }

    func testAccountContextTreeRejectsMissingParentsMultipleRootsAndCycles() {
        let surface = makeSurface(contextKinds: [.personal, .credential])
        let source = makeSource()

        let missingParent = makeSnapshot(contexts: [
            AccountContext(
                contextID: "credential",
                kind: .credential,
                regionID: "global",
                parentContextID: "missing"
            )
        ])
        assertValidation(
            missingParent,
            surface: surface,
            source: source,
            contains: [.missingRootContext, .missingParentContext]
        )

        let multipleRoots = makeSnapshot(contexts: [
            AccountContext(contextID: "one", kind: .personal, regionID: "global"),
            AccountContext(contextID: "two", kind: .credential, regionID: "global")
        ])
        assertValidation(
            multipleRoots,
            surface: surface,
            source: source,
            contains: [.multipleRootContexts]
        )

        let cycle = makeSnapshot(contexts: [
            AccountContext(
                contextID: "one",
                kind: .personal,
                regionID: "global",
                parentContextID: "two"
            ),
            AccountContext(
                contextID: "two",
                kind: .credential,
                regionID: "global",
                parentContextID: "one"
            )
        ])
        assertValidation(
            cycle,
            surface: surface,
            source: source,
            contains: [.missingRootContext, .contextCycle]
        )
    }

    func testAvailabilityStatesRemainDistinctAndValidateTheirValueRules() throws {
        let observedAt = Date(timeIntervalSince1970: 1_000)
        let metrics = [
            makeMetric(
                id: "known",
                availability: .known,
                values: CapacityValues(
                    consumed: CapacityValue(value: 125, origin: .reported),
                    limit: CapacityValue(value: 100, origin: .reported)
                ),
                conditions: [.overage],
                observedAt: observedAt
            ),
            makeMetric(
                id: "unlimited",
                availability: .unlimited,
                values: CapacityValues(
                    consumed: CapacityValue(value: 25, origin: .reported)
                ),
                observedAt: observedAt
            ),
            makeMetric(id: "unavailable", availability: .unavailable, observedAt: observedAt),
            makeMetric(id: "manual", availability: .manual, observedAt: observedAt),
            makeMetric(id: "unknown", availability: .unknown, observedAt: observedAt)
        ]
        let snapshot = makeSnapshot(metrics: metrics, observedAt: observedAt)

        try ProviderContractValidator.validate(
            snapshot: snapshot,
            surface: makeSurface(),
            sources: [makeSource()]
        )

        XCTAssertEqual(metrics.map(\.availability), [
            .known, .unlimited, .unavailable, .manual, .unknown
        ])

        let invalid = makeSnapshot(
            metrics: [
                makeMetric(
                    id: "manual",
                    availability: .manual,
                    values: CapacityValues(
                        remaining: CapacityValue(value: 1, origin: .reported)
                    ),
                    observedAt: observedAt
                )
            ],
            observedAt: observedAt
        )
        assertValidation(
            invalid,
            surface: makeSurface(),
            source: makeSource(),
            contains: [.invalidAvailability]
        )
    }

    func testSingleSnapshotValidationRejectsInvalidSourceRegistryProvenance() {
        let snapshot = makeSnapshot(
            metrics: [
                makeMetric(
                    id: "known",
                    availability: .known,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 1, origin: .reported)
                    )
                )
            ]
        )

        assertValidation(
            snapshot,
            surface: makeSurface(),
            sources: [makeSource(providerID: "other")],
            contains: [.providerMismatch, .missingSource]
        )
        assertValidation(
            snapshot,
            surface: makeSurface(),
            sources: [makeSource(surfaceID: "other")],
            contains: [.surfaceMismatch, .missingSource]
        )
        assertValidation(
            snapshot,
            surface: makeSurface(),
            sources: [makeSource(capabilities: ["quota-windows", "credits"])],
            contains: [.unsupportedCapability]
        )
        assertValidation(
            snapshot,
            surface: makeSurface(),
            sources: [makeSource(), makeSource()],
            contains: [.duplicateIdentifier]
        )
    }

    func testDerivedValuesRequireSupportedTargetsAndExactDecimalResults() throws {
        let correctMetric = makeMetric(
            id: "correct",
            availability: .known,
            values: CapacityValues(
                consumed: CapacityValue(
                    value: Decimal(string: "0.1")!,
                    origin: .reported
                ),
                remaining: CapacityValue(
                    value: Decimal(string: "0.2")!,
                    origin: .derived
                ),
                limit: CapacityValue(
                    value: Decimal(string: "0.3")!,
                    origin: .reported
                )
            ),
            derivations: [
                Derivation(
                    kind: .remainingFromLimitMinusConsumed,
                    target: .remaining,
                    inputs: [.limit, .consumed]
                )
            ]
        )

        try ProviderContractValidator.validate(
            snapshot: makeSnapshot(metrics: [correctMetric]),
            surface: makeSurface(),
            sources: [makeSource()]
        )

        let wrongResult = makeMetric(
            id: "wrong-result",
            availability: .known,
            values: CapacityValues(
                consumed: CapacityValue(value: 25, origin: .reported),
                remaining: CapacityValue(value: 999, origin: .derived),
                limit: CapacityValue(value: 100, origin: .reported)
            ),
            derivations: [
                Derivation(
                    kind: .remainingFromLimitMinusConsumed,
                    target: .remaining,
                    inputs: [.limit, .consumed]
                )
            ]
        )
        assertValidation(
            makeSnapshot(metrics: [wrongResult]),
            surface: makeSurface(),
            source: makeSource(),
            contains: [.invalidDerivation]
        )

        let derivedLimit = makeMetric(
            id: "derived-limit",
            availability: .known,
            values: CapacityValues(
                consumed: CapacityValue(value: 25, origin: .reported),
                remaining: CapacityValue(value: 75, origin: .derived),
                limit: CapacityValue(value: 100, origin: .derived)
            ),
            derivations: [
                Derivation(
                    kind: .remainingFromLimitMinusConsumed,
                    target: .remaining,
                    inputs: [.limit, .consumed]
                )
            ]
        )
        assertValidation(
            makeSnapshot(metrics: [derivedLimit]),
            surface: makeSurface(),
            source: makeSource(),
            contains: [.invalidDerivation]
        )
    }

    func testUnknownFreshnessPolicyRejectsFutureValidityClaim() {
        let observedAt = Date(timeIntervalSince1970: 1_000)
        let metric = makeMetric(
            id: "future-validity",
            availability: .known,
            values: CapacityValues(
                consumed: CapacityValue(value: 1, origin: .reported)
            ),
            observedAt: observedAt,
            validUntil: Date(timeIntervalSince1970: 1_100)
        )

        assertValidation(
            makeSnapshot(metrics: [metric], observedAt: observedAt),
            surface: makeSurface(),
            source: makeSource(freshnessPolicy: FreshnessPolicy(kind: .unknown)),
            contains: [.invalidFreshness]
        )
    }

    func testCurrencyUnitRequiresThreeUppercaseASCIILetters() throws {
        for code in ["USD", "EUR", "ZZZ"] {
            let structurallyValidCurrency = makeMetric(
                id: code.lowercased(),
                availability: .known,
                values: CapacityValues(
                    consumed: CapacityValue(value: 1, origin: .reported)
                ),
                unit: CapacityUnit(kind: .currency, currencyCode: code)
            )
            try ProviderContractValidator.validate(
                snapshot: makeSnapshot(metrics: [structurallyValidCurrency]),
                surface: makeSurface(),
                sources: [makeSource()]
            )
        }

        for (index, code) in ["usd", "US", "USDD", "US$", "АБВ", "USD\n"].enumerated() {
            let structurallyInvalidCurrency = makeMetric(
                id: "invalid-\(index)",
                availability: .known,
                values: CapacityValues(
                    consumed: CapacityValue(value: 1, origin: .reported)
                ),
                unit: CapacityUnit(kind: .currency, currencyCode: code)
            )
            assertValidation(
                makeSnapshot(metrics: [structurallyInvalidCurrency]),
                surface: makeSurface(),
                source: makeSource(),
                contains: [.invalidUnit]
            )
        }
    }

    func testSnapshotDropsOnlyMetricWithUnknownRequiredDiscriminator() throws {
        let snapshot = makeSnapshot(
            metrics: [
                makeMetric(
                    id: "future",
                    availability: .known,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 1, origin: .reported)
                    )
                ),
                makeMetric(
                    id: "known",
                    availability: .known,
                    values: CapacityValues(
                        consumed: CapacityValue(value: 2, origin: .reported)
                    )
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var metrics = try XCTUnwrap(object["metrics"] as? [[String: Any]])
        metrics[0]["availability"] = "future-state"
        object["metrics"] = metrics
        object["futureMetadata"] = ["ignored": true]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            CapacitySnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.metrics.map(\.metricID), ["known"])
        XCTAssertEqual(decoded.decodingDiagnostics, [
            ContractDiagnostic(
                code: .unsupportedMetricDiscriminator,
                field: "metrics[0]"
            )
        ])
    }

    func testLegacyBridgeProjectsPercentageWindowsWithoutClampingOrFreeFormValues() throws {
        let observedAt = Date(timeIntervalSince1970: 10_000)
        let resetAt = Date(timeIntervalSince1970: 20_000)
        let legacy = UsageSnapshot(
            providerID: "mock",
            accountID: "work",
            accountDisplayName: "Work",
            displayName: "Mock",
            status: .warning,
            periodLabel: "Weekly",
            usedPercent: 135,
            remainingLabel: "Provider-specific text",
            resetAt: resetAt,
            limitWindows: [
                UsageLimitWindow(
                    id: "weekly",
                    displayName: "Weekly",
                    usedPercent: 135,
                    remainingLabel: "Provider-specific text",
                    resetAt: resetAt
                )
            ],
            lastUpdatedAt: observedAt,
            confidence: .localEstimate,
            source: "Generated data",
            warnings: ["Presentation-only warning"]
        )
        let bridge = LegacyUsageSnapshotBridge(
            surface: makeSurface(),
            source: makeSource(),
            accountContext: makeRootContext()
        )

        let projected = try bridge.makeCapacitySnapshot(from: legacy)
        let metric = try XCTUnwrap(projected.metrics.first)

        XCTAssertEqual(metric.metricID, "weekly")
        XCTAssertEqual(metric.availability, .known)
        XCTAssertEqual(metric.values?.consumed?.value, 135)
        XCTAssertEqual(metric.values?.remaining?.value, -35)
        XCTAssertEqual(metric.values?.remaining?.origin, .derived)
        XCTAssertEqual(metric.derivations.map(\.kind), [.percentComplement])
        XCTAssertEqual(metric.window.kind, .unknown)
        XCTAssertEqual(metric.window.nextTransition?.at, resetAt)
        XCTAssertNil(metric.window.durationSeconds)
    }

    func testLegacyBridgeKeepsManualUnavailableAndUnknownDistinct() throws {
        let bridge = LegacyUsageSnapshotBridge(
            surface: makeSurface(),
            source: makeSource(),
            accountContext: makeRootContext()
        )

        let manual = try bridge.makeCapacitySnapshot(
            from: legacyState(status: .unavailable, confidence: .manual)
        )
        let unavailable = try bridge.makeCapacitySnapshot(
            from: legacyState(status: .unavailable, confidence: .unknown)
        )
        let unknown = try bridge.makeCapacitySnapshot(
            from: legacyState(status: .error, confidence: .unknown)
        )

        XCTAssertEqual(manual.metrics.first?.availability, .manual)
        XCTAssertEqual(unavailable.metrics.first?.availability, .unavailable)
        XCTAssertEqual(unknown.metrics.first?.availability, .unknown)
        XCTAssertNil(manual.metrics.first?.values)
        XCTAssertNil(unavailable.metrics.first?.values)
        XCTAssertNil(unknown.metrics.first?.values)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeSurface(
        contextKinds: [AccountContextKind] = [.personal]
    ) -> ProviderSurface {
        ProviderSurface(
            providerID: "mock",
            surfaceID: "subscription",
            displayName: "Mock Subscription",
            interactionModel: .subscription,
            regions: [RegionDescriptor(regionID: "global", displayName: "Global")],
            accountContextKinds: contextKinds,
            capabilities: ["quota-windows"]
        )
    }

    private func makeSource(
        providerID: String = "mock",
        surfaceID: String = "subscription",
        sourceID: String = "legacy",
        freshnessPolicy: FreshnessPolicy = FreshnessPolicy(kind: .unknown),
        capabilities: [String] = ["quota-windows"]
    ) -> SourceDescriptor {
        SourceDescriptor(
            providerID: providerID,
            surfaceID: surfaceID,
            sourceID: sourceID,
            displayName: "Legacy snapshot",
            kind: .localEstimate,
            authority: .estimated,
            maturity: .stable,
            defaultConfidence: .localEstimate,
            freshnessPolicy: freshnessPolicy,
            capabilities: capabilities,
            authRequirement: AuthRequirement(
                category: .none,
                privilege: .none,
                storageBoundary: .none
            )
        )
    }

    private func makeRootContext() -> AccountContext {
        AccountContext(
            contextID: "account",
            kind: .personal,
            displayName: "Account",
            regionID: "global"
        )
    }

    private func makeSnapshot(
        contexts: [AccountContext]? = nil,
        metrics: [CapacityMetric] = [],
        observedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> CapacitySnapshot {
        CapacitySnapshot(
            providerID: "mock",
            surfaceID: "subscription",
            savedAccountID: "work",
            accountContexts: contexts ?? [makeRootContext()],
            observedAt: observedAt,
            metrics: metrics
        )
    }

    private func makeMetric(
        id: String,
        availability: CapacityAvailability,
        values: CapacityValues? = nil,
        conditions: [CapacityCondition] = [],
        observedAt: Date = Date(timeIntervalSince1970: 1_000),
        validUntil: Date? = nil,
        unit: CapacityUnit = CapacityUnit(kind: .percent),
        derivations: [Derivation] = []
    ) -> CapacityMetric {
        CapacityMetric(
            metricID: id,
            accountContextID: "account",
            sourceID: "legacy",
            capability: "quota-windows",
            displayName: id,
            availability: availability,
            conditions: conditions,
            unit: unit,
            values: values,
            window: CapacityWindow(kind: .unknown),
            freshness: ObservationFreshness(
                observedAt: observedAt,
                validUntil: validUntil
            ),
            confidence: .localEstimate,
            derivations: derivations
        )
    }

    private func legacyState(
        status: UsageStatus,
        confidence: ConfidenceLevel
    ) -> UsageSnapshot {
        UsageSnapshot(
            providerID: "mock",
            accountID: "work",
            accountDisplayName: "Work",
            displayName: "Mock",
            status: status,
            remainingLabel: "Presentation-only state",
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
            confidence: confidence,
            source: "Legacy"
        )
    }

    private func assertValidation(
        _ snapshot: CapacitySnapshot,
        surface: ProviderSurface,
        source: SourceDescriptor,
        contains expectedCodes: Set<ContractValidationCode>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertValidation(
            snapshot,
            surface: surface,
            sources: [source],
            contains: expectedCodes,
            file: file,
            line: line
        )
    }

    private func assertValidation(
        _ snapshot: CapacitySnapshot,
        surface: ProviderSurface,
        sources: [SourceDescriptor],
        contains expectedCodes: Set<ContractValidationCode>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try ProviderContractValidator.validate(
                snapshot: snapshot,
                surface: surface,
                sources: sources
            )
            XCTFail("Expected contract validation to fail.", file: file, line: line)
        } catch let failure as ContractValidationFailure {
            let codes = Set(failure.issues.map(\.code))
            XCTAssertTrue(
                expectedCodes.isSubset(of: codes),
                "Expected \(expectedCodes), received \(codes).",
                file: file,
                line: line
            )
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private struct ContractFixture: Decodable {
    let fixtureVersion: UInt
    let contractVersion: ContractVersion
    let surfaces: [ProviderSurface]
    let sources: [SourceDescriptor]
    let snapshots: [ContractFixtureSnapshot]
}

private struct ContractFixtureSnapshot: Decodable {
    let providerID: String
    let surfaceID: String
    let savedAccountID: String
    let accountContexts: [AccountContext]
    let observedAt: Date
    let metrics: [CapacityMetric]

    func capacitySnapshot(contractVersion: ContractVersion) -> CapacitySnapshot {
        CapacitySnapshot(
            contractVersion: contractVersion,
            providerID: providerID,
            surfaceID: surfaceID,
            savedAccountID: savedAccountID,
            accountContexts: accountContexts,
            observedAt: observedAt,
            metrics: metrics
        )
    }
}
