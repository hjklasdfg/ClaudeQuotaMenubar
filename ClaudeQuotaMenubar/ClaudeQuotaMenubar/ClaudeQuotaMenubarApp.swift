import SwiftUI

@MainActor
@Observable
final class AppState {
    var fiveHourUtil: Double?
    var sevenDayUtil: Double?
    var opusUtil: Double?
    var sonnetUtil: Double?
    var fiveHourResetsAt: String?
    var sevenDayResetsAt: String?
    var hourlyTrend: Double?
    var isLoading = false
    var errorMessage: String?
    var showSettings = false
    var showTrend = false
    var showLogin = false
    var loginRefreshId = UUID()
    var loginForceLogout = false
    var isLoggedIn = false
    var consecutiveFailures = 0
    var sessionExpired = false

    let keychain = KeychainService()
    var store: QuotaStore?
    var fetcher: QuotaFetcher?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init() {
        do {
            store = try QuotaStore()
            try store?.purgeOlderThan(days: 30)
        } catch {
            errorMessage = "Failed to open database: \(error.localizedDescription)"
        }
        checkLoginState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.startPolling()
        }

        // Hide from Dock when all windows are closed
        let knownTitles: Set = ["Claude Quota Settings", "Usage Trend", "Login to Claude"]
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let hasAppWindows = NSApp.windows.contains { $0.isVisible && knownTitles.contains($0.title) }
                if !hasAppWindows {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    var statusText: String {
        if sessionExpired { return "⚠️" }
        if let util = fiveHourUtil {
            return "\(Int(util))%"
        }
        return "--"
    }

    var statusColor: Color {
        if sessionExpired { return .red }
        guard let util = fiveHourUtil else { return .gray }
        return UsageColor.for(utilization: util)
    }

    func checkLoginState() {
        isLoggedIn = keychain.hasCredentials
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func startPolling() {
        stopPolling()
        guard keychain.hasCredentials else {
            showLogin = true
            return
        }
        setupFetcher()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        timer?.tolerance = 30

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard let fetcher else {
            errorMessage = "Not logged in"
            return
        }
        isLoading = true
        errorMessage = nil

        do {
            let response = try await fetcher.fetch()
            let sample = UsageSample(from: response)

            fiveHourUtil = response.fiveHour?.utilization
            sevenDayUtil = response.sevenDay?.utilization
            opusUtil = response.sevenDayOpus?.utilization
            sonnetUtil = response.sevenDaySonnet?.utilization
            fiveHourResetsAt = response.fiveHour?.resetsAt
            sevenDayResetsAt = response.sevenDay?.resetsAt

            try store?.insert(sample)

            if let hourAgoSample = try store?.fetchSampleClosestTo(date: Date().addingTimeInterval(-3600)),
               let currentUtil = fiveHourUtil,
               let pastUtil = hourAgoSample.fiveHourUtil {
                hourlyTrend = currentUtil - pastUtil
            }

            consecutiveFailures = 0
            sessionExpired = false
        } catch {
            consecutiveFailures += 1
            errorMessage = error.localizedDescription

            fetcher.reset()
            setupFetcher()

            // Treat repeated failures as session expiry
            if consecutiveFailures >= 2 {
                sessionExpired = true
                showLogin = true
            }
        }

        isLoading = false
    }

    func setupFetcher() {
        guard let sk = keychain.sessionKey, let orgId = keychain.organizationId else { return }
        fetcher = QuotaFetcher(sessionKey: sk, organizationId: orgId)
    }

    func logout() {
        keychain.delete(account: "sessionKey")
        keychain.delete(account: "organizationId")
        fetcher?.reset()
        fetcher = nil
        fiveHourUtil = nil
        sevenDayUtil = nil
        opusUtil = nil
        sonnetUtil = nil
        hourlyTrend = nil
        errorMessage = nil
        sessionExpired = false
        consecutiveFailures = 0
        checkLoginState()

        // Prepare for next login: force logout from WebView session
        loginForceLogout = true
        loginRefreshId = UUID()
    }

    func relogin() {
        // Stop polling and clear old credentials
        stopPolling()
        fetcher?.reset()
        fetcher = nil
        keychain.delete(account: "sessionKey")
        keychain.delete(account: "organizationId")
        checkLoginState()
        loginForceLogout = true
        loginRefreshId = UUID()
        showLogin = true
    }

    func onCredentialsSaved() {
        sessionExpired = false
        consecutiveFailures = 0
        checkLoginState()
        setupFetcher()
        startPolling()
    }

    func parseResetDate(_ isoString: String?) -> Date? {
        guard let isoString else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: isoString) { return date }
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: isoString)
    }

    func formatResetTime(_ isoString: String?) -> String {
        guard let date = parseResetDate(isoString) else { return "" }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
            if days > 0 {
                return "in \(days)d"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "M/d"
                return formatter.string(from: date)
            }
        }
    }

    func trendText() -> String {
        guard let trend = hourlyTrend else { return "" }
        let arrow = trend >= 0 ? "↑" : "↓"
        return "  \(arrow)1h: \(trend >= 0 ? "+" : "")\(Int(trend))%"
    }
}

@main
struct ClaudeQuotaMenubarApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Text("C \(state.statusText)")
                .monospacedDigit()
        }

        Window("Claude Quota Settings", id: "settings") {
            SettingsView(keychain: state.keychain, isLoggedIn: state.isLoggedIn, onSave: state.onCredentialsSaved, onLogout: state.logout, onRelogin: state.relogin)
        }
        .windowResizability(.contentSize)

        Window("Usage Trend", id: "trend") {
            TrendWindow(store: state.store)
        }
        .defaultSize(width: 600, height: 400)

        Window("Login to Claude", id: "login") {
            LoginWebView(keychain: state.keychain, onLoginSuccess: {
                state.onCredentialsSaved()
                state.showLogin = false
                state.loginForceLogout = false
                NSApp.windows.first { $0.title == "Login to Claude" }?.close()
                NSApp.setActivationPolicy(.accessory)
            }, forceLogout: state.loginForceLogout)
            .id(state.loginRefreshId) // Force new WebView on each login attempt
            .frame(minWidth: 800, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
    }
}
