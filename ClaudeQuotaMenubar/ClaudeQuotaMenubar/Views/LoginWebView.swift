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
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        context.coordinator.webView = webView
        context.coordinator.startObservingURL()

        // Load login page, then use JS to logout first if there's an existing session
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            // POST to logout API to clear server session, then reload login
            let js = """
                try {
                    await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' });
                } catch(e) {}
                window.location.href = '/login';
            """
            try? await webView.callAsyncJavaScript(js, arguments: [:], contentWorld: .page)

            // Clean session cookies from store
            let cookieStore = config.websiteDataStore.httpCookieStore
            let cookies = await cookieStore.allCookies()
            for cookie in cookies where cookie.name.contains("sessionKey") {
                await cookieStore.deleteCookie(cookie)
            }
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    @MainActor
    class Coordinator: NSObject, WKUIDelegate {
        let keychain: KeychainService
        let onLoginSuccess: () -> Void
        weak var webView: WKWebView?
        private var hasCompleted = false
        private var urlObservation: NSKeyValueObservation?

        init(keychain: KeychainService, onLoginSuccess: @escaping () -> Void) {
            self.keychain = keychain
            self.onLoginSuccess = onLoginSuccess
        }

        func startObservingURL() {
            urlObservation = webView?.observe(\.url, options: [.new]) { [weak self] _, change in
                guard let self, let url = change.newValue??.absoluteString else { return }
                Task { @MainActor in
                    await self.handleURLChange(url)
                }
            }
        }

        private func handleURLChange(_ url: String) async {
            guard !hasCompleted else { return }
            // Ignore non-claude.ai URLs and the login/logout pages
            guard url.contains("claude.ai"),
                  !url.contains("/login"),
                  !url.contains("/api/auth") else { return }

            print("[LoginWebView] Login success detected! URL: \(url)")
            hasCompleted = true

            // Retry extraction with increasing delays — cookie may not be set immediately
            for attempt in 1...5 {
                let delay = Double(attempt) * 2
                try? await Task.sleep(for: .seconds(delay))
                print("[LoginWebView] Extraction attempt \(attempt)/5...")
                await extractCredentials()
                if keychain.hasCredentials {
                    print("[LoginWebView] Login complete!")
                    onLoginSuccess()
                    return
                }
            }
            print("[LoginWebView] Failed after 5 attempts — use Settings > Advanced for manual entry")
            // Don't reset hasCompleted — prevents infinite loop
        }

        private func extractCredentials() async {
            guard let webView else { return }

            // Use JS to get both sessionKey (from cookie) and orgId (from API)
            let js = """
                async function extractCredentials() {
                    // Get sessionKey from cookies
                    const cookies = document.cookie.split(';').map(c => c.trim());
                    let sessionKey = null;
                    for (const cookie of cookies) {
                        if (cookie.startsWith('sessionKey=')) {
                            sessionKey = cookie.substring('sessionKey='.length);
                            break;
                        }
                    }

                    // If not in document.cookie, try fetching session info
                    if (!sessionKey) {
                        try {
                            const resp = await fetch('/api/auth/session', {
                                credentials: 'include'
                            });
                            const data = await resp.json();
                            if (data.sessionKey) sessionKey = data.sessionKey;
                        } catch(e) {}
                    }

                    // Get organization ID
                    let orgId = null;
                    try {
                        const resp = await fetch('/api/organizations', {
                            credentials: 'include',
                            headers: { 'accept': 'application/json' }
                        });
                        const orgs = await resp.json();
                        if (Array.isArray(orgs) && orgs.length > 0) {
                            orgId = orgs[0].uuid;
                        }
                    } catch(e) {}

                    return JSON.stringify({ sessionKey, orgId });
                }
                return await extractCredentials();
            """

            print("[LoginWebView] Extracting credentials via JS...")
            do {
                let result = try await webView.callAsyncJavaScript(js, arguments: [:], contentWorld: .page)
                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("[LoginWebView] Failed to parse JS result: \(result ?? "nil")")
                    // Try cookie store as fallback
                    await extractFromCookieStore()
                    return
                }

                print("[LoginWebView] JS result: \(jsonString.prefix(200))")

                let sessionKey = obj["sessionKey"] as? String
                let orgId = obj["orgId"] as? String

                if let sk = sessionKey, !sk.isEmpty {
                    print("[LoginWebView] sessionKey from JS: \(sk.prefix(20))...")
                    keychain.save(account: "sessionKey", value: sk)
                } else {
                    print("[LoginWebView] No sessionKey from JS, trying cookie store...")
                    await extractSessionKeyFromCookieStore()
                }

                if let orgId, !orgId.isEmpty {
                    print("[LoginWebView] orgId: \(orgId)")
                    keychain.save(account: "organizationId", value: orgId)
                }

            } catch {
                print("[LoginWebView] JS error: \(error)")
                await extractFromCookieStore()
            }
        }

        private func extractFromCookieStore() async {
            await extractSessionKeyFromCookieStore()
        }

        private func extractSessionKeyFromCookieStore() async {
            guard let webView else { return }
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let cookies = await cookieStore.allCookies()
            if let sk = cookies.first(where: { $0.name == "sessionKey" }) {
                print("[LoginWebView] sessionKey from cookie store: \(sk.value.prefix(20))...")
                keychain.save(account: "sessionKey", value: sk.value)
            } else {
                print("[LoginWebView] sessionKey not found in cookie store either")
                let names = cookies.filter { $0.domain.contains("claude.ai") }.map { $0.name }
                print("[LoginWebView] Available claude.ai cookies: \(names)")
            }
        }

        // Handle OAuth popups
        func webView(
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
    }
}
