import XCTest
@testable import Bairometer

final class OllamaWebPageNavigationTests: XCTestCase {
    func testInteractiveNavigationAllowsOllamaAuthenticationRedirects() {
        XCTAssertTrue(
            OllamaWebPageNavigationPolicy.allowsMainFrameNavigation(
                URL(string: "https://api.workos.com/user_management/authorize")!,
                interactive: true
            )
        )
        XCTAssertTrue(
            OllamaWebPageNavigationPolicy.allowsMainFrameNavigation(
                URL(string: "https://signin.ollama.com/")!,
                interactive: true
            )
        )
        XCTAssertTrue(
            OllamaWebPageNavigationPolicy.allowsMainFrameNavigation(
                URL(string: "https://accounts.google.com/o/oauth2/auth")!,
                interactive: true
            )
        )
        XCTAssertTrue(
            OllamaWebPageNavigationPolicy.allowsMainFrameNavigation(
                URL(string: "https://accounts.google.by/signin/v2/challenge/totp")!,
                interactive: true
            )
        )
    }

    func testScheduledNavigationRejectsAuthenticationRedirects() {
        XCTAssertFalse(
            OllamaWebPageNavigationPolicy.allowsMainFrameNavigation(
                URL(string: "https://api.workos.com/user_management/authorize")!,
                interactive: false
            )
        )
        XCTAssertTrue(
            OllamaWebPageNavigationPolicy.allowsMainFrameNavigation(
                URL(string: "https://ollama.com/settings")!,
                interactive: false
            )
        )
    }

    func testNavigationPolicyRejectsUnexpectedHosts() {
        XCTAssertFalse(
            OllamaWebPageNavigationPolicy.allowsMainFrameNavigation(
                URL(string: "https://example.com/")!,
                interactive: true
            )
        )
        XCTAssertFalse(
            OllamaWebPageNavigationPolicy.allowsMainFrameNavigation(
                URL(string: "http://ollama.com/settings")!,
                interactive: true
            )
        )
        XCTAssertFalse(
            OllamaWebPageNavigationPolicy.allowsMainFrameNavigation(
                URL(string: "https://accounts.google.evil.example/signin")!,
                interactive: true
            )
        )
    }

    func testNavigationFailurePolicyIgnoresCancelledRedirects() {
        XCTAssertTrue(
            OllamaWebPageNavigationFailurePolicy.shouldIgnore(
                URLError(.cancelled),
                currentURL: nil,
                hasReachedSettingsPage: false
            )
        )
        XCTAssertFalse(
            OllamaWebPageNavigationFailurePolicy.shouldIgnore(
                URLError(.notConnectedToInternet),
                currentURL: nil,
                hasReachedSettingsPage: false
            )
        )
    }

    func testNavigationFailurePolicyPreservesVisibleSettingsPage() {
        XCTAssertTrue(
            OllamaWebPageNavigationFailurePolicy.shouldIgnore(
                URLError(.cannotFindHost),
                currentURL: URL(string: "https://ollama.com/settings")!,
                hasReachedSettingsPage: true
            )
        )
        XCTAssertFalse(
            OllamaWebPageNavigationFailurePolicy.shouldIgnore(
                URLError(.cannotFindHost),
                currentURL: URL(string: "https://api.workos.com/user_management/authorize")!,
                hasReachedSettingsPage: true
            )
        )
    }
}
