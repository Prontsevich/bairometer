import Darwin
import Foundation
import XCTest
@testable import BairometerCore

final class OpenRouterAPIClientTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_774_611_200)

    override func tearDown() {
        OpenRouterURLProtocolStub.clearHandler()
        super.tearDown()
    }

    func testRequestsUseFixedTrustedEndpointsAndSeparateCredentialCapabilities() async throws {
        let recorder = OpenRouterRequestRecorder()
        let currentKeyData = try fixture("current-key-monthly")
        let creditsData = try fixture("credits")
        OpenRouterURLProtocolStub.setHandler { request, stub in
            recorder.append(request)
            switch request.url?.path {
            case "/api/v1/key":
                stub.respond(statusCode: 200, data: currentKeyData)
            case "/api/v1/credits":
                stub.respond(statusCode: 200, data: creditsData)
            default:
                stub.respond(statusCode: 404, data: Data())
            }
        }
        let client = makeClient(timeout: 5)

        _ = try await client.fetchCurrentKeyCapacity(
            credential: try ordinaryCredential("synthetic-ordinary-credential")
        )
        _ = try await client.fetchManagementCredits(
            credential: try managementCredential("synthetic-management-credential")
        )

        let requests = recorder.requests
        XCTAssertEqual(requests.count, 2)
        assertRequest(
            requests[0],
            url: URLSessionOpenRouterAPIClient.currentKeyURL,
            credential: "synthetic-ordinary-credential"
        )
        assertRequest(
            requests[1],
            url: URLSessionOpenRouterAPIClient.managementCreditsURL,
            credential: "synthetic-management-credential"
        )
        XCTAssertFalse(requests.contains { $0.url?.path == "/api/v1/keys" })
    }

    func testCredentialWrappersEnforceProviderAndRoleWithoutExposingSecret() throws {
        let secretValue = "synthetic-role-secret"
        let secret = try CredentialSecret(secretValue)
        let ordinarySlot = credentialSlot(
            accountID: "private-ordinary-account",
            contextID: "private-ordinary-context",
            slotID: "private-ordinary-slot",
            role: .ordinary
        )
        let managementSlot = credentialSlot(
            accountID: "private-management-account",
            contextID: "private-management-context",
            slotID: "private-management-slot",
            role: .management
        )
        let wrongProviderSlot = credentialSlot(
            providerID: "another-provider",
            role: .ordinary
        )

        let ordinary = try OpenRouterOrdinaryCredential(
            slot: ordinarySlot,
            secret: secret
        )
        let management = try OpenRouterManagementCredential(
            slot: managementSlot,
            secret: secret
        )

        let rendered = [
            String(describing: ordinary),
            String(reflecting: ordinary),
            String(describing: management),
            String(reflecting: management)
        ].joined(separator: " ")
        for forbidden in [
            secretValue,
            ordinarySlot.accountID,
            ordinarySlot.contextID,
            ordinarySlot.slotID,
            managementSlot.accountID,
            managementSlot.contextID,
            managementSlot.slotID
        ] {
            XCTAssertFalse(rendered.contains(forbidden))
        }
        XCTAssertThrowsError(
            try OpenRouterOrdinaryCredential(
                slot: managementSlot,
                secret: secret
            )
        ) {
            XCTAssertEqual($0 as? OpenRouterCredentialRoleError, .roleMismatch)
        }
        XCTAssertThrowsError(
            try OpenRouterManagementCredential(
                slot: ordinarySlot,
                secret: secret
            )
        ) {
            XCTAssertEqual($0 as? OpenRouterCredentialRoleError, .roleMismatch)
        }
        XCTAssertThrowsError(
            try OpenRouterOrdinaryCredential(
                slot: wrongProviderSlot,
                secret: secret
            )
        ) {
            XCTAssertEqual($0 as? OpenRouterCredentialRoleError, .providerMismatch)
        }
    }

    func testCredentialIdentityOwnsMetricContextWithoutCallerOverride() async throws {
        installResponse(fixtureName: "current-key-monthly")
        let first = try await makeClient().fetchCurrentKeyCapacity(
            credential: try ordinaryCredential(
                "synthetic-first-credential",
                accountID: "first-account",
                contextID: "first-key-context",
                slotID: "first-slot"
            )
        )

        installResponse(fixtureName: "current-key-monthly")
        let second = try await makeClient().fetchCurrentKeyCapacity(
            credential: try ordinaryCredential(
                "synthetic-second-credential",
                accountID: "second-account",
                contextID: "second-key-context",
                slotID: "second-slot"
            )
        )

        XCTAssertTrue(
            first.metrics.allSatisfy {
                $0.accountContextID == "first-key-context"
            }
        )
        XCTAssertTrue(
            second.metrics.allSatisfy {
                $0.accountContextID == "second-key-context"
            }
        )
        XCTAssertFalse(
            first.metrics.contains {
                $0.accountContextID == "second-key-context"
            }
        )
    }

    func testRedirectsAreRejectedWithoutSendingCredentialToAnotherEndpoint() async throws {
        let recorder = OpenRouterRequestRecorder()
        OpenRouterURLProtocolStub.setHandler { request, stub in
            recorder.append(request)
            stub.respond(
                statusCode: 302,
                headers: ["Location": "https://example.invalid/untrusted"],
                data: Data()
            )
        }

        await assertCurrentKeyError(.httpFailure(statusCode: 302))
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(
            recorder.requests.first?.url,
            URLSessionOpenRouterAPIClient.currentKeyURL
        )
    }

    func testRedirectDelegateRejectsProposedRequestContainingAuthorization() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let originalTask = session.dataTask(
            with: URLSessionOpenRouterAPIClient.currentKeyURL
        )
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: URLSessionOpenRouterAPIClient.currentKeyURL,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Location": "https://example.invalid/untrusted"
                ]
            )
        )
        var redirectedRequest = URLRequest(
            url: try XCTUnwrap(URL(string: "https://example.invalid/untrusted"))
        )
        redirectedRequest.setValue(
            "Bearer synthetic-private-credential",
            forHTTPHeaderField: "Authorization"
        )

        let acceptedRequest: URLRequest? = await withCheckedContinuation {
            continuation in
            OpenRouterStreamingResponseDelegate(
                responseLimit: 32
            ).urlSession(
                session,
                task: originalTask,
                willPerformHTTPRedirection: response,
                newRequest: redirectedRequest
            ) {
                continuation.resume(returning: $0)
            }
        }

        XCTAssertNil(acceptedRequest)
    }

    func testDefaultSessionDisablesPersistentCookiesCachesAndCredentialStorage() {
        let session = URLSessionOpenRouterAPIClient.makeDefaultSession()
        defer { session.invalidateAndCancel() }
        let configuration = session.configuration

        XCTAssertNil(configuration.identifier)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertEqual(
            configuration.requestCachePolicy,
            .reloadIgnoringLocalAndRemoteCacheData
        )
    }

    func testCurrentKeySuccessProducesExactNativeUSDMetricsAndIgnoresUnknownFields() async throws {
        installResponse(fixtureName: "current-key-monthly")
        let result = try await makeClient().fetchCurrentKeyCapacity(
            credential: try ordinaryCredential(
                "synthetic-credential",
                contextID: "key-context"
            )
        )

        XCTAssertEqual(result.metrics.count, 9)
        XCTAssertEqual(result.tier, .paid)
        XCTAssertFalse(result.includesBYOKInLimit)
        XCTAssertEqual(
            result.expiresAt,
            ISO8601DateFormatter().date(from: "2030-01-02T03:04:05Z")
        )
        XCTAssertTrue(
            result.metrics.allSatisfy {
                $0.accountContextID == "key-context"
                    && $0.unit == CapacityUnit(kind: .currency, currencyCode: "USD")
                    && $0.availability == .known
            }
        )

        let totalUsage = try metric("key-total-usage", in: result)
        XCTAssertEqual(totalUsage.values?.consumed?.value, decimal("8.125"))
        XCTAssertNil(totalUsage.values?.remaining)
        XCTAssertNil(totalUsage.values?.limit)

        let byokUsage = try metric("key-total-byok-usage", in: result)
        XCTAssertEqual(byokUsage.values?.consumed?.value, decimal("2.375"))

        let limit = try metric("key-credit-limit", in: result)
        XCTAssertNil(limit.values?.consumed)
        XCTAssertEqual(limit.values?.limit?.value, decimal("10.5"))
        XCTAssertEqual(limit.values?.remaining?.value, decimal("-0.25"))
        XCTAssertEqual(limit.conditions, [.overage])
        XCTAssertEqual(limit.window.kind, .billingCycle)
        XCTAssertEqual(
            limit.window.nextTransition?.at,
            utcDate("2026-04-01T00:00:00Z")
        )
    }

    func testManagementCreditsProduceExactDerivedRemainingWithoutClamping() async throws {
        installResponse(fixtureName: "credits")
        let result = try await makeClient().fetchManagementCredits(
            credential: try managementCredential("synthetic-management-credential")
        )

        let metric = result.metric
        XCTAssertEqual(metric.metricID, "account-credits")
        XCTAssertEqual(metric.accountContextID, "account")
        XCTAssertEqual(metric.sourceID, "management-api")
        XCTAssertEqual(metric.unit, CapacityUnit(kind: .currency, currencyCode: "USD"))
        XCTAssertEqual(metric.values?.limit?.value, decimal("12.375"))
        XCTAssertEqual(metric.values?.consumed?.value, decimal("13.625"))
        XCTAssertEqual(metric.values?.remaining?.value, decimal("-1.25"))
        XCTAssertEqual(metric.values?.remaining?.origin, .derived)
        XCTAssertEqual(metric.conditions, [.overage])
        XCTAssertEqual(
            metric.derivations,
            [
                Derivation(
                    kind: .remainingFromLimitMinusConsumed,
                    target: .remaining,
                    inputs: [.limit, .consumed]
                )
            ]
        )
    }

    func testProducedMetricsValidateAsOneContractV1AccountSnapshot() async throws {
        let currentKeyData = try fixture("current-key-monthly")
        let creditsData = try fixture("credits")
        OpenRouterURLProtocolStub.setHandler { request, stub in
            stub.respond(
                statusCode: 200,
                data: request.url?.path == "/api/v1/credits"
                    ? creditsData
                    : currentKeyData
            )
        }
        let client = makeClient()
        let currentKey = try await client.fetchCurrentKeyCapacity(
            credential: try ordinaryCredential("synthetic-ordinary-credential")
        )
        let credits = try await client.fetchManagementCredits(
            credential: try managementCredential("synthetic-management-credential")
        )
        let surface = ProviderSurface(
            providerID: "openrouter",
            surfaceID: "api-account",
            displayName: "OpenRouter API account",
            interactionModel: .api,
            regions: [RegionDescriptor(regionID: "global", displayName: "Global")],
            accountContextKinds: [.personal, .credential],
            capabilities: ["credits", "spend"]
        )
        let snapshot = CapacitySnapshot(
            providerID: "openrouter",
            surfaceID: "api-account",
            savedAccountID: "saved-account",
            accountContexts: [
                AccountContext(
                    contextID: "account",
                    kind: .personal,
                    regionID: "global"
                ),
                AccountContext(
                    contextID: "key",
                    kind: .credential,
                    regionID: "global",
                    parentContextID: "account"
                )
            ],
            observedAt: observedAt,
            metrics: currentKey.metrics + [credits.metric]
        )

        XCTAssertNoThrow(
            try ProviderContractValidator.validate(
                snapshot: snapshot,
                surface: surface,
                sources: [
                    source(
                        id: "current-key-api",
                        privilege: .leastPrivilege,
                        capabilities: ["credits", "spend"]
                    ),
                    source(
                        id: "management-api",
                        privilege: .elevated,
                        capabilities: ["credits"]
                    )
                ]
            )
        )
    }

    func testNullAndAbsentLimitsRemainUnavailableInsteadOfUnlimited() async throws {
        for fixtureName in [
            "current-key-null-limit",
            "current-key-absent-limit"
        ] {
            installResponse(fixtureName: fixtureName)
            let result = try await makeClient().fetchCurrentKeyCapacity(
                credential: try ordinaryCredential("synthetic-credential")
            )

            XCTAssertEqual(result.metrics.count, 8, fixtureName)
            XCTAssertFalse(
                result.metrics.contains { $0.metricID == "key-credit-limit" },
                fixtureName
            )
            XCTAssertFalse(
                result.metrics.contains { $0.availability == .unlimited },
                fixtureName
            )
        }
    }

    func testDailyWeeklyMonthlyAndLifetimeLimitResetVariantsAreDeterministic() async throws {
        let cases: [
            (
                fixture: String,
                kind: CapacityWindowKind,
                duration: UInt?,
                transition: Date?,
                includesBYOK: Bool
            )
        ] = [
            (
                "current-key-daily",
                .fixed,
                86_400,
                utcDate("2026-03-28T00:00:00Z"),
                true
            ),
            (
                "current-key-weekly",
                .fixed,
                604_800,
                utcDate("2026-03-30T00:00:00Z"),
                false
            ),
            (
                "current-key-monthly",
                .billingCycle,
                nil,
                utcDate("2026-04-01T00:00:00Z"),
                false
            ),
            (
                "current-key-lifetime",
                .lifetime,
                nil,
                nil,
                false
            )
        ]

        for item in cases {
            installResponse(fixtureName: item.fixture)
            let result = try await makeClient().fetchCurrentKeyCapacity(
                credential: try ordinaryCredential("synthetic-credential")
            )
            let limit = try metric("key-credit-limit", in: result)

            XCTAssertEqual(limit.window.kind, item.kind, item.fixture)
            XCTAssertEqual(limit.window.durationSeconds, item.duration, item.fixture)
            XCTAssertEqual(
                limit.window.nextTransition?.at,
                item.transition,
                item.fixture
            )
            XCTAssertEqual(result.includesBYOKInLimit, item.includesBYOK, item.fixture)
        }

        installResponse(fixtureName: "current-key-daily")
        let zeroLimit = try await makeClient().fetchCurrentKeyCapacity(
            credential: try ordinaryCredential("synthetic-credential")
        )
        let metric = try metric("key-credit-limit", in: zeroLimit)
        XCTAssertEqual(metric.values?.limit?.value, .zero)
        XCTAssertEqual(metric.values?.remaining?.value, decimal("-1.5"))
    }

    func testMalformedRequiredNumbersTypesAndPartialPayloadsFailClosed() async throws {
        for fixtureName in [
            "current-key-rounded-number",
            "current-key-wrong-type",
            "current-key-exponent-int-min",
            "current-key-exponent-positive-boundary",
            "current-key-exponent-negative-boundary",
            "current-key-exponent-overlong",
            "current-key-management",
            "current-key-missing-tier"
        ] {
            installResponse(fixtureName: fixtureName)
            await assertCurrentKeyError(.decodingFailure, file: #filePath, line: #line)
        }

        installResponse(data: Data(#"{"data":{"usage":1}}"#.utf8))
        await assertCurrentKeyError(.decodingFailure)

        installResponse(
            data: Data(
                """
                {
                  "data": {
                    "usage": "__BairometerJSONNumber__:1",
                    "usage_daily": 0,
                    "usage_weekly": 0,
                    "usage_monthly": 0,
                    "byok_usage": 0,
                    "byok_usage_daily": 0,
                    "byok_usage_weekly": 0,
                    "byok_usage_monthly": 0,
                    "include_byok_in_limit": false,
                    "is_free_tier": false,
                    "is_management_key": false
                  }
                }
                """.utf8
            )
        )
        await assertCurrentKeyError(.decodingFailure)

        installResponse(
            data: Data(
                """
                {
                  "data": {
                    "usage": -1,
                    "usage_daily": 0,
                    "usage_weekly": 0,
                    "usage_monthly": 0,
                    "byok_usage": 0,
                    "byok_usage_daily": 0,
                    "byok_usage_weekly": 0,
                    "byok_usage_monthly": 0,
                    "include_byok_in_limit": false,
                    "is_free_tier": false,
                    "is_management_key": false
                  }
                }
                """.utf8
            )
        )
        await assertCurrentKeyError(.decodingFailure)
    }

    func testExactlyRepresentableExponentNumbersPreserveNativeValues() async throws {
        installResponse(fixtureName: "current-key-exponent-valid")

        let result = try await makeClient().fetchCurrentKeyCapacity(
            credential: try ordinaryCredential("synthetic-credential")
        )

        XCTAssertEqual(
            try metric("key-total-usage", in: result).values?.consumed?.value,
            decimal("1.25")
        )
        XCTAssertEqual(
            try metric("key-daily-usage", in: result).values?.consumed?.value,
            decimal("0.5")
        )
        XCTAssertEqual(
            try metric("key-weekly-usage", in: result).values?.consumed?.value,
            decimal("10")
        )
        XCTAssertEqual(
            try metric("key-monthly-usage", in: result).values?.consumed?.value,
            decimal("12.5")
        )
    }

    func testHTTPFailuresAndRetryAfterVariantsAreSanitizedAndDistinct() async throws {
        let errorData = try fixture("http-error")
        let retryDate = utcDate("2030-10-21T07:28:00Z")
        let cases: [
            (
                status: Int,
                retryAfter: String?,
                expected: OpenRouterAPIClientError
            )
        ] = [
            (401, nil, .authenticationFailure),
            (402, nil, .insufficientCredits),
            (403, nil, .insufficientPrivilege),
            (429, "17", .throttled(retryAfter: .seconds(17))),
            (
                503,
                "Mon, 21 Oct 2030 07:28:00 GMT",
                .serviceUnavailable(retryAfter: .date(retryDate))
            ),
            (503, "not-a-delay", .serviceUnavailable(retryAfter: nil)),
            (500, nil, .serverFailure(statusCode: 500)),
            (502, nil, .serverFailure(statusCode: 502)),
            (418, nil, .httpFailure(statusCode: 418))
        ]

        for item in cases {
            let headers = item.retryAfter.map { ["Retry-After": $0] } ?? [:]
            let recorder = OpenRouterRequestRecorder()
            OpenRouterURLProtocolStub.setHandler { request, stub in
                recorder.append(request)
                stub.respond(
                    statusCode: item.status,
                    headers: headers,
                    data: errorData
                )
            }
            await assertCurrentKeyError(item.expected, file: #filePath, line: #line)
            XCTAssertEqual(recorder.requests.count, 1, "Unexpected retry for \(item.status)")
        }
    }

    func testRetryAfterAcceptsOnlyASCIIDeltaSecondsAndCanonicalHTTPDates() async throws {
        let legacyDate = utcDate("1994-11-06T08:49:37Z")
        let cases: [(String, OpenRouterRetryAfter)] = [
            ("0", .seconds(0)),
            ("17", .seconds(17)),
            (" \t17\t ", .seconds(17)),
            (String(UInt.max), .seconds(UInt.max)),
            (
                "Sun, 06 Nov 1994 08:49:37 GMT",
                .date(legacyDate)
            ),
            (
                "\tSunday, 06-Nov-94 08:49:37 GMT ",
                .date(legacyDate)
            ),
            (
                "Sun Nov  6 08:49:37 1994",
                .date(legacyDate)
            )
        ]

        for (header, expected) in cases {
            installResponse(
                statusCode: 429,
                headers: ["Retry-After": header],
                data: try fixture("http-error")
            )
            await assertCurrentKeyError(
                .throttled(retryAfter: expected),
                file: #filePath,
                line: #line
            )
        }
    }

    func testRetryAfterRejectsSignsUnicodeDigitsOverflowAndNonGMTZones() async throws {
        let rejected = [
            "+17",
            "-0",
            "1 7",
            "١٧",
            "１７",
            "\(UInt.max)0",
            "Mon, 21 Oct 2030 07:28:00 PST",
            "Mon, 21 Oct 2030 07:28:00 UTC",
            "Monday, 21-Oct-30 07:28:00 PST",
            "Monday, 21-Oct-30 07:28:00 UTC",
            "Mon, 1 Oct 2030 07:28:00 GMT",
            "Sun Nov  6 08:49:37 1994 GMT"
        ]

        for header in rejected {
            installResponse(
                statusCode: 429,
                headers: ["Retry-After": header],
                data: try fixture("http-error")
            )
            await assertCurrentKeyError(
                .throttled(retryAfter: nil),
                file: #filePath,
                line: #line
            )
        }
    }

    func testTransportTimeoutCancellationAndResponseLimitAreDistinct() async throws {
        OpenRouterURLProtocolStub.setHandler { _, stub in
            stub.fail(with: URLError(.cannotConnectToHost))
        }
        await assertCurrentKeyError(.transportFailure)

        OpenRouterURLProtocolStub.setHandler { _, _ in }
        await assertCurrentKeyError(.timedOut, client: makeClient(timeout: 0.02))

        let requestStarted = expectation(description: "Request started")
        OpenRouterURLProtocolStub.setHandler { _, _ in
            requestStarted.fulfill()
        }
        let client = makeClient(timeout: 5)
        let credential = try ordinaryCredential("synthetic-credential")
        let task = Task {
            try await client.fetchCurrentKeyCapacity(
                credential: credential
            )
        }
        await fulfillment(of: [requestStarted], timeout: 1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch {
            XCTAssertEqual(error as? OpenRouterAPIClientError, .cancelled)
        }

        installResponse(data: try fixture("current-key-monthly"))
        await assertCurrentKeyError(
            .responseTooLarge,
            client: makeClient(responseLimit: 16)
        )
    }

    func testJSONNumberPreservationExpansionIsBounded() async {
        let numbers = Array(repeating: "0", count: 128).joined(separator: ",")
        let data = Data(#"{"data":["#.utf8)
            + Data(numbers.utf8)
            + Data("]}".utf8)
        installResponse(data: data)

        await assertCurrentKeyError(
            .responseTooLarge,
            client: makeClient(responseLimit: data.count + 1)
        )
    }

    func testActualURLSessionRejectsOversizedContentLengthBeforeDelayedBody() async throws {
        let server = try OpenRouterLoopbackHTTPServer(
            scenario: .delayedBody(
                statusCode: 200,
                contentLength: 1_048_576
            )
        )
        server.start()

        await assertCurrentKeyError(
            .responseTooLarge,
            client: makeLoopbackClient(
                endpoint: server.url,
                responseLimit: 32
            )
        )

        let observation = try XCTUnwrap(server.waitForObservation())
        XCTAssertNil(observation.serverError)
        XCTAssertEqual(observation.requestCount, 1)
        XCTAssertTrue(observation.peerClosedBeforeFullBody)
        XCTAssertEqual(observation.bodyBytesSent, 16_384)
    }

    func testActualURLSessionStopsChunkedResponseAtStreamingBoundary() async throws {
        let server = try OpenRouterLoopbackHTTPServer(
            scenario: .pacedChunkedBody(totalBodyBytes: 4_096)
        )
        server.start()

        await assertCurrentKeyError(
            .responseTooLarge,
            client: makeLoopbackClient(
                endpoint: server.url,
                responseLimit: 32
            )
        )

        let observation = try XCTUnwrap(server.waitForObservation())
        XCTAssertNil(observation.serverError)
        XCTAssertEqual(observation.requestCount, 1)
        XCTAssertTrue(observation.peerClosedBeforeFullBody)
        XCTAssertGreaterThanOrEqual(observation.bodyBytesSent, 33)
        XCTAssertLessThan(observation.bodyBytesSent, 4_096)
    }

    func testActualURLSessionRejectsNonSuccessBeforeDelayedBody() async throws {
        let server = try OpenRouterLoopbackHTTPServer(
            scenario: .delayedBody(
                statusCode: 401,
                contentLength: 1_048_576
            )
        )
        server.start()

        await assertCurrentKeyError(
            .authenticationFailure,
            client: makeLoopbackClient(
                endpoint: server.url,
                responseLimit: 32
            )
        )

        let observation = try XCTUnwrap(server.waitForObservation())
        XCTAssertNil(observation.serverError)
        XCTAssertEqual(observation.requestCount, 1)
        XCTAssertTrue(observation.peerClosedBeforeFullBody)
        XCTAssertEqual(observation.bodyBytesSent, 16_384)
    }

    func testErrorsAndDebugDescriptionsDoNotExposeCredentialBodyHeaderOrMonetaryValues() async throws {
        let credential = "synthetic-private-credential"
        let rawBodyMarker = "synthetic-provider-message"
        let rawHeaderMarker = "synthetic-header-value"
        let rawMoneyMarker = "987654321.123456789"
        OpenRouterURLProtocolStub.setHandler { _, stub in
            stub.respond(
                statusCode: 500,
                headers: ["X-Synthetic-Private": rawHeaderMarker],
                data: Data(
                    """
                    {"error":{"message":"\(rawBodyMarker)","amount":\(rawMoneyMarker)}}
                    """.utf8
                )
            )
        }

        do {
            _ = try await makeClient().fetchCurrentKeyCapacity(
                credential: try ordinaryCredential(credential)
            )
            XCTFail("Expected sanitized failure.")
        } catch {
            let rendered = [
                String(describing: error),
                String(reflecting: error),
                (error as? LocalizedError)?.errorDescription ?? ""
            ].joined(separator: " ")
            for forbidden in [
                credential,
                rawBodyMarker,
                rawHeaderMarker,
                rawMoneyMarker
            ] {
                XCTAssertFalse(rendered.contains(forbidden))
            }
        }
    }

    func testAllOpenRouterFixturesAreValidSanitizedJSON() throws {
        let directory = try XCTUnwrap(
            Bundle.module.url(
                forResource: "OpenRouter",
                withExtension: nil,
                subdirectory: "Fixtures"
            )
        )
        let fixtureURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        XCTAssertEqual(fixtureURLs.count, 17)
        for fixtureURL in fixtureURLs {
            let data = try Data(contentsOf: fixtureURL)
            let preserved = try JSONNumberPreserver.preserve(
                in: data,
                outputLimit: 1_048_576
            )
            let object = try JSONSerialization.jsonObject(with: preserved.data)
            assertSanitizedFixtureValue(
                object,
                fixtureName: fixtureURL.lastPathComponent
            )

            let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
            for pattern in [
                #"sk-or-[A-Za-z0-9_-]+"#,
                #"(?i)bearer\s+[A-Za-z0-9._-]+"#,
                #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}"#,
                #"(?i)(workspace|creator|user)[_-]?[A-Za-z0-9]{6,}"#
            ] {
                XCTAssertNil(
                    raw.range(of: pattern, options: .regularExpression),
                    "\(fixtureURL.lastPathComponent) contains sensitive-looking data matching \(pattern)"
                )
            }
        }
    }

    private func assertSanitizedFixtureValue(
        _ value: Any,
        fixtureName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let dictionary = value as? [String: Any] {
            if dictionary["__BairometerJSONNumberNonce"] != nil {
                XCTAssertNotNil(
                    dictionary["lexeme"],
                    fixtureName,
                    file: file,
                    line: line
                )
                return
            }

            let forbiddenKeys = Set([
                "api_key",
                "authorization",
                "creator_user_id",
                "key_hash",
                "label",
                "message",
                "model_slug",
                "provider_name",
                "token",
                "user_id",
                "workspace_id"
            ])
            for (key, nestedValue) in dictionary {
                XCTAssertFalse(
                    forbiddenKeys.contains(key.lowercased()),
                    "\(fixtureName) contains forbidden fixture key \(key)",
                    file: file,
                    line: line
                )
                assertSanitizedFixtureValue(
                    nestedValue,
                    fixtureName: fixtureName,
                    file: file,
                    line: line
                )
            }
            return
        }

        if let array = value as? [Any] {
            for nestedValue in array {
                assertSanitizedFixtureValue(
                    nestedValue,
                    fixtureName: fixtureName,
                    file: file,
                    line: line
                )
            }
            return
        }

        guard let string = value as? String else {
            return
        }
        let lowered = string.lowercased()
        for forbidden in [
            "sk-or-",
            "bearer ",
            "/users/",
            "workspace_",
            "creator_",
            "user_"
        ] {
            XCTAssertFalse(
                lowered.contains(forbidden),
                "\(fixtureName) contains sensitive-looking string data",
                file: file,
                line: line
            )
        }
        XCTAssertNil(
            string.range(
                of: #"(?i)\b(?=[0-9a-f]{32,}\b)(?=[0-9a-f]*[a-f])[0-9a-f]+\b"#,
                options: .regularExpression
            ),
            "\(fixtureName) contains a sensitive-looking opaque identifier",
            file: file,
            line: line
        )
    }

    private func makeClient(
        timeout: TimeInterval = 1,
        responseLimit: Int = 1_048_576
    ) -> URLSessionOpenRouterAPIClient {
        let fixedObservedAt = observedAt
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenRouterURLProtocolStub.self]
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSessionOpenRouterAPIClient(
            session: URLSession(configuration: configuration),
            timeout: timeout,
            responseLimit: responseLimit,
            now: { fixedObservedAt }
        )
    }

    private func makeLoopbackClient(
        endpoint: URL,
        responseLimit: Int
    ) -> URLSessionOpenRouterAPIClient {
        let fixedObservedAt = observedAt
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.connectionProxyDictionary = [:]
        return URLSessionOpenRouterAPIClient(
            session: URLSession(configuration: configuration),
            timeout: 3,
            responseLimit: responseLimit,
            now: { fixedObservedAt },
            currentKeyURL: endpoint,
            managementCreditsURL: endpoint
        )
    }

    private func installResponse(
        fixtureName: String,
        statusCode: Int = 200,
        headers: [String: String] = [:]
    ) {
        do {
            installResponse(
                statusCode: statusCode,
                headers: headers,
                data: try fixture(fixtureName)
            )
        } catch {
            XCTFail("Unable to load fixture \(fixtureName): \(error)")
        }
    }

    private func installResponse(
        statusCode: Int = 200,
        headers: [String: String] = [:],
        data: Data
    ) {
        OpenRouterURLProtocolStub.setHandler { _, stub in
            stub.respond(statusCode: statusCode, headers: headers, data: data)
        }
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Fixtures/OpenRouter"
            )
        )
        return try Data(contentsOf: url)
    }

    private func metric(
        _ id: String,
        in result: OpenRouterCurrentKeyCapacity
    ) throws -> CapacityMetric {
        try XCTUnwrap(result.metrics.first { $0.metricID == id })
    }

    private func source(
        id: String,
        privilege: AuthPrivilege,
        capabilities: [String]
    ) -> SourceDescriptor {
        SourceDescriptor(
            providerID: "openrouter",
            surfaceID: "api-account",
            sourceID: id,
            displayName: id,
            kind: .documentedRemoteAPI,
            authority: .providerReported,
            maturity: .stable,
            defaultConfidence: .live,
            freshnessPolicy: FreshnessPolicy(
                kind: .maximumAge,
                maxAgeSeconds: 600
            ),
            capabilities: capabilities,
            authRequirement: AuthRequirement(
                category: .apiKey,
                privilege: privilege,
                storageBoundary: .keychain
            )
        )
    }

    private func ordinaryCredential(
        _ value: String,
        accountID: String = "account",
        contextID: String = "key",
        slotID: String = ProviderCredentialRole.ordinary.rawValue
    ) throws -> OpenRouterOrdinaryCredential {
        try OpenRouterOrdinaryCredential(
            slot: credentialSlot(
                accountID: accountID,
                contextID: contextID,
                slotID: slotID,
                role: .ordinary
            ),
            secret: CredentialSecret(value)
        )
    }

    private func managementCredential(
        _ value: String,
        accountID: String = "account",
        contextID: String = "account",
        slotID: String = ProviderCredentialRole.management.rawValue
    ) throws -> OpenRouterManagementCredential {
        try OpenRouterManagementCredential(
            slot: credentialSlot(
                accountID: accountID,
                contextID: contextID,
                slotID: slotID,
                role: .management
            ),
            secret: CredentialSecret(value)
        )
    }

    private func credentialSlot(
        providerID: String = "openrouter",
        accountID: String = "account",
        contextID: String? = nil,
        slotID: String? = nil,
        role: ProviderCredentialRole
    ) -> ProviderCredentialSlot {
        ProviderCredentialSlot(
            providerID: providerID,
            accountID: accountID,
            slotID: slotID ?? role.rawValue,
            contextID: contextID ?? (role == .ordinary ? "key" : "account"),
            role: role,
            isEnabled: true,
            keychainReference: "synthetic-reference"
        )
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func utcDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func assertRequest(
        _ request: URLRequest,
        url: URL,
        credential: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(request.url, url, file: file, line: line)
        XCTAssertEqual(request.httpMethod, "GET", file: file, line: line)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer \(credential)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Accept"),
            "application/json",
            file: file,
            line: line
        )
        XCTAssertNil(request.httpBody, file: file, line: line)
        XCTAssertFalse(request.httpShouldHandleCookies, file: file, line: line)
        XCTAssertEqual(request.timeoutInterval, 5, file: file, line: line)
        XCTAssertNil(request.url?.query, file: file, line: line)
    }

    private func assertCurrentKeyError(
        _ expected: OpenRouterAPIClientError,
        client: URLSessionOpenRouterAPIClient? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await (client ?? makeClient()).fetchCurrentKeyCapacity(
                credential: try ordinaryCredential("synthetic-credential")
            )
            XCTFail("Expected OpenRouter request to fail.", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? OpenRouterAPIClientError,
                expected,
                file: file,
                line: line
            )
        }
    }
}

private final class OpenRouterURLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest, OpenRouterURLProtocolStub) -> Void

    private static let handlerStorage = OpenRouterURLProtocolHandlerStorage()

    static func setHandler(_ handler: @escaping Handler) {
        handlerStorage.set(handler)
    }

    static func clearHandler() {
        handlerStorage.set(nil)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handlerStorage.handler else {
            fail(with: URLError(.resourceUnavailable))
            return
        }
        handler(request, self)
    }

    override func stopLoading() {}

    func beginResponse(
        statusCode: Int,
        headers: [String: String] = [:]
    ) {
        guard let response = makeResponse(
            statusCode: statusCode,
            headers: headers
        ) else {
            fail(with: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
    }

    func send(_ data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }

    func finish() {
        client?.urlProtocolDidFinishLoading(self)
    }

    func respond(
        statusCode: Int,
        headers: [String: String] = [:],
        data: Data
    ) {
        guard makeResponse(statusCode: statusCode, headers: headers) != nil else {
            fail(with: URLError(.badServerResponse))
            return
        }
        beginResponse(statusCode: statusCode, headers: headers)
        send(data)
        finish()
    }

    func fail(with error: Error) {
        client?.urlProtocol(self, didFailWithError: error)
    }

    private func makeResponse(
        statusCode: Int,
        headers: [String: String]
    ) -> HTTPURLResponse? {
        guard let url = request.url else {
            return nil
        }
        return HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )
    }
}

private final class OpenRouterURLProtocolHandlerStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var storedHandler: OpenRouterURLProtocolStub.Handler?

    var handler: OpenRouterURLProtocolStub.Handler? {
        lock.withLock { storedHandler }
    }

    func set(_ handler: OpenRouterURLProtocolStub.Handler?) {
        lock.withLock {
            storedHandler = handler
        }
    }
}

private final class OpenRouterRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    func append(_ request: URLRequest) {
        lock.withLock {
            storedRequests.append(request)
        }
    }
}

private final class OpenRouterLoopbackHTTPServer: @unchecked Sendable {
    enum Scenario: Sendable {
        case delayedBody(statusCode: Int, contentLength: Int)
        case pacedChunkedBody(totalBodyBytes: Int)
    }

    struct Observation: Sendable {
        var requestCount = 0
        var bodyBytesSent = 0
        var peerClosedBeforeFullBody = false
        var serverError: Int32?
    }

    let url: URL

    private let listener: Int32
    private let scenario: Scenario
    private let queue = DispatchQueue(
        label: "io.github.Prontsevich.Bairometer.OpenRouterLoopbackHTTPServer"
    )
    private let completion = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var storedObservation: Observation?
    private var didStart = false

    init(scenario: Scenario) throws {
        let listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw Self.posixError()
        }

