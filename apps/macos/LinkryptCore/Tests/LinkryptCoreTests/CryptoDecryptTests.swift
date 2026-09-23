import XCTest
@testable import LinkryptCore

private func hexToData(_ s: String) -> Data {
    var d = Data(); var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        d.append(UInt8(s[i..<j], radix: 16)!); i = j
    }
    return d
}
private struct Vec: Decodable { let name: String; let key: String?; let iv: String?; let pt: String?; let ct: String? }

final class CryptoDecryptTests: XCTestCase {
    private func loadVectors() throws -> [Vec] {
        let here = URL(fileURLWithPath: #filePath)
        let fixture = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("cli/tests/fixtures/vectors.json").standardizedFileURL
        return try JSONDecoder().decode([Vec].self, from: Data(contentsOf: fixture))
    }

    func testDecryptsGoldenVectorsBackToPlaintext() throws {
        for v in try loadVectors() where v.ct != nil {
            guard let key = v.key, let iv = v.iv, let pt = v.pt, let ct = v.ct else { continue }
            let got = try Crypto.aesGcmDecrypt(key: hexToData(key), iv: hexToData(iv), ciphertext: hexToData(ct))
            XCTAssertEqual(got, hexToData(pt), "decrypt mismatch for \(v.name)")
        }
    }

    func testTamperedTagThrows() throws {
        let key = Data(repeating: 0, count: 32), iv = Data(repeating: 0, count: 12)
        var sealed = try Crypto.aesGcmEncrypt(key: key, iv: iv, plaintext: Data("hi".utf8))
        sealed[sealed.count - 1] ^= 0xff   // flip a tag byte
        XCTAssertThrowsError(try Crypto.aesGcmDecrypt(key: key, iv: iv, ciphertext: sealed))
    }

    func testCiphertextShorterThanTagThrowsControlled() {
        let key = Data(repeating: 0, count: 32), iv = Data(repeating: 0, count: 12)
        XCTAssertThrowsError(try Crypto.aesGcmDecrypt(key: key, iv: iv, ciphertext: Data(repeating: 0, count: 10))) { err in
            XCTAssertEqual(err as? CryptoError, .ciphertextTooShort)
        }
    }
}
