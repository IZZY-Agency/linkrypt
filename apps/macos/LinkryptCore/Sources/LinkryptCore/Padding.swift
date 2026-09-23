import Foundation

/// Length-fingerprinting defense. Wraps plaintext in a
/// bucket-aligned envelope before AES-GCM so the ciphertext length reveals
/// only the bucket, not the exact byte count. Byte-for-byte port of the web
/// client's `nextPaddingBucket` / `padToBucket` / `unpadFromBucket`;
/// parity is gated by `PaddingTests`.
///
/// Envelope: `[0x01][big-endian uint32 original length][plaintext][zero pad]`,
/// total length = `nextBucket(originalLen + 5)`.

public enum PaddingError: Error {
    case bufferTooShort
    case unsupportedVersion(UInt8)
    case declaredLengthExceedsBuffer
}

public enum Padding {
    static let minBytes = 4 * 1024
    static let oneMiB = 1024 * 1024
    static let headerLen = 5 // version byte + uint32 length

    /// Smallest bucket ≥ `plaintextLen`: 4 KiB floor, power-of-2 up to 1 MiB,
    /// then 1 MiB steps (doubling would waste up to 50 % above 1 MiB).
    public static func nextBucket(_ plaintextLen: Int) -> Int {
        if plaintextLen <= minBytes { return minBytes }
        if plaintextLen > oneMiB {
            return ((plaintextLen + oneMiB - 1) / oneMiB) * oneMiB // ceil to MiB
        }
        var p = minBytes
        while p < plaintextLen { p *= 2 }
        return p
    }

    /// Wrap plaintext in the padded envelope. The result is fed to `aesGcmEncrypt`.
    public static func pad(_ plaintext: Data) -> Data {
        let originalLen = plaintext.count
        let target = nextBucket(originalLen + headerLen)
        var out = Data(count: target) // zero-initialized
        out[0] = 0x01 // version
        out[1] = UInt8((originalLen >> 24) & 0xff)
        out[2] = UInt8((originalLen >> 16) & 0xff)
        out[3] = UInt8((originalLen >> 8) & 0xff)
        out[4] = UInt8(originalLen & 0xff)
        if originalLen > 0 {
            out.replaceSubrange(headerLen..<(headerLen + originalLen), with: plaintext)
        }
        return out
    }

    /// Inverse of `pad`. Throws on a non-padded / truncated / corrupt buffer.
    public static func unpad(_ padded: Data) throws -> Data {
        let b = Array(padded) // normalize to 0-based indices (Data may be a slice)
        guard b.count >= headerLen else { throw PaddingError.bufferTooShort }
        guard b[0] == 0x01 else { throw PaddingError.unsupportedVersion(b[0]) }
        let declaredLen = (Int(b[1]) << 24) | (Int(b[2]) << 16) | (Int(b[3]) << 8) | Int(b[4])
        guard declaredLen + headerLen <= b.count else {
            throw PaddingError.declaredLengthExceedsBuffer
        }
        return Data(b[headerLen..<(headerLen + declaredLen)])
    }
}

extension Crypto {
    /// v1 length-hiding seal: pad to bucket, then AES-256-GCM encrypt. The
    /// share must be created with `paddingVersion: .v1`, `size` = the returned
    /// ciphertext length, and `rawSize` = the original plaintext length.
    public static func sealPaddedV1(key: Data, iv: Data, plaintext: Data) throws -> Data {
        try aesGcmEncrypt(key: key, iv: iv, plaintext: Padding.pad(plaintext))
    }
}
