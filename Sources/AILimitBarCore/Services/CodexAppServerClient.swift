import Foundation

public struct CodexRateLimitWindowPayload: Codable, Equatable, Sendable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: Int?

    public init(
        usedPercent: Double?,
        windowDurationMins: Int? = nil,
        resetsAt: Int? = nil
    ) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct CodexRateLimitBucketPayload: Codable, Equatable, Sendable {
    public let limitID: String?
    public let primary: CodexRateLimitWindowPayload?
    public let secondary: CodexRateLimitWindowPayload?

    public init(
        limitID: String?,
        primary: CodexRateLimitWindowPayload?,
        secondary: CodexRateLimitWindowPayload?
    ) {
        self.limitID = limitID
        self.primary = primary
        self.secondary = secondary
    }

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case primary
        case secondary
    }
}

public struct CodexRateLimitsPayload: Codable, Equatable, Sendable {
    public let rateLimits: CodexRateLimitBucketPayload
    public let rateLimitsByLimitID: [String: CodexRateLimitBucketPayload]?

    public init(
        rateLimits: CodexRateLimitBucketPayload,
        rateLimitsByLimitID: [String: CodexRateLimitBucketPayload]? = nil
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitID = rateLimitsByLimitID
    }

    private enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitID = "rateLimitsByLimitId"
    }
}

public protocol CodexAppServerClient: Sendable {
    func fetchRateLimits(executablePath: String?) async throws -> CodexRateLimitsPayload
}

public enum CodexAppServerClientError: Error, LocalizedError, Equatable, Sendable {
    case executableNotFound
    case configuredExecutableNotFound
    case processLaunchFailed
    case authenticationUnavailable
    case unsupportedProtocol
    case malformedResponse
    case responseTooLarge
    case processExited
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Codex CLI was not found."
        case .configuredExecutableNotFound:
            "The configured Codex executable is unavailable."
        case .processLaunchFailed:
            "Codex app-server could not be started."
        case .authenticationUnavailable:
            "Codex CLI is not authenticated with an account that exposes ChatGPT rate limits."
        case .unsupportedProtocol:
            "This Codex CLI version does not support the required app-server rate-limit interface."
        case .malformedResponse:
            "Codex app-server returned an unsupported response."
        case .responseTooLarge:
            "Codex app-server returned an unexpectedly large response."
        case .processExited:
            "Codex app-server exited before returning rate limits."
        case .timedOut:
            "Codex app-server timed out while reading rate limits."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .executableNotFound:
            "Install Codex CLI or configure its executable path in Settings."
        case .configuredExecutableNotFound:
            "Choose an executable Codex CLI path or clear the override to use automatic discovery."
        case .processLaunchFailed:
            "Verify that the selected Codex CLI can run, then try again."
        case .authenticationUnavailable:
            "Sign in with codex login, then refresh this account again."
        case .unsupportedProtocol:
            "Update Codex CLI and try refreshing again."
        case .malformedResponse, .responseTooLarge, .processExited:
            "Update Codex CLI and try refreshing again."
        case .timedOut:
            "Check your Codex connection and try the refresh again."
        }
    }

    public var isTransient: Bool {
        switch self {
        case .processLaunchFailed, .processExited, .timedOut:
            true
        case .executableNotFound,
             .configuredExecutableNotFound,
             .authenticationUnavailable,
             .unsupportedProtocol,
             .malformedResponse,
             .responseTooLarge:
            false
        }
    }
}

public struct CodexExecutableLocator: Sendable {
    public init() {}

    public func locate(executablePath: String?) throws -> URL {
        let trimmedOverride = executablePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedOverride.isEmpty {
            let url = URL(fileURLWithPath: (trimmedOverride as NSString).expandingTildeInPath)
                .standardizedFileURL
            guard isExecutableFile(at: url) else {
                throw CodexAppServerClientError.configuredExecutableNotFound
            }
            return url
        }

        guard let url = Self.automaticCandidates().first(where: isExecutableFile) else {
            throw CodexAppServerClientError.executableNotFound
        }
        return url
    }

    public static func automaticCandidates(
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let pathCandidates = (path ?? "")
            .split(separator: ":")
            .compactMap { entry -> URL? in
                guard entry.hasPrefix("/") else { return nil }
                return URL(fileURLWithPath: String(entry)).appendingPathComponent("codex")
            }
        let standardCandidates = [
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            homeDirectory.appendingPathComponent(".local/share/mise/shims/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            URL(fileURLWithPath: "/usr/bin/codex")
        ]

        var seen = Set<String>()
        return (pathCandidates + standardCandidates).filter { seen.insert($0.path).inserted }
    }

    private func isExecutableFile(at url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }
}

public struct ProcessCodexAppServerClient: CodexAppServerClient {
    private let locator: CodexExecutableLocator
    private let timeout: TimeInterval
    private let responseLimit: Int
    private let environment: @Sendable () -> [String: String]
    private let workingDirectoryURL: URL

