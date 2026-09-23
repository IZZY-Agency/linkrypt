import XCTest
@testable import LinkryptCore

/// Byte-for-byte parity gate for the Argon2id passphrase KDF. The golden
/// outputs were generated from the REAL web client's `deriveArgon2idHash`
/// (hash-wasm, OWASP 2024 params: m=64 MiB, t=3,
/// p=1, 32-byte output, Argon2id v1.3). The Swift `Crypto.argon2id` must
/// reproduce them exactly so a macOS-created passphrase share opens on the
/// web/CLI recipient.
final class CryptoArgon2Tests: XCTestCase {

    private func hexToData(_ s: String) -> Data {
        var d = Data(); var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            d.append(UInt8(s[i..<j], radix: 16)!); i = j
        }
        return d
    }
    private func dataToHex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    func testArgon2idGoldenVectorAscii() throws {
        let out = try Crypto.argon2id(passphrase: "correct horse battery staple",
                                      salt: hexToData("0102030405060708090a0b0c0d0e0f10"))
        XCTAssertEqual(dataToHex(out),
                       "d8ebeb50632cc1993711eda85db155a107f0fb1cafab88a3a79f3d4661ac7a0c")
    }

    func testArgon2idGoldenVectorUnicode() throws {
        let out = try Crypto.argon2id(passphrase: "café 🦀 password",
                                      salt: hexToData("a1a2a3a4a5a6a7a8a9aaabacadaeafb0"))
        XCTAssertEqual(dataToHex(out),
                       "08780043dee35850e2cbe88d0e1dd0157ea00a132263b00dc4f8c38c9779d26a")
    }

    func testArgon2idOutputIs32Bytes() throws {
        let out = try Crypto.argon2id(passphrase: "x", salt: hexToData("0102030405060708090a0b0c0d0e0f10"))
        XCTAssertEqual(out.count, 32)
    }

    func testArgon2idIsDeterministic() throws {
        let salt = hexToData("0102030405060708090a0b0c0d0e0f10")
        XCTAssertEqual(try Crypto.argon2id(passphrase: "p@ss", salt: salt),
                       try Crypto.argon2id(passphrase: "p@ss", salt: salt))
    }

    func testArgon2idDiffersFromPbkdf2() throws {
        // Sanity: confirm we're really running Argon2id, not accidentally the
        // legacy PBKDF2 path. Different KDFs MUST produce different outputs.
        let salt = hexToData("0102030405060708090a0b0c0d0e0f10")
        XCTAssertNotEqual(try Crypto.argon2id(passphrase: "shared", salt: salt),
                          Crypto.pbkdf2(passphrase: "shared", salt: salt))
    }
}
