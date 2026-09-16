import AILimitBarCore
import Foundation
import WebKit

@MainActor
final class OllamaWebPageClientController: NSObject, OllamaWebPageClient, @unchecked Sendable {
    static let settingsURL = URL(string: "https://ollama.com/settings")!
    private var sessions: [String: OllamaWebPageSession] = [:]

    func fetchUsage(account: ProviderAccount) async throws -> OllamaUsagePagePayload {
        guard account.webDataStoreID != nil else {
            throw ProviderAdapterError(
                providerID: "ollama-cloud",
                message: "Ollama session is not connected.",
                recoverySuggestion: "Choose Connect Ollama and sign in through Bairometer."
            )
        }
        return try await session(for: account).loadUsage(interactive: false)
    }

    func connect(account: ProviderAccount) async throws -> OllamaUsagePagePayload {
        guard account.webDataStoreID != nil else {
            throw ProviderAdapterError(
                providerID: "ollama-cloud",
                message: "Ollama session could not be created.",
                recoverySuggestion: "Save the Ollama account before starting the connection flow."
            )
        }
        return try await session(for: account).loadUsage(interactive: true)
    }

    func webView(for account: ProviderAccount) -> WKWebView? {
        guard account.webDataStoreID != nil else { return nil }
        return try? session(for: account).webView
    }

    func forgetSession(for account: ProviderAccount) {
        sessions.removeValue(forKey: account.id)
        guard let identifier = account.webDataStoreID else { return }
        WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in }
    }

    private func session(for account: ProviderAccount) throws -> OllamaWebPageSession {
        guard let dataStoreID = account.webDataStoreID else {
            throw ProviderAdapterError(
                providerID: "ollama-cloud",
                message: "Ollama session is not connected.",
                recoverySuggestion: "Choose Connect Ollama and sign in through Bairometer."
            )
        }

        if let existing = sessions[account.id], existing.dataStoreID == dataStoreID {
            return existing
        }

        let created = OllamaWebPageSession(dataStoreID: dataStoreID)
        sessions[account.id] = created
        return created
    }
}

@MainActor
private final class OllamaWebPageSession: NSObject, WKNavigationDelegate {
    let dataStoreID: UUID
    let webView: WKWebView

    private let messageHandler: WeakScriptMessageHandler
    private var continuation: CheckedContinuation<OllamaUsagePagePayload, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private var isInteractive = false
    private var hasReachedSettingsPage = false