    public init(
        locator: CodexExecutableLocator = CodexExecutableLocator(),
        timeout: TimeInterval = 15,
        responseLimit: Int = 1_048_576,
        environment: @escaping @Sendable () -> [String: String] = {
            ProcessInfo.processInfo.environment
        },
        workingDirectoryURL: URL? = nil
    ) {
        self.locator = locator
        self.timeout = timeout
        self.responseLimit = responseLimit
        self.environment = environment
        self.workingDirectoryURL = (workingDirectoryURL ?? ProviderCLIProcessIsolation.defaultWorkingDirectoryURL())
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    public func fetchRateLimits(executablePath: String?) async throws -> CodexRateLimitsPayload {
        let executableURL = try locator.locate(executablePath: executablePath)
        let session = CodexAppServerProcessSession()

        return try await withThrowingTaskGroup(of: CodexRateLimitsPayload.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await runProcess(
                        executableURL: executableURL,
                        session: session,
                        responseLimit: responseLimit
                    )
                } onCancel: {
                    session.terminate()
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw CodexAppServerClientError.timedOut
            }

            defer {
                group.cancelAll()
                session.terminate()
            }

            guard let result = try await group.next() else {
                throw CodexAppServerClientError.processExited
            }
            return result
        }
    }

    private func runProcess(
        executableURL: URL,
        session: CodexAppServerProcessSession,
        responseLimit: Int
    ) async throws -> CodexRateLimitsPayload {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        do {
            try ProviderCLIProcessIsolation.prepareWorkingDirectory(at: workingDirectoryURL)
        } catch {
            throw CodexAppServerClientError.processLaunchFailed
        }
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = workingDirectoryURL
        process.environment = ProviderCLIProcessIsolation.isolatedEnvironment(
            from: environment(),
            workingDirectoryURL: workingDirectoryURL
        )
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CodexAppServerClientError.processLaunchFailed
        }
        session.install(process)
        let outputReader = CodexAppServerOutputReader(limit: responseLimit)
        outputReader.startReading(from: output.fileHandleForReading)
        defer {
            outputReader.stop()
            try? input.fileHandleForWriting.close()
            session.terminate()
        }

        do {
            try writeRequest(initializationRequest, to: input.fileHandleForWriting)
        } catch {
            throw CodexAppServerClientError.processLaunchFailed
        }

        try await awaitInitialization(from: outputReader)

        do {
            try writeRequest(initializedNotification, to: input.fileHandleForWriting)
            try writeRequest(rateLimitsRequest, to: input.fileHandleForWriting)
        } catch {
            throw CodexAppServerClientError.processLaunchFailed
        }

        return try await awaitRateLimits(from: outputReader)
    }

    private var initializationRequest: [String: Any] {
        [
            "method": "initialize",
            "id": 1,
            "params": [
                "clientInfo": [
                    "name": "ai_limitbar",
                    "title": "Bairometer",
                    "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
                ]
            ]
        ]
    }

    private var initializedNotification: [String: Any] {
        [
            "method": "initialized",
            "params": [:]
        ]
    }

    private var rateLimitsRequest: [String: Any] {
        [
            "method": "account/rateLimits/read",
            "id": 2
        ]
    }

    private func writeRequest(_ request: [String: Any], to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: request)
        handle.write(data)
        handle.write(Data([0x0A]))
    }

    private func awaitInitialization(
        from outputReader: CodexAppServerOutputReader
    ) async throws {
        let decoder = JSONDecoder()

        while true {
            let line = try await outputReader.nextLine()
            let header = try decodeHeader(from: line, decoder: decoder)
            if header.method == "account/chatgptAuthTokens/refresh" {
                throw CodexAppServerClientError.authenticationUnavailable
            }
            guard header.id == 1 else { continue }

            let response = try decodeResponse(EmptyResult.self, from: line, decoder: decoder)
            if response.error != nil {
                throw classify(response.error)
            }
            guard response.result != nil else {
                throw CodexAppServerClientError.malformedResponse
            }
            return
        }
    }

    private func awaitRateLimits(
        from outputReader: CodexAppServerOutputReader
    ) async throws -> CodexRateLimitsPayload {
        let decoder = JSONDecoder()

        while true {
            let line = try await outputReader.nextLine()
            let header = try decodeHeader(from: line, decoder: decoder)
            if header.method == "account/chatgptAuthTokens/refresh" {
                throw CodexAppServerClientError.authenticationUnavailable
            }
            guard header.id == 2 else { continue }

            let response = try decodeResponse(CodexRateLimitsPayload.self, from: line, decoder: decoder)
            if let error = response.error {
                throw classify(error)
            }
            guard let result = response.result else {
                throw CodexAppServerClientError.malformedResponse
            }
            return result
        }
    }

    private func decodeHeader(from data: Data, decoder: JSONDecoder) throws -> JSONRPCHeader {
        do {
            return try decoder.decode(JSONRPCHeader.self, from: data)
        } catch {
            throw CodexAppServerClientError.malformedResponse
        }
    }

    private func decodeResponse<Result: Decodable>(
        _ resultType: Result.Type,
        from data: Data,
        decoder: JSONDecoder
    ) throws -> JSONRPCResponse<Result> {
        do {
            return try decoder.decode(JSONRPCResponse<Result>.self, from: data)
        } catch {
            throw CodexAppServerClientError.malformedResponse
        }
    }

    private func classify(_ error: JSONRPCError?) -> CodexAppServerClientError {
        guard let error else { return .malformedResponse }
        let message = error.message.lowercased()
        if error.code == -32601 || message.contains("requires experimentalapi") || message.contains("unknown method") {
            return .unsupportedProtocol
        }
        if message.contains("auth") || message.contains("login") || message.contains("unauthorized") || message.contains("not logged") {
            return .authenticationUnavailable
        }
        return .unsupportedProtocol
    }
}

