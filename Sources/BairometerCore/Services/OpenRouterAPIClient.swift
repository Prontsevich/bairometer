import Foundation

public enum OpenRouterKeyTier: Equatable, Sendable {
    case free
    case paid
}

public enum OpenRouterCredentialRoleError: Error, LocalizedError, Equatable, Sendable {
    case providerMismatch
    case roleMismatch

    public var errorDescription: String? {
        switch self {
        case .providerMismatch:
            "The credential does not belong to OpenRouter."
        case .roleMismatch:
            "The credential role does not match the requested OpenRouter capability."
        }
    }
}

private struct OpenRouterCredentialIdentity: Sendable {
    let providerID: String
    let accountID: String
    let contextID: String
    let slotID: String
    let credentialRevision: Int

    init(slot: ProviderCredentialSlot) {
        providerID = slot.providerID
        accountID = slot.accountID
        contextID = slot.contextID
        slotID = slot.slotID
        credentialRevision = slot.credentialRevision
    }
}

public struct OpenRouterOrdinaryCredential:
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    private let secret: CredentialSecret
    private let identity: OpenRouterCredentialIdentity

    public init(
        slot: ProviderCredentialSlot,
        secret: CredentialSecret
    ) throws {
        guard slot.providerID == "openrouter" else {
            throw OpenRouterCredentialRoleError.providerMismatch
        }
        guard slot.role == .ordinary else {
            throw OpenRouterCredentialRoleError.roleMismatch
        }
        self.secret = secret
        identity = OpenRouterCredentialIdentity(slot: slot)
    }

    public var description: String { "<redacted OpenRouter ordinary credential>" }
    public var debugDescription: String { description }

    fileprivate func withUTF8String<Result>(
        _ body: (String) throws -> Result
    ) throws -> Result {
        try secret.withUTF8String(body)
    }

    var accountContextID: String { identity.contextID }
    var credentialSlotID: String { identity.slotID }
    var credentialRevision: Int { identity.credentialRevision }
}

public struct OpenRouterManagementCredential:
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    private let secret: CredentialSecret
    private let identity: OpenRouterCredentialIdentity

    public init(
        slot: ProviderCredentialSlot,
        secret: CredentialSecret
    ) throws {
        guard slot.providerID == "openrouter" else {
            throw OpenRouterCredentialRoleError.providerMismatch
        }
        guard slot.role == .management else {
            throw OpenRouterCredentialRoleError.roleMismatch
        }
        self.secret = secret
        identity = OpenRouterCredentialIdentity(slot: slot)
    }

    public var description: String { "<redacted OpenRouter management credential>" }
    public var debugDescription: String { description }

    fileprivate func withUTF8String<Result>(
        _ body: (String) throws -> Result
    ) throws -> Result {
        try secret.withUTF8String(body)
    }

    var accountContextID: String { identity.contextID }
    var credentialSlotID: String { identity.slotID }
    var credentialRevision: Int { identity.credentialRevision }
}

public struct OpenRouterCurrentKeyCapacity: Equatable, Sendable {
    public let metrics: [CapacityMetric]
    public let includesBYOKInLimit: Bool
    public let tier: OpenRouterKeyTier
    public let expiresAt: Date?

    init(
        metrics: [CapacityMetric],
        includesBYOKInLimit: Bool,
        tier: OpenRouterKeyTier,
        expiresAt: Date?
    ) {
        self.metrics = metrics
        self.includesBYOKInLimit = includesBYOKInLimit
        self.tier = tier
        self.expiresAt = expiresAt
    }
}

public struct OpenRouterManagementCreditsCapacity: Equatable, Sendable {
    public let metric: CapacityMetric

    init(metric: CapacityMetric) {
        self.metric = metric
    }
}

public enum OpenRouterRetryAfter: Equatable, Sendable {
    case seconds(UInt)
    case date(Date)
}

