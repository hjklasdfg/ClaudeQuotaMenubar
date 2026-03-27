import SwiftUI
import Charts

enum TrendMetric: String, CaseIterable {
    case fiveHour = "5h"
    case sevenDay = "7d"
    case opus = "Opus"
    case sonnet = "Sonnet"
}

enum TrendRange: String, CaseIterable {
    case day = "24h"
    case week = "7d"
    case month = "30d"

    var seconds: TimeInterval {
        switch self {
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        case .month: return 30 * 24 * 3600
        }
    }
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

struct TrendWindow: View {
    let store: QuotaStore?
    @State private var metric: TrendMetric = .fiveHour
    @State private var range: TrendRange = .day
    @State private var dataPoints: [ChartDataPoint] = []

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Picker("Metric", selection: $metric) {
                    ForEach(TrendMetric.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer()

                Picker("Range", selection: $range) {
                    ForEach(TrendRange.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            if dataPoints.isEmpty {
                ContentUnavailableView("No data yet", systemImage: "chart.line.downtrend.xyaxis",
                    description: Text("Usage data will appear after a few polling cycles"))
                .frame(maxHeight: .infinity)
            } else {
                Chart(dataPoints) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Usage %", point.value)
                    )
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Usage %", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue.opacity(0.1))
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)%")
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel(format: range == .day ? .dateTime.hour().minute() : .dateTime.month().day())
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 350)
        .onChange(of: metric) { loadData() }
        .onChange(of: range) { loadData() }
        .onAppear { loadData() }
    }

    private func loadData() {
        guard let store else { return }
        let since = Date().addingTimeInterval(-range.seconds)
        guard let samples = try? store.fetchSamples(since: since) else { return }

        dataPoints = samples.compactMap { sample in
            let value: Double?
            switch metric {
            case .fiveHour: value = sample.fiveHourUtil
            case .sevenDay: value = sample.sevenDayUtil
            case .opus: value = sample.opusUtil
            case .sonnet: value = sample.sonnetUtil
            }
            guard let v = value else { return nil }
            return ChartDataPoint(timestamp: sample.timestamp, value: v)
        }
    }
}
