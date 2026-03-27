import XCTest
@testable import ClaudeQuotaMenubar

final class LoginWebViewTests: XCTestCase {
    func testParseOrganizationId() throws {
        let json = """
        [
            {
                "uuid": "abc12345-1234-5678-9abc-def012345678",
                "name": "Personal",
                "settings": {}
            }
        ]
        """
        let orgId = LoginCredentialExtractor.parseOrganizationId(from: json)
        XCTAssertEqual(orgId, "abc12345-1234-5678-9abc-def012345678")
    }

    func testParseOrganizationIdEmptyArray() {
        let json = "[]"
        let orgId = LoginCredentialExtractor.parseOrganizationId(from: json)
        XCTAssertNil(orgId)
    }

    func testParseOrganizationIdInvalidJSON() {
        let orgId = LoginCredentialExtractor.parseOrganizationId(from: "not json")
        XCTAssertNil(orgId)
    }
}