public enum OpenRouterAPIClientError: Error, LocalizedError, Equatable, Sendable {
    case timedOut
    case cancelled
    case transportFailure
    case authenticationFailure
    case insufficientCredits
    case insufficientPrivilege
    case throttled(retryAfter: OpenRouterRetryAfter?)
    case serviceUnavailable(retryAfter: OpenRouterRetryAfter?)
    case serverFailure(statusCode: Int)
    case httpFailure(statusCode: Int)
    case decodingFailure
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .timedOut:
            "OpenRouter request timed out."
        case .cancelled:
            "OpenRouter request was cancelled."
        case .transportFailure:
            "OpenRouter could not be reached."
        case .authenticationFailure:
            "OpenRouter credential authentication failed."
        case .insufficientCredits:
            "OpenRouter reported insufficient credits."
        case .insufficientPrivilege:
            "OpenRouter credential privileges are insufficient."
        case .throttled:
            "OpenRouter request was throttled."
        case .serviceUnavailable:
            "OpenRouter service is temporarily unavailable."
        case .serverFailure:
            "OpenRouter service returned a server failure."
        case .httpFailure:
            "OpenRouter request returned an unsupported HTTP response."
        case .decodingFailure:
            "OpenRouter returned an unsupported response."
        case .responseTooLarge:
            "OpenRouter returned an unexpectedly large response."
        }
    }
}

public protocol OpenRouterAPIClient: Sendable {
    func fetchCurrentKeyCapacity(
        credential: OpenRouterOrdinaryCredential
    ) async throws -> OpenRouterCurrentKeyCapacity

    func fetchManagementCredits(
        credential: OpenRouterManagementCredential
    ) async throws -> OpenRouterManagementCreditsCapacity
}

public struct URLSessionOpenRouterAPIClient: OpenRouterAPIClient {
    static let currentKeyURL = URL(string: "https://openrouter.ai/api/v1/key")!
    static let managementCreditsURL = URL(
        string: "https://openrouter.ai/api/v1/credits"
    )!

    private static let minimumTimeout: TimeInterval = 0.01
    private static let maximumTimeout: TimeInterval = 60
    private static let maximumResponseLimit = 4_194_304
    private static let maximumPreservedJSONLimit = 8_388_608
    private let sessionConfiguration: URLSessionConfiguration
    private let timeout: TimeInterval
    private let responseLimit: Int
    private let preservedJSONLimit: Int
    private let now: @Sendable () -> Date
    private let currentKeyURL: URL
    private let managementCreditsURL: URL

    public init() {
        self.init(session: Self.makeDefaultSession())
    }

    init(
        session: URLSession,
        timeout: TimeInterval = 15,
        responseLimit: Int = 1_048_576,
        now: @escaping @Sendable () -> Date = Date.init,
        currentKeyURL: URL = Self.currentKeyURL,
        managementCreditsURL: URL = Self.managementCreditsURL
    ) {
        sessionConfiguration = session.configuration
        self.timeout = timeout.isFinite
            ? min(max(timeout, Self.minimumTimeout), Self.maximumTimeout)
            : 15
        let boundedResponseLimit = min(
            max(1, responseLimit),
            Self.maximumResponseLimit
        )
        self.responseLimit = boundedResponseLimit
        self.preservedJSONLimit = min(
            boundedResponseLimit * 8,
            Self.maximumPreservedJSONLimit
        )
        self.now = now
        self.currentKeyURL = currentKeyURL
        self.managementCreditsURL = managementCreditsURL
    }

    public func fetchCurrentKeyCapacity(
        credential: OpenRouterOrdinaryCredential
    ) async throws -> OpenRouterCurrentKeyCapacity {
        let request = try makeRequest(
            url: currentKeyURL,
            credential: credential
        )
        let data = try await perform(request)
        let envelope: OpenRouterCurrentKeyEnvelope = try decode(data)
        let observedAt = now()

        do {
            return try envelope.data.capacity(
                accountContextID: credential.accountContextID,
                observedAt: observedAt
            )
        } catch {
            throw OpenRouterAPIClientError.decodingFailure
        }
    }

