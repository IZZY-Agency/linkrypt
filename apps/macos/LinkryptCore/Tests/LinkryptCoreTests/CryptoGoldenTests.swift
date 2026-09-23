import XCTest
@testable import LinkryptCore

private struct Vector: Decodable {
    let name: String
    let key: String?; let iv: String?; let pt: String?; let ct: String?
    let passphrase: String?; let salt: String?; let out: String?
}

private func hexToData(_ s: String) -> Data {
    var d = Data(); var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        d.append(UInt8(s[i..<j], radix: 16)!); i = j
    }
    return d
}
private func dataToHex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

final class CryptoGoldenTests: XCTestCase {
    private func loadVectors() throws -> [Vector] {
        let here = URL(fileURLWithPath: #filePath)              // .../Tests/LinkryptCoreTests/CryptoGoldenTests.swift
        let fixture = here
            .deletingLastPathComponent()  // LinkryptCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // LinkryptCore
            .deletingLastPathComponent()  // macos
            .deletingLastPathComponent()  // apps
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("cli/tests/fixtures/vectors.json")
            .standardizedFileURL
        let data = try Data(contentsOf: fixture)
        return try JSONDecoder().decode([Vector].self, from: data)
    }

    func testGoldenVectorsByteForByte() throws {
        let vectors = try loadVectors()
        XCTAssertEqual(vectors.count, 5, "expected 5 shared vectors")
        for v in vectors {
            if let key = v.key, let iv = v.iv, let pt = v.pt, let ct = v.ct {
                let got = try Crypto.aesGcmEncrypt(key: hexToData(key), iv: hexToData(iv), plaintext: hexToData(pt))
                XCTAssertEqual(dataToHex(got), ct, "AES mismatch for \(v.name)")
            } else if let pass = v.passphrase, let salt = v.salt, let out = v.out {
                let got = Crypto.pbkdf2(passphrase: pass, salt: hexToData(salt))
                XCTAssertEqual(dataToHex(got), out, "PBKDF2 mismatch for \(v.name)")
            } else {
                XCTFail("unrecognized vector \(v.name)")
            }
        }
    }
}
