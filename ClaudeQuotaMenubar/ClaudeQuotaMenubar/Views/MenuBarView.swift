import SwiftUI

struct MenuBarView: View {
    var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let fiveHour = state.fiveHourUtil {
            Button("5 小时用量：\(Int(fiveHour))%\(state.trendText())（重置：\(state.formatResetTime(state.fiveHourResetsAt))）") {}
        }

        if let sevenDay = state.sevenDayUtil {
            Button("7 天用量：\(Int(sevenDay))%（重置：\(state.formatResetTime(state.sevenDayResetsAt))）") {}
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

        Button("📈 查看趋势") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "trend")
        }

        Divider()

        Button("⟳ 刷新") {
            Task { await state.refresh() }
        }
        .disabled(state.isLoading)

        Button("⚙ 设置...") {
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

        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
    }
}