private struct JSONRPCHeader: Decodable {
    let id: Int?
    let method: String?
}

private struct JSONRPCResponse<Result: Decodable>: Decodable {
    let id: Int?
    let result: Result?
    let error: JSONRPCError?
}

private struct JSONRPCError: Decodable {
    let code: Int
    let message: String
}

private struct EmptyResult: Decodable {}

private final class CodexAppServerProcessSession: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var shouldTerminate = false

    func install(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = self.shouldTerminate
        lock.unlock()

        if shouldTerminate {
            terminate(process)
        }
    }

    func terminate() {
        lock.lock()
        shouldTerminate = true
        let process = process
        lock.unlock()

        if let process {
            terminate(process)
        }
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
    }
}

private final class CodexAppServerOutputReader: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var bufferedData = Data()
    private var queuedLines: [Data] = []
    private var byteCount = 0
    private var handle: FileHandle?
    private var continuation: CheckedContinuation<Data, Error>?
    private var terminalError: Error?
    private var didStop = false

    init(limit: Int) {
        self.limit = limit
    }

    func startReading(from handle: FileHandle) {
        lock.lock()
        guard !didStop else {
            lock.unlock()
            return
        }
        self.handle = handle
        lock.unlock()

        handle.readabilityHandler = { [weak self] readableHandle in
            self?.appendAvailableData(from: readableHandle)
        }
    }

    func nextLine() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !queuedLines.isEmpty {
                let line = queuedLines.removeFirst()
                lock.unlock()
                continuation.resume(returning: line)
                return
            }
            if let terminalError {
                lock.unlock()
                continuation.resume(throwing: terminalError)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func stop() {
        lock.lock()
        guard !didStop else {
            lock.unlock()
            return
        }
        didStop = true
        let handle = handle
        self.handle = nil
        terminalError = CancellationError()
        resumeNextWaiterIfPossible()
        lock.unlock()

        handle?.readabilityHandler = nil
    }

    private func appendAvailableData(from handle: FileHandle) {
        let availableData = handle.availableData

        lock.lock()
        guard !didStop else {
            lock.unlock()
            return
        }

        if availableData.isEmpty {
            terminalError = CodexAppServerClientError.processExited
            resumeNextWaiterIfPossible()
            self.handle = nil
            lock.unlock()
            handle.readabilityHandler = nil
            return
        }

        byteCount += availableData.count
        guard byteCount <= limit else {
            terminalError = CodexAppServerClientError.responseTooLarge
            queuedLines.removeAll()
            bufferedData.removeAll(keepingCapacity: false)
            resumeNextWaiterIfPossible()
            self.handle = nil
            lock.unlock()
            handle.readabilityHandler = nil
            return
        }

        bufferedData.append(availableData)
        while let newlineIndex = bufferedData.firstIndex(of: 0x0A) {
            let line = Data(bufferedData[..<newlineIndex])
            bufferedData.removeSubrange(...newlineIndex)
            if !line.isEmpty {
                queuedLines.append(line)
            }
        }
        resumeNextWaiterIfPossible()
        lock.unlock()
    }

    private func resumeNextWaiterIfPossible() {
        guard let continuation else { return }

        if !queuedLines.isEmpty {
            let line = queuedLines.removeFirst()
            self.continuation = nil
            continuation.resume(returning: line)
        } else if let terminalError {
            self.continuation = nil
            continuation.resume(throwing: terminalError)
        }
    }
}
