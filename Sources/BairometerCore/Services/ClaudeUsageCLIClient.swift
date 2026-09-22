import Foundation

public struct ClaudeUsageCLITokenUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationInputTokens: Int
    public let cacheReadInputTokens: Int

    public init(
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheReadInputTokens: Int
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationInputTokens + cacheReadInputTokens
    }

    public var hasInferenceActivity: Bool {
        inputTokens != 0 ||
            outputTokens != 0 ||
            cacheCreationInputTokens != 0 ||
            cacheReadInputTokens != 0
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

public struct ClaudeUsageCLIModelUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationInputTokens: Int
    public let cacheReadInputTokens: Int
    public let costUSD: Double

    public init(
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheReadInputTokens: Int,
        costUSD: Double
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.costUSD = costUSD
    }

    public var hasInferenceActivity: Bool {
        inputTokens != 0 ||
            outputTokens != 0 ||
            cacheCreationInputTokens != 0 ||
            cacheReadInputTokens != 0 ||
            costUSD != 0
    }
}

public struct ClaudeUsageCLIEnvelope: Equatable, Sendable {
    public let result: String
    public let numTurns: Int
    public let totalCostUSD: Double
    public let usage: ClaudeUsageCLITokenUsage
    public let modelUsage: [String: ClaudeUsageCLIModelUsage]

    public init(
        result: String,
        numTurns: Int = 0,
        totalCostUSD: Double = 0,
        usage: ClaudeUsageCLITokenUsage = ClaudeUsageCLITokenUsage(
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0
        ),
        modelUsage: [String: ClaudeUsageCLIModelUsage] = [:]
    ) {
        self.result = result
        self.numTurns = numTurns
        self.totalCostUSD = totalCostUSD
        self.usage = usage
        self.modelUsage = modelUsage
    }
}

public protocol ClaudeUsageCLIClient: Sendable {
    func fetchUsage(executablePath: String?) async throws -> ClaudeUsageCLIEnvelope
}

public enum ClaudeUsageCLIClientError: Error, LocalizedError, Equatable, Sendable {
    case executableNotFound
    case configuredExecutableNotFound
    case processLaunchFailed
    case authenticationUnavailable
    case unsupportedOutput
    case malformedResponse
    case inferenceActivityDetected
    case responseTooLarge
    case processExited
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Claude Code CLI was not found."
        case .configuredExecutableNotFound:
            "The configured Claude executable is unavailable."
        case .processLaunchFailed:
            "Claude Code CLI could not be started."
        case .authenticationUnavailable:
            "Claude Code CLI is not authenticated with a supported subscription account."
        case .unsupportedOutput:
            "Claude Code CLI did not return supported /usage output."
        case .malformedResponse:
            "Claude Code CLI returned a malformed response."
        case .inferenceActivityDetected:
            "Claude Code CLI reported model activity while reading /usage."
        case .responseTooLarge:
            "Claude Code CLI returned an unexpectedly large response."
        case .processExited:
            "Claude Code CLI exited before returning usage limits."
        case .timedOut:
            "Claude Code CLI timed out while reading usage limits."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .executableNotFound:
            "Install Claude Code CLI or configure its executable path in Settings."
        case .configuredExecutableNotFound:
            "Choose an executable Claude CLI path or clear the override to use automatic discovery."
        case .processLaunchFailed, .processExited, .timedOut:
            "Verify that Claude Code can run and is signed in, then try refreshing again."
        case .authenticationUnavailable:
            "Sign in to Claude Code CLI, then refresh this account again."
        case .unsupportedOutput, .malformedResponse, .responseTooLarge:
            "Update Claude Code CLI or switch this account to Manual or managed statusLine."
        case .inferenceActivityDetected:
            "Stop using the /usage CLI source and switch this account to Manual or managed statusLine."
        }
    }

    public var isTransient: Bool {
        switch self {
        case .processLaunchFailed, .processExited, .timedOut:
            true
        case .executableNotFound,
             .configuredExecutableNotFound,
             .authenticationUnavailable,
             .unsupportedOutput,
             .malformedResponse,
             .inferenceActivityDetected,
             .responseTooLarge:
            false
        }
    }
}

