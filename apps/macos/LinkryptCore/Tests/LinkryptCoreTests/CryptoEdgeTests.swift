import XCTest
import CryptoKit
@testable import LinkryptCore

final class CryptoEdgeTests: XCTestCase {
    func testRoundTrip() throws {
        let key = Crypto.randomBytes(32)
        let iv = Crypto.randomBytes(12)
        let pt = Data("hello".utf8)
        let ct = try Crypto.aesGcmEncrypt(key: key, iv: iv, plaintext: pt)
        // ct = ciphertext ‖ 16-byte tag
        XCTAssertEqual(ct.count, pt.count + 16)
        // decrypt via CryptoKit to confirm tag layout
        let nonce = try AES.GCM.Nonce(data: iv)
        let body = ct.prefix(ct.count - 16)
        let tag = ct.suffix(16)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: body, tag: tag)
        let back = try AES.GCM.open(box, using: SymmetricKey(data: key))
        XCTAssertEqual(back, pt)
    }
    func testRandomLengthAndUniqueness() {
        XCTAssertEqual(Crypto.randomBytes(12).count, 12)
        XCTAssertNotEqual(Crypto.randomBytes(32), Crypto.randomBytes(32))
    }
}

extension CryptoEdgeTests {
    func testPbkdf2Length() {
        let out = Crypto.pbkdf2(passphrase: "any", salt: Data(repeating: 1, count: 16))
        XCTAssertEqual(out.count, 32)
    }
}
