import Foundation

public struct UsageSnapshotDocument: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 2

    public let formatVersion: Int
    public let snapshots: [UsageSnapshot]

    public init(formatVersion: Int = UsageSnapshotDocument.currentFormatVersion, snapshots: [UsageSnapshot]) {
        self.formatVersion = formatVersion
        self.snapshots = snapshots
    }
}
