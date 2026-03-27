import SwiftUI

// MARK: - API Response

struct UsagePeriod: Codable {
    let utilization: Double
    let resetsAt: String

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct UsageResponse: Codable {
    let fiveHour: UsagePeriod?
    let sevenDay: UsagePeriod?
    let sevenDayOpus: UsagePeriod?
    let sevenDaySonnet: UsagePeriod?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

// MARK: - Local Storage Model

struct UsageSample {
    let id: Int64?
    let timestamp: Date
    let fiveHourUtil: Double?
    let fiveHourResetsAt: String?
    let sevenDayUtil: Double?
    let sevenDayResetsAt: String?
    let opusUtil: Double?
    let sonnetUtil: Double?

    init(from response: UsageResponse, at date: Date = Date()) {
        self.id = nil
        self.timestamp = date
        self.fiveHourUtil = response.fiveHour?.utilization
        self.fiveHourResetsAt = response.fiveHour?.resetsAt
        self.sevenDayUtil = response.sevenDay?.utilization
        self.sevenDayResetsAt = response.sevenDay?.resetsAt
        self.opusUtil = response.sevenDayOpus?.utilization
        self.sonnetUtil = response.sevenDaySonnet?.utilization
    }

    init(id: Int64?, timestamp: Date, fiveHourUtil: Double?, fiveHourResetsAt: String?,
         sevenDayUtil: Double?, sevenDayResetsAt: String?, opusUtil: Double?, sonnetUtil: Double?) {
        self.id = id
        self.timestamp = timestamp
        self.fiveHourUtil = fiveHourUtil
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayUtil = sevenDayUtil
        self.sevenDayResetsAt = sevenDayResetsAt
        self.opusUtil = opusUtil
        self.sonnetUtil = sonnetUtil
    }
}

// MARK: - Color Coding

enum UsageColor {
    static func `for`(utilization: Double) -> Color {
        switch utilization {
        case ..<50:
            return .green
        case 50..<80:
            return .yellow
        default:
            return .red
        }
    }
}
