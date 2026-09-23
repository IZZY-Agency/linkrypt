import XCTest
@testable import LinkryptCore

final class ShareLinkParseTests: XCTestCase {
    private let key = Data(repeating: 0xab, count: 32)
    private let iv = Data(repeating: 0xcd, count: 12)

    func testParsesLangURL() {
        let u = ShareLink.recipientURL(baseURL: "https://linkrypt.sh", id: "abc123", key: key, iv: iv)
        let p = ShareLink.parse(u)
        XCTAssertEqual(p?.baseURL, "https://linkrypt.sh")
        XCTAssertEqual(p?.id, "abc123")
        XCTAssertEqual(p?.key, key)
        XCTAssertEqual(p?.iv, iv)
    }

    func testParsesNoLangURL() {
        let u = "https://linkrypt.sh/s/xyz#k=\(Base64URL.encode(key))&iv=\(Base64URL.encode(iv))"
        XCTAssertEqual(ShareLink.parse(u)?.id, "xyz")
    }

    func testPreservesPort() {
        let u = "https://example.com:8443/en/s/p1#k=\(Base64URL.encode(key))&iv=\(Base64URL.encode(iv))"
        XCTAssertEqual(ShareLink.parse(u)?.baseURL, "https://example.com:8443")
    }

    func testRejectsNonHttps() {
        let u = "http://linkrypt.sh/en/s/x#k=\(Base64URL.encode(key))&iv=\(Base64URL.encode(iv))"
        XCTAssertNil(ShareLink.parse(u))
    }
    func testRejectsUserinfo() {
        let u = "https://evil:pw@linkrypt.sh/en/s/x#k=\(Base64URL.encode(key))&iv=\(Base64URL.encode(iv))"
        XCTAssertNil(ShareLink.parse(u))
    }
    func testRejectsWrongPath() {
        let u = "https://linkrypt.sh/en/notshare/x#k=\(Base64URL.encode(key))&iv=\(Base64URL.encode(iv))"
        XCTAssertNil(ShareLink.parse(u))
    }
    func testRejectsNonLanguageTwoCharSegment() {
        // 2 chars but not [a-z]{2} → not a locale segment
        let u = "https://linkrypt.sh/12/s/x#k=\(Base64URL.encode(key))&iv=\(Base64URL.encode(iv))"
        XCTAssertNil(ShareLink.parse(u))
    }
    func testRejectsExtraPathSegment() {
        let u = "https://linkrypt.sh/s/x/extra#k=\(Base64URL.encode(key))&iv=\(Base64URL.encode(iv))"
        XCTAssertNil(ShareLink.parse(u))
    }
    func testRejectsMissingFragment() {
        XCTAssertNil(ShareLink.parse("https://linkrypt.sh/en/s/x"))
    }
    func testRejectsMissingKeyOrIv() {
        XCTAssertNil(ShareLink.parse("https://linkrypt.sh/en/s/x#k=\(Base64URL.encode(key))"))
    }
    func testRejectsBadBase64() {
        XCTAssertNil(ShareLink.parse("https://linkrypt.sh/en/s/x#k=@@@&iv=@@@"))
    }
    func testRejectsWrongKeyLength() {
        let shortKey = Base64URL.encode(Data(repeating: 1, count: 16))
        let u = "https://linkrypt.sh/en/s/x#k=\(shortKey)&iv=\(Base64URL.encode(iv))"
        XCTAssertNil(ShareLink.parse(u))
    }

    func testRequestURLIsKeyless() {
        XCTAssertEqual(ShareLink.requestURL(baseURL: "https://linkrypt.sh", id: "abc"),
                       "https://linkrypt.sh/en/r/abc")
    }
    func testRequestURLStripsTrailingSlashAndUsesLang() {
        XCTAssertEqual(ShareLink.requestURL(baseURL: "https://linkrypt.sh/", lang: "fr", id: "x"),
                       "https://linkrypt.sh/fr/r/x")
    }
}
