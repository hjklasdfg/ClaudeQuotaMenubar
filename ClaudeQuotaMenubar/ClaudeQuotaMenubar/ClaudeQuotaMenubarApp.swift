import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var fiveHourUtil: Double?
    @Published var sevenDayUtil: Double?
    @Published var opusUtil: Double?
    @Published var sonnetUtil: Double?
    @Published var fiveHourResetsAt: String?
    @Published var sevenDayResetsAt: String?
    @Published var hourlyTrend: Double?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published var showTrend = false
    @Published var consecutiveFailures = 0

    let keychain = KeychainService()
    var store: QuotaStore?
    var fetcher: QuotaFetcher?
    private var timer: Timer?

    init() {
        do {
            store = try QuotaStore()
            try store?.purgeOlderThan(days: 30)
        } catch {
            errorMessage = "Failed to open database: \(error.localizedDescription)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.startPolling()
        }
    }

    var statusText: String {
        if let util = fiveHourUtil {
            return "\(Int(util))%"
        }
        return "--"
    }

    var statusColor: Color {
        guard let util = fiveHourUtil else { return .gray }
        return UsageColor.for(utilization: util)
    }

    func startPolling() {
        guard keychain.hasCredentials else {
            showSettings = true
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

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard let fetcher else {
            showSettings = true
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
        } catch {
            consecutiveFailures += 1
            errorMessage = error.localizedDescription

            fetcher.reset()
            setupFetcher()
        }

        isLoading = false
    }

    func setupFetcher() {
        guard let sk = keychain.sessionKey, let orgId = keychain.organizationId else { return }
        fetcher = QuotaFetcher(sessionKey: sk, organizationId: orgId)
    }

    func onCredentialsSaved() {
        setupFetcher()
        Task { await refresh() }
    }

    func formatResetTime(_ isoString: String?) -> String {
        guard let isoString, let date = ISO8601DateFormatter().date(from: isoString) else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
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
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "circle.fill")
                    .foregroundColor(state.statusColor)
                    .imageScale(.small)
                Text(state.statusText)
                    .monospacedDigit()
            }
        }

        Window("Claude Quota Settings", id: "settings") {
            SettingsView(keychain: state.keychain, onSave: state.onCredentialsSaved)
        }
        .windowResizability(.contentSize)

        Window("Usage Trend", id: "trend") {
            TrendWindow(store: state.store)
        }
        .defaultSize(width: 600, height: 400)
    }
}
