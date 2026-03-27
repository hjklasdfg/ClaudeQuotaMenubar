import XCTest
@testable import ClaudeQuotaMenubar

final class QuotaStoreTests: XCTestCase {

    var store: QuotaStore!

    override func setUp() {
        super.setUp()
        store = try! QuotaStore(path: ":memory:")
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    func testInsertAndFetchLatest() throws {
        let sample = UsageSample(
            id: nil, timestamp: Date(), fiveHourUtil: 83.5, fiveHourResetsAt: "2026-03-26T15:00:00Z",
            sevenDayUtil: 22.0, sevenDayResetsAt: "2026-03-30T00:00:00Z", opusUtil: 45.0, sonnetUtil: 18.0
        )
        try store.insert(sample)

        let latest = try store.fetchLatest()
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.fiveHourUtil, 83.5)
        XCTAssertEqual(latest?.sevenDayUtil, 22.0)
        XCTAssertEqual(latest?.opusUtil, 45.0)
        XCTAssertEqual(latest?.sonnetUtil, 18.0)
    }

    func testFetchSamplesSince() throws {
        let now = Date()
        for i in 0..<5 {
            let sample = UsageSample(
                id: nil, timestamp: now.addingTimeInterval(Double(i) * -300),
                fiveHourUtil: Double(i * 10), fiveHourResetsAt: nil,
                sevenDayUtil: nil, sevenDayResetsAt: nil, opusUtil: nil, sonnetUtil: nil
            )
            try store.insert(sample)
        }

        let oneHourAgo = now.addingTimeInterval(-3600)
        let samples = try store.fetchSamples(since: oneHourAgo)
        XCTAssertEqual(samples.count, 5)
    }

    func testPurgeOldRecords() throws {
        let old = Date().addingTimeInterval(-31 * 24 * 3600)
        let recent = Date()

        try store.insert(UsageSample(
            id: nil, timestamp: old, fiveHourUtil: 10.0, fiveHourResetsAt: nil,
            sevenDayUtil: nil, sevenDayResetsAt: nil, opusUtil: nil, sonnetUtil: nil
        ))
        try store.insert(UsageSample(
            id: nil, timestamp: recent, fiveHourUtil: 50.0, fiveHourResetsAt: nil,
            sevenDayUtil: nil, sevenDayResetsAt: nil, opusUtil: nil, sonnetUtil: nil
        ))

        let purged = try store.purgeOlderThan(days: 30)
        XCTAssertEqual(purged, 1)

        let all = try store.fetchSamples(since: old)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.fiveHourUtil, 50.0)
    }

    func testFetchSampleOneHourAgo() throws {
        let now = Date()
        try store.insert(UsageSample(
            id: nil, timestamp: now.addingTimeInterval(-65 * 60),
            fiveHourUtil: 40.0, fiveHourResetsAt: nil,
            sevenDayUtil: nil, sevenDayResetsAt: nil, opusUtil: nil, sonnetUtil: nil
        ))
        try store.insert(UsageSample(
            id: nil, timestamp: now,
            fiveHourUtil: 52.0, fiveHourResetsAt: nil,
            sevenDayUtil: nil, sevenDayResetsAt: nil, opusUtil: nil, sonnetUtil: nil
        ))

        let hourAgoSample = try store.fetchSampleClosestTo(date: now.addingTimeInterval(-3600))
        XCTAssertNotNil(hourAgoSample)
        XCTAssertEqual(hourAgoSample?.fiveHourUtil, 40.0)
    }
}
