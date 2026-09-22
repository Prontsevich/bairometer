import Foundation

public enum MiniMaxCredentialError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case providerMismatch
    case roleMismatch

    public var errorDescription: String? {
        switch self {
        case .providerMismatch:
            "The credential does not belong to MiniMax."
        case .roleMismatch:
            "The credential role does not match the MiniMax Token Plan source."
        }
    }
}

public struct MiniMaxSubscriptionKey:
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    private let secret: CredentialSecret
    fileprivate let accountContextID: String

    public init(
        slot: ProviderCredentialSlot,
        secret: CredentialSecret
    ) throws {
        guard slot.providerID == MiniMaxProviderContract.providerID else {
            throw MiniMaxCredentialError.providerMismatch
        }
        guard slot.role == .ordinary else {
            throw MiniMaxCredentialError.roleMismatch
        }
        self.secret = secret
        accountContextID = slot.contextID
    }

    public var description: String {
        "<redacted MiniMax subscription credential>"
    }

    public var debugDescription: String { description }

    fileprivate func withUTF8String<Result>(
        _ body: (String) throws -> Result
    ) throws -> Result {
        try secret.withUTF8String(body)
    }
}

public enum MiniMaxRetryAfter: Equatable, Sendable {
    case seconds(UInt)
    case date(Date)
}

public enum MiniMaxAPIClientError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case timedOut
    case cancelled
    case transportFailure
    case authenticationFailure
    case throttled(retryAfter: MiniMaxRetryAfter?)
    case unavailableSubscription
    case usageExhausted
    case insufficientResource
    case serviceUnavailable(retryAfter: MiniMaxRetryAfter?)
    case serverFailure(statusCode: Int)
    case httpFailure(statusCode: Int)
    case businessFailure(statusCode: Int)
    case decodingFailure
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .timedOut:
            "MiniMax request timed out."
        case .cancelled:
            "MiniMax request was cancelled."
        case .transportFailure:
            "MiniMax could not be reached."
        case .authenticationFailure:
            "MiniMax subscription authentication failed."
        case .throttled:
            "MiniMax request was throttled."
        case .unavailableSubscription:
            "MiniMax Token Plan subscription is unavailable."
        case .usageExhausted:
            "MiniMax reported exhausted included usage."
        case .insufficientResource:
            "MiniMax reported an unavailable balance or resource."
        case .serviceUnavailable:
            "MiniMax service is temporarily unavailable."
        case .serverFailure:
            "MiniMax service returned a server failure."
        case .httpFailure:
            "MiniMax request returned an unsupported HTTP response."
        case .businessFailure:
            "MiniMax returned an unsupported business failure."
        case .decodingFailure:
            "MiniMax returned an unsupported response."
        case .responseTooLarge:
            "MiniMax returned an unexpectedly large response."
        }
    }
}

public enum MiniMaxMappingDiagnosticCode:
    String,
    Equatable,
    Sendable
{
    case unknownQuotaCategory = "unknown-quota-category"
}

public struct MiniMaxMappingDiagnostic: Equatable, Sendable {
    public let code: MiniMaxMappingDiagnosticCode

    public init(code: MiniMaxMappingDiagnosticCode) {
        self.code = code
    }
}

public struct MiniMaxCapacityResult: Equatable, Sendable {
    public let observedAt: Date
    public let metrics: [CapacityMetric]
    public let diagnostics: [MiniMaxMappingDiagnostic]

    public init(
        observedAt: Date,
        metrics: [CapacityMetric],
        diagnostics: [MiniMaxMappingDiagnostic]
    ) {
        self.observedAt = observedAt
        self.metrics = metrics
        self.diagnostics = diagnostics
    }
}

public protocol MiniMaxAPIClient: Sendable {
    func fetchTokenPlanCapacity(
        credential: MiniMaxSubscriptionKey
    ) async throws -> MiniMaxCapacityResult
}

public struct URLSessionMiniMaxAPIClient: MiniMaxAPIClient {
    static let remainsURL = URL(
        string: "https://api.minimax.io/v1/token_plan/remains"
    )!

    private static let minimumTimeout: TimeInterval = 0.01
    private static let maximumTimeout: TimeInterval = 60
    private static let maximumResponseLimit = 4_194_304

