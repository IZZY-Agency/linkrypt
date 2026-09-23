import XCTest
@testable import LinkryptCore

final class Base64URLTests: XCTestCase {
    func testEncodeNoPadding() {
        XCTAssertEqual(Base64URL.encode(Data([0xfb, 0xff])), "-_8")
    }
    func testDecodeRoundTrip() {
        XCTAssertEqual(Base64URL.decode("-_8"), Data([0xfb, 0xff]))
    }
    func testEmpty() {
        XCTAssertEqual(Base64URL.encode(Data()), "")
        XCTAssertEqual(Base64URL.decode(""), Data())
    }
    func testDecodeRejectsInvalid() {
        XCTAssertNil(Base64URL.decode("not base64!!"))
    }
}
