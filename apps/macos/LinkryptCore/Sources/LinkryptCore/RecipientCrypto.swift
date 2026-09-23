import Foundation

/// Recipient-side composition over the existing crypto primitives. Pure.
public enum RecipientCrypto {
    /// AES-GCM decrypt, then unwrap the v1 padding envelope if present.
    public static func decrypt(ciphertext: Data, key: Data, iv: Data,
                               padding: PaddingVersion) throws -> Data {
        let pt = try Crypto.aesGcmDecrypt(key: key, iv: iv, ciphertext: ciphertext)
        return padding == .v1 ? try Padding.unpad(pt) : pt
    }

    /// Derived passphrase attempt to POST as `passphraseAttempt` — never the raw
    /// passphrase. base64url of the per-share KDF output (Argon2id or PBKDF2).
    public static func passphraseAttempt(passphrase: String, salt: Data,
                                         kdf: PassphraseKdf) throws -> String {
        let hash: Data
        switch kdf {
        case .argon2id: hash = try Crypto.argon2id(passphrase: passphrase, salt: salt)
        case .pbkdf2:   hash = Crypto.pbkdf2(passphrase: passphrase, salt: salt)
        }
        return Base64URL.encode(hash)
    }
}
