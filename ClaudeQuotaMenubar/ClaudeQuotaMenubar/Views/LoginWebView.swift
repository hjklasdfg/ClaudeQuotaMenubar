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
    let refreshId: UUID  // Change this to force a new WebView

    func makeCoordinator() -> Coordinator {
        Coordinator(keychain: keychain, onLoginSuccess: onLoginSuccess)
    }

    func makeNSView(context: Context) -> WKWebView {
        createAndLoadWebView(context: context)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // When refreshId changes, rebuild the WebView
        if context.coordinator.currentRefreshId != refreshId {
            context.coordinator.currentRefreshId = refreshId
            context.coordinator.hasCompleted = false

            let config = nsView.configuration
            let cookieStore = config.websiteDataStore.httpCookieStore

            Task {
                // Clear all claude.ai cookies
                let cookies = await cookieStore.allCookies()
                for cookie in cookies where cookie.domain.contains("claude.ai") {
                    await cookieStore.deleteCookie(cookie)
                }
                let url = URL(string: "https://claude.ai/login")!
                nsView.load(URLRequest(url: url))
            }
        }
    }

    private func createAndLoadWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        context.coordinator.webView = webView
        context.coordinator.currentRefreshId = refreshId

        let cookieStore = config.websiteDataStore.httpCookieStore
        cookieStore.add(context.coordinator)

        Task {
            let cookies = await cookieStore.allCookies()
            for cookie in cookies where cookie.domain.contains("claude.ai") {
                await cookieStore.deleteCookie(cookie)
            }
            let url = URL(string: "https://claude.ai/login")!
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    @MainActor
    class Coordinator: NSObject, WKHTTPCookieStoreObserver, WKUIDelegate, WKNavigationDelegate {
        let keychain: KeychainService
        let onLoginSuccess: () -> Void
        weak var webView: WKWebView?
        var hasCompleted = false
        var currentRefreshId: UUID?

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
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // After page finishes loading, check if already logged in
        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                guard let url = webView.url?.absoluteString else { return }
                // If we landed on the main page (not /login), user is already authenticated
                if !url.contains("/login") && url.contains("claude.ai") {
                    let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                    await self.checkForSessionKey(in: cookieStore)
                }
            }
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in
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
                    hasCompleted = false
                }
            } catch {
                hasCompleted = false
            }
        }
    }
}
