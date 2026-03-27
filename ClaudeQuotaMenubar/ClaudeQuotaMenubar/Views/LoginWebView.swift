import Foundation
import SwiftUI
import WebKit

// MARK: - Credential Extraction

enum LoginCredentialExtractor {
    static func parseOrganizationId(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first,
              let uuid = first["uuid"] as? String else {
            return nil
        }
        return uuid
    }
}

// MARK: - LoginWebView

/// Each instance uses a fresh non-persistent data store, so no cookie cleanup is needed.
/// To force a new instance, change `refreshId`.
struct LoginWebView: NSViewRepresentable {
    let keychain: KeychainService
    let onLoginSuccess: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(keychain: keychain, onLoginSuccess: onLoginSuccess)
    }

    func makeNSView(context: Context) -> WKWebView {
        createFreshWebView(context: context)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No-op: view is recreated via .id(refreshId) in parent
    }

    private func createFreshWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        context.coordinator.webView = webView

        config.websiteDataStore.httpCookieStore.add(context.coordinator)

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return webView
    }

    @MainActor
    class Coordinator: NSObject, WKHTTPCookieStoreObserver, WKUIDelegate {
        let keychain: KeychainService
        let onLoginSuccess: () -> Void
        weak var webView: WKWebView?
        var hasCompleted = false

        init(keychain: KeychainService, onLoginSuccess: @escaping () -> Void) {
            self.keychain = keychain
            self.onLoginSuccess = onLoginSuccess
        }

        // Handle OAuth popups
        nonisolated func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in
                guard !self.hasCompleted else { return }
                await self.checkForSessionKey(in: cookieStore)
            }
        }

        private func checkForSessionKey(in cookieStore: WKHTTPCookieStore) async {
            let cookies = await cookieStore.allCookies()
            guard let sessionCookie = cookies.first(where: {
                $0.name == "sessionKey" && $0.value.hasPrefix("sk-ant-sid01-")
            }) else { return }

            hasCompleted = true
            keychain.save(account: "sessionKey", value: sessionCookie.value)

            // Small delay for page to stabilize
            try? await Task.sleep(for: .seconds(2))
            await fetchOrganizationId()
        }

        private func fetchOrganizationId() async {
            guard let webView else { return }

            let js = """
                try {
                    const response = await fetch('https://claude.ai/api/organizations', {
                        method: 'GET',
                        credentials: 'include',
                        headers: { 'accept': 'application/json' }
                    });
                    const data = await response.json();
                    return JSON.stringify(data);
                } catch (e) {
                    return JSON.stringify({ error: e.message });
                }
            """

            do {
                let result = try await webView.callAsyncJavaScript(
                    js, arguments: [:], contentWorld: .page
                )
                if let jsonString = result as? String,
                   let orgId = LoginCredentialExtractor.parseOrganizationId(from: jsonString) {
                    keychain.save(account: "organizationId", value: orgId)
                    onLoginSuccess()
                }
            } catch {
                // Org fetch failed — user can use manual entry as fallback
            }
        }
    }
}
