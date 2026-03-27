import XCTest
@testable import ClaudeQuotaMenubar

final class UsageDataTests: XCTestCase {

    func testDecodeFullResponse() throws {
        let json = """
        {
            "five_hour": { "utilization": 83.5, "resets_at": "2026-03-26T15:00:00Z" },
            "seven_day": { "utilization": 22.0, "resets_at": "2026-03-30T00:00:00Z" },
            "seven_day_opus": { "utilization": 45.0, "resets_at": "2026-03-30T00:00:00Z" },
            "seven_day_sonnet": { "utilization": 18.0, "resets_at": "2026-03-30T00:00:00Z" }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization, 83.5)
        XCTAssertEqual(response.sevenDay?.utilization, 22.0)
        XCTAssertEqual(response.sevenDayOpus?.utilization, 45.0)
        XCTAssertEqual(response.sevenDaySonnet?.utilization, 18.0)
    }

    func testDecodePartialResponse() throws {
        let json = """
        {
            "five_hour": { "utilization": 10.0, "resets_at": "2026-03-26T15:00:00Z" }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization, 10.0)
        XCTAssertNil(response.sevenDay)
        XCTAssertNil(response.sevenDayOpus)
        XCTAssertNil(response.sevenDaySonnet)
    }

    func testUsageSampleFromResponse() throws {
        let json = """
        {
            "five_hour": { "utilization": 83.5, "resets_at": "2026-03-26T15:00:00Z" },
            "seven_day": { "utilization": 22.0, "resets_at": "2026-03-30T00:00:00Z" },
            "seven_day_opus": { "utilization": 45.0, "resets_at": "2026-03-30T00:00:00Z" },
            "seven_day_sonnet": { "utilization": 18.0, "resets_at": "2026-03-30T00:00:00Z" }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        let sample = UsageSample(from: response)

        XCTAssertEqual(sample.fiveHourUtil, 83.5)
        XCTAssertEqual(sample.sevenDayUtil, 22.0)
        XCTAssertEqual(sample.opusUtil, 45.0)
        XCTAssertEqual(sample.sonnetUtil, 18.0)
        XCTAssertNotNil(sample.timestamp)
    }

    func testColorForUtilization() {
        XCTAssertEqual(UsageColor.for(utilization: 30.0), .green)
        XCTAssertEqual(UsageColor.for(utilization: 50.0), .yellow)
        XCTAssertEqual(UsageColor.for(utilization: 65.0), .yellow)
        XCTAssertEqual(UsageColor.for(utilization: 80.1), .red)
        XCTAssertEqual(UsageColor.for(utilization: 100.0), .red)
    }
}
