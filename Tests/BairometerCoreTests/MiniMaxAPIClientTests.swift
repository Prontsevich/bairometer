import Foundation
import XCTest
@testable import BairometerCore

final class MiniMaxAPIClientTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_893_456_000)

    override func tearDown() {
        MiniMaxURLProtocolStub.clearHandler()
        super.tearDown()
    }

    func testProductionMappingAcceptsOnlyExactQuotaCategoryIdentifiers() throws {
        let mapping = MiniMaxProviderContract.reviewedQuotaCategories

        XCTAssertEqual(
            try XCTUnwrap(
                mapping.reviewedCategory(forProviderIdentifier: "general")
            ).stableID,
            "quota-category-a"
        )
        XCTAssertEqual(
            try XCTUnwrap(
                mapping.reviewedCategory(forProviderIdentifier: "video")
            ).stableID,
            "quota-category-b"
        )
        for unknownIdentifier in [
            "MiniMax-M2",
            "MiniMax-M*",
            "generalized",
            "speech-hd",
            "image-01"
        ] {
            XCTAssertNil(mapping.reviewedCategory(
                forProviderIdentifier: unknownIdentifier
            ))
        }
        XCTAssertThrowsError(
            try MiniMaxReviewedQuotaCategory(
                providerIdentifier: "MiniMax-M*",
                stableID: "wildcard",
                displayName: "Wildcard"
            )
        ) { error in
            XCTAssertEqual(
                error as? MiniMaxQuotaCategoryMappingError,
                .invalidEntry
            )
        }
    }

    func testProductionMappingIgnoresPrefixLikeQuotaCategoryWithSanitizedDiagnostic() async throws {
        let json = String(decoding: try fixture("synthetic-success"), as: UTF8.self)
            .replacingOccurrences(of: "synthetic-row-a", with: "general")
            .replacingOccurrences(of: "synthetic-row-b", with: "video")
            .replacingOccurrences(
                of: "synthetic-row-unreviewed",
                with: "MiniMax-M2"
            )
        MiniMaxURLProtocolStub.setHandler { _, stub in
            stub.respond(statusCode: 200, data: Data(json.utf8))
        }

        let result = try await makeClient(
            reviewedCategories: MiniMaxProviderContract.reviewedQuotaCategories
        ).fetchTokenPlanCapacity(
            credential: try credential("synthetic-subscription-key")
        )

        XCTAssertEqual(result.metrics.map(\.metricID), [
            "quota-category-a.current",
            "quota-category-a.weekly",
            "quota-category-b.current",
            "quota-category-b.weekly"
        ])
        XCTAssertEqual(result.diagnostics, [.init(code: .unknownQuotaCategory)])
        XCTAssertFalse(result.metrics.contains { metric in
            ["MiniMax", "general", "video"].contains(where: { providerValue in
                metric.metricID.contains(providerValue)
                    || metric.displayName.contains(providerValue)
            })
        })
    }

    func testFixedGlobalRequestMapsIndependentReviewedWindows() async throws {
        let recorder = MiniMaxRequestRecorder()
        let data = try fixture("synthetic-success")
        MiniMaxURLProtocolStub.setHandler { request, stub in
            recorder.append(request)
            stub.respond(statusCode: 200, data: data)
        }

        let result = try await makeClient().fetchTokenPlanCapacity(
            credential: try credential("synthetic-subscription-key")
        )

        XCTAssertEqual(recorder.requests.count, 1)
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url, URLSessionMiniMaxAPIClient.remainsURL)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer synthetic-subscription-key"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.url?.query)
        XCTAssertFalse(request.httpShouldHandleCookies)

        XCTAssertEqual(result.observedAt, observedAt)
        XCTAssertEqual(result.metrics.map(\.metricID), [
            "quota-a.current", "quota-a.weekly",
            "quota-b.current", "quota-b.weekly"
        ])
        XCTAssertEqual(result.diagnostics, [.init(code: .unknownQuotaCategory)])

        let currentA = try metric("quota-a.current", in: result)
        XCTAssertEqual(currentA.window.kind, .rolling)
        XCTAssertEqual(currentA.availability, .known)
        XCTAssertEqual(currentA.unit, CapacityUnit(kind: .percent))
        XCTAssertEqual(currentA.values?.remaining?.value, 63.5)
        XCTAssertEqual(currentA.values?.remaining?.origin, .reported)
        XCTAssertEqual(currentA.values?.limit?.value, 100)
        XCTAssertEqual(currentA.values?.limit?.origin, .reported)
        XCTAssertEqual(currentA.values?.consumed?.value, 36.5)
        XCTAssertEqual(currentA.values?.consumed?.origin, .derived)
        XCTAssertEqual(currentA.derivations, [
            Derivation(
                kind: .consumedFromLimitMinusRemaining,
                target: .consumed,
                inputs: [.limit, .remaining]
            )
        ])
        XCTAssertEqual(currentA.accountContextID, "synthetic-team")

        let weeklyA = try metric("quota-a.weekly", in: result)
        XCTAssertEqual(weeklyA.window.kind, .fixed)
        XCTAssertEqual(weeklyA.availability, .known)
        XCTAssertEqual(weeklyA.values?.remaining?.value, 0)
        XCTAssertEqual(weeklyA.values?.consumed?.value, 100)

        let currentB = try metric("quota-b.current", in: result)
        XCTAssertEqual(currentB.availability, .unknown)
        XCTAssertNil(currentB.values)

        let weeklyB = try metric("quota-b.weekly", in: result)
        XCTAssertEqual(weeklyB.conditions, [.boost])
        XCTAssertEqual(weeklyB.values?.remaining?.value, 78.25)
        XCTAssertEqual(weeklyB.values?.consumed?.value, 21.75)
    }

    func testReportedPercentageRemainsPresentableForZeroCountsAndStatusThree() async throws {
        let json = String(decoding: try fixture("synthetic-success"), as: UTF8.self)
            .replacingOccurrences(
                of: "\"current_interval_usage_count\": 3,\n      \"current_interval_status\": 3",
                with: "\"current_interval_usage_count\": 0,\n      \"current_interval_remaining_percent\": 42.5,\n      \"current_interval_status\": 3"
            )
        MiniMaxURLProtocolStub.setHandler { _, stub in
            stub.respond(statusCode: 200, data: Data(json.utf8))
        }

        let result = try await makeClient().fetchTokenPlanCapacity(
            credential: try credential("synthetic-subscription-key")
        )
        let currentB = try metric("quota-b.current", in: result)

        XCTAssertEqual(currentB.availability, .known)
        XCTAssertEqual(currentB.unit, CapacityUnit(kind: .percent))
        XCTAssertEqual(currentB.values?.remaining, CapacityValue(value: 42.5, origin: .reported))
        XCTAssertEqual(currentB.values?.limit, CapacityValue(value: 100, origin: .reported))
        XCTAssertEqual(currentB.values?.consumed, CapacityValue(value: 57.5, origin: .derived))
        XCTAssertEqual(currentB.window.nextTransition?.kind, .reset)
        XCTAssertEqual(
            currentB.window.nextTransition?.at,
            Date(timeIntervalSince1970: 1_893_477_600)
        )
    }

    func testMissingOrOutOfRangePercentageUsesNonClaimingState() async throws {
        let missingResult = try await fetchFixtureResult()
        let missingCurrentB = try metric("quota-b.current", in: missingResult)
        XCTAssertEqual(missingCurrentB.availability, .unknown)
        XCTAssertNil(missingCurrentB.values)

        let json = String(decoding: try fixture("synthetic-success"), as: UTF8.self)
            .replacingOccurrences(
                of: "\"current_interval_usage_count\": 3,\n      \"current_interval_status\": 3",
                with: "\"current_interval_usage_count\": 3,\n      \"current_interval_remaining_percent\": 101,\n      \"current_interval_status\": 3"
            )
        MiniMaxURLProtocolStub.setHandler { _, stub in
            stub.respond(statusCode: 200, data: Data(json.utf8))
        }

        let outOfRangeResult = try await makeClient().fetchTokenPlanCapacity(
            credential: try credential("synthetic-subscription-key")
        )
        let outOfRangeCurrentB = try metric("quota-b.current", in: outOfRangeResult)
        XCTAssertEqual(outOfRangeCurrentB.availability, .unknown)
        XCTAssertNil(outOfRangeCurrentB.values)
    }

    func testBusinessStatusIsValidatedBeforeQuotaCategoriesAndProjectsSanitizedErrors() async throws {
        installJSON(
            #"{"base_resp":{"status_code":1004,"status_msg":""},"model_remains":null}"#
        )
        await assertError(.authenticationFailure)

        installJSON(
            #"{"base_resp":{"status_code":1004,"status_msg":""},"model_remains":{"unexpected":"shape"}}"#
        )
        await assertError(.authenticationFailure)

        installJSON(
            #"{"base_resp":{"status_code":2045,"status_msg":""},"model_remains":null}"#,
            headers: ["Retry-After": "17"]
        )
        await assertError(.throttled(retryAfter: .seconds(17)))

        installJSON(
            #"{"base_resp":{"status_code":2045,"status_msg":""},"model_remains":["malformed"]}"#,
            headers: ["Retry-After": "17"]
        )
        await assertError(.throttled(retryAfter: .seconds(17)))

        installJSON(
            #"{"base_resp":{"status_code":2062,"status_msg":""},"model_remains":null}"#
        )
        await assertError(.unavailableSubscription)

        installJSON(
            #"{"base_resp":{"status_code":2056,"status_msg":""},"model_remains":null}"#
        )
        await assertError(.usageExhausted)
    }

    func testHTTPRetryAfterAndTransportErrorsRemainDistinct() async throws {
        MiniMaxURLProtocolStub.setHandler { _, stub in
            stub.respond(
                statusCode: 429,
                headers: ["Retry-After": "Wed, 01 Jan 2031 00:00:00 GMT"],
                data: Data()
            )
        }
        await assertError(
            .throttled(retryAfter: .date(Date(timeIntervalSince1970: 1_924_992_000)))
        )

        MiniMaxURLProtocolStub.setHandler { _, stub in
            stub.fail(with: URLError(.notConnectedToInternet))
        }
        await assertError(.transportFailure)
    }

    func testResponseLimitIsStreamingAndDoesNotMaskHTTPError() async throws {
        MiniMaxURLProtocolStub.setHandler { _, stub in
            stub.respond(
                statusCode: 429,
                headers: ["Retry-After": "17"],
                data: Data(repeating: 0, count: 4_096)
            )
        }
        await assertError(
            .throttled(retryAfter: .seconds(17)),
            client: makeClient(responseLimit: 1)
        )

        MiniMaxURLProtocolStub.setHandler { _, stub in
            stub.respond(statusCode: 200, data: Data(repeating: 0, count: 2))
        }
        await assertError(.responseTooLarge, client: makeClient(responseLimit: 1))
    }

    func testMalformedAndUnknownFieldsFailClosed() async throws {
        installJSON(
            #"{"base_resp":{"status_code":0,"status_msg":""},"model_remains":[]}"#
        )
        await assertError(.decodingFailure)

        installJSON(
            #"{"base_resp":{"status_code":0,"status_msg":"","unexpected":"value"},"model_remains":[]}"#
        )
        await assertError(.decodingFailure)

        installJSON(
            #"{"base_resp":{"status_code":0,"status_msg":""},"model_remains":[{"model_name":"synthetic-row-a"}]}"#
        )
        await assertError(.decodingFailure)
    }

    func testTimeoutAndCancellationRemainDistinct() async throws {
        MiniMaxURLProtocolStub.setHandler { _, _ in }
        await assertError(.timedOut, client: makeClient(timeout: 0.01))

        MiniMaxURLProtocolStub.setHandler { _, _ in }
        let client = makeClient(timeout: 5)
        let subscriptionKey = try credential("synthetic-subscription-key")
        let task = Task {
            try await client.fetchTokenPlanCapacity(credential: subscriptionKey)
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch {
            XCTAssertEqual(error as? MiniMaxAPIClientError, .cancelled)
        }
    }

    func testCredentialWrapperRejectsWrongSlotAndDoesNotRenderSecret() throws {
        let secret = try CredentialSecret("synthetic-secret")
        let valid = try MiniMaxSubscriptionKey(
            slot: credentialSlot(),
            secret: secret
        )
        XCTAssertFalse(String(reflecting: valid).contains("synthetic-secret"))

        XCTAssertThrowsError(
            try MiniMaxSubscriptionKey(
                slot: credentialSlot(providerID: "other"),
                secret: secret
            )
        ) { XCTAssertEqual($0 as? MiniMaxCredentialError, .providerMismatch) }
        XCTAssertThrowsError(
            try MiniMaxSubscriptionKey(
                slot: credentialSlot(role: .management),
                secret: secret
            )
        ) { XCTAssertEqual($0 as? MiniMaxCredentialError, .roleMismatch) }
    }

    func testSyntheticFixtureContainsNoCredentialOrOpaqueIdentifierShape() throws {
        let object = try JSONSerialization.jsonObject(with: fixture("synthetic-success"))
        let text = String(describing: object).lowercased()
        for forbidden in ["bearer ", "sk-", "token", "email", "user_id", "team_id"] {
            XCTAssertFalse(text.contains(forbidden))
        }
        XCTAssertNil(text.range(
            of: #"\b(?=[0-9a-f]{32,}\b)(?=[0-9a-f]*[a-f])[0-9a-f]+\b"#,
            options: .regularExpression
        ))
    }

    private func makeClient(
        timeout: TimeInterval = 1,
        responseLimit: Int = 1_048_576,
        reviewedCategories: MiniMaxQuotaCategoryMapping? = nil
    ) -> URLSessionMiniMaxAPIClient {
        let fixedObservedAt = observedAt
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MiniMaxURLProtocolStub.self]
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSessionMiniMaxAPIClient(
            session: URLSession(configuration: configuration),
            reviewedCategories: reviewedCategories
                ?? (try! MiniMaxQuotaCategoryMapping(categories: [
                    try! MiniMaxReviewedQuotaCategory(
                        providerIdentifier: "synthetic-row-a",
                        stableID: "quota-a",
                        displayName: "Synthetic capacity A"
                    ),
                    try! MiniMaxReviewedQuotaCategory(
                        providerIdentifier: "synthetic-row-b",
                        stableID: "quota-b",
                        displayName: "Synthetic capacity B"
                    )
                ])),
            timeout: timeout,
            responseLimit: responseLimit,
            now: { fixedObservedAt }
        )
    }

    private func credential(_ value: String) throws -> MiniMaxSubscriptionKey {
        try MiniMaxSubscriptionKey(
            slot: credentialSlot(),
            secret: CredentialSecret(value)
        )
    }

    private func credentialSlot(
        providerID: String = "minimax",
        role: ProviderCredentialRole = .ordinary
    ) -> ProviderCredentialSlot {
        ProviderCredentialSlot(
            providerID: providerID,
            accountID: "synthetic-account",
            slotID: "synthetic-slot",
            contextID: "synthetic-team",
            role: role,
            isEnabled: true,
            keychainReference: "synthetic-reference"
        )
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/MiniMax"
        ))
        return try Data(contentsOf: url)
    }

    private func installJSON(
        _ json: String,
        headers: [String: String] = [:]
    ) {
        MiniMaxURLProtocolStub.setHandler { _, stub in
            stub.respond(statusCode: 200, headers: headers, data: Data(json.utf8))
        }
    }

    private func fetchFixtureResult() async throws -> MiniMaxCapacityResult {
        let data = try fixture("synthetic-success")
        MiniMaxURLProtocolStub.setHandler { _, stub in
            stub.respond(statusCode: 200, data: data)
        }
        return try await makeClient().fetchTokenPlanCapacity(
            credential: try credential("synthetic-subscription-key")
        )
    }

    private func metric(_ id: String, in result: MiniMaxCapacityResult) throws -> CapacityMetric {
        try XCTUnwrap(result.metrics.first { $0.metricID == id })
    }

    private func assertError(
        _ expected: MiniMaxAPIClientError,
        client: URLSessionMiniMaxAPIClient? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await (client ?? makeClient()).fetchTokenPlanCapacity(
                credential: try credential("synthetic-subscription-key")
            )
            XCTFail("Expected MiniMax request to fail.", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? MiniMaxAPIClientError, expected, file: file, line: line)
        }
    }
}

private final class MiniMaxURLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest, MiniMaxURLProtocolStub) -> Void
    private static let storage = MiniMaxURLProtocolHandlerStorage()

    static func setHandler(_ handler: @escaping Handler) { storage.set(handler) }
    static func clearHandler() { storage.set(nil) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.storage.handler else {
            fail(with: URLError(.resourceUnavailable))
            return
        }
        handler(request, self)
    }

    override func stopLoading() {}

    func respond(statusCode: Int, headers: [String: String] = [:], data: Data) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
              )
        else {
            fail(with: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    func fail(with error: Error) { client?.urlProtocol(self, didFailWithError: error) }
}

private final class MiniMaxURLProtocolHandlerStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var storedHandler: MiniMaxURLProtocolStub.Handler?
    var handler: MiniMaxURLProtocolStub.Handler? { lock.withLock { storedHandler } }
    func set(_ handler: MiniMaxURLProtocolStub.Handler?) { lock.withLock { storedHandler = handler } }
}

private final class MiniMaxRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { storedRequests } }
    func append(_ request: URLRequest) { lock.withLock { storedRequests.append(request) } }
}
