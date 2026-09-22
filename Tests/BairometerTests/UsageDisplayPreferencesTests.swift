import BairometerCore
import Foundation
import XCTest
@testable import Bairometer

final class UsageDisplayPreferencesTests: XCTestCase {
    @MainActor
    func testGlobalDisplayModeDefaultsToUsedAndPersists() throws {
        let directory = try temporaryDirectory()
        let (userDefaults, suiteName) = try testUserDefaults()
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let model = AppModel(storageDirectory: directory, userDefaults: userDefaults)
        XCTAssertEqual(model.usageDisplayMode, .used)

        model.setUsageDisplayMode(.left)
        let reloaded = AppModel(storageDirectory: directory, userDefaults: userDefaults)
        XCTAssertEqual(reloaded.usageDisplayMode, .left)
    }

    @MainActor
    func testOverridesPersistAndQuickToggleStoresOnlyNecessaryState() throws {
        let directory = try temporaryDirectory()
        let (userDefaults, suiteName) = try testUserDefaults()
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let model = AppModel(storageDirectory: directory, userDefaults: userDefaults)
        let account = try XCTUnwrap(model.addAccount(providerID: "mock", displayName: "Work"))
        let windowID = "weekly"

        model.setUsageDisplayMode(.left)
        XCTAssertEqual(model.usageDisplayMode(for: account, windowID: windowID), .left)
        XCTAssertTrue(model.setUsageDisplayOverride(.used, for: account, windowID: windowID))
        XCTAssertEqual(model.usageDisplayOverrideSelection(for: account, windowID: windowID), .used)
        XCTAssertEqual(model.usageDisplayMode(for: account, windowID: windowID), .used)

        let reloaded = AppModel(storageDirectory: directory, userDefaults: userDefaults)
        let reloadedAccount = try XCTUnwrap(reloaded.providerAccounts.first)
        XCTAssertEqual(reloaded.usageDisplayOverrideSelection(for: reloadedAccount, windowID: windowID), .used)

        reloaded.setUsageDisplayMode(.used)
        XCTAssertTrue(reloaded.toggleUsageDisplayMode(for: reloadedAccount, windowID: windowID))
        XCTAssertEqual(reloaded.usageDisplayOverrideSelection(for: reloadedAccount, windowID: windowID), .left)
        XCTAssertTrue(reloaded.toggleUsageDisplayMode(for: reloadedAccount, windowID: windowID))
        XCTAssertEqual(reloaded.usageDisplayOverrideSelection(for: reloadedAccount, windowID: windowID), .global)
        XCTAssertEqual(reloaded.usageDisplayMode(for: reloadedAccount, windowID: windowID), .used)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func testUserDefaults() throws -> (UserDefaults, String) {
        let suiteName = "BairometerTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return (userDefaults, suiteName)
    }
}