    init(dataStoreID: UUID) {
        self.dataStoreID = dataStoreID

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)
        let userContentController = WKUserContentController()
        userContentController.addUserScript(OllamaWebPageAppearanceScript.userScript())
        userContentController.addUserScript(
            WKUserScript(
                source: Self.usageUserScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        self.messageHandler = WeakScriptMessageHandler()
        configuration.userContentController = userContentController

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        messageHandler.owner = self
        userContentController.add(messageHandler, name: OllamaWebPageUsageExtractionPolicy.messageHandlerName)
        webView.navigationDelegate = self
    }

    func loadUsage(interactive: Bool) async throws -> OllamaUsagePagePayload {
        guard continuation == nil else {
            throw ProviderAdapterError(
                providerID: "ollama-cloud",
                message: "Ollama connection is already loading.",
                recoverySuggestion: "Finish or cancel the current Ollama connection before refreshing again."
            )
        }

        isInteractive = interactive
        hasReachedSettingsPage = false
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if !interactive {
                    timeoutTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 20_000_000_000)
                        guard !Task.isCancelled else { return }
                        self?.finish(
                            failure: ProviderAdapterError(
                                providerID: "ollama-cloud",
                                message: "Ollama settings page timed out.",
                                recoverySuggestion: "Reconnect Ollama and try again.",
                                isTransient: true
                            )
                        )
                    }
                } else {
                    // Interactive sign-in remains available until OAuth finishes
                    // or the user explicitly cancels the connection sheet.
                    timeoutTask = nil
                }
                webView.load(URLRequest(url: OllamaWebPageClientController.settingsURL))
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(failure: CancellationError())
            }
        })
    }

    func handleScriptMessage(_ message: WKScriptMessage) {
        guard message.name == OllamaWebPageUsageExtractionPolicy.messageHandlerName,
              let body = message.body as? String,
              let data = body.data(using: .utf8)
        else {
            finish(
                failure: ProviderAdapterError(
                    providerID: "ollama-cloud",
                    message: "Ollama settings page returned an unsupported usage payload.",
                    recoverySuggestion: "Reconnect Ollama and check whether its settings page structure has changed."
                )
            )
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            finish(success: try decoder.decode(OllamaUsagePagePayload.self, from: data))
        } catch {
            finish(
                failure: ProviderAdapterError(
                    providerID: "ollama-cloud",
                    message: "Ollama settings page returned malformed usage data.",
                    recoverySuggestion: "Reconnect Ollama and check whether its settings page structure has changed."
                )
            )
        }
    }

    private func finish(success payload: OllamaUsagePagePayload) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: payload)
    }

    private func finish(failure error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.stopLoading()
        continuation.resume(throwing: error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame == true else {
            decisionHandler(.allow)
            return
        }

        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let isAllowed = OllamaWebPageNavigationPolicy.allowsMainFrameNavigation(
            url,
            interactive: isInteractive
        )
        guard isAllowed else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard continuation != nil else { return }
        guard let url = webView.url else {
            finish(
                failure: ProviderAdapterError(
                    providerID: "ollama-cloud",
                    message: "Ollama session is missing or expired.",
                    recoverySuggestion: "Reconnect Ollama through Bairometer."
                )
            )
            return
        }

        guard OllamaWebPageNavigationPolicy.isSettingsURL(url) else {
            guard !isInteractive else { return }
            finish(
                failure: ProviderAdapterError(
                    providerID: "ollama-cloud",
                    message: "Ollama session is missing or expired.",
                    recoverySuggestion: "Reconnect Ollama through Bairometer."
                )
            )
            return
        }

        hasReachedSettingsPage = true
        extractUsageFromSettingsPage()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !OllamaWebPageNavigationFailurePolicy.shouldIgnore(
            error,
            currentURL: webView.url,
            hasReachedSettingsPage: hasReachedSettingsPage
        ) else {
            extractUsageFromSettingsPage()
            return
        }
        finish(
            failure: ProviderAdapterError(
                providerID: "ollama-cloud",
                message: "Ollama settings page failed to load.",
                recoverySuggestion: "Check the network connection and reconnect Ollama.",
                isTransient: true
            )
        )
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    private func extractUsageFromSettingsPage() {
        guard continuation != nil,
              let url = webView.url,
              OllamaWebPageUsageExtractionPolicy.allowsExtraction(from: url)
        else { return }

        webView.evaluateJavaScript(Self.usageUserScript) { [weak self] _, error in
            guard let self, error != nil, self.continuation != nil else { return }
            self.finish(
                failure: ProviderAdapterError(
                    providerID: "ollama-cloud",
                    message: "Ollama settings page could not be inspected.",
                    recoverySuggestion: "Reconnect Ollama and try again.",
                    isTransient: true
                )
            )
        }
    }

    private static let usageUserScript = #"""
    (() => {
      if (window.location.origin !== "\#(OllamaWebPageUsageExtractionPolicy.settingsOrigin)" || window.location.pathname !== "\#(OllamaWebPageUsageExtractionPolicy.settingsPath)") {
        return;
      }

      const usageLabels = ["Session usage", "Weekly usage"];
      const percentPattern = /(\d+(?:\.\d+)?)\s*%/g;
      const textForLabel = (text, label, otherLabels) => {
        const labelIndex = text.indexOf(label);
        if (labelIndex < 0) return text;

        const nextLabelIndexes = otherLabels
          .map((otherLabel) => text.indexOf(otherLabel, labelIndex + label.length))
          .filter((index) => index >= 0);
        const nextLabelIndex = nextLabelIndexes.length > 0 ? Math.min(...nextLabelIndexes) : text.length;
        return text.slice(labelIndex, nextLabelIndex);
      };

      const parseResetAt = (text) => {
        const normalized = text.replace(/\s+/g, " ").trim();
        const relativeMatch = normalized.match(/(?:in|after)\s+(\d+(?:\.\d+)?)\s+(second|minute|hour|day|week)s?/i);
        if (relativeMatch) {
          const amount = Number(relativeMatch[1]);
          const unitMilliseconds = {
            second: 1_000,
            minute: 60_000,
            hour: 3_600_000,
            day: 86_400_000,
            week: 604_800_000
          }[relativeMatch[2].toLowerCase()];
          if (unitMilliseconds) return new Date(Date.now() + amount * unitMilliseconds).toISOString();
        }

        const resetMatch = normalized.match(/(?:reset|resets|renew|renews)\s*(?:on|at)?\s*:?\s*(.+)/i);
        if (resetMatch) {
          const timestamp = Date.parse(resetMatch[1]);
          if (!Number.isNaN(timestamp)) return new Date(timestamp).toISOString();
        }
        return null;
      };

      const sectionFor = (label) => {
        const anchor = Array.from(document.querySelectorAll("body *"))
          .find((element) => element.children.length === 0 && element.textContent?.trim() === label);
        if (!anchor) return null;

        const otherLabels = usageLabels.filter((candidate) => candidate !== label);
        let section = null;
        let candidate = anchor.parentElement;
        while (candidate && candidate !== document.body) {
          const candidateText = candidate.innerText || "";
          const candidatePercentages = candidateText.match(percentPattern) || [];
          const containsOtherUsageLabel = otherLabels.some((otherLabel) => candidateText.includes(otherLabel));
          if (candidateText.includes(label) && !containsOtherUsageLabel && candidatePercentages.length > 0) {
            section = candidate;
            break;
          }
          candidate = candidate.parentElement;
        }

        section = section || anchor.closest("section") || anchor.parentElement?.parentElement || anchor.parentElement;
        const text = section?.innerText || "";
        const sharedSection = anchor.closest("section");
        const sharedText = sharedSection?.innerText || "";
        const scopedText = textForLabel(text, label, otherLabels);
        const hasOtherUsageLabel = otherLabels.some((otherLabel) => text.includes(otherLabel));
        const percentMatch = scopedText.match(/(\d+(?:\.\d+)?)\s*%/) ||
          (!hasOtherUsageLabel ? text.match(/(\d+(?:\.\d+)?)\s*%/) : null);

        let resetSection = section;
        let parent = section?.parentElement;
        while (parent && parent !== document.body) {
          const parentText = parent.innerText || "";
          if (otherLabels.some((otherLabel) => parentText.includes(otherLabel))) break;
          if (parent.querySelector("time[datetime]") || /(?:reset|resets|renew|renews)/i.test(parentText)) {
            resetSection = parent;
            break;
          }
          parent = parent.parentElement;
        }

        let resetAt = null;
        const resetText = resetSection?.innerText || text;
        const resetScopedText = textForLabel(resetText, label, otherLabels);
        const timeElement = hasOtherUsageLabel ? null : resetSection?.querySelector("time[datetime]");
        const timeValue = timeElement?.getAttribute("datetime");
        if (timeValue && !Number.isNaN(Date.parse(timeValue))) {
          resetAt = new Date(timeValue).toISOString();
        }

        if (!resetAt && sharedSection && sharedSection !== resetSection) {
          const sharedTimeElements = Array.from(sharedSection.querySelectorAll("time[datetime]"));
          const usageIndex = usageLabels.indexOf(label);
          if (sharedTimeElements.length === usageLabels.length && usageIndex >= 0) {
            const sharedTimeValue = sharedTimeElements[usageIndex].getAttribute("datetime");
            if (sharedTimeValue && !Number.isNaN(Date.parse(sharedTimeValue))) {
              resetAt = new Date(sharedTimeValue).toISOString();
            }
          }
        }

        if (!resetAt) {
          resetAt = parseResetAt(resetScopedText);
        }
        if (!resetAt && sharedSection && sharedSection !== resetSection) {
          resetAt = parseResetAt(textForLabel(sharedText, label, otherLabels));
        }

        return {
          usedPercent: percentMatch ? Number(percentMatch[1]) : null,
          resetAt
        };
      };

      let delivered = false;
      const publishUsage = () => {
        if (delivered) return true;
        const session = sectionFor("Session usage");
        const weekly = sectionFor("Weekly usage");
        if (!session && !weekly) return false;

        delivered = true;
        window.webkit.messageHandlers.\#(OllamaWebPageUsageExtractionPolicy.messageHandlerName).postMessage(JSON.stringify({ session, weekly }));
        return true;
      };

      if (!publishUsage()) {
        const observer = new MutationObserver(() => {
          if (publishUsage()) observer.disconnect();
        });
        observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
        setTimeout(() => observer.disconnect(), 10_000);
      }
    })();
    """#
}

enum OllamaWebPageAppearancePolicy {
    static let allowedOrigins: Set<String> = [
        "https://ollama.com",
        "https://signin.ollama.com"
    ]

    static func allowsVisualStyling(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              url.port == nil || url.port == 443
        else { return false }

        return allowedOrigins.contains("https://\(host)")
    }
}

enum OllamaWebPageAppearanceScript {
    static let styleElementID = "ai-limitbar-ollama-appearance"
    static let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    static let isForMainFrameOnly = true
    static let usesDefaultClientWorld = true

    static let source = #"""
    (() => {
      const allowedOrigins = new Set(["https://ollama.com", "https://signin.ollama.com"]);
      if (!allowedOrigins.has(window.location.origin)) return;

      const styleID = "ai-limitbar-ollama-appearance";
      if (document.getElementById(styleID)) return;

      const style = document.createElement("style");
      style.id = styleID;
      style.textContent = `
        :root,
        :root .radix-themes {
          color-scheme: light !important;
          --gray-1: #ffffff !important;
          --gray-2: #f9f9fb !important;
          --gray-3: #f0f0f3 !important;
          --gray-4: #e8e8ec !important;
          --gray-5: #e0e1e6 !important;
          --gray-6: #d9d9df !important;
          --gray-7: #cdced6 !important;
          --gray-8: #b9bbc6 !important;
          --gray-9: #8b8d98 !important;
          --gray-10: #7e808a !important;
          --gray-11: #60646c !important;
          --gray-12: #1c2024 !important;
          --gray-a1: rgb(0 0 0 / 0.012) !important;
          --gray-a2: rgb(0 0 0 / 0.027) !important;
          --gray-a3: rgb(0 0 0 / 0.047) !important;
          --gray-a4: rgb(0 0 0 / 0.071) !important;
          --gray-a5: rgb(0 0 0 / 0.090) !important;
          --gray-a6: rgb(0 0 0 / 0.114) !important;
          --gray-a7: rgb(0 0 0 / 0.153) !important;
          --gray-a8: rgb(0 0 0 / 0.255) !important;
          --gray-a9: rgb(0 0 0 / 0.447) !important;
          --gray-a10: rgb(0 0 0 / 0.506) !important;
          --gray-a11: rgb(0 0 0 / 0.624) !important;
          --gray-a12: rgb(0 0 0 / 0.890) !important;
          --color-background: var(--gray-1) !important;
          --color-panel: var(--gray-1) !important;
          --color-surface: var(--gray-2) !important;
          --color-overlay: var(--gray-2) !important;
          --branded-page-background: var(--gray-1) !important;
        }

        :root,
        :root body,
        :root .radix-themes {
          background-color: var(--color-background) !important;
          color: var(--gray-12) !important;
        }

        :root .radix-themes .rt-BaseCard,
        :root .radix-themes .rt-TextFieldRoot,
        :root .radix-themes .rt-BaseButton.rt-variant-surface {
          background-color: var(--color-surface) !important;
          color: var(--gray-12) !important;
        }

        @media (prefers-color-scheme: dark) {
          :root,
          :root .radix-themes {
            color-scheme: dark !important;
            --gray-1: #111113 !important;
            --gray-2: #19191b !important;
            --gray-3: #222225 !important;
            --gray-4: #2a2a2e !important;
            --gray-5: #313136 !important;
            --gray-6: #3a3a40 !important;
            --gray-7: #4a4a52 !important;
            --gray-8: #5c5c66 !important;
            --gray-9: #6e6e78 !important;
            --gray-10: #7c7c86 !important;
            --gray-11: #b5b5bd !important;
            --gray-12: #eeeef0 !important;
            --gray-a1: rgb(255 255 255 / 0.030) !important;
            --gray-a2: rgb(255 255 255 / 0.060) !important;
            --gray-a3: rgb(255 255 255 / 0.090) !important;
            --gray-a4: rgb(255 255 255 / 0.120) !important;
            --gray-a5: rgb(255 255 255 / 0.150) !important;
            --gray-a6: rgb(255 255 255 / 0.190) !important;
            --gray-a7: rgb(255 255 255 / 0.250) !important;
            --gray-a8: rgb(255 255 255 / 0.330) !important;
            --gray-a9: rgb(255 255 255 / 0.440) !important;
            --gray-a10: rgb(255 255 255 / 0.520) !important;
            --gray-a11: rgb(255 255 255 / 0.740) !important;
            --gray-a12: rgb(255 255 255 / 0.930) !important;
            --color-background: var(--gray-1) !important;
            --color-panel: var(--gray-1) !important;
            --color-surface: var(--gray-2) !important;
            --color-overlay: var(--gray-2) !important;
            --branded-page-background: var(--gray-1) !important;
          }
        }
      `;
      (document.head || document.documentElement).appendChild(style);
    })();
    """#

    @MainActor
    static func userScript() -> WKUserScript {
        WKUserScript(
            source: source,
            injectionTime: injectionTime,
            forMainFrameOnly: isForMainFrameOnly,
            in: .defaultClient
        )
    }
}

enum OllamaWebPageUsageExtractionPolicy {
    static let settingsOrigin = "https://ollama.com"
    static let settingsPath = "/settings"
    static let messageHandlerName = "ollamaUsage"

    static func allowsExtraction(from url: URL) -> Bool {
        url.scheme == "https" &&
            url.host?.lowercased() == "ollama.com" &&
            (url.port == nil || url.port == 443) &&
            url.path == settingsPath
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: OllamaWebPageSession?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.handleScriptMessage(message)
    }
}

enum OllamaWebPageNavigationPolicy {
    static func allowsMainFrameNavigation(_ url: URL, interactive: Bool) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }

        if host == "ollama.com" || host.hasSuffix(".ollama.com") {
            return true
        }

        guard interactive else { return false }
        return host == "api.workos.com" ||
            host == "accounts.google.com" ||
            allowsRegionalGoogleAccountHost(host) ||
            host == "google.com" ||
            host.hasSuffix(".google.com") ||
            host == "github.com" ||
            host.hasSuffix(".github.com")
    }

    private static func allowsRegionalGoogleAccountHost(_ host: String) -> Bool {
        let prefix = "accounts.google."
        guard host.hasPrefix(prefix) else { return false }

        let suffixLabels = host
            .dropFirst(prefix.count)
            .split(separator: ".")
        if suffixLabels == ["com"] {
            return true
        }
        if suffixLabels.count == 1, suffixLabels[0].count == 2 {
            return true
        }
        return suffixLabels.count == 2 &&
            (suffixLabels[0] == "co" || suffixLabels[0] == "com") &&
            suffixLabels[1].count == 2
    }

    static func isSettingsURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "ollama.com" && url.path == "/settings"
    }
}

enum OllamaWebPageNavigationFailurePolicy {
    static func shouldIgnore(
        _ error: Error,
        currentURL: URL?,
        hasReachedSettingsPage: Bool
    ) -> Bool {
        let error = error as NSError
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            return true
        }
        return hasReachedSettingsPage && currentURL.map(OllamaWebPageNavigationPolicy.isSettingsURL) == true
    }
}