public struct ClaudeExecutableLocator: Sendable {
    public init() {}

    public func locate(executablePath: String?) throws -> URL {
        let trimmedOverride = executablePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedOverride.isEmpty {
            let url = URL(fileURLWithPath: (trimmedOverride as NSString).expandingTildeInPath)
                .standardizedFileURL
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw ClaudeUsageCLIClientError.configuredExecutableNotFound
            }
            return url
        }

        guard let url = Self.automaticCandidates().first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw ClaudeUsageCLIClientError.executableNotFound
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
                return URL(fileURLWithPath: String(entry)).appendingPathComponent("claude")
            }
        let standardCandidates = [
            homeDirectory.appendingPathComponent(".local/bin/claude"),
            homeDirectory.appendingPathComponent(".local/share/mise/shims/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            URL(fileURLWithPath: "/usr/bin/claude")
        ]

        var seen = Set<String>()
        return (pathCandidates + standardCandidates).filter { seen.insert($0.path).inserted }
    }
}

public struct ProcessClaudeUsageCLIClient: ClaudeUsageCLIClient {
    private let locator: ClaudeExecutableLocator
    private let timeout: TimeInterval
    private let responseLimit: Int
    private let environment: @Sendable () -> [String: String]
    private let workingDirectoryURL: URL

    public init(
        locator: ClaudeExecutableLocator = ClaudeExecutableLocator(),
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

    public func fetchUsage(executablePath: String?) async throws -> ClaudeUsageCLIEnvelope {
        let executableURL = try locator.locate(executablePath: executablePath)
        let session = ClaudeUsageCLIProcessSession()

        return try await withThrowingTaskGroup(of: ClaudeUsageCLIEnvelope.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await runProcess(executableURL: executableURL, session: session)
                } onCancel: {
                    session.terminate()
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw ClaudeUsageCLIClientError.timedOut
            }

            defer {
                group.cancelAll()
                session.terminate()
            }

            guard let result = try await group.next() else {
                throw ClaudeUsageCLIClientError.processExited
            }
            return result
        }
    }

    private func runProcess(
        executableURL: URL,
        session: ClaudeUsageCLIProcessSession
    ) async throws -> ClaudeUsageCLIEnvelope {
        let process = Process()
        let output = Pipe()
        let termination = ClaudeUsageCLIProcessTermination()
        let collector = ClaudeUsageCLIOutputCollector(limit: responseLimit) {
            session.terminate()
        }

        do {
            try ProviderCLIProcessIsolation.prepareWorkingDirectory(at: workingDirectoryURL)
        } catch {
            throw ClaudeUsageCLIClientError.processLaunchFailed
        }
        process.executableURL = executableURL
        process.arguments = [
            "--safe-mode",
            "-p",
            "/usage",
            "--output-format",
            "json",
            "--tools",
            "",
            "--no-session-persistence"
        ]
        process.currentDirectoryURL = workingDirectoryURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var processEnvironment = ProviderCLIProcessIsolation.isolatedEnvironment(
            from: environment(),
            workingDirectoryURL: workingDirectoryURL
        )
        processEnvironment["TZ"] = "UTC"
        processEnvironment["LC_ALL"] = "en_US.UTF-8"
        processEnvironment["LANG"] = "en_US.UTF-8"
        process.environment = processEnvironment
        process.terminationHandler = { process in
            termination.finish(status: process.terminationStatus)
        }

        collector.startReading(from: output.fileHandleForReading)
        do {
            try process.run()
        } catch {
            collector.stop()
            throw ClaudeUsageCLIClientError.processLaunchFailed
        }
        session.install(process)

        defer {
            collector.stop()
            session.terminate()
        }

        let data = try await collector.data()
        let status = await termination.status()
        try Task.checkCancellation()

        guard status == 0 else {
            throw ClaudeUsageCLIClientError.processExited
        }
        return try ClaudeUsageCLIEnvelopeDecoder.decode(data)
    }
}

