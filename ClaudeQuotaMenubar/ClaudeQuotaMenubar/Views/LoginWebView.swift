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

struct LoginWebView: NSViewRepresentable {
    let keychain: KeychainService
    let onLoginSuccess: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(keychain: keychain, onLoginSuccess: onLoginSuccess)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView

        // Clear stale cookies before login
        let cookieStore = config.websiteDataStore.httpCookieStore
        cookieStore.add(context.coordinator)

        Task {
            let cookies = await cookieStore.allCookies()
            for cookie in cookies where cookie.domain.contains("claude.ai") {
                await cookieStore.deleteCookie(cookie)
            }
            // Load login page after cleanup
            let url = URL(string: "https://claude.ai/login")!
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    @MainActor
    class Coordinator: NSObject, WKHTTPCookieStoreObserver, WKUIDelegate {
        let keychain: KeychainService
        let onLoginSuccess: () -> Void
        weak var webView: WKWebView?
        private var hasCompleted = false

        init(keychain: KeychainService, onLoginSuccess: @escaping () -> Void) {
            self.keychain = keychain
            self.onLoginSuccess = onLoginSuccess
        }

        // Handle OAuth popups (e.g., Google login opens a new window)
        nonisolated func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Load popup URLs in the same WebView instead of opening a new window
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in
                await self.checkForSessionKey(in: cookieStore)
            }
        }

        private func checkForSessionKey(in cookieStore: WKHTTPCookieStore) async {
            guard !hasCompleted else { return }

            let cookies = await cookieStore.allCookies()
            guard let sessionCookie = cookies.first(where: {
                $0.name == "sessionKey" && $0.value.hasPrefix("sk-ant-sid01-")
            }) else { return }

            hasCompleted = true
            keychain.save(account: "sessionKey", value: sessionCookie.value)

            // Fetch organization ID
            await fetchOrganizationId(sessionKey: sessionCookie.value)
        }

        private func fetchOrganizationId(sessionKey: String) async {
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
                    return JSON.stringify([]);
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
                } else {
                    hasCompleted = false // Allow retry on next cookie change
                }
            } catch {
                hasCompleted = false // Allow retry on next cookie change
            }
        }
    }
}
