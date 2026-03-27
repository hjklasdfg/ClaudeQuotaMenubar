import SwiftUI

struct MenuBarView: View {
    var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let fiveHour = state.fiveHourUtil {
                Button("5h Usage: \(Int(fiveHour))%\(state.trendText()) (resets: \(state.formatResetTime(state.fiveHourResetsAt)))") {}
            }

            if let sevenDay = state.sevenDayUtil {
                Button("7d Usage: \(Int(sevenDay))% (resets: \(state.formatResetTime(state.sevenDayResetsAt)))") {}
            }

            if state.fiveHourUtil != nil || state.sevenDayUtil != nil {
                Divider()
            }

            if let opus = state.opusUtil {
                Button("Opus (7d)：\(Int(opus))%") {}
            }
            if let sonnet = state.sonnetUtil {
                Button("Sonnet (7d)：\(Int(sonnet))%") {}
            }

            if state.opusUtil != nil || state.sonnetUtil != nil {
                Divider()
            }

            Button("📈 Trend") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "trend")
            }

            Divider()

            Button("⟳ Refresh") {
                Task { await state.refresh() }
            }
            .disabled(state.isLoading)

            Button("⚙ Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }

            if let error = state.errorMessage {
                Divider()
                Text("⚠ \(error)")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onChange(of: state.showLogin) { _, shouldShow in
            if shouldShow {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "login")
                state.showLogin = false
            }
        }
    }
}
