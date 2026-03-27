import Foundation
import WebKit

@MainActor
final class QuotaFetcher: NSObject {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<UsageResponse, Error>?
    private let sessionKey: String
    private let organizationId: String

    init(sessionKey: String, organizationId: String) {
        self.sessionKey = sessionKey
        self.organizationId = organizationId
        super.init()
    }

    func fetch() async throws -> UsageResponse {
        if webView == nil {
            webView = createWebView()
        }

        try await navigateToClaude()
        try await Task.sleep(for: .seconds(3))
        let json = try await fetchUsageViaJS()
        return try Self.parseResponse(json)
    }

    static func parseResponse(_ json: String) throws -> UsageResponse {
        guard let data = json.data(using: .utf8) else {
            throw QuotaFetcherError.invalidResponse
        }
        if json.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            throw QuotaFetcherError.htmlResponse
        }
        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }

    func reset() {
        webView?.stopLoading()
        webView = nil
    }

    // MARK: - Private

    private func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let wv = WKWebView(frame: .zero, configuration: config)

        let cookieStore = config.websiteDataStore.httpCookieStore

        let sessionCookie = HTTPCookie(properties: [
            .name: "sessionKey",
            .value: sessionKey,
            .domain: ".claude.ai",
            .path: "/",
            .secure: "TRUE",
        ])!

        let orgCookie = HTTPCookie(properties: [
            .name: "lastActiveOrg",
            .value: organizationId,
            .domain: ".claude.ai",
            .path: "/",
            .secure: "TRUE",
        ])!

        Task {
            await cookieStore.setCookie(sessionCookie)
            await cookieStore.setCookie(orgCookie)
        }

        return wv
    }

    private func navigateToClaude() async throws {
        guard let webView else { throw QuotaFetcherError.noWebView }

        return try await withCheckedThrowingContinuation { continuation in
            let url = URL(string: "https://claude.ai/")!
            webView.navigationDelegate = self
            self.navigationContinuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    private var navigationContinuation: CheckedContinuation<Void, Error>?

    private func fetchUsageViaJS() async throws -> String {
        guard let webView else { throw QuotaFetcherError.noWebView }

        let url = "https://claude.ai/api/organizations/\(organizationId)/usage"

        let js = """
            (async () => {
                try {
                    const response = await fetch('\(url)', {
                        method: 'GET',
                        credentials: 'include',
                        headers: {
                            'accept': '*/*',
                            'anthropic-client-platform': 'web_claude_ai'
                        }
                    });
                    if (!response.ok) {
                        return JSON.stringify({ error: response.status + ' ' + response.statusText });
                    }
                    const data = await response.json();
                    return JSON.stringify(data);
                } catch (e) {
                    return JSON.stringify({ error: e.message });
                }
            })()
        """

        let result = try await webView.evaluateJavaScript(js)

        guard let jsonString = result as? String else {
            throw QuotaFetcherError.invalidResponse
        }

        if let data = jsonString.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMsg = obj["error"] as? String {
            throw QuotaFetcherError.apiFailed(errorMsg)
        }

        return jsonString
    }
}

// MARK: - WKNavigationDelegate

extension QuotaFetcher: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            navigationContinuation?.resume()
            navigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            navigationContinuation?.resume(throwing: error)
            navigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            navigationContinuation?.resume(throwing: error)
            navigationContinuation = nil
        }
    }
}

enum QuotaFetcherError: LocalizedError {
    case noWebView
    case invalidResponse
    case htmlResponse
    case apiFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWebView: return "WebView not initialized"
        case .invalidResponse: return "Invalid response from API"
        case .htmlResponse: return "Received HTML instead of JSON (likely Cloudflare block)"
        case .apiFailed(let msg): return "API error: \(msg)"
        }
    }
}
