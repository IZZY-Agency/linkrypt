import XCTest
@testable import LinkryptCore

final class ShareLinkTests: XCTestCase {
    func testBuildFragment() {
        let key = Data(repeating: 0xAB, count: 32)
        let iv = Data(repeating: 0xCD, count: 12)
        let frag = ShareLink.buildFragment(key: key, iv: iv)
        XCTAssertTrue(frag.hasPrefix("k="))
        XCTAssertTrue(frag.contains("&iv="))
        XCTAssertEqual(frag, "k=\(Base64URL.encode(key))&iv=\(Base64URL.encode(iv))")
    }
    func testRecipientURLHasMandatoryLang() {
        let url = ShareLink.recipientURL(baseURL: "https://linkrypt.sh",
                                         lang: "en", id: "a7f3k9",
                                         key: Data(repeating: 1, count: 32),
                                         iv: Data(repeating: 2, count: 12))
        XCTAssertTrue(url.hasPrefix("https://linkrypt.sh/en/s/a7f3k9#k="))
        XCTAssertTrue(url.contains("&iv="))
    }
    func testParseFragmentRoundTrip() {
        let key = Crypto.randomBytes(32), iv = Crypto.randomBytes(12)
        let frag = ShareLink.buildFragment(key: key, iv: iv)
        let parsed = ShareLink.parseFragment(frag)
        XCTAssertEqual(parsed?.key, key)
        XCTAssertEqual(parsed?.iv, iv)
    }
}
