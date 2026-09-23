import XCTest
@testable import LinkryptCore

final class WhoAmIDecodeTests: XCTestCase {
    private func decode(_ json: String) throws -> WhoAmI {
        try JSONDecoder().decode(WhoAmI.self, from: Data(json.utf8))
    }

    func testDecodesEmail() throws {
        let w = try decode(#"{"userId":"u","email":"a@b.com","scopes":["shares:read"]}"#)
        XCTAssertEqual(w.userId, "u")
        XCTAssertEqual(w.email, "a@b.com")
        XCTAssertEqual(w.scopes, ["shares:read"])
    }

    func testDecodesMissingEmailAsNil() throws {       // back-compat: older server
        let w = try decode(#"{"userId":"u","scopes":[]}"#)
        XCTAssertNil(w.email)
    }

    func testDecodesExplicitNullEmailAsNil() throws {  // narrow-scope token branch
        let w = try decode(#"{"userId":"u","email":null,"scopes":[]}"#)
        XCTAssertNil(w.email)
    }
}
