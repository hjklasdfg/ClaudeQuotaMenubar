import XCTest
@testable import ClaudeQuotaMenubar

final class QuotaFetcherTests: XCTestCase {

    func testParseValidJSON() throws {
        let json = """
        {
            "five_hour": { "utilization": 55.0, "resets_at": "2026-03-26T15:00:00Z" },
            "seven_day": { "utilization": 30.0, "resets_at": "2026-03-30T00:00:00Z" }
        }
        """
        let response = try QuotaFetcher.parseResponse(json)
        XCTAssertEqual(response.fiveHour?.utilization, 55.0)
        XCTAssertEqual(response.sevenDay?.utilization, 30.0)
    }

    func testParseInvalidJSON() {
        XCTAssertThrowsError(try QuotaFetcher.parseResponse("not json"))
    }

    func testParseHTMLError() {
        let html = "<html><body>Access Denied</body></html>"
        XCTAssertThrowsError(try QuotaFetcher.parseResponse(html))
    }
}
