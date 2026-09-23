import XCTest
@testable import LinkryptCore

final class SecretFileTests: XCTestCase {
    func testValidUtf8WithinCap() {
        let text = "API_KEY=abc123\nDB_URL=postgres://x\n"
        guard case .success(let out) = SecretFile.decode(Data(text.utf8)) else {
            return XCTFail("expected .success")
        }
        XCTAssertEqual(out, text)
    }

    func testExactlyAtCapSucceeds() {
        let data = Data(repeating: 0x41, count: Crypto.maxTextPlaintextBytes) // 'A'
        guard case .success = SecretFile.decode(data) else { return XCTFail("expected .success at cap") }
    }

    func testOneByteOverCapIsTooLarge() {
        let data = Data(repeating: 0x41, count: Crypto.maxTextPlaintextBytes + 1)
        guard case .failure(let e) = SecretFile.decode(data), e == .tooLarge else {
            return XCTFail("expected .tooLarge")
        }
    }

    func testInvalidUtf8IsNotUtf8() {
        let data = Data([0x68, 0x69, 0xff]) // 0xFF is never valid UTF-8
        guard case .failure(let e) = SecretFile.decode(data), e == .notUTF8 else {
            return XCTFail("expected .notUTF8")
        }
    }
}
