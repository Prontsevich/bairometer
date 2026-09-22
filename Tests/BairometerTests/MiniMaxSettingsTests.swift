#if DEBUG
import XCTest
@testable import Bairometer
@testable import BairometerCore

@MainActor
final class MiniMaxSettingsTests: XCTestCase {
    func testSettingsDetailSelectsMiniMaxCredentialComponent() {
        let account = miniMaxAccount()
        let presentation = SettingsAccountDetailPresentation(
            account: account,
            providerDisplayName: "MiniMax",
            refreshStatus: .idle,
            refreshIssue: nil,
            diagnosticsAvailability: .noData,
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(presentation.contentKind, .miniMax)
        XCTAssertEqual(presentation.providerSubtitle, "MiniMax")
        XCTAssertNil(presentation.accountExceptionText)
    }

    func testMiniMaxCredentialPresentationNeverContainsStoredMaterial() throws {
        let secretMarker = "private-subscription-key-material"
        let keychain = MiniMaxSettingsKeychainReadTrap()
        let model = AppModel(
            storageDirectory: temporaryDirectory(),
            userDefaults: isolatedDefaults(),
            miniMaxAPIClient: InjectedNoopMiniMaxAPIClient(),
            credentialKeychainService: keychain
        )
        let account = try XCTUnwrap(
            model.addAccount(providerID: "minimax", displayName: "Privacy")
        )
        _ = try model.createMiniMaxSubscriptionKey(
            for: account,
            credentialValue: secretMarker
        )
        XCTAssertEqual(keychain.storedCredentialCount, 1)
        XCTAssertEqual(keychain.readCount, 0)

        model.reloadMiniMaxPresentationData(for: account)
        let credential = try XCTUnwrap(
            model.miniMaxCredentialContexts(for: account).first
        )
        let presentation = MiniMaxCredentialRowPresentation(
            credential: credential,
            diagnostic: model.miniMaxCredentialDiagnostics(for: account).first,
            locale: Locale(identifier: "en")
        )
        let exposedValues = [
            presentation.stateText,
            presentation.primaryActionTitle,
            presentation.accessibilityIdentifier,
            AppStrings.MiniMax.boundaryDescription.localized(
                locale: Locale(identifier: "en")
            ),
            MiniMaxSettingsAccessibilityID.boundary,
            MiniMaxSettingsAccessibilityID.primaryAction,
            MiniMaxSettingsAccessibilityID.enabledAction,
            MiniMaxSettingsAccessibilityID.removeAction
        ]

        XCTAssertEqual(presentation.stateText, "Stored securely · Enabled")
        XCTAssertEqual(
            presentation.accessibilityIdentifier,
            "settings.minimax.subscription-key"
        )
        XCTAssertEqual(keychain.readCount, 0)
        for value in exposedValues {
            XCTAssertFalse(value.contains(secretMarker))
            XCTAssertFalse(value.contains(credential.slot.keychainReference))
            XCTAssertFalse(value.localizedCaseInsensitiveContains("general"))
            XCTAssertFalse(value.localizedCaseInsensitiveContains("video"))
        }
    }

    func testMiniMaxCredentialStatesAndActionsAreDeterministic() {
        let locale = Locale(identifier: "en")
        let missing = MiniMaxCredentialRowPresentation(
            credential: nil,
            diagnostic: nil,
            locale: locale
        )
        XCTAssertEqual(missing.stateText, "Not added")
        XCTAssertEqual(missing.primaryActionTitle, "Add Key")
        XCTAssertFalse(missing.canChangeEnabledState)
        XCTAssertFalse(missing.canRemove)

        let disabled = MiniMaxCredentialRowPresentation(
            credential: miniMaxCredential(isEnabled: false),
            diagnostic: nil,
            locale: locale
        )
        XCTAssertEqual(disabled.stateText, "Stored securely · Disabled")
        XCTAssertEqual(disabled.primaryActionTitle, "Replace Key")
        XCTAssertTrue(disabled.canChangeEnabledState)
        XCTAssertTrue(disabled.canRemove)

        let recovery = MiniMaxCredentialRowPresentation(
            credential: miniMaxCredential(
                lifecycleState: .pendingCreation
            ),
            diagnostic: nil,
            locale: locale
        )
        XCTAssertEqual(recovery.stateText, "Recovery required")
        XCTAssertEqual(recovery.primaryActionTitle, "Recover Key")
        XCTAssertFalse(recovery.canChangeEnabledState)
        XCTAssertTrue(recovery.canRemove)

        let pendingRemoval = MiniMaxCredentialRowPresentation(
            credential: miniMaxCredential(
                lifecycleState: .pendingDeletion
            ),
            diagnostic: nil,
            locale: locale
        )
        XCTAssertEqual(pendingRemoval.stateText, "Secure removal pending")
        XCTAssertFalse(pendingRemoval.canChangeEnabledState)
        XCTAssertTrue(pendingRemoval.canRemove)
    }

    func testMiniMaxEnglishRussianStringsAndAccessibilityIDs() {
        let english = Locale(identifier: "en_US")
        let russian = Locale(identifier: "ru_RU")

        XCTAssertEqual(
            AppStrings.MiniMax.credentialsTitle.localized(locale: english),
            "SUBSCRIPTION KEY"
        )
        XCTAssertEqual(
            AppStrings.MiniMax.credentialsTitle.localized(locale: russian),
            "КЛЮЧ ПОДПИСКИ"
        )
        XCTAssertEqual(
            AppStrings.MiniMax.addKey.localized(locale: english),
            "Add Key"
        )
        XCTAssertEqual(
            AppStrings.MiniMax.addKey.localized(locale: russian),
            "Добавить ключ"
        )
        XCTAssertTrue(
            AppStrings.MiniMax.boundaryDescription
                .localized(locale: english)
                .contains("Global · personal Default Team · locally configured")
        )
        XCTAssertTrue(
            AppStrings.MiniMax.boundaryDescription
                .localized(locale: russian)
                .contains("Global · личная Default Team · настроено локально")
        )

        let englishEditor = MiniMaxCredentialEditorPresentation(
            mode: .replace,
            locale: english
        )
        let russianEditor = MiniMaxCredentialEditorPresentation(
            mode: .replace,
            locale: russian
        )
        XCTAssertEqual(englishEditor.title, "Replace MiniMax Subscription Key")
        XCTAssertEqual(russianEditor.title, "Заменить ключ подписки MiniMax")
        XCTAssertEqual(englishEditor.fieldsetTitle, "KEY DETAILS")
        XCTAssertEqual(russianEditor.fieldsetTitle, "ДАННЫЕ КЛЮЧА")
        XCTAssertEqual(
            MiniMaxSettingsAccessibilityID.editorValue,
            "settings.minimax.credential-value"
        )
        XCTAssertEqual(
            MiniMaxSettingsAccessibilityID.editorSave,
            "settings.minimax.editor-save"
        )
    }

    func testMiniMaxDiagnosticPresentationUsesOnlyFixedLocalCopy() {
        let credential = miniMaxCredential()
        let diagnostic = CredentialContextDiagnostic(
            providerID: credential.slot.providerID,
            accountID: credential.slot.accountID,
            slotID: credential.slot.slotID,
            code: .authentication,
            occurredAt: Date(timeIntervalSince1970: 1_000)
        )
        let presentation = MiniMaxCredentialRowPresentation(
            credential: credential,
            diagnostic: diagnostic,
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(
            presentation.stateText,
            "Stored securely · Authentication failed"
        )
        XCTAssertFalse(presentation.stateText.contains(diagnostic.id))
        XCTAssertFalse(presentation.stateText.contains(credential.slot.keychainReference))
    }

    func testMiniMaxUnavailableSubscriptionDiagnosticIsLocalizedAndDistinctFromAuthentication() {
        let credential = miniMaxCredential()
        let unavailable = CredentialContextDiagnostic(
            providerID: credential.slot.providerID,
            accountID: credential.slot.accountID,
            slotID: credential.slot.slotID,
            code: .insufficientPrivilege,
            occurredAt: Date(timeIntervalSince1970: 1_000)
        )
        let authentication = CredentialContextDiagnostic(
            providerID: credential.slot.providerID,
            accountID: credential.slot.accountID,
            slotID: credential.slot.slotID,
            code: .authentication,
            occurredAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(
            MiniMaxCredentialRowPresentation(
                credential: credential,
                diagnostic: unavailable,
                locale: Locale(identifier: "en_US")
            ).stateText,
            "Stored securely · Subscription unavailable or expired"
        )
        XCTAssertEqual(
            MiniMaxCredentialRowPresentation(
                credential: credential,
                diagnostic: unavailable,
                locale: Locale(identifier: "ru_RU")
            ).stateText,
            "Безопасно сохранён · Подписка недоступна или истекла"
        )
        XCTAssertNotEqual(
            MiniMaxCredentialRowPresentation(
                credential: credential,
                diagnostic: unavailable,
                locale: Locale(identifier: "en_US")
            ).stateText,
            MiniMaxCredentialRowPresentation(
                credential: credential,
                diagnostic: authentication,
                locale: Locale(identifier: "en_US")
            ).stateText
        )
    }

    private func miniMaxAccount() -> ProviderAccount {
        ProviderAccount(
            providerID: MiniMaxProviderContract.providerID,
            accountID: "account-local",
            displayName: "MiniMax Local",
            isEnabled: true,
            sourceMode: .miniMaxTokenPlan
        )
    }

    private func miniMaxCredential(
        keychainReference: String = "reference-local",
        lifecycleState: CredentialLifecycleState = .active,
        isEnabled: Bool = true
    ) -> ProviderCredentialContext {
        let account = miniMaxAccount()
        let rootContextID = "\(account.accountID)-\(AppModel.miniMaxRootContextSuffix)"
        let context = ProviderAccountContextConfiguration(
            providerID: account.providerID,
            accountID: account.accountID,
            contextID: "\(account.accountID)-\(AppModel.miniMaxCredentialContextSuffix)",
            kind: .credential,
            displayName: "Subscription Key",
            regionID: "global",
            parentContextID: rootContextID
        )
        let slot = ProviderCredentialSlot(
            providerID: account.providerID,
            accountID: account.accountID,
            slotID: AppModel.miniMaxSubscriptionSlotID,
            contextID: context.contextID,
            role: .ordinary,
            isEnabled: isEnabled,
            keychainReference: keychainReference,
            lifecycleState: lifecycleState
        )
        return ProviderCredentialContext(context: context, slot: slot)
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "MiniMaxSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private actor InjectedNoopMiniMaxAPIClient: MiniMaxAPIClient {
    func fetchTokenPlanCapacity(
        credential: MiniMaxSubscriptionKey
    ) async throws -> MiniMaxCapacityResult {
        throw MiniMaxAPIClientError.transportFailure
    }
}

private final class MiniMaxSettingsKeychainReadTrap:
    KeychainService,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [String: CredentialSecret] = [:]
    private var reads = 0

    var storedCredentialCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return values.count
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }

    func createCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard values[reference] == nil else {
            throw KeychainServiceError.duplicateReference
        }
        values[reference] = credential
    }

    func readCredential(reference: String) throws -> CredentialSecret {
        lock.lock()
        reads += 1
        lock.unlock()
        throw KeychainServiceError.accessDenied
    }

    func replaceCredential(
        _ credential: CredentialSecret,
        reference: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard values[reference] != nil else {
            throw KeychainServiceError.credentialNotFound
        }
        values[reference] = credential
    }

    func deleteCredential(reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: reference)
    }
}
#endif
