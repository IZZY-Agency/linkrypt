import XCTest
@testable import LinkryptCore

private func hex(_ s: String) -> Data {
    var d = Data(); var i = s.startIndex
    while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }
    return d
}

final class RecipientCryptoTests: XCTestCase {
    private let key = Data(repeating: 0x11, count: 32)
    private let iv = Data(repeating: 0x22, count: 12)

    func testDecryptV0RoundTrip() throws {
        let pt = Data("plain v0".utf8)
        let ct = try Crypto.aesGcmEncrypt(key: key, iv: iv, plaintext: pt)
        XCTAssertEqual(try RecipientCrypto.decrypt(ciphertext: ct, key: key, iv: iv, padding: .v0), pt)
    }

    func testDecryptV1UnpadsRoundTrip() throws {
        let pt = Data("a padded secret".utf8)
        let ct = try Crypto.sealPaddedV1(key: key, iv: iv, plaintext: pt)
        XCTAssertEqual(try RecipientCrypto.decrypt(ciphertext: ct, key: key, iv: iv, padding: .v1), pt)
    }

    func testDecryptV1TreatedAsV0StaysPadded() throws {
        let pt = Data("x".utf8)
        let ct = try Crypto.sealPaddedV1(key: key, iv: iv, plaintext: pt)
        let asV0 = try RecipientCrypto.decrypt(ciphertext: ct, key: key, iv: iv, padding: .v0)
        XCTAssertGreaterThan(asV0.count, pt.count)   // still the padded envelope
    }

    func testPassphraseAttemptPbkdf2() throws {
        let out = try RecipientCrypto.passphraseAttempt(
            passphrase: "correct horse battery staple",
            salt: hex("0102030405060708090a0b0c0d0e0f10"), kdf: .pbkdf2)
        XCTAssertEqual(out, Base64URL.encode(hex("0008e69b89ffac1aa7bb1f44289ba65afaa711dd450f0aab6c322e4cd57bb216")))
    }
    func testPassphraseAttemptArgon2id() throws {
        let out = try RecipientCrypto.passphraseAttempt(
            passphrase: "correct horse battery staple",
            salt: hex("0102030405060708090a0b0c0d0e0f10"), kdf: .argon2id)
        XCTAssertEqual(out, Base64URL.encode(hex("d8ebeb50632cc1993711eda85db155a107f0fb1cafab88a3a79f3d4661ac7a0c")))
    }
}
