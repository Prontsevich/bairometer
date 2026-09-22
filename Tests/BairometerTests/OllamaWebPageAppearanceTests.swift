import WebKit
import XCTest
@testable import Bairometer

@MainActor
final class OllamaWebPageAppearanceTests: XCTestCase {
    func testAppearancePolicyAllowsOnlyExactOllamaOrigins() {
        XCTAssertTrue(
            OllamaWebPageAppearancePolicy.allowsVisualStyling(
                URL(string: "https://ollama.com/settings")!
            )
        )
        XCTAssertTrue(
            OllamaWebPageAppearancePolicy.allowsVisualStyling(
                URL(string: "https://signin.ollama.com/signin")!
            )
        )

        [
            "http://ollama.com/settings",
            "https://ollama.com:8443/settings",
            "https://account.ollama.com/settings",
            "https://ollama.com.evil.example/settings",
            "https://api.workos.com/user_management/authorize",
            "https://accounts.google.com/o/oauth2/auth",
            "https://github.com/login/oauth/authorize"
        ].forEach { string in
            XCTAssertFalse(
                OllamaWebPageAppearancePolicy.allowsVisualStyling(URL(string: string)!),
                "Unexpected visual styling allowlist entry: \(string)"
            )
        }
    }

    func testAppearanceScriptIsMainFrameVisualOnlyAndAdaptive() {
        let userScript = OllamaWebPageAppearanceScript.userScript()
        let source = OllamaWebPageAppearanceScript.source

        XCTAssertEqual(userScript.injectionTime, .atDocumentStart)
        XCTAssertTrue(userScript.isForMainFrameOnly)
        XCTAssertTrue(OllamaWebPageAppearanceScript.usesDefaultClientWorld)
        XCTAssertTrue(source.contains(OllamaWebPageAppearanceScript.styleElementID))
        XCTAssertTrue(source.contains("https://ollama.com"))
        XCTAssertTrue(source.contains("https://signin.ollama.com"))
        XCTAssertTrue(source.contains("prefers-color-scheme: dark"))
        XCTAssertTrue(source.contains("color-scheme: light"))
        XCTAssertTrue(source.contains(".radix-themes"))
        XCTAssertTrue(source.contains("--branded-page-background: var(--gray-1) !important;"))
        XCTAssertNotNil(
            source.range(
                of: #":root,\s*:root \.radix-themes"#,
                options: .regularExpression
            )
        )

        XCTAssertFalse(source.contains(OllamaWebPageUsageExtractionPolicy.messageHandlerName))
        XCTAssertFalse(source.contains("postMessage"))
        XCTAssertFalse(source.contains("MutationObserver"))
        XCTAssertFalse(source.contains("display:"))
        XCTAssertFalse(source.contains("visibility:"))
        XCTAssertFalse(source.contains("position:"))
        XCTAssertFalse(source.contains("pointer-events:"))
        XCTAssertFalse(source.contains("transform:"))
    }

    func testAppearanceScriptOverridesWorkOSViewportBackground() {
        let userContentController = WKUserContentController()
        userContentController.addUserScript(OllamaWebPageAppearanceScript.userScript())

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let delegate = WebViewLoadDelegate()
        let loadExpectation = expectation(description: "WorkOS fixture loads")
        delegate.didFinish = { loadExpectation.fulfill() }
        webView.navigationDelegate = delegate

        webView.loadHTMLString(
            Self.workOSFixture,
            baseURL: URL(string: "https://signin.ollama.com/")!
        )
        wait(for: [loadExpectation], timeout: 5)

        let styleExpectation = expectation(description: "Appearance style is applied")
        var computedBackground: String?
        var evaluationError: Error?
        webView.evaluateJavaScript(
            "getComputedStyle(document.querySelector('.ak-Background')).backgroundColor"
        ) { result, error in
            computedBackground = result as? String
            evaluationError = error
            styleExpectation.fulfill()
        }
        wait(for: [styleExpectation], timeout: 5)

        XCTAssertNil(evaluationError)
        XCTAssertNotEqual(computedBackground, "rgb(255, 0, 0)")
    }

    func testUsageExtractionRemainsScopedToSettingsAndSeparateFromAppearance() {
        XCTAssertTrue(
            OllamaWebPageUsageExtractionPolicy.allowsExtraction(
                from: URL(string: "https://ollama.com/settings")!
            )
        )
        XCTAssertFalse(
            OllamaWebPageUsageExtractionPolicy.allowsExtraction(
                from: URL(string: "https://signin.ollama.com/signin")!
            )
        )
        XCTAssertFalse(
            OllamaWebPageUsageExtractionPolicy.allowsExtraction(
                from: URL(string: "https://ollama.com/account")!
            )
        )
        XCTAssertFalse(
            OllamaWebPageUsageExtractionPolicy.allowsExtraction(
                from: URL(string: "https://ollama.com:8443/settings")!
            )
        )
    }

    private static let workOSFixture = #"""
    <!doctype html>
    <html>
      <head>
        <style>
          :root { --branded-page-background: rgb(255, 0, 0); }
          :root body { background-color: var(--branded-page-background); }
          .ak-Background {
            min-height: 100vh;
            background-color: var(--branded-page-background);
          }
        </style>
      </head>
      <body>
        <main class="ak-Background"></main>
      </body>
    </html>
    """#
}

@MainActor
private final class WebViewLoadDelegate: NSObject, WKNavigationDelegate {
    var didFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish?()
    }
}
