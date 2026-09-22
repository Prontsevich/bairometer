import Foundation

public enum ProviderCredentialRole: String, Codable, CaseIterable, Sendable {
    case ordinary
    case management
}

public enum CredentialLifecycleState: String, Codable, CaseIterable, Sendable {
    case active
    case pendingCreation = "pending-creation"
    case pendingDeletion = "pending-deletion"
}

public struct ProviderAccountContextConfiguration: Codable, Identifiable, Equatable, Sendable {
    public var id: String {
        "\(providerID):\(accountID):\(contextID)"
    }

    public let providerID: String
    public let accountID: String
    public let contextID: String
    public var kind: AccountContextKind
    public var displayName: String?
    public var regionID: String
    public var parentContextID: String?

    public init(
        providerID: String,
        accountID: String,
        contextID: String,
        kind: AccountContextKind,
        displayName: String? = nil,
        regionID: String,
        parentContextID: String? = nil
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.contextID = contextID
        self.kind = kind
        self.displayName = displayName
        self.regionID = regionID
        self.parentContextID = parentContextID
    }

    public var contractContext: AccountContext {
        AccountContext(
            contextID: contextID,
            kind: kind,
            displayName: displayName,
            regionID: regionID,
            parentContextID: parentContextID
        )
    }
}

public struct ProviderCredentialSlot: Codable, Identifiable, Equatable, Sendable {
    public var id: String {
        "\(providerID):\(accountID):\(slotID)"
    }

    public let providerID: String
    public let accountID: String
    public let slotID: String
    public let contextID: String
    public let role: ProviderCredentialRole
    public var isEnabled: Bool
    public let keychainReference: String
    public var lifecycleState: CredentialLifecycleState
    public let credentialRevision: Int

    public init(
        providerID: String,
        accountID: String,
        slotID: String,
        contextID: String,
        role: ProviderCredentialRole,
        isEnabled: Bool,
        keychainReference: String,
        lifecycleState: CredentialLifecycleState = .active,
        credentialRevision: Int = 1
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.slotID = slotID
        self.contextID = contextID
        self.role = role
        self.isEnabled = isEnabled
        self.keychainReference = keychainReference
        self.lifecycleState = lifecycleState
        self.credentialRevision = max(1, credentialRevision)
    }
}

public struct ProviderCredentialContext: Identifiable, Equatable, Sendable {
    public var id: String { slot.id }

    public let context: ProviderAccountContextConfiguration
    public let slot: ProviderCredentialSlot

    public init(
        context: ProviderAccountContextConfiguration,
        slot: ProviderCredentialSlot
    ) {
        self.context = context
        self.slot = slot
    }
}

public struct CredentialContextRefreshState: Equatable, Sendable {
    public let providerID: String
    public let accountID: String
    public let slotID: String
    public let lastAttemptAt: Date?
    public let lastSuccessfulRefreshAt: Date?
    public let lastFailedRefreshAt: Date?
    public let lastCompletedAt: Date?
    public let retryNotBefore: Date?
    public let consecutiveFailureCount: Int

    public init(
        providerID: String,
        accountID: String,
        slotID: String,
        lastAttemptAt: Date?,
        lastSuccessfulRefreshAt: Date?,
        lastFailedRefreshAt: Date?,
        lastCompletedAt: Date? = nil,
        retryNotBefore: Date? = nil,
        consecutiveFailureCount: Int = 0
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.slotID = slotID
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.lastFailedRefreshAt = lastFailedRefreshAt
        self.lastCompletedAt = lastCompletedAt
        self.retryNotBefore = retryNotBefore
        self.consecutiveFailureCount = max(0, consecutiveFailureCount)
    }
}

public enum CredentialContextDiagnosticCode: String, Codable, CaseIterable, Sendable {
    case authentication
    case insufficientPrivilege = "insufficient-privilege"
    case throttled
    case transientFailure = "transient-failure"
    case credentialDisabled = "credential-disabled"
    case credentialMissing = "credential-missing"

    public var message: String {
        switch self {
        case .authentication:
            "Credential authentication failed."
        case .insufficientPrivilege:
            "Credential privileges are insufficient."
        case .throttled:
            "Credential refresh was throttled."
        case .transientFailure:
            "Credential refresh failed temporarily."
        case .credentialDisabled:
            "Credential is disabled."
        case .credentialMissing:
            "Credential is unavailable."
        }
    }
}

public struct CredentialContextDiagnostic: Identifiable, Equatable, Sendable {
    public let providerID: String
    public let accountID: String
    public let slotID: String
    public let code: CredentialContextDiagnosticCode
    public let occurredAt: Date

    public var id: String {
        "\(providerID):\(accountID):\(slotID):\(code.rawValue):\(occurredAt.timeIntervalSince1970)"
    }

    public var message: String { code.message }

    public init(
        providerID: String,
        accountID: String,
        slotID: String,
        code: CredentialContextDiagnosticCode,
        occurredAt: Date
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.slotID = slotID
        self.code = code
        self.occurredAt = occurredAt
    }
}

public enum CredentialStoreError: Error, LocalizedError, Equatable, Sendable {
    case accountNotFound
    case contextNotFound
    case slotNotFound
    case invalidContextTree
    case invalidCredentialRole
    case managementCredentialAlreadyExists
    case contextAlreadyHasCredential
    case credentialDisabled
    case credentialPendingCreation
    case credentialPendingDeletion
    case credentialMissing
    case keychain(KeychainServiceError)
    case storageUnavailable

    public var errorDescription: String? {
        switch self {
        case .accountNotFound:
            "The credential account is unavailable."
        case .contextNotFound:
            "The credential context is unavailable."
        case .slotNotFound:
            "The credential slot is unavailable."
        case .invalidContextTree:
            "The account context configuration is invalid."
        case .invalidCredentialRole:
            "The credential role does not match its account context."
        case .managementCredentialAlreadyExists:
            "The account already has a management credential."
        case .contextAlreadyHasCredential:
            "The account context already has a credential."
        case .credentialDisabled:
            "The credential is disabled."
        case .credentialPendingCreation:
            "The credential is not ready."
        case .credentialPendingDeletion:
            "The credential is pending secure deletion."
        case .credentialMissing:
            "The credential is unavailable."
        case let .keychain(error):
            error.errorDescription
        case .storageUnavailable:
            "Credential metadata storage is unavailable."
        }
    }
}