    private let sessionConfiguration: URLSessionConfiguration
    private let timeout: TimeInterval
    private let responseLimit: Int
    private let now: @Sendable () -> Date
    private let reviewedCategories: MiniMaxQuotaCategoryMapping
    private let remainsURL: URL

    public init(reviewedCategories: MiniMaxQuotaCategoryMapping) {
        self.init(
            session: Self.makeDefaultSession(),
            reviewedCategories: reviewedCategories
        )
    }

    init(
        session: URLSession,
        reviewedCategories: MiniMaxQuotaCategoryMapping,
        timeout: TimeInterval = 15,
        responseLimit: Int = 1_048_576,
        now: @escaping @Sendable () -> Date = Date.init,
        remainsURL: URL = Self.remainsURL
    ) {
        sessionConfiguration = session.configuration
        self.reviewedCategories = reviewedCategories
        self.timeout = timeout.isFinite
            ? min(max(timeout, Self.minimumTimeout), Self.maximumTimeout)
            : 15
        self.responseLimit = min(
            max(1, responseLimit),
            Self.maximumResponseLimit
        )
        self.now = now
        self.remainsURL = remainsURL
    }

    public func fetchTokenPlanCapacity(
        credential: MiniMaxSubscriptionKey
    ) async throws -> MiniMaxCapacityResult {
        let request = try makeRequest(credential: credential)
        let result = try await perform(request)
        let businessEnvelope: MiniMaxBusinessEnvelope = try decode(result.data)
        let retryAfter = Self.retryAfter(from: result.response)

        guard businessEnvelope.baseResponse.statusCode == 0 else {
            throw Self.businessError(
                statusCode: businessEnvelope.baseResponse.statusCode,
                quotaCategoriesState: businessEnvelope.quotaCategoriesState,
                retryAfter: retryAfter
            )
        }
        guard businessEnvelope.quotaCategoriesState == .present else {
            throw MiniMaxAPIClientError.decodingFailure
        }

        let successEnvelope: MiniMaxSuccessEnvelope = try decode(result.data)
        guard !successEnvelope.quotaCategories.isEmpty
        else {
            throw MiniMaxAPIClientError.decodingFailure
        }

        let observedAt = now()
        do {
            return try successEnvelope.quotaCategories.capacity(
                reviewedCategories: reviewedCategories,
                accountContextID: credential.accountContextID,
                observedAt: observedAt
            )
        } catch let error as MiniMaxAPIClientError {
            throw error
        } catch {
            throw MiniMaxAPIClientError.decodingFailure
        }
    }

