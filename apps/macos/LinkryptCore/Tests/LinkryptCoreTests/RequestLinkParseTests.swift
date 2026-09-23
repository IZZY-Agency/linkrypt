import XCTest
@testable import LinkryptCore

final class RequestLinkParseTests: XCTestCase {
    func testParsesLangRequestLink() {
        let p = RequestLink.parse("https://linkrypt.sh/en/r/abc123")
        XCTAssertEqual(p?.id, "abc123")
        XCTAssertEqual(p?.baseURL, "https://linkrypt.sh")
    }
    func testParsesNoLangRequestLink() {
        let p = RequestLink.parse("https://linkrypt.sh/r/xyz")
        XCTAssertEqual(p?.id, "xyz")
        XCTAssertEqual(p?.baseURL, "https://linkrypt.sh")
    }
    func testRejectsNonRequestPath() {
        XCTAssertNil(RequestLink.parse("https://linkrypt.sh/en/s/abc"))
    }
    func testRejectsNonHttps() {
        XCTAssertNil(RequestLink.parse("http://linkrypt.sh/en/r/abc"))
    }
    func testRejectsUserinfo() {
        XCTAssertNil(RequestLink.parse("https://u:p@linkrypt.sh/en/r/abc"))
    }
}
