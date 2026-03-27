import XCTest
@testable import ClaudeQuotaMenubar

final class KeychainServiceTests: XCTestCase {

    let service = KeychainService(serviceName: "com.claude-quota-menubar.test")

    override func tearDown() {
        service.delete(account: "sessionKey")
        service.delete(account: "organizationId")
        super.tearDown()
    }

    func testSaveAndLoad() {
        let saved = service.save(account: "sessionKey", value: "sk-ant-sid01-test123")
        XCTAssertTrue(saved)

        let loaded = service.load(account: "sessionKey")
        XCTAssertEqual(loaded, "sk-ant-sid01-test123")
    }

    func testLoadMissing() {
        let loaded = service.load(account: "nonexistent")
        XCTAssertNil(loaded)
    }

    func testUpdate() {
        service.save(account: "sessionKey", value: "old-value")
        let updated = service.save(account: "sessionKey", value: "new-value")
        XCTAssertTrue(updated)

        let loaded = service.load(account: "sessionKey")
        XCTAssertEqual(loaded, "new-value")
    }

    func testDelete() {
        service.save(account: "sessionKey", value: "to-delete")
        service.delete(account: "sessionKey")

        let loaded = service.load(account: "sessionKey")
        XCTAssertNil(loaded)
    }

    func testHasCredentials() {
        XCTAssertFalse(service.hasCredentials)

        service.save(account: "sessionKey", value: "sk-test")
        XCTAssertFalse(service.hasCredentials) // need both

        service.save(account: "organizationId", value: "org-uuid")
        XCTAssertTrue(service.hasCredentials)
    }
}
