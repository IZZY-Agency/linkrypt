import Foundation
import Argon2Swift

extension Crypto {
    /// OWASP 2024 Argon2id parameters — must match the web client's
    /// `deriveArgon2idHash` so passphrase shares created here open on
    /// the web/CLI recipient.
    public static let argon2MemoryKiB = 65536   // 64 MiB
    public static let argon2Iterations = 3
    public static let argon2Parallelism = 1

    /// Argon2id passphrase KDF — parity with the web default (memory-hard,
    /// replaces the legacy PBKDF2 path for new passphrase-2FA shares). Returns
    /// a 32-byte raw hash. Byte-compatible with the web; gated by the
    /// `CryptoArgon2Tests` golden vectors. Callers pass a 16-byte salt
    /// (`saltLen`), well above Argon2's 8-byte minimum.
    ///
    /// Throws (rather than crashing like `pbkdf2`) because this allocates 64 MiB
    /// — an allocation failure under memory pressure is a real runtime fault the
    /// caller should surface, not a `preconditionFailure` that aborts mid-share.
    public static func argon2id(passphrase: String, salt: Data) throws -> Data {
        let result = try Argon2Swift.hashPasswordBytes(
            password: Data(passphrase.utf8),
            salt: Salt(bytes: salt),
            iterations: argon2Iterations,
            memory: argon2MemoryKiB,
            parallelism: argon2Parallelism,
            length: pbkdf2OutLen,        // 32 bytes, same envelope as PBKDF2
            type: .id,
            version: .V13
        )
        return result.hashData()
    }
}
