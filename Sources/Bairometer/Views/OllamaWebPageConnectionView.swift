import BairometerCore
import SwiftUI
import WebKit

struct OllamaWebPageConnectionSheet: View {
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    let account: ProviderAccount
    let client: OllamaWebPageClientController
    let dismiss: () -> Void

    @State private var attempt = 0
    @State private var isConnecting = false
    @State private var status: ConnectionStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    account.webDataStoreID == nil
                        ? AppStrings.Ollama.connect.resource(locale: locale)
                        : AppStrings.Ollama.reconnect.resource(locale: locale)
                )
                    .font(.title2.weight(.semibold))
                Text(AppStrings.Ollama.description.resource(locale: locale))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let webView = client.webView(for: account) {
                OllamaWebView(webView: webView)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    }
            } else {
                ContentUnavailableView(
                    AppStrings.Ollama.profileUnavailable.localized(locale: locale),
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(AppStrings.Ollama.saveBeforeOpening.resource(locale: locale))
                )
            }

            if let status {
                Text(status.text(locale: locale))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()

                Button(AppStrings.Common.cancel.localized(locale: locale), role: .cancel) {
                    dismiss()
                }

                if status != nil && !isConnecting {
                    Button(AppStrings.Ollama.tryAgain.localized(locale: locale)) {
                        attempt += 1
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 980, idealWidth: 1080, minHeight: 780, idealHeight: 840)
        .task(id: attempt) {
            await connect()
        }
    }

    private func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        status = .loading
        defer { isConnecting = false }

        do {
            let payload = try await client.connect(account: account)
            appModel.acceptOllamaUsagePayload(payload, for: account)
            dismiss()
        } catch is CancellationError {
            status = .cancelled
        } catch {
            status = .providerError(connectionMessage(for: error))
        }
    }

    private func connectionMessage(for error: Error) -> String {
        guard let providerError = error as? ProviderAdapterError else {
            return AppStrings.Ollama.failed.localized(locale: locale)
        }
        if let recoverySuggestion = providerError.recoverySuggestion {
            return "\(providerError.message) \(recoverySuggestion)"
        }
        return providerError.message
    }
}

private enum ConnectionStatus {
    case loading
    case cancelled
    case providerError(String)

    func text(locale: Locale) -> String {
        switch self {
        case .loading:
            AppStrings.Ollama.loading.localized(locale: locale)
        case .cancelled:
            AppStrings.Ollama.cancelled.localized(locale: locale)
        case let .providerError(message):
            message
        }
    }
}

struct OllamaWebPageConnectionWindow: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.locale) private var locale
    @ObservedObject var appModel: AppModel
    var dismiss: (() -> Void)? = nil

    var body: some View {
        Group {
            if let account = appModel.ollamaConnectionAccount,
               let client = appModel.ollamaWebPageClient {
                OllamaWebPageConnectionSheet(
                    appModel: appModel,
                    account: account,
                    client: client,
                    dismiss: { closeConnection(for: account) }
                )
            } else {
                ContentUnavailableView(
                    AppStrings.Ollama.windowUnavailable.localized(locale: locale),
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(AppStrings.Ollama.chooseFromAccount.resource(locale: locale))
                )
                .frame(
                    minWidth: OllamaConnectionWindowConfiguration.preferredSize.width,
                    minHeight: OllamaConnectionWindowConfiguration.preferredSize.height
                )
            }
        }
        .onDisappear {
            if let account = appModel.ollamaConnectionAccount {
                appModel.clearOllamaConnection(for: account)
            }
        }
    }

    private func closeConnection(for account: ProviderAccount) {
        appModel.clearOllamaConnection(for: account)
        if let dismiss {
            dismiss()
        } else {
            dismissWindow(id: OllamaConnectionWindowConfiguration.id)
        }
    }
}

private struct OllamaWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