    static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }

    private func makeRequest(
        credential: MiniMaxSubscriptionKey
    ) throws -> URLRequest {
        var request = URLRequest(
            url: remainsURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try credential.withUTF8String {
            request.setValue(
                "Bearer \($0)",
                forHTTPHeaderField: "Authorization"
            )
        }
        return request
    }

    private func perform(
        _ request: URLRequest
    ) async throws -> MiniMaxHTTPResult {
        do {
            let result = try await withThrowingTaskGroup(
                of: MiniMaxHTTPResult.self
            ) { group in
                group.addTask {
                    try await loadBoundedResponse(for: request)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw MiniMaxAPIClientError.timedOut
                }

                defer { group.cancelAll() }
                guard let result = try await group.next() else {
                    throw MiniMaxAPIClientError.transportFailure
                }
                return result
            }

            guard result.response.statusCode == 200 else {
                throw Self.httpError(for: result.response)
            }
            return result
        } catch let error as MiniMaxAPIClientError {
            throw error
        } catch is CancellationError {
            throw MiniMaxAPIClientError.cancelled
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw MiniMaxAPIClientError.timedOut
            case .cancelled:
                throw MiniMaxAPIClientError.cancelled
            default:
                throw MiniMaxAPIClientError.transportFailure
            }
        } catch {
            throw MiniMaxAPIClientError.transportFailure
        }
    }

    private func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw MiniMaxAPIClientError.decodingFailure
        }
    }

    private func loadBoundedResponse(
        for request: URLRequest
    ) async throws -> MiniMaxHTTPResult {
        let delegate = MiniMaxStreamingResponseDelegate(
            responseLimit: responseLimit
        )
        let requestSession = URLSession(
            configuration: sessionConfiguration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { requestSession.finishTasksAndInvalidate() }
        return try await delegate.load(request: request, using: requestSession)
    }

    private static func httpError(
        for response: HTTPURLResponse
    ) -> MiniMaxAPIClientError {
        switch response.statusCode {
        case 401, 403:
            .authenticationFailure
        case 429:
            .throttled(retryAfter: retryAfter(from: response))
        case 503:
            .serviceUnavailable(retryAfter: retryAfter(from: response))
        case 500 ... 599:
            .serverFailure(statusCode: response.statusCode)
        default:
            .httpFailure(statusCode: response.statusCode)
        }
    }

    private static func businessError(
        statusCode: Int,
        quotaCategoriesState: MiniMaxQuotaCategoriesState,
        retryAfter: MiniMaxRetryAfter?
    ) -> MiniMaxAPIClientError {
        switch statusCode {
        case 1004, 2049:
            .authenticationFailure
        case 1002, 2045:
            .throttled(retryAfter: retryAfter)
        case 2056:
            .usageExhausted
        case 2062 where quotaCategoriesState == .null:
            .unavailableSubscription
        case 1008:
            .insufficientResource
        case 1000, 1001, 1024, 1033:
            .serviceUnavailable(retryAfter: retryAfter)
        default:
            .businessFailure(statusCode: statusCode)
        }
    }

    private static func retryAfter(
        from response: HTTPURLResponse
    ) -> MiniMaxRetryAfter? {
        guard let headerValue = response.value(forHTTPHeaderField: "Retry-After"),
              let rawValue = trimHTTPOptionalWhitespace(headerValue),
              !rawValue.isEmpty
        else {
            return nil
        }

        let bytes = rawValue.utf8
        if bytes.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
           let seconds = UInt(rawValue) {
            return .seconds(seconds)
        }

        for (pattern, format) in [
            (
                #"^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), [0-9]{2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT$"#,
                "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
            ),
            (
                #"^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), [0-9]{2}-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT$"#,
                "EEEE',' dd-MMM-yy HH':'mm':'ss 'GMT'"
            ),
            (
                #"^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) ( [1-9]|[12][0-9]|3[01]) [0-9]{2}:[0-9]{2}:[0-9]{2} [0-9]{4}$"#,
                "EEE MMM d HH':'mm':'ss yyyy"
            )
        ] {
            guard rawValue.range(
                of: pattern,
                options: .regularExpression
            ) != nil else {
                continue
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: rawValue) {
                return .date(date)
            }
        }
        return nil
    }

    private static func trimHTTPOptionalWhitespace(
        _ value: String
    ) -> String? {
        let bytes = Array(value.utf8)
        var start = bytes.startIndex
        var end = bytes.endIndex
        while start < end, bytes[start] == 0x20 || bytes[start] == 0x09 {
            start += 1
        }
        while end > start, bytes[end - 1] == 0x20 || bytes[end - 1] == 0x09 {
            end -= 1
        }
        return String(bytes: bytes[start ..< end], encoding: .utf8)
    }
}

private struct MiniMaxHTTPResult: @unchecked Sendable {
    let data: Data
    let response: HTTPURLResponse
}

