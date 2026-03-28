import Foundation
import SwiftUI
import WebKit

// MARK: - LoginWebView

struct LoginWebView: NSViewRepresentable {
    let keychain: KeychainService
    let onLoginSuccess: () -> Void
    var forceLogout: Bool = false

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

        if forceLogout {
            // Re-login: load page → JS logout → clear cookies → observe → /login
            webView.load(URLRequest(url: URL(string: "https://claude.ai")!))
            Task { @MainActor [weak webView] in
                try? await Task.sleep(for: .seconds(3))
                guard let webView else { return }

                let js = """
                    try { await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' }); } catch(e) {}
                    return 'done';
                """
                _ = try? await webView.callAsyncJavaScript(js, arguments: [:], contentWorld: .page)

                let cookieStore = config.websiteDataStore.httpCookieStore
                let cookies = await cookieStore.allCookies()
                for cookie in cookies where cookie.name.contains("sessionKey") {
                    await cookieStore.deleteCookie(cookie)
                }

                context.coordinator.startObservingURL()
                webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
            }
        } else {
            // First login: observe immediately and load login page
            context.coordinator.startObservingURL()
            webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
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

        deinit {
            urlObservation?.invalidate()
            urlObservation = nil
        }

        func startObservingURL() {
            urlObservation?.invalidate()
            urlObservation = webView?.observe(\.url, options: [.new]) { [weak self] _, change in
                guard let url = change.newValue??.absoluteString else { return }
                Task { @MainActor [weak self] in
                    await self?.handleURLChange(url)
                }
            }
        }

        private func handleURLChange(_ url: String) async {
            guard !hasCompleted else { return }
            guard url.contains("claude.ai"),
                  !url.contains("/login"),
                  !url.contains("/api/") else { return }

            hasCompleted = true

            // Retry extraction — sessionKey cookie may be set with a delay
            for attempt in 1...5 {
                let delay = max(1.0, Double(attempt) * 1.5)
                try? await Task.sleep(for: .seconds(delay))
                await extractCredentials()
                if keychain.hasCredentials {
                    onLoginSuccess()
                    return
                }
            }
            // Failed — user can use Settings > Advanced for manual entry
        }

        private func extractCredentials() async {
            guard let webView else { return }

            let js = """
                async function extractCredentials() {
                    const cookies = document.cookie.split(';').map(c => c.trim());
                    let sessionKey = null;
                    for (const cookie of cookies) {
                        if (cookie.startsWith('sessionKey=')) {
                            sessionKey = cookie.substring('sessionKey='.length);
                            break;
                        }
                    }
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

            do {
                let result = try await webView.callAsyncJavaScript(js, arguments: [:], contentWorld: .page)
                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    await extractSessionKeyFromCookieStore()
                    return
                }

                let sessionKey = obj["sessionKey"] as? String
                let orgId = obj["orgId"] as? String

                if let sk = sessionKey, !sk.isEmpty {
                    keychain.save(account: "sessionKey", value: sk)
                } else {
                    await extractSessionKeyFromCookieStore()
                }

                if let orgId, !orgId.isEmpty {
                    keychain.save(account: "organizationId", value: orgId)
                }
            } catch {
                await extractSessionKeyFromCookieStore()
            }
        }

        private func extractSessionKeyFromCookieStore() async {
            guard let webView else { return }
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let cookies = await cookieStore.allCookies()
            if let sk = cookies.first(where: { $0.name == "sessionKey" }) {
                keychain.save(account: "sessionKey", value: sk.value)
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
