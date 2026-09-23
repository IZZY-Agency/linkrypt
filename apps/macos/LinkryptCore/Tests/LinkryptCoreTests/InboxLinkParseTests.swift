import XCTest
@testable import LinkryptCore

final class InboxLinkParseTests: XCTestCase {
    private let key = Data(repeating: 0xab, count: 32)
    private let iv = Data(repeating: 0xcd, count: 12)

    func testParsesInboxLink() {
        let frag = ShareLink.buildFragment(key: key, iv: iv)
        let p = InboxLink.parse("https://linkrypt.sh/app/inbox/abc123#\(frag)")
        XCTAssertEqual(p?.id, "abc123")
        XCTAssertEqual(p?.baseURL, "https://linkrypt.sh")
        XCTAssertEqual(p?.key, key)
        XCTAssertEqual(p?.iv, iv)
    }
    func testRejectsNonInboxPath() {
        let frag = ShareLink.buildFragment(key: key, iv: iv)
        XCTAssertNil(InboxLink.parse("https://linkrypt.sh/en/s/abc#\(frag)"))
    }
    func testRejectsMissingFragment() {
        XCTAssertNil(InboxLink.parse("https://linkrypt.sh/app/inbox/abc123"))
    }
    func testRejectsNonHttps() {
        let frag = ShareLink.buildFragment(key: key, iv: iv)
        XCTAssertNil(InboxLink.parse("http://linkrypt.sh/app/inbox/abc#\(frag)"))
    }
    func testRejectsUserinfo() {
        let frag = ShareLink.buildFragment(key: key, iv: iv)
        XCTAssertNil(InboxLink.parse("https://user:pass@linkrypt.sh/app/inbox/abc#\(frag)"))
    }
    func testRejectsWrongKeyLength() {
        let shortKey = ShareLink.buildFragment(key: Data(repeating: 1, count: 16), iv: iv)
        XCTAssertNil(InboxLink.parse("https://linkrypt.sh/app/inbox/abc#\(shortKey)"))
    }
}