private struct ClaudeUsageCLIRawEnvelope: Decodable {
    let type: String
    let subtype: String
    let isError: Bool
    let result: String
    let numTurns: Int
    let totalCostUSD: Double
    let usage: ClaudeUsageCLITokenUsage
    let modelUsage: [String: ClaudeUsageCLIModelUsage]?

    private enum CodingKeys: String, CodingKey {
        case type
        case subtype
        case isError = "is_error"
        case result
        case numTurns = "num_turns"
        case totalCostUSD = "total_cost_usd"
        case usage
        case modelUsage
    }
}

private enum ClaudeUsageCLIEnvelopeDecoder {
    static func decode(_ data: Data) throws -> ClaudeUsageCLIEnvelope {
        let raw: ClaudeUsageCLIRawEnvelope
        do {
            raw = try JSONDecoder().decode(ClaudeUsageCLIRawEnvelope.self, from: data)
        } catch {
            throw ClaudeUsageCLIClientError.malformedResponse
        }

        guard raw.type == "result" else {
            throw ClaudeUsageCLIClientError.unsupportedOutput
        }
        guard raw.subtype == "success", !raw.isError else {
            throw classifyFailure(raw.result)
        }
        guard raw.numTurns == 0,
              raw.totalCostUSD == 0,
              !raw.usage.hasInferenceActivity,
              raw.modelUsage?.values.contains(where: \.hasInferenceActivity) != true
        else {
            throw ClaudeUsageCLIClientError.inferenceActivityDetected
        }
        guard !raw.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeUsageCLIClientError.unsupportedOutput
        }

        return ClaudeUsageCLIEnvelope(
            result: raw.result,
            numTurns: raw.numTurns,
            totalCostUSD: raw.totalCostUSD,
            usage: raw.usage,
            modelUsage: raw.modelUsage ?? [:]
        )
    }

    private static func classifyFailure(_ result: String) -> ClaudeUsageCLIClientError {
        let normalized = result.lowercased()
        if normalized.contains("auth") ||
            normalized.contains("login") ||
            normalized.contains("logged in") ||
            normalized.contains("sign in") ||
            normalized.contains("subscription") {
            return .authenticationUnavailable
        }
        return .unsupportedOutput
    }
}

private final class ClaudeUsageCLIProcessSession: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var shouldTerminate = false

    func install(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = shouldTerminate
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

private final class ClaudeUsageCLIProcessTermination: @unchecked Sendable {
    private let lock = NSLock()
    private var terminationStatus: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    func finish(status: Int32) {
        lock.lock()
        terminationStatus = status
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: status)
    }

    func status() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let terminationStatus {
                lock.unlock()
                continuation.resume(returning: terminationStatus)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}

private final class ClaudeUsageCLIOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private let limitExceeded: @Sendable () -> Void
    private var bufferedData = Data()
    private var handle: FileHandle?
    private var continuation: CheckedContinuation<Data, Error>?
    private var terminalResult: Result<Data, Error>?
    private var didStop = false

    init(limit: Int, limitExceeded: @escaping @Sendable () -> Void) {
        self.limit = limit
        self.limitExceeded = limitExceeded
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

    func data() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let terminalResult {
                lock.unlock()
                continuation.resume(with: terminalResult)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
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
        if terminalResult == nil {
            finishLocked(.failure(CancellationError()))
        }
        lock.unlock()
        handle?.readabilityHandler = nil
    }

    private func appendAvailableData(from handle: FileHandle) {
        let availableData = handle.availableData

        lock.lock()
        guard !didStop, terminalResult == nil else {
            lock.unlock()
            return
        }

        if availableData.isEmpty {
            self.handle = nil
            finishLocked(.success(bufferedData))
            lock.unlock()
            handle.readabilityHandler = nil
            return
        }

        guard bufferedData.count + availableData.count <= limit else {
            self.handle = nil
            bufferedData.removeAll(keepingCapacity: false)
            finishLocked(.failure(ClaudeUsageCLIClientError.responseTooLarge))
            lock.unlock()
            handle.readabilityHandler = nil
            limitExceeded()
            return
        }

        bufferedData.append(availableData)
        lock.unlock()
    }

    private func finishLocked(_ result: Result<Data, Error>) {
        terminalResult = result
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}