private final class MiniMaxStreamingResponseDelegate:
    NSObject,
    URLSessionDataDelegate,
    @unchecked Sendable
{
    private enum PendingOutcome {
        case result(MiniMaxHTTPResult)
        case failure(Error)
    }

    private let responseLimit: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<MiniMaxHTTPResult, Error>?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var pendingOutcome: PendingOutcome?
    private var didComplete = false

    init(responseLimit: Int) {
        self.responseLimit = responseLimit
    }

    func load(
        request: URLRequest,
        using session: URLSession
    ) async throws -> MiniMaxHTTPResult {
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    self.continuation = continuation
                }
                task.resume()
                if Task.isCancelled {
                    task.cancel()
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let disposition: URLSession.ResponseDisposition = lock.withLock {
            guard let httpResponse = response as? HTTPURLResponse else {
                pendingOutcome = .failure(MiniMaxAPIClientError.transportFailure)
                return .cancel
            }
            self.response = httpResponse
            guard httpResponse.statusCode == 200 else {
                pendingOutcome = .result(
                    MiniMaxHTTPResult(data: Data(), response: httpResponse)
                )
                return .cancel
            }
            guard response.expectedContentLength <= Int64(responseLimit) else {
                pendingOutcome = .failure(MiniMaxAPIClientError.responseTooLarge)
                return .cancel
            }
            return .allow
        }
        completionHandler(disposition)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive receivedData: Data
    ) {
        let shouldCancel = lock.withLock {
            guard pendingOutcome == nil else {
                return false
            }
            guard receivedData.count <= responseLimit - data.count else {
                pendingOutcome = .failure(MiniMaxAPIClientError.responseTooLarge)
                return true
            }
            data.append(receivedData)
            return false
        }
        if shouldCancel {
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let completed: (CheckedContinuation<MiniMaxHTTPResult, Error>, PendingOutcome)? = lock.withLock {
            guard !didComplete, let continuation else {
                return nil
            }
            didComplete = true
            let outcome: PendingOutcome
            if let pendingOutcome {
                outcome = pendingOutcome
            } else if let error {
                outcome = .failure(error)
            } else if let response {
                outcome = .result(MiniMaxHTTPResult(data: data, response: response))
            } else {
                outcome = .failure(MiniMaxAPIClientError.transportFailure)
            }
            return (continuation, outcome)
        }
        guard let completed else {
            return
        }
        switch completed.1 {
        case let .result(result):
            completed.0.resume(returning: result)
        case let .failure(error):
            completed.0.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct MiniMaxBusinessEnvelope: Decodable {
    let baseResponse: MiniMaxBaseResponse
    let quotaCategoriesState: MiniMaxQuotaCategoriesState

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseResponse = try container.decode(
            MiniMaxBaseResponse.self,
            forKey: .baseResponse
        )
        guard container.contains(.quotaCategories) else {
            quotaCategoriesState = .absent
            return
        }
        if try container.decodeNil(forKey: .quotaCategories) {
            quotaCategoriesState = .null
        } else {
            quotaCategoriesState = .present
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case baseResponse = "base_resp"
        case quotaCategories = "model_remains"
    }
}

private struct MiniMaxSuccessEnvelope: Decodable {
    let quotaCategories: [MiniMaxTokenPlanQuotaCategory]

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decode(MiniMaxBaseResponse.self, forKey: .baseResponse)
        quotaCategories = try container.decode(
            [MiniMaxTokenPlanQuotaCategory].self,
            forKey: .quotaCategories
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case baseResponse = "base_resp"
        case quotaCategories = "model_remains"
    }
}

private struct MiniMaxBaseResponse: Decodable {
    let statusCode: Int

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusCode = try container.decode(Int.self, forKey: .statusCode)
        _ = try container.decode(String.self, forKey: .statusMessage)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case statusCode = "status_code"
        case statusMessage = "status_msg"
    }
}

private enum MiniMaxQuotaCategoriesState: Equatable {
    case absent
    case null
    case present
}

private struct MiniMaxTokenPlanQuotaCategory: Decodable, Equatable {
    let providerIdentifier: String
    let startTime: Int64
    let endTime: Int64
    let remainsTime: Int64
    let currentIntervalRemainingPercent: Decimal?
    let currentWeeklyRemainingPercent: Decimal?
    let weeklyStartTime: Int64
    let weeklyEndTime: Int64
    let weeklyRemainsTime: Int64
    let weeklyBoostPermille: Int64?

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerIdentifier = try container.decode(
            String.self,
            forKey: .providerIdentifier
        )
        startTime = try container.decode(Int64.self, forKey: .startTime)
        endTime = try container.decode(Int64.self, forKey: .endTime)
        remainsTime = try container.decode(Int64.self, forKey: .remainsTime)
        _ = try container.decode(Int64.self, forKey: .currentIntervalTotalCount)
        _ = try container.decode(Int64.self, forKey: .currentIntervalUsageCount)
        currentIntervalRemainingPercent = try container.decodeIfPresent(
            Decimal.self,
            forKey: .currentIntervalRemainingPercent
        )
        _ = try container.decode(Int64.self, forKey: .currentWeeklyTotalCount)
        _ = try container.decode(Int64.self, forKey: .currentWeeklyUsageCount)
        currentWeeklyRemainingPercent = try container.decodeIfPresent(
            Decimal.self,
            forKey: .currentWeeklyRemainingPercent
        )
        _ = try container.decodeIfPresent(Int.self, forKey: .currentIntervalStatus)
        _ = try container.decodeIfPresent(Int.self, forKey: .currentWeeklyStatus)
        weeklyStartTime = try container.decode(
            Int64.self,
            forKey: .weeklyStartTime
        )
        weeklyEndTime = try container.decode(
            Int64.self,
            forKey: .weeklyEndTime
        )
        weeklyRemainsTime = try container.decode(
            Int64.self,
            forKey: .weeklyRemainsTime
        )
        weeklyBoostPermille = try container.decodeIfPresent(
            Int64.self,
            forKey: .weeklyBoostPermille
        )

        guard !providerIdentifier.isEmpty,
              remainsTime >= 0,
              weeklyRemainsTime >= 0,
              currentIntervalRemainingPercent?.isNaN != true,
              currentWeeklyRemainingPercent?.isNaN != true,
              weeklyBoostPermille.map({ $0 >= 0 }) != false
        else {
            throw MiniMaxPayloadValidationError.invalidValue
        }
        _ = try Self.window(
            kind: .rolling,
            startMilliseconds: startTime,
            endMilliseconds: endTime
        )
        _ = try Self.window(
            kind: .fixed,
            startMilliseconds: weeklyStartTime,
            endMilliseconds: weeklyEndTime
        )
    }

    func currentMetric(
        category: MiniMaxReviewedQuotaCategory,
        accountContextID: String,
        observedAt: Date
    ) throws -> CapacityMetric {
        try metric(
            idSuffix: "current",
            displayNameSuffix: "current rolling window",
            remainingPercent: currentIntervalRemainingPercent,
            conditions: [],
            window: Self.window(
                kind: .rolling,
                startMilliseconds: startTime,
                endMilliseconds: endTime
            ),
            category: category,
            accountContextID: accountContextID,
            observedAt: observedAt
        )
    }

    func weeklyMetric(
        category: MiniMaxReviewedQuotaCategory,
        accountContextID: String,
        observedAt: Date
    ) throws -> CapacityMetric {
        try metric(
            idSuffix: "weekly",
            displayNameSuffix: "weekly window",
            remainingPercent: currentWeeklyRemainingPercent,
            conditions: weeklyBoostPermille.map({ $0 > 1_000 }) == true
                ? [.boost]
                : [],
            window: Self.window(
                kind: .fixed,
                startMilliseconds: weeklyStartTime,
                endMilliseconds: weeklyEndTime
            ),
            category: category,
            accountContextID: accountContextID,
            observedAt: observedAt
        )
    }

    private func metric(
        idSuffix: String,
        displayNameSuffix: String,
        remainingPercent: Decimal?,
        conditions: [CapacityCondition],
        window: CapacityWindow,
        category: MiniMaxReviewedQuotaCategory,
        accountContextID: String,
        observedAt: Date
    ) throws -> CapacityMetric {
        let availability: CapacityAvailability
        let values: CapacityValues?
        let derivations: [Derivation]

        if let remainingPercent,
           Self.isUsablePercentage(remainingPercent) {
            availability = .known
            values = CapacityValues(
                consumed: CapacityValue(
                    value: 100 - remainingPercent,
                    origin: .derived
                ),
                remaining: CapacityValue(
                    value: remainingPercent,
                    origin: .reported
                ),
                limit: CapacityValue(
                    value: 100,
                    origin: .reported
                )
            )
            derivations = [
                Derivation(
                    kind: .consumedFromLimitMinusRemaining,
                    target: .consumed,
                    inputs: [.limit, .remaining]
                )
            ]
        } else {
            availability = .unknown
            values = nil
            derivations = []
        }

        return CapacityMetric(
            metricID: "\(category.stableID).\(idSuffix)",
            accountContextID: accountContextID,
            sourceID: MiniMaxProviderContract.sourceID,
            capability: "quota-windows",
            displayName: "\(category.displayName) — \(displayNameSuffix)",
            availability: availability,
            conditions: conditions,
            unit: CapacityUnit(kind: .percent),
            values: values,
            window: window,
            freshness: ObservationFreshness(observedAt: observedAt),
            confidence: .live,
            derivations: derivations
        )
    }

    private static func isUsablePercentage(_ value: Decimal) -> Bool {
        value >= 0 && value <= 100
    }

    private static func window(
        kind: CapacityWindowKind,
        startMilliseconds: Int64,
        endMilliseconds: Int64
    ) throws -> CapacityWindow {
        let (durationMilliseconds, overflow) = endMilliseconds
            .subtractingReportingOverflow(startMilliseconds)
        guard !overflow,
              durationMilliseconds > 0,
              durationMilliseconds % 1_000 == 0
        else {
            throw MiniMaxPayloadValidationError.invalidValue
        }
        let seconds = durationMilliseconds / 1_000
        guard let durationSeconds = UInt(exactly: seconds) else {
            throw MiniMaxPayloadValidationError.invalidValue
        }
        let start = Date(
            timeIntervalSince1970: TimeInterval(startMilliseconds) / 1_000
        )
        let end = Date(
            timeIntervalSince1970: TimeInterval(endMilliseconds) / 1_000
        )
        guard start.timeIntervalSince1970.isFinite,
              end.timeIntervalSince1970.isFinite
        else {
            throw MiniMaxPayloadValidationError.invalidValue
        }
        return CapacityWindow(
            kind: kind,
            durationSeconds: durationSeconds,
            startsAt: start,
            endsAt: end,
            nextTransition: CapacityTransition(kind: .reset, at: end)
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case providerIdentifier = "model_name"
        case startTime = "start_time"
        case endTime = "end_time"
        case remainsTime = "remains_time"
        case currentIntervalTotalCount = "current_interval_total_count"
        case currentIntervalUsageCount = "current_interval_usage_count"
        case currentIntervalRemainingPercent =
            "current_interval_remaining_percent"
        case currentWeeklyTotalCount = "current_weekly_total_count"
        case currentWeeklyUsageCount = "current_weekly_usage_count"
        case currentWeeklyRemainingPercent =
            "current_weekly_remaining_percent"
        case currentIntervalStatus = "current_interval_status"
        case currentWeeklyStatus = "current_weekly_status"
        case weeklyStartTime = "weekly_start_time"
        case weeklyEndTime = "weekly_end_time"
        case weeklyRemainsTime = "weekly_remains_time"
        case weeklyBoostPermille = "weekly_boost_permille"
    }
}

private extension Array where Element == MiniMaxTokenPlanQuotaCategory {
    func capacity(
        reviewedCategories: MiniMaxQuotaCategoryMapping,
        accountContextID: String,
        observedAt: Date
    ) throws -> MiniMaxCapacityResult {
        var seenProviderIdentifiers = Set<String>()
        var metrics: [CapacityMetric] = []
        var diagnostics: [MiniMaxMappingDiagnostic] = []

        for quotaCategory in self {
            guard seenProviderIdentifiers.insert(
                quotaCategory.providerIdentifier
            ).inserted else {
                throw MiniMaxPayloadValidationError.duplicateQuotaCategory
            }
            guard let reviewedCategory = reviewedCategories.reviewedCategory(
                forProviderIdentifier: quotaCategory.providerIdentifier
            ) else {
                diagnostics.append(
                    MiniMaxMappingDiagnostic(code: .unknownQuotaCategory)
                )
                continue
            }
            metrics.append(
                try quotaCategory.currentMetric(
                    category: reviewedCategory,
                    accountContextID: accountContextID,
                    observedAt: observedAt
                )
            )
            metrics.append(
                try quotaCategory.weeklyMetric(
                    category: reviewedCategory,
                    accountContextID: accountContextID,
                    observedAt: observedAt
                )
            )
        }

        return MiniMaxCapacityResult(
            observedAt: observedAt,
            metrics: metrics,
            diagnostics: diagnostics
        )
    }
}

private enum MiniMaxPayloadValidationError: Error {
    case invalidValue
    case duplicateQuotaCategory
    case unknownField
}

private struct MiniMaxAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension Decoder {
    func rejectUnknownKeys(allowed: Set<String>) throws {
        let container = try container(keyedBy: MiniMaxAnyCodingKey.self)
        guard container.allKeys.allSatisfy({
            allowed.contains($0.stringValue)
        }) else {
            throw MiniMaxPayloadValidationError.unknownField
        }
    }
}
