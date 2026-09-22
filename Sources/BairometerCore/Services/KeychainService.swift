import Foundation
import Security

public struct CredentialSecret: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let data: Data

    public init(_ value: String) throws {
        guard !value.isEmpty else {
            throw KeychainServiceError.invalidCredential
        }
        data = Data(value.utf8)
    }

    init(data: Data) throws {
        guard !data.isEmpty, String(data: data, encoding: .utf8) != nil else {
            throw KeychainServiceError.invalidCredential
        }
        self.data = data
    }

    public func withUTF8String<Result>(
        _ body: (String) throws -> Result
    ) throws -> Result {
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainServiceError.invalidCredential
        }
        return try body(value)
    }

    public var description: String { "<redacted credential>" }
    public var debugDescription: String { description }

    fileprivate var keychainData: Data { data }
}

public protocol KeychainService: Sendable {
    func createCredential(_ credential: CredentialSecret, reference: String) throws
    func readCredential(reference: String) throws -> CredentialSecret
    func replaceCredential(_ credential: CredentialSecret, reference: String) throws
    func deleteCredential(reference: String) throws
}

public struct DisabledKeychainService: KeychainService {
    public init() {}

    public func createCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        throw KeychainServiceError.credentialsDisabled
    }

    public func readCredential(reference: String) throws -> CredentialSecret {
        throw KeychainServiceError.credentialsDisabled
    }

    public func replaceCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        throw KeychainServiceError.credentialsDisabled
    }

    public func deleteCredential(reference: String) throws {
        throw KeychainServiceError.credentialsDisabled
    }
}

public struct MacOSKeychainService: KeychainService {
    public static let defaultService = "io.github.Prontsevich.Bairometer.credentials"

    private let service: String
    private let backend: any KeychainBackend

    public init(service: String = Self.defaultService) {
        self.init(service: service, backend: SecurityKeychainBackend())
    }

    init(service: String, backend: any KeychainBackend) {
        self.service = service
        self.backend = backend
    }

    public func createCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        guard !reference.isEmpty else {
            throw KeychainServiceError.invalidReference
        }
        try Self.check(
            backend.create(
                service: service,
                reference: reference,
                credential: credential.keychainData
            ),
            operation: .create
        )
    }

    public func readCredential(reference: String) throws -> CredentialSecret {
        guard !reference.isEmpty else {
            throw KeychainServiceError.invalidReference
        }
        let result = backend.read(service: service, reference: reference)
        try Self.check(result.status, operation: .read)
        guard let credential = result.credential else {
            throw KeychainServiceError.invalidCredential
        }
        return try CredentialSecret(data: credential)
    }

    public func replaceCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        guard !reference.isEmpty else {
            throw KeychainServiceError.invalidReference
        }
        try Self.check(
            backend.replace(
                service: service,
                reference: reference,
                credential: credential.keychainData
            ),
            operation: .replace
        )
    }

    public func deleteCredential(reference: String) throws {
        guard !reference.isEmpty else {
            throw KeychainServiceError.invalidReference
        }
        let status = backend.delete(service: service, reference: reference)
        guard status != errSecItemNotFound else {
            return
        }
        try Self.check(status, operation: .delete)
    }

    private static func check(
        _ status: OSStatus,
        operation: KeychainOperation
    ) throws {
        guard status == errSecSuccess else {
            switch status {
            case errSecItemNotFound:
                throw KeychainServiceError.credentialNotFound
            case errSecDuplicateItem:
                throw KeychainServiceError.duplicateReference
            case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
                throw KeychainServiceError.accessDenied
            case errSecParam, errSecDecode:
                throw KeychainServiceError.invalidCredential
            default:
                throw KeychainServiceError.unexpectedStatus(
                    operation: operation,
                    status: status
                )
            }
        }
    }
}

public enum KeychainOperation: String, Equatable, Sendable {
    case create
    case read
    case replace
    case delete
}

public enum KeychainServiceError: Error, LocalizedError, Equatable, Sendable {
    case credentialsDisabled
    case invalidReference
    case invalidCredential
    case credentialNotFound
    case duplicateReference
    case accessDenied
    case unexpectedStatus(operation: KeychainOperation, status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .credentialsDisabled:
            "Credential storage is unavailable."
        case .invalidReference:
            "The credential reference is invalid."
        case .invalidCredential:
            "The credential value is invalid."
        case .credentialNotFound:
            "The credential is unavailable."
        case .duplicateReference:
            "The credential reference is already in use."
        case .accessDenied:
            "Keychain access was denied."
        case let .unexpectedStatus(operation, status):
            "Keychain \(operation.rawValue) failed with status \(status)."
        }
    }
}

protocol KeychainBackend: Sendable {
    func create(service: String, reference: String, credential: Data) -> OSStatus
    func read(service: String, reference: String) -> (status: OSStatus, credential: Data?)
    func replace(service: String, reference: String, credential: Data) -> OSStatus
    func delete(service: String, reference: String) -> OSStatus
}

struct SecurityKeychainBackend: KeychainBackend {
    static func itemIdentityQuery(
        service: String,
        reference: String
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    static func itemCreationQuery(
        service: String,
        reference: String,
        credential: Data
    ) -> [String: Any] {
        var query = Self.itemIdentityQuery(
            service: service,
            reference: reference
        )
        query[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = credential
        return query
    }

    func create(service: String, reference: String, credential: Data) -> OSStatus {
        return SecItemAdd(
            Self.itemCreationQuery(
                service: service,
                reference: reference,
                credential: credential
            ) as CFDictionary,
            nil
        )
    }

    func read(
        service: String,
        reference: String
    ) -> (status: OSStatus, credential: Data?) {
        var result: CFTypeRef?
        var query = Self.itemIdentityQuery(
            service: service,
            reference: reference
        )
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )
        return (status, result as? Data)
    }

    func replace(
        service: String,
        reference: String,
        credential: Data
    ) -> OSStatus {
        SecItemUpdate(
            Self.itemIdentityQuery(
                service: service,
                reference: reference
            ) as CFDictionary,
            [kSecValueData: credential] as CFDictionary
        )
    }

    func delete(service: String, reference: String) -> OSStatus {
        SecItemDelete(
            Self.itemIdentityQuery(
                service: service,
                reference: reference
            ) as CFDictionary
        )
    }
}