        var reuseAddress: Int32 = 1
        guard withUnsafePointer(to: &reuseAddress, {
            Darwin.setsockopt(
                listener,
                SOL_SOCKET,
                SO_REUSEADDR,
                $0,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }) == 0 else {
            let error = Self.posixError()
            Darwin.close(listener)
            throw error
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    listener,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindResult == 0, Darwin.listen(listener, 4) == 0 else {
            let error = Self.posixError()
            Darwin.close(listener)
            throw error
        }

        var boundAddress = sockaddr_in()
        var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(listener, $0, &boundAddressLength)
            }
        }
        guard nameResult == 0 else {
            let error = Self.posixError()
            Darwin.close(listener)
            throw error
        }

        let port = UInt16(bigEndian: boundAddress.sin_port)
        guard let url = URL(
            string: "http://127.0.0.1:\(port)/api/v1/key"
        ) else {
            Darwin.close(listener)
            throw URLError(.badURL)
        }
        self.listener = listener
        self.scenario = scenario
        self.url = url
    }

    deinit {
        Darwin.close(listener)
    }

    func start() {
        let shouldStart = lock.withLock {
            guard !didStart else {
                return false
            }
            didStart = true
            return true
        }
        guard shouldStart else {
            return
        }
        queue.async {
            self.run()
        }
    }

    func waitForObservation(
        timeout: TimeInterval = 4
    ) -> Observation? {
        guard completion.wait(timeout: .now() + timeout) == .success else {
            return nil
        }
        return lock.withLock { storedObservation }
    }

    private func run() {
        var observation = Observation()
        var peerAddress = sockaddr()
        var peerAddressLength = socklen_t(MemoryLayout<sockaddr>.size)
        let connection = Darwin.accept(
            listener,
            &peerAddress,
            &peerAddressLength
        )
        guard connection >= 0 else {
            observation.serverError = errno
            finish(observation)
            return
        }
        defer { Darwin.close(connection) }
        observation.requestCount = 1

        var noSignal: Int32 = 1
        _ = withUnsafePointer(to: &noSignal) {
            Darwin.setsockopt(
                connection,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                $0,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }
        guard Self.readRequestHeaders(from: connection) else {
            observation.serverError = errno == 0 ? EIO : errno
            finish(observation)
            return
        }

        switch scenario {
        case let .delayedBody(statusCode, contentLength):
            let reason = statusCode == 200 ? "OK" : "Unauthorized"
            let headers = "HTTP/1.1 \(statusCode) \(reason)\r\n"
                + "Content-Length: \(contentLength)\r\n"
                + "Connection: close\r\n\r\n"
            guard Self.sendAll(Data(headers.utf8), to: connection) else {
                observation.serverError = errno
                finish(observation)
                return
            }
            usleep(50_000)
            let triggerByteCount = min(16_384, contentLength)
            guard Self.sendAll(
                Data(repeating: 0x20, count: triggerByteCount),
                to: connection
            ) else {
                observation.peerClosedBeforeFullBody = true
                finish(observation)
                return
            }
            observation.bodyBytesSent = triggerByteCount
            observation.peerClosedBeforeFullBody = Self.waitForPeerClose(
                connection,
                timeoutMilliseconds: 1_500
            )

        case let .pacedChunkedBody(totalBodyBytes):
            let headers = "HTTP/1.1 200 OK\r\n"
                + "Transfer-Encoding: chunked\r\n"
                + "Connection: close\r\n\r\n"
            guard Self.sendAll(Data(headers.utf8), to: connection) else {
                observation.serverError = errno
                finish(observation)
                return
            }

            while observation.bodyBytesSent < totalBodyBytes {
                let byteCount = min(
                    16,
                    totalBodyBytes - observation.bodyBytesSent
                )
                var frame = Data(String(byteCount, radix: 16).utf8)
                frame.append(Data("\r\n".utf8))
                frame.append(Data(repeating: 0x20, count: byteCount))
                frame.append(Data("\r\n".utf8))
                guard Self.sendAll(frame, to: connection) else {
                    observation.peerClosedBeforeFullBody = true
                    break
                }
                observation.bodyBytesSent += byteCount
                usleep(20_000)
                if Self.waitForPeerClose(
                    connection,
                    timeoutMilliseconds: 0
                ) {
                    observation.peerClosedBeforeFullBody = true
                    break
                }
            }

            if observation.bodyBytesSent < totalBodyBytes,
               !observation.peerClosedBeforeFullBody
            {
                observation.peerClosedBeforeFullBody =
                    Self.waitForPeerClose(
                        connection,
                        timeoutMilliseconds: 1_000
                    )
            }
        }

        observation.requestCount += Self.additionalRequestCount(
            listener: listener
        )
        finish(observation)
    }

    private func finish(_ observation: Observation) {
        lock.withLock {
            storedObservation = observation
        }
        completion.signal()
    }

    private static func readRequestHeaders(from socket: Int32) -> Bool {
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            Darwin.setsockopt(
                socket,
                SOL_SOCKET,
                SO_RCVTIMEO,
                $0,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while received.count <= 65_536 {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.recv(socket, $0.baseAddress, $0.count, 0)
            }
            guard count > 0 else {
                return false
            }
            received.append(buffer, count: count)
            if received.range(of: Data("\r\n\r\n".utf8)) != nil {
                return true
            }
        }
        return false
    }

    private static func sendAll(_ data: Data, to socket: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return true
            }
            var sent = 0
            while sent < rawBuffer.count {
                let count = Darwin.send(
                    socket,
                    baseAddress.advanced(by: sent),
                    rawBuffer.count - sent,
                    0
                )
                guard count > 0 else {
                    return false
                }
                sent += count
            }
            return true
        }
    }

    private static func waitForPeerClose(
        _ socket: Int32,
        timeoutMilliseconds: Int32
    ) -> Bool {
        var descriptor = pollfd(
            fd: socket,
            events: Int16(POLLIN | POLLHUP | POLLERR),
            revents: 0
        )
        let result = Darwin.poll(
            &descriptor,
            nfds_t(1),
            timeoutMilliseconds
        )
        guard result > 0 else {
            return false
        }
        if descriptor.revents & Int16(POLLHUP | POLLERR) != 0 {
            return true
        }
        guard descriptor.revents & Int16(POLLIN) != 0 else {
            return false
        }

        var byte: UInt8 = 0
        let count = Darwin.recv(
            socket,
            &byte,
            1,
            MSG_PEEK | MSG_DONTWAIT
        )
        return count == 0
            || (count < 0 && (errno == ECONNRESET || errno == ENOTCONN))
    }

    private static func additionalRequestCount(listener: Int32) -> Int {
        var descriptor = pollfd(
            fd: listener,
            events: Int16(POLLIN),
            revents: 0
        )
        guard Darwin.poll(&descriptor, nfds_t(1), 250) > 0,
              descriptor.revents & Int16(POLLIN) != 0
        else {
            return 0
        }

        let connection = Darwin.accept(listener, nil, nil)
        guard connection >= 0 else {
            return 0
        }
        Darwin.close(connection)
        return 1
    }

    private static func posixError() -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno)
        )
    }
}
