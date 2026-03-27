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
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        context.coordinator.webView = webView

        let cookieStore = config.websiteDataStore.httpCookieStore
        cookieStore.add(context.coordinator)

        // Clear old claude.ai cookies before loading login page
        Task { @MainActor in
            let cookies = await cookieStore.allCookies()
            for cookie in cookies where cookie.domain.contains("claude.ai") {
                await cookieStore.deleteCookie(cookie)
            }
            webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        }

        return webView
    }

    @MainActor
    class Coordinator: NSObject, WKHTTPCookieStoreObserver, WKUIDelegate, WKNavigationDelegate {
        let keychain: KeychainService
        let onLoginSuccess: () -> Void
        weak var webView: WKWebView?
        var hasCompleted = false

        init(keychain: KeychainService, onLoginSuccess: @escaping () -> Void) {
            self.keychain = keychain
            self.onLoginSuccess = onLoginSuccess
        }

        // Detect navigation to main page (login success)
        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                guard !self.hasCompleted else { return }
                guard let url = webView.url?.absoluteString else { return }
                print("[LoginWebView] Page loaded: \(url)")

                // If URL is no longer /login, user has authenticated
                if url.contains("claude.ai") && !url.contains("/login") {
                    print("[LoginWebView] Login detected! Dumping ALL cookies...")
                    let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                    let cookies = await cookieStore.allCookies()
                    for cookie in cookies {
                        print("[LoginWebView]   \(cookie.domain) | \(cookie.name) = \(cookie.value.prefix(30))...")
                    }

                    // Try to get sessionKey via JavaScript (checks document.cookie + localStorage)
                    let js = """
                        (function() {
                            let info = {
                                cookies: document.cookie,
                                url: window.location.href,
                                localStorage: {}
                            };
                            try {
                                for (let i = 0; i < localStorage.length; i++) {
                                    let key = localStorage.key(i);
                                    if (key.toLowerCase().includes('session') || key.toLowerCase().includes('token') || key.toLowerCase().includes('key') || key.toLowerCase().includes('auth')) {
                                        info.localStorage[key] = localStorage.getItem(key).substring(0, 50);
                                    }
                                }
                            } catch(e) {}
                            return JSON.stringify(info);
                        })()
                    """
                    do {
                        let result = try await webView.callAsyncJavaScript(js, arguments: [:], contentWorld: .page)
                        print("[LoginWebView] JS info: \(result ?? "nil")")
                    } catch {
                        print("[LoginWebView] JS error: \(error)")
                    }
                }
            }
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

            // Debug: log all cookie names from claude.ai
            let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
            print("[LoginWebView] claude.ai cookies: \(claudeCookies.map { "\($0.name)=\($0.value.prefix(20))..." })")

            guard let sessionCookie = cookies.first(where: {
                $0.name == "sessionKey" && $0.value.hasPrefix("sk-ant-sid01-")
            }) else {
                // Also check without prefix requirement
                if let anyCookie = cookies.first(where: { $0.name == "sessionKey" }) {
                    print("[LoginWebView] Found sessionKey but wrong prefix: \(anyCookie.value.prefix(30))...")
                }
                return
            }

            print("[LoginWebView] sessionKey found! Saving to Keychain...")
            hasCompleted = true
            keychain.save(account: "sessionKey", value: sessionCookie.value)

            try? await Task.sleep(for: .seconds(2))
            await fetchOrganizationId()
        }

        private func fetchOrganizationId() async {
            guard let webView else {
                print("[LoginWebView] fetchOrganizationId: webView is nil!")
                return
            }

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

            print("[LoginWebView] Fetching organizations...")
            do {
                let result = try await webView.callAsyncJavaScript(
                    js, arguments: [:], contentWorld: .page
                )
                let jsonString = result as? String ?? "nil"
                print("[LoginWebView] Org response: \(jsonString.prefix(200))")
                if let orgId = LoginCredentialExtractor.parseOrganizationId(from: jsonString) {
                    print("[LoginWebView] orgId found: \(orgId)")
                    keychain.save(account: "organizationId", value: orgId)
                    onLoginSuccess()
                } else {
                    print("[LoginWebView] Failed to parse orgId from response")
                }
            } catch {
                print("[LoginWebView] JS error: \(error)")
            }
        }
    }
}
