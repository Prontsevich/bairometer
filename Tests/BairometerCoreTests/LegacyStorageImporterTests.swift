import Foundation
import XCTest
@testable import BairometerCore

final class LegacyStorageImporterTests: XCTestCase {
    func testLegacyImportRetainsDataResolvesNamesAndIsIdempotent() throws {
        let directory = try temporaryDirectory()
        let customSnapshotURL = directory.appendingPathComponent("custom-statusline.json")
        let accounts = [
            ProviderAccount(providerID: "mock", accountID: "one", displayName: "Work", isEnabled: true),
            ProviderAccount(
                providerID: "claude-code",
                accountID: "two",
                displayName: " work ",
                isEnabled: true,
                sourceMode: .claudeStatusLine,
                localSnapshotPath: customSnapshotURL.path
            )
        ]
        try JSONEncoder().encode(accounts).write(to: directory.appendingPathComponent("providers.json"))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(UsageSnapshotDocument(snapshots: [
            UsageSnapshot(
                providerID: "mock",
                accountID: "one",
                accountDisplayName: "Work",
                displayName: "Mock",
                status: .ok,
                usedPercent: 12,
                lastUpdatedAt: Date(timeIntervalSince1970: 10),
                confidence: .live,
                source: "Legacy"
            )
        ])).write(to: directory.appendingPathComponent("snapshots.json"))
        try JSONEncoder().encode(RefreshSettings(interval: .thirtyMinutes))
            .write(to: directory.appendingPathComponent("refresh-settings.json"))
        try encoder.encode(ClaudeCodeLocalSnapshot(
            schemaVersion: 1,
            periodLabel: "Claude Code rate limits",
            usedPercent: 64,
            lastUpdatedAt: Date(timeIntervalSince1970: 20)
        )).write(to: customSnapshotURL)

        let database = try AppDatabase(directory: directory)
        let importer = LegacyStorageImporter(
            directory: directory,
            database: database,
            knownProviderIDs: ["mock", "claude-code"]
        )
        try importer.runIfNeeded()

        let accountStore = DatabaseProviderConfigurationStore(database: database)
        XCTAssertEqual(
            accountStore.load(knownProviderIDs: ["mock", "claude-code"]).accounts.map(\.displayName),
            ["Work", "work (2)"]
        )
        XCTAssertEqual(
            DatabaseRefreshSettingsStore(database: database)
                .load(defaults: RefreshSettings()).settings.interval,
            .thirtyMinutes
        )
        XCTAssertEqual(DatabaseSnapshotStore(database: database).load().snapshots.map(\.id).sorted(), [
            "claude-code:two", "mock:one"
        ])
        XCTAssertTrue(DatabaseSourceDiagnosticStore(database: database).load().contains {
            $0.code == "legacy-custom-statusline"
        })
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("providers.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: customSnapshotURL.path))

        try importer.runIfNeeded()
        XCTAssertEqual(DatabaseSnapshotStore(database: database).load().snapshots.count, 2)
    }

    func testMalformedLegacySnapshotDoesNotReplaceExistingDatabaseState() throws {
        let directory = try temporaryDirectory()
        let database = try AppDatabase(directory: directory)
        let account = ProviderAccount(providerID: "mock", accountID: "one", displayName: "Work", isEnabled: true)
        try DatabaseProviderConfigurationStore(database: database).save([account])
        let original = UsageSnapshot(
            providerID: "mock",
            accountID: "one",
            accountDisplayName: "Work",
            displayName: "Mock",
            status: .ok,
            usedPercent: 48,
            lastUpdatedAt: Date(timeIntervalSince1970: 10),
            confidence: .live,
            source: "Existing"
        )
        try DatabaseSnapshotStore(database: database).save([original])
        try Data("{invalid".utf8).write(to: directory.appendingPathComponent("snapshots.json"))

        try LegacyStorageImporter(
            directory: directory,
            database: database,
            knownProviderIDs: ["mock"]
        ).runIfNeeded()

        XCTAssertEqual(
            try DatabaseSnapshotStore(database: database).snapshot(providerID: "mock", accountID: "one"),
            original
        )
        XCTAssertTrue(DatabaseSourceDiagnosticStore(database: database).load().contains {
            $0.code == "legacy-snapshots-unavailable"
        })
    }

    func testFailedImportRollsBackAndCanBeRetried() throws {
        let directory = try temporaryDirectory()
        try JSONEncoder().encode([
            ProviderAccount(providerID: "mock", accountID: "one", displayName: "Work", isEnabled: true)
        ]).write(to: directory.appendingPathComponent("providers.json"))
        let database = try AppDatabase(directory: directory)

        XCTAssertThrowsError(
            try LegacyStorageImporter(
                directory: directory,
                database: database,
                knownProviderIDs: ["mock"],
                beforeCommit: { throw ForcedImportError.failure }
            ).runIfNeeded()
        )
        XCTAssertTrue(DatabaseProviderConfigurationStore(database: database).load(knownProviderIDs: ["mock"]).accounts.isEmpty)

        try LegacyStorageImporter(
            directory: directory,
            database: database,
            knownProviderIDs: ["mock"]
        ).runIfNeeded()
        XCTAssertEqual(DatabaseProviderConfigurationStore(database: database).load(knownProviderIDs: ["mock"]).accounts.count, 1)
    }

    func testConcurrentAppAndHelperWritesPreserveNewestSnapshot() throws {
        let directory = try temporaryDirectory()
        let database = try AppDatabase(directory: directory)
        let account = ProviderAccount(
            providerID: "claude-code",
            accountID: "work",
            displayName: "Work",
            isEnabled: true,
            sourceMode: .claudeStatusLine
        )
        try DatabaseProviderConfigurationStore(database: database).save([account])
        let snapshotStore = DatabaseSnapshotStore(database: database)
        let errors = LockedErrors()

        DispatchQueue.concurrentPerform(iterations: 8) { index in
            do {
                if index.isMultiple(of: 2) {
                    _ = try ClaudeCodeStatusLineDatabaseWriter(directory: directory).writeSnapshot(
                        from: Data("{\"rate_limits\":{\"five_hour\":{\"used_percentage\":\(index)}}}".utf8),
                        accountID: account.accountID,
                        now: Date(timeIntervalSince1970: TimeInterval(index))
                    )
                } else {
                    try snapshotStore.save([
                        UsageSnapshot(
                            providerID: account.providerID,
                            accountID: account.accountID,
                            accountDisplayName: account.displayName,
                            displayName: "Claude Code",
                            status: .ok,
                            usedPercent: Double(index),
                            lastUpdatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                            confidence: .localEstimate,
                            source: "App refresh"
                        )
                    ])
                }
            } catch {
                errors.append(error)
            }
        }

        XCTAssertTrue(errors.values.isEmpty, "Unexpected database write errors: \(errors.values)")
        XCTAssertEqual(
            try DatabaseSnapshotStore(database: database).snapshot(providerID: account.providerID, accountID: account.accountID)?.lastUpdatedAt,
            Date(timeIntervalSince1970: 7)
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum ForcedImportError: Error, Sendable {
    case failure
}

private final class LockedErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Error] = []

    var values: [Error] {
        lock.withLock { storage }
    }

    func append(_ error: Error) {
        lock.withLock { storage.append(error) }
    }
}
