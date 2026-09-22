import Foundation

public enum ProviderSourceKind: String, Codable, CaseIterable, Sendable {
    case manual
    case localSnapshot = "local-snapshot"
    case live
    case delayed

    public var displayName: String {
        switch self {
        case .manual: "Manual"
        case .localSnapshot: "Local snapshot"
        case .live: "Live"
        case .delayed: "Delayed"
        }
    }
}

public struct ProviderSourceCapability: Codable, Equatable, Sendable {
    public let mode: ProviderSourceMode
    public let kind: ProviderSourceKind
    public let summary: String

    public init(
        mode: ProviderSourceMode,
        kind: ProviderSourceKind,
        summary: String
    ) {
        self.mode = mode
        self.kind = kind
        self.summary = summary
    }
}

public struct ProviderCapabilities: Codable, Equatable, Sendable {
    public let sources: [ProviderSourceCapability]

    public init(sources: [ProviderSourceCapability]) {
        self.sources = sources
    }

    public func capability(for mode: ProviderSourceMode) -> ProviderSourceCapability? {
        sources.first { $0.mode == mode }
    }

    public var supportedSourceModes: [ProviderSourceMode] {
        sources.map(\.mode)
    }

    public static let manualOnly = ProviderCapabilities(sources: [
        ProviderSourceCapability(
            mode: .manual,
            kind: .manual,
            summary: "Usage is entered or checked manually."
        )
    ])
}
