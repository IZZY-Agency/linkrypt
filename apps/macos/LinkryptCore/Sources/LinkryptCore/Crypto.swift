import Foundation
import CryptoKit
import CommonCrypto

public enum CryptoError: Error, Equatable {
    case ciphertextTooShort
}

public enum Crypto {
    public static let keyLen = 32
    public static let ivLen = 12
    public static let tagLen = 16
    public static let pbkdf2Iterations: UInt32 = 600_000
    public static let saltLen = 16
    public static let pbkdf2OutLen = 32

    /// Largest text-share plaintext. Chosen so the v1-padded + GCM-sealed
    /// ciphertext lands exactly in the 1 MiB bucket (+16-byte tag), staying
    /// under the server's MAX_TEXT_PAYLOAD (1,126,400). Mirrors the web
    /// client's `MAX_TEXT_PLAINTEXT`.
    public static let maxTextPlaintextBytes = 1024 * 1024 - 5

    /// Single source of truth for the text-share size guard: whether a
    /// plaintext of `byteCount` may go out as a text share. Larger payloads
    /// must use a file share — a padded text blob would cross into a bigger
    /// bucket and be rejected at finalize. Used by both the composer and the
    /// clipboard hotkey guards.
    public static func textPlaintextFitsCap(_ byteCount: Int) -> Bool {
        byteCount <= maxTextPlaintextBytes
    }

    public static func randomBytes(_ n: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: n)
        let status = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes)
    }

    /// AES-256-GCM. Returns ciphertext ‖ tag (16-byte tag appended), matching
    /// the JS WebCrypto / Rust `aes_encrypt` wire format. The 12-byte `iv` is
    /// the GCM nonce and travels separately in the URL fragment.
    public static func aesGcmEncrypt(key: Data, iv: Data, plaintext: Data) throws -> Data {
        precondition(key.count == keyLen, "AES key must be \(keyLen) bytes, got \(key.count)")
        precondition(iv.count == ivLen,   "AES IV must be \(ivLen) bytes, got \(iv.count)")
        let box = try AES.GCM.seal(plaintext,
                                   using: SymmetricKey(data: key),
                                   nonce: try AES.GCM.Nonce(data: iv))
        return box.ciphertext + box.tag
    }

    /// Inverse of `aesGcmEncrypt`. Input is `ct‖tag` (last `tagLen` bytes are
    /// the GCM tag); the 12-byte `iv` is the nonce. Throws
    /// `CryptoError.ciphertextTooShort` for a sub-tag input, or a CryptoKit
    /// error on a bad key/tag (tamper / wrong key).
    public static func aesGcmDecrypt(key: Data, iv: Data, ciphertext: Data) throws -> Data {
        precondition(key.count == keyLen, "AES key must be \(keyLen) bytes, got \(key.count)")
        precondition(iv.count == ivLen,   "AES IV must be \(ivLen) bytes, got \(iv.count)")
        guard ciphertext.count >= tagLen else { throw CryptoError.ciphertextTooShort }
        let ct = Data(ciphertext.prefix(ciphertext.count - tagLen))
        let tag = Data(ciphertext.suffix(tagLen))
        let box = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: iv), ciphertext: ct, tag: tag)
        return try AES.GCM.open(box, using: SymmetricKey(data: key))
    }

    /// PBKDF2-HMAC-SHA256, 600k iterations, 32-byte output. Matches the Rust
    /// CLI `pbkdf2_derive` and the legacy web KDF. CryptoKit has no PBKDF2, so
    /// this uses CommonCrypto. Used only when passphrase 2FA is enabled.
    public static func pbkdf2(passphrase: String, salt: Data) -> Data {
        let pwd = Array(passphrase.utf8)
        var out = [UInt8](repeating: 0, count: pbkdf2OutLen)
        let saltBytes = [UInt8](salt)
        let status = saltBytes.withUnsafeBufferPointer { saltPtr in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                pwd, pwd.count,
                saltPtr.baseAddress, saltPtr.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                pbkdf2Iterations,
                &out, out.count
            )
        }
        precondition(status == kCCSuccess, "PBKDF2 failed")
        return Data(out)
    }
}
