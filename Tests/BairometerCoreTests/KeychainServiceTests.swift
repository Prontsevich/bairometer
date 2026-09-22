import Security
import XCTest
@testable import BairometerCore

final class KeychainServiceTests: XCTestCase {
    func testMacOSServiceCreatesReadsReplacesAndDeletesIndependentItems() throws {
        let backend = FakeKeychainBackend()
        let service = MacOSKeychainService(
            service: "test.credentials",
            backend: backend
        )
        let first = try CredentialSecret("first-private-value")
        let replacement = try CredentialSecret("replacement-private-value")
        let second = try CredentialSecret("second-private-value")

        try service.createCredential(first, reference: "first-reference")
        try service.createCredential(second, reference: "second-reference")

        XCTAssertEqual(
            try value(of: service.readCredential(reference: "first-reference")),
            "first-private-value"
        )
        XCTAssertEqual(
            try value(of: service.readCredential(reference: "second-reference")),
            "second-private-value"
        )

        try service.replaceCredential(
            replacement,
            reference: "first-reference"
        )

        XCTAssertEqual(
            try value(of: service.readCredential(reference: "first-reference")),
            "replacement-private-value"
        )
        XCTAssertEqual(
            try value(of: service.readCredential(reference: "second-reference")),
            "second-private-value"
        )

        try service.deleteCredential(reference: "first-reference")
        XCTAssertThrowsError(
            try service.readCredential(reference: "first-reference")
        ) { error in
            XCTAssertEqual(error as? KeychainServiceError, .credentialNotFound)
        }
        XCTAssertEqual(
            try value(of: service.readCredential(reference: "second-reference")),
            "second-private-value"
        )
    }

    func testDeleteIsIdempotentWhenTheItemIsMissing() throws {
        let service = MacOSKeychainService(
            service: "test.credentials",
            backend: FakeKeychainBackend()
        )

        XCTAssertNoThrow(
            try service.deleteCredential(reference: "missing-reference")
        )
    }

    func testStatusFailuresAreTypedAndDoNotContainCredentialMaterial() throws {
        let backend = FakeKeychainBackend()
        backend.createStatus = errSecInteractionNotAllowed
        let service = MacOSKeychainService(
            service: "test.credentials",
            backend: backend
        )
        let credential = try CredentialSecret("never-include-this-value")

        XCTAssertThrowsError(
            try service.createCredential(
                credential,
                reference: "local-reference"
            )
        ) { error in
            XCTAssertEqual(error as? KeychainServiceError, .accessDenied)
            XCTAssertFalse(
                String(describing: error).contains("never-include-this-value")
            )
            XCTAssertFalse(
                error.localizedDescription.contains("never-include-this-value")
            )
        }

        backend.createStatus = -999_001
        XCTAssertThrowsError(
            try service.createCredential(
                credential,
                reference: "local-reference"
            )
        ) { error in
            XCTAssertEqual(
                error as? KeychainServiceError,
                .unexpectedStatus(operation: .create, status: -999_001)
            )
            XCTAssertFalse(
                error.localizedDescription.contains("never-include-this-value")
            )
        }
    }

    func testCredentialDescriptionAndDebugDescriptionAreAlwaysRedacted() throws {
        let credential = try CredentialSecret("never-render-this-value")

        XCTAssertEqual(String(describing: credential), "<redacted credential>")
        XCTAssertEqual(
            String(reflecting: credential),
            "<redacted credential>"
        )
    }

    func testInvalidReferencesAndMissingItemsUseSanitizedTypedFailures() throws {
        let service = MacOSKeychainService(
            service: "test.credentials",
            backend: FakeKeychainBackend()
        )

        XCTAssertThrowsError(try service.readCredential(reference: "")) {
            XCTAssertEqual($0 as? KeychainServiceError, .invalidReference)
        }
        XCTAssertThrowsError(
            try service.readCredential(reference: "missing-reference")
        ) {
            XCTAssertEqual($0 as? KeychainServiceError, .credentialNotFound)
        }
    }

    func testDataProtectionKeychainIdentityQueryIsConsistent() {
        let query = SecurityKeychainBackend.itemIdentityQuery(
            service: "test.credentials",
            reference: "opaque-reference"
        )

        XCTAssertEqual(query[kSecAttrService as String] as? String, "test.credentials")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "opaque-reference")
        XCTAssertNotNil(query[kSecClass as String])
        XCTAssertNil(query[kSecAttrAccessible as String])
        XCTAssertNil(query[kSecAttrAccessGroup as String])
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(
            query[kSecUseDataProtectionKeychain as String] as? Bool,
            true
        )
    }

    func testDataProtectionKeychainCreationIsDeviceLocalAndNonSynchronizing() {
        let credential = Data("private-value".utf8)
        let query = SecurityKeychainBackend.itemCreationQuery(
            service: "test.credentials",
            reference: "opaque-reference",
            credential: credential
        )

        XCTAssertEqual(query[kSecValueData as String] as? Data, credential)
        XCTAssertEqual(
            query[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(
            query[kSecUseDataProtectionKeychain as String] as? Bool,
            true
        )
    }

    private func value(of credential: CredentialSecret) throws -> String {
        try credential.withUTF8String { $0 }
    }
}

private final class FakeKeychainBackend: KeychainBackend, @unchecked Sendable {
    var createStatus: OSStatus?
    var readStatus: OSStatus?
    var replaceStatus: OSStatus?
    var deleteStatus: OSStatus?

    private var items: [String: Data] = [:]

    func create(
        service: String,
        reference: String,
        credential: Data
    ) -> OSStatus {
        if let createStatus {
            return createStatus
        }
        let key = "\(service):\(reference)"
        guard items[key] == nil else {
            return errSecDuplicateItem
        }
        items[key] = credential
        return errSecSuccess
    }

    func read(
        service: String,
        reference: String
    ) -> (status: OSStatus, credential: Data?) {
        if let readStatus {
            return (readStatus, nil)
        }
        let credential = items["\(service):\(reference)"]
        return (
            credential == nil ? errSecItemNotFound : errSecSuccess,
            credential
        )
    }

    func replace(
        service: String,
        reference: String,
        credential: Data
    ) -> OSStatus {
        if let replaceStatus {
            return replaceStatus
        }
        let key = "\(service):\(reference)"
        guard items[key] != nil else {
            return errSecItemNotFound
        }
        items[key] = credential
        return errSecSuccess
    }

    func delete(service: String, reference: String) -> OSStatus {
        if let deleteStatus {
            return deleteStatus
        }
        let key = "\(service):\(reference)"
        guard items.removeValue(forKey: key) != nil else {
            return errSecItemNotFound
        }
        return errSecSuccess
    }
}
