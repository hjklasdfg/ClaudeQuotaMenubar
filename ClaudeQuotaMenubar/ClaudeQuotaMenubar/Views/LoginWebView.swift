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
    let refreshId: UUID

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
        context.coordinator.currentRefreshId = refreshId

        webView.navigationDelegate = context.coordinator

        let cookieStore = config.websiteDataStore.httpCookieStore
        cookieStore.add(context.coordinator)

        cleanAndLoad(webView: webView, cookieStore: cookieStore)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard context.coordinator.currentRefreshId != refreshId else { return }
        context.coordinator.currentRefreshId = refreshId
        context.coordinator.hasCompleted = false
        context.coordinator.isCleaningUp = true

        let cookieStore = nsView.configuration.websiteDataStore.httpCookieStore
        cleanAndLoad(webView: nsView, cookieStore: cookieStore)
    }

    private func cleanAndLoad(webView: WKWebView, cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in
            let cookies = await cookieStore.allCookies()
            for cookie in cookies where cookie.domain.contains("claude.ai") {
                await cookieStore.deleteCookie(cookie)
            }
            // Small delay to ensure cookies are fully cleared
            try? await Task.sleep(for: .milliseconds(100))
            webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        }
    }

    @MainActor
    class Coordinator: NSObject, WKHTTPCookieStoreObserver, WKUIDelegate, WKNavigationDelegate {
        let keychain: KeychainService
        let onLoginSuccess: () -> Void
        weak var webView: WKWebView?
        var hasCompleted = false
        var currentRefreshId: UUID?
        var isCleaningUp = true  // Don't check cookies during cleanup

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

        // Enable cookie monitoring once login page has loaded
        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.isCleaningUp = false
            }
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in
                guard !self.isCleaningUp, !self.hasCompleted else { return }
                await self.checkForSessionKey(in: cookieStore)
            }
        }

        func checkForSessionKey(in cookieStore: WKHTTPCookieStore) async {
            guard !hasCompleted else { return }

            let cookies = await cookieStore.allCookies()
            guard let sessionCookie = cookies.first(where: {
                $0.name == "sessionKey" && $0.value.hasPrefix("sk-ant-sid01-")
            }) else { return }

            hasCompleted = true
            keychain.save(account: "sessionKey", value: sessionCookie.value)

            // Wait a moment for the page to stabilize before fetching org
            try? await Task.sleep(for: .seconds(1))
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
                }
                // If org fetch fails, don't retry — user can use manual entry
            } catch {
                // Don't reset hasCompleted — avoid retry loops
            }
        }

        /// Called after login page finishes loading to enable cookie monitoring
        func enableCookieMonitoring() {
            isCleaningUp = false
        }
    }
}