    public func fetchManagementCredits(
        credential: OpenRouterManagementCredential
    ) async throws -> OpenRouterManagementCreditsCapacity {
        let request = try makeRequest(
            url: managementCreditsURL,
            credential: credential
        )
        let data = try await perform(request)
        let envelope: OpenRouterCreditsEnvelope = try decode(data)
        let observedAt = now()

        do {
            return try envelope.data.capacity(
                accountContextID: credential.accountContextID,
                observedAt: observedAt
            )
        } catch {
            throw OpenRouterAPIClientError.decodingFailure
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
        url: URL,
        credential: OpenRouterOrdinaryCredential
    ) throws -> URLRequest {
        try makeRequest(url: url) {
            try credential.withUTF8String($0)
        }
    }

    private func makeRequest(
        url: URL,
        credential: OpenRouterManagementCredential
    ) throws -> URLRequest {
        try makeRequest(url: url) {
            try credential.withUTF8String($0)
        }
    }

    private func makeRequest(
        url: URL,
        authorization: (_ setAuthorization: (String) -> Void) throws -> Void
    ) rethrows -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try authorization {
            request.setValue("Bearer \($0)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let result = try await withThrowingTaskGroup(
                of: OpenRouterHTTPResult.self
            ) { group in
                group.addTask {
                    try await loadBoundedResponse(for: request)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw OpenRouterAPIClientError.timedOut
                }

                defer { group.cancelAll() }
                guard let result = try await group.next() else {
                    throw OpenRouterAPIClientError.transportFailure
                }
                return result
            }

            guard let response = result.response as? HTTPURLResponse else {
                throw OpenRouterAPIClientError.transportFailure
            }
            guard response.statusCode == 200 else {
                throw Self.error(for: response)
            }
            return result.data
        } catch let error as OpenRouterAPIClientError {
            throw error
        } catch is CancellationError {
            throw OpenRouterAPIClientError.cancelled
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw OpenRouterAPIClientError.timedOut
            case .cancelled:
                throw OpenRouterAPIClientError.cancelled
            default:
                throw OpenRouterAPIClientError.transportFailure
            }
        } catch {
            throw OpenRouterAPIClientError.transportFailure
        }
    }

    private func loadBoundedResponse(
        for request: URLRequest
    ) async throws -> OpenRouterHTTPResult {
        let delegate = OpenRouterStreamingResponseDelegate(
            responseLimit: responseLimit
        )
        let requestSession = URLSession(
            configuration: sessionConfiguration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { requestSession.finishTasksAndInvalidate() }
        return try await delegate.load(
            request: request,
            using: requestSession
        )
    }

    private func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do {
            let preserved = try JSONNumberPreserver.preserve(
                in: data,
                outputLimit: preservedJSONLimit
            )
            let decoder = JSONDecoder()
            decoder.userInfo[JSONNumberPreserver.nonceUserInfoKey] = preserved.nonce
            return try decoder.decode(Value.self, from: preserved.data)
        } catch JSONNumberPreserverError.expansionLimitExceeded {
            throw OpenRouterAPIClientError.responseTooLarge
        } catch {
            throw OpenRouterAPIClientError.decodingFailure
        }
    }

    private static func error(for response: HTTPURLResponse) -> OpenRouterAPIClientError {
        switch response.statusCode {
        case 401:
            .authenticationFailure
        case 402:
            .insufficientCredits
        case 403:
            .insufficientPrivilege
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

    private static func retryAfter(from response: HTTPURLResponse) -> OpenRouterRetryAfter? {
        guard let headerValue = response.value(forHTTPHeaderField: "Retry-After"),
            let rawValue = trimHTTPOptionalWhitespace(headerValue),
            !rawValue.isEmpty
        else {
            return nil
        }

        let bytes = rawValue.utf8
        if bytes.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
           let seconds = UInt(rawValue)
        {
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

    private static func trimHTTPOptionalWhitespace(_ value: String) -> String? {
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

private struct OpenRouterHTTPResult: @unchecked Sendable {
    let data: Data
    let response: URLResponse
}

final class OpenRouterStreamingResponseDelegate:
    NSObject,
    URLSessionDataDelegate,
    @unchecked Sendable
{
    private enum PendingOutcome {
        case result(OpenRouterHTTPResult)
        case failure(Error)
    }

    private let responseLimit: Int
    private let lock = NSLock()
    private var continuation:
        CheckedContinuation<OpenRouterHTTPResult, Error>?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var pendingOutcome: PendingOutcome?
    private var didComplete = false

    init(responseLimit: Int) {
        self.responseLimit = responseLimit
    }

    fileprivate func load(
        request: URLRequest,
        using session: URLSession
    ) async throws -> OpenRouterHTTPResult {
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
                pendingOutcome = .failure(
                    OpenRouterAPIClientError.transportFailure
                )
                return .cancel
            }
            self.response = httpResponse
            guard httpResponse.statusCode == 200 else {
                pendingOutcome = .result(
                    OpenRouterHTTPResult(
                        data: Data(),
                        response: httpResponse
                    )
                )
                return .cancel
            }
            guard response.expectedContentLength <= Int64(responseLimit) else {
                pendingOutcome = .failure(
                    OpenRouterAPIClientError.responseTooLarge
                )
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
                pendingOutcome = .failure(
                    OpenRouterAPIClientError.responseTooLarge
                )
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
        let completed: (
            CheckedContinuation<OpenRouterHTTPResult, Error>,
            PendingOutcome
        )? = lock.withLock {
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
                outcome = .result(
                    OpenRouterHTTPResult(
                        data: data,
                        response: response
                    )
                )
            } else {
                outcome = .failure(
                    OpenRouterAPIClientError.transportFailure
                )
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

private struct OpenRouterCurrentKeyEnvelope: Decodable {
    let data: OpenRouterCurrentKeyData
}

private struct OpenRouterCurrentKeyData: Decodable {
    let usage: StrictJSONDecimal
    let usageDaily: StrictJSONDecimal
    let usageWeekly: StrictJSONDecimal
    let usageMonthly: StrictJSONDecimal
    let byokUsage: StrictJSONDecimal
    let byokUsageDaily: StrictJSONDecimal
    let byokUsageWeekly: StrictJSONDecimal
    let byokUsageMonthly: StrictJSONDecimal
    let limit: StrictJSONDecimal?
    let limitRemaining: StrictJSONDecimal?
    let limitReset: OpenRouterLimitReset?
    let includesBYOKInLimit: Bool
    let isFreeTier: Bool
    let isManagementKey: Bool
    let expiresAt: String?

    private enum CodingKeys: String, CodingKey {
        case usage
        case usageDaily = "usage_daily"
        case usageWeekly = "usage_weekly"
        case usageMonthly = "usage_monthly"
        case byokUsage = "byok_usage"
        case byokUsageDaily = "byok_usage_daily"
        case byokUsageWeekly = "byok_usage_weekly"
        case byokUsageMonthly = "byok_usage_monthly"
        case limit
        case limitRemaining = "limit_remaining"
        case limitReset = "limit_reset"
        case includesBYOKInLimit = "include_byok_in_limit"
        case isFreeTier = "is_free_tier"
        case isManagementKey = "is_management_key"
        case expiresAt = "expires_at"
    }

    func capacity(
        accountContextID: String,
        observedAt: Date
    ) throws -> OpenRouterCurrentKeyCapacity {
        let requiredUsageValues = [
            usage,
            usageDaily,
            usageWeekly,
            usageMonthly,
            byokUsage,
            byokUsageDaily,
            byokUsageWeekly,
            byokUsageMonthly
        ]
        guard requiredUsageValues.allSatisfy({ $0.value >= .zero }) else {
            throw OpenRouterPayloadValidationError.invalidValue
        }
        guard limit == nil || limit!.value >= .zero else {
            throw OpenRouterPayloadValidationError.invalidValue
        }
        guard limit != nil || (limitRemaining == nil && limitReset == nil) else {
            throw OpenRouterPayloadValidationError.invalidValue
        }
        guard !isManagementKey else {
            throw OpenRouterPayloadValidationError.invalidValue
        }

        let tier: OpenRouterKeyTier = isFreeTier ? .free : .paid
        let expiration = try expiresAt.map(OpenRouterDateParser.parse)
        var metrics = [
            Self.spendMetric(
                id: "key-total-usage",
                displayName: "API key total usage",
                value: usage.value,
                accountContextID: accountContextID,
                window: OpenRouterCapacityWindow.lifetime,
                observedAt: observedAt
            ),
            Self.spendMetric(
                id: "key-daily-usage",
                displayName: "API key daily usage",
                value: usageDaily.value,
                accountContextID: accountContextID,
                window: OpenRouterCapacityWindow.daily(observedAt: observedAt),
                observedAt: observedAt
            ),
            Self.spendMetric(
                id: "key-weekly-usage",
                displayName: "API key weekly usage",
                value: usageWeekly.value,
                accountContextID: accountContextID,
                window: OpenRouterCapacityWindow.weekly(observedAt: observedAt),
                observedAt: observedAt
            ),
            Self.spendMetric(
                id: "key-monthly-usage",
                displayName: "API key monthly usage",
                value: usageMonthly.value,
                accountContextID: accountContextID,
                window: OpenRouterCapacityWindow.monthly(observedAt: observedAt),
                observedAt: observedAt
            ),
            Self.spendMetric(
                id: "key-total-byok-usage",
                displayName: "API key total BYOK usage",
                value: byokUsage.value,
                accountContextID: accountContextID,
                window: OpenRouterCapacityWindow.lifetime,
                observedAt: observedAt
            ),
            Self.spendMetric(
                id: "key-daily-byok-usage",
                displayName: "API key daily BYOK usage",
                value: byokUsageDaily.value,
                accountContextID: accountContextID,
                window: OpenRouterCapacityWindow.daily(observedAt: observedAt),
                observedAt: observedAt
            ),
            Self.spendMetric(
                id: "key-weekly-byok-usage",
                displayName: "API key weekly BYOK usage",
                value: byokUsageWeekly.value,
                accountContextID: accountContextID,
                window: OpenRouterCapacityWindow.weekly(observedAt: observedAt),
                observedAt: observedAt
            ),
            Self.spendMetric(
                id: "key-monthly-byok-usage",
                displayName: "API key monthly BYOK usage",
                value: byokUsageMonthly.value,
                accountContextID: accountContextID,
                window: OpenRouterCapacityWindow.monthly(observedAt: observedAt),
                observedAt: observedAt
            )
        ]

        if let limit {
            let remaining = limitRemaining.map {
                CapacityValue(value: $0.value, origin: .reported)
            }
            metrics.append(
                CapacityMetric(
                    metricID: "key-credit-limit",
                    accountContextID: accountContextID,
                    sourceID: "current-key-api",
                    capability: "credits",
                    displayName: "API key credit limit",
                    availability: .known,
                    conditions: limitRemaining?.value ?? .zero < .zero ? [.overage] : [],
                    unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
                    values: CapacityValues(
                        remaining: remaining,
                        limit: CapacityValue(value: limit.value, origin: .reported)
                    ),
                    window: OpenRouterCapacityWindow.limit(
                        reset: limitReset,
                        observedAt: observedAt
                    ),
                    freshness: ObservationFreshness(observedAt: observedAt),
                    confidence: .live
                )
            )
        }

        return OpenRouterCurrentKeyCapacity(
            metrics: metrics,
            includesBYOKInLimit: includesBYOKInLimit,
            tier: tier,
            expiresAt: expiration
        )
    }

    private static func spendMetric(
        id: String,
        displayName: String,
        value: Decimal,
        accountContextID: String,
        window: CapacityWindow,
        observedAt: Date
    ) -> CapacityMetric {
        CapacityMetric(
            metricID: id,
            accountContextID: accountContextID,
            sourceID: "current-key-api",
            capability: "spend",
            displayName: displayName,
            availability: .known,
            unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
            values: CapacityValues(
                consumed: CapacityValue(value: value, origin: .reported)
            ),
            window: window,
            freshness: ObservationFreshness(observedAt: observedAt),
            confidence: .live
        )
    }
}

private struct OpenRouterCreditsEnvelope: Decodable {
    let data: OpenRouterCreditsData
}

private struct OpenRouterCreditsData: Decodable {
    let totalCredits: StrictJSONDecimal
    let totalUsage: StrictJSONDecimal

    private enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }

    func capacity(
        accountContextID: String,
        observedAt: Date
    ) throws -> OpenRouterManagementCreditsCapacity {
        guard totalCredits.value >= .zero, totalUsage.value >= .zero else {
            throw OpenRouterPayloadValidationError.invalidValue
        }
        let remaining = totalCredits.value - totalUsage.value
        guard !remaining.isNaN else {
            throw OpenRouterPayloadValidationError.invalidValue
        }

        return OpenRouterManagementCreditsCapacity(
            metric: CapacityMetric(
                metricID: "account-credits",
                accountContextID: accountContextID,
                sourceID: "management-api",
                capability: "credits",
                displayName: "Account credits",
                availability: .known,
                conditions: remaining < .zero ? [.overage] : [],
                unit: CapacityUnit(kind: .currency, currencyCode: "USD"),
                values: CapacityValues(
                    consumed: CapacityValue(value: totalUsage.value, origin: .reported),
                    remaining: CapacityValue(value: remaining, origin: .derived),
                    limit: CapacityValue(value: totalCredits.value, origin: .reported)
                ),
                window: CapacityWindow(kind: .none),
                freshness: ObservationFreshness(observedAt: observedAt),
                confidence: .live,
                derivations: [
                    Derivation(
                        kind: .remainingFromLimitMinusConsumed,
                        target: .remaining,
                        inputs: [.limit, .consumed]
                    )
                ]
            )
        )
    }
}

private enum OpenRouterLimitReset: String, Decodable {
    case daily
    case weekly
    case monthly
}

private enum OpenRouterCapacityWindow {
    static let lifetime = CapacityWindow(kind: .lifetime)

    static func daily(observedAt: Date) -> CapacityWindow {
        CapacityWindow(
            kind: .fixed,
            durationSeconds: 86_400,
            nextTransition: CapacityTransition(
                kind: .reset,
                at: nextDailyReset(after: observedAt)
            )
        )
    }

    static func weekly(observedAt: Date) -> CapacityWindow {
        CapacityWindow(
            kind: .fixed,
            durationSeconds: 604_800,
            nextTransition: CapacityTransition(
                kind: .reset,
                at: nextWeeklyReset(after: observedAt)
            )
        )
    }

    static func monthly(observedAt: Date) -> CapacityWindow {
        CapacityWindow(
            kind: .billingCycle,
            nextTransition: CapacityTransition(
                kind: .reset,
                at: nextMonthlyReset(after: observedAt)
            )
        )
    }

    static func limit(
        reset: OpenRouterLimitReset?,
        observedAt: Date
    ) -> CapacityWindow {
        switch reset {
        case .daily:
            daily(observedAt: observedAt)
        case .weekly:
            weekly(observedAt: observedAt)
        case .monthly:
            monthly(observedAt: observedAt)
        case nil:
            lifetime
        }
    }

    private static func nextDailyReset(after date: Date) -> Date {
        utcCalendar.date(
            byAdding: .day,
            value: 1,
            to: utcCalendar.startOfDay(for: date)
        )!
    }

    private static func nextWeeklyReset(after date: Date) -> Date {
        let startOfDay = utcCalendar.startOfDay(for: date)
        let weekday = utcCalendar.component(.weekday, from: startOfDay)
        let daysUntilMonday = (9 - weekday) % 7
        let offset = daysUntilMonday == 0 ? 7 : daysUntilMonday
        return utcCalendar.date(byAdding: .day, value: offset, to: startOfDay)!
    }

    private static func nextMonthlyReset(after date: Date) -> Date {
        let components = utcCalendar.dateComponents([.year, .month], from: date)
        let startOfMonth = utcCalendar.date(from: components)!
        return utcCalendar.date(byAdding: .month, value: 1, to: startOfMonth)!
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private enum OpenRouterDateParser {
    static func parse(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }
        throw OpenRouterPayloadValidationError.invalidValue
    }
}

private enum OpenRouterPayloadValidationError: Error {
    case invalidValue
}

private struct StrictJSONDecimal: Decodable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nonce = try container.decode(String.self, forKey: .nonce)
        let lexeme = try container.decode(String.self, forKey: .lexeme)
        guard let expectedNonce = decoder.userInfo[
            JSONNumberPreserver.nonceUserInfoKey
        ] as? String,
            nonce == expectedNonce
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .nonce,
                in: container,
                debugDescription: "Expected a JSON number."
            )
        }
        guard let canonical = Self.canonicalPlainDecimal(from: lexeme),
              let decimal = Decimal(
                  string: lexeme,
                  locale: Locale(identifier: "en_US_POSIX")
              ),
              !decimal.isNaN,
              NSDecimalNumber(decimal: decimal).stringValue == canonical
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .lexeme,
                in: container,
                debugDescription: "Expected an exactly representable decimal number."
            )
        }
        value = decimal
    }

    private enum CodingKeys: String, CodingKey {
        case nonce = "__BairometerJSONNumberNonce"
        case lexeme
    }

    private static func canonicalPlainDecimal(from lexeme: String) -> String? {
        guard let match = lexeme.wholeMatch(
            of: /(-?)(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?/
        ) else {
            return nil
        }

        let isNegative = !match.1.isEmpty
        let integer = String(match.2)
        let fraction = match.3.map(String.init) ?? ""
        let exponentString = match.4.map(String.init) ?? "0"
        guard let exponent = Int(exponentString),
              exponent >= -1_000,
              exponent <= 1_000
        else {
            return nil
        }

        let digits = integer + fraction
        let decimalIndex = integer.count + exponent
        let unsigned: String
        if decimalIndex <= 0 {
            unsigned = "0." + String(repeating: "0", count: -decimalIndex) + digits
        } else if decimalIndex >= digits.count {
            unsigned = digits + String(repeating: "0", count: decimalIndex - digits.count)
        } else {
            let splitIndex = digits.index(digits.startIndex, offsetBy: decimalIndex)
            unsigned = String(digits[..<splitIndex]) + "." + String(digits[splitIndex...])
        }

        let components = unsigned.split(
            separator: ".",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let trimmedInteger = components[0].drop { $0 == "0" }
        let normalizedInteger = trimmedInteger.isEmpty ? "0" : String(trimmedInteger)
        var normalizedFraction = components.count == 2 ? String(components[1]) : ""
        while normalizedFraction.last == "0" {
            normalizedFraction.removeLast()
        }

        guard normalizedInteger != "0" || !normalizedFraction.isEmpty else {
            return "0"
        }
        let normalized = normalizedFraction.isEmpty
            ? normalizedInteger
            : "\(normalizedInteger).\(normalizedFraction)"
        return isNegative ? "-\(normalized)" : normalized
    }
}

enum JSONNumberPreserver {
    static let nonceUserInfoKey = CodingUserInfoKey(
        rawValue: "Bairometer.OpenRouter.JSONNumberNonce"
    )!

    static func preserve(
        in data: Data,
        outputLimit: Int
    ) throws -> PreservedJSONNumbers {
        let nonce = UUID().uuidString
        let bytes = Array(data)
        var result: [UInt8] = []
        result.reserveCapacity(min(bytes.count, outputLimit))
        var index = 0
        var isInsideString = false
        var isEscaped = false

        while index < bytes.count {
            let byte = bytes[index]
            if isInsideString {
                try append(byte, to: &result, limit: outputLimit)
                if isEscaped {
                    isEscaped = false
                } else if byte == 0x5C {
                    isEscaped = true
                } else if byte == 0x22 {
                    isInsideString = false
                }
                index += 1
                continue
            }

            if byte == 0x22 {
                isInsideString = true
                try append(byte, to: &result, limit: outputLimit)
                index += 1
                continue
            }

            if byte == 0x2D || isDigit(byte) {
                let start = index
                index = try scanNumber(in: bytes, from: index)
                let lexeme = bytes[start ..< index]
                try append(
                    contentsOf: #"{"__BairometerJSONNumberNonce":""#.utf8,
                    to: &result,
                    limit: outputLimit
                )
                try append(contentsOf: nonce.utf8, to: &result, limit: outputLimit)
                try append(
                    contentsOf: #"","lexeme":""#.utf8,
                    to: &result,
                    limit: outputLimit
                )
                try append(contentsOf: lexeme, to: &result, limit: outputLimit)
                try append(
                    contentsOf: #""}"#.utf8,
                    to: &result,
                    limit: outputLimit
                )
                continue
            }

            try append(byte, to: &result, limit: outputLimit)
            index += 1
        }

        guard !isInsideString else {
            throw OpenRouterPayloadValidationError.invalidValue
        }
        return PreservedJSONNumbers(data: Data(result), nonce: nonce)
    }

    private static func append(
        _ byte: UInt8,
        to result: inout [UInt8],
        limit: Int
    ) throws {
        guard result.count < limit else {
            throw JSONNumberPreserverError.expansionLimitExceeded
        }
        result.append(byte)
    }

    private static func append<Bytes: Collection>(
        contentsOf bytes: Bytes,
        to result: inout [UInt8],
        limit: Int
    ) throws where Bytes.Element == UInt8 {
        guard bytes.count <= limit - result.count else {
            throw JSONNumberPreserverError.expansionLimitExceeded
        }
        result.append(contentsOf: bytes)
    }

    private static func scanNumber(
        in bytes: [UInt8],
        from start: Int
    ) throws -> Int {
        var index = start
        if bytes[index] == 0x2D {
            index += 1
            guard index < bytes.count else {
                throw OpenRouterPayloadValidationError.invalidValue
            }
        }

        if bytes[index] == 0x30 {
            index += 1
        } else {
            guard isNonZeroDigit(bytes[index]) else {
                throw OpenRouterPayloadValidationError.invalidValue
            }
            index += 1
            while index < bytes.count, isDigit(bytes[index]) {
                index += 1
            }
        }

        if index < bytes.count, bytes[index] == 0x2E {
            index += 1
            guard index < bytes.count, isDigit(bytes[index]) else {
                throw OpenRouterPayloadValidationError.invalidValue
            }
            while index < bytes.count, isDigit(bytes[index]) {
                index += 1
            }
        }

        if index < bytes.count,
           bytes[index] == 0x65 || bytes[index] == 0x45
        {
            index += 1
            if index < bytes.count,
               bytes[index] == 0x2B || bytes[index] == 0x2D
            {
                index += 1
            }
            guard index < bytes.count, isDigit(bytes[index]) else {
                throw OpenRouterPayloadValidationError.invalidValue
            }
            while index < bytes.count, isDigit(bytes[index]) {
                index += 1
            }
        }

        if index < bytes.count {
            let delimiter = bytes[index]
            guard delimiter == 0x2C
                || delimiter == 0x5D
                || delimiter == 0x7D
                || delimiter == 0x20
                || delimiter == 0x09
                || delimiter == 0x0A
                || delimiter == 0x0D
            else {
                throw OpenRouterPayloadValidationError.invalidValue
            }
        }
        return index
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    private static func isNonZeroDigit(_ byte: UInt8) -> Bool {
        byte >= 0x31 && byte <= 0x39
    }
}

struct PreservedJSONNumbers {
    let data: Data
    let nonce: String
}

enum JSONNumberPreserverError: Error {
    case expansionLimitExceeded
}
