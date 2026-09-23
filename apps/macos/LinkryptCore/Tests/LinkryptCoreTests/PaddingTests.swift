import XCTest
@testable import LinkryptCore

/// Byte-for-byte parity gate for the length-hiding padding
/// envelope. The Swift `Padding` type must produce identical bytes to the
/// web client's `padToBucket` / `unpadFromBucket` / `nextPaddingBucket`.
/// Cases mirror the web client's own unit tests, plus stricter exact-byte
/// header/zero-tail checks.
final class PaddingTests: XCTestCase {

    // MARK: nextBucket — mirrors web `nextPaddingBucket`

    func testNextBucketRoundsUpToFourKiBMinimum() {
        XCTAssertEqual(Padding.nextBucket(0), 4 * 1024)
        XCTAssertEqual(Padding.nextBucket(1), 4 * 1024)
        XCTAssertEqual(Padding.nextBucket(4 * 1024), 4 * 1024)
    }

    func testNextBucketPowerOfTwoBetween4KiBAnd1MiB() {
        XCTAssertEqual(Padding.nextBucket(4 * 1024 + 1), 8 * 1024)
        XCTAssertEqual(Padding.nextBucket(8 * 1024), 8 * 1024)
        XCTAssertEqual(Padding.nextBucket(8 * 1024 + 1), 16 * 1024)
        XCTAssertEqual(Padding.nextBucket(100 * 1024), 128 * 1024)
        XCTAssertEqual(Padding.nextBucket(512 * 1024), 512 * 1024)
        XCTAssertEqual(Padding.nextBucket(512 * 1024 + 1), 1024 * 1024)
    }

    func testNextBucketStepsOneMiBAbove1MiB() {
        XCTAssertEqual(Padding.nextBucket(1024 * 1024 + 1), 2 * 1024 * 1024)
        XCTAssertEqual(Padding.nextBucket(5 * 1024 * 1024 + 100), 6 * 1024 * 1024)
        XCTAssertEqual(Padding.nextBucket(63 * 1024 * 1024), 63 * 1024 * 1024)
        XCTAssertEqual(Padding.nextBucket(63 * 1024 * 1024 + 1), 64 * 1024 * 1024)
    }

    // MARK: pad / unpad round-trip — mirrors web `padToBucket` / `unpadFromBucket`

    func testPadRoundTripsSmallText() throws {
        let plain = Data("hello, world".utf8)
        let padded = Padding.pad(plain)
        XCTAssertEqual(padded.count, 4 * 1024)
        XCTAssertEqual(Array(padded)[0], 0x01) // version
        let back = try Padding.unpad(padded)
        XCTAssertEqual(String(decoding: back, as: UTF8.self), "hello, world")
    }

    func testPadRoundTripsEmpty() throws {
        let padded = Padding.pad(Data())
        XCTAssertEqual(padded.count, 4 * 1024)
        let back = try Padding.unpad(padded)
        XCTAssertEqual(back.count, 0)
    }

    func testPadRoundTripsAtBucketBoundary() throws {
        // 4 KiB minus 5-byte header = max content for the 4 KiB bucket
        let plain = Data(repeating: 0x55, count: 4 * 1024 - 5)
        let padded = Padding.pad(plain)
        XCTAssertEqual(padded.count, 4 * 1024)
        let back = try Padding.unpad(padded)
        XCTAssertEqual(back, plain)
    }

    func testPadRoundTripsLargerContentSixteenKiBBucket() throws {
        var plain = Data(count: 10 * 1024)
        for i in 0..<plain.count { plain[i] = UInt8(i & 0xff) }
        let padded = Padding.pad(plain)
        XCTAssertEqual(padded.count, 16 * 1024)
        let back = try Padding.unpad(padded)
        XCTAssertEqual(back, plain)
    }

    // MARK: exact-byte golden — fully determines the envelope (stricter than web)

    func testPadProducesExactHeaderAndZeroTail() {
        let plain = Data("hello, world".utf8) // 12 bytes
        let bytes = Array(Padding.pad(plain))
        XCTAssertEqual(bytes.count, 4 * 1024)
        // header: version 0x01 + big-endian uint32 length (12) + plaintext
        let expectedHead: [UInt8] = [
            0x01, 0x00, 0x00, 0x00, 0x0c,
            0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x2c, 0x20, 0x77, 0x6f, 0x72, 0x6c, 0x64, // "hello, world"
        ]
        XCTAssertEqual(Array(bytes[0..<expectedHead.count]), expectedHead)
        XCTAssertTrue(bytes[expectedHead.count...].allSatisfy { $0 == 0 }, "tail must be zero-filled")
    }

    func testPadEncodesMultiByteLengthBigEndian() {
        let plain = Data(repeating: 0xab, count: 300) // 300 = 0x012c
        let bytes = Array(Padding.pad(plain))
        XCTAssertEqual(Array(bytes[0..<5]), [0x01, 0x00, 0x00, 0x01, 0x2c])
        XCTAssertEqual(bytes.count, 4 * 1024)
    }

    // MARK: unpad error paths — mirrors web throws

    func testUnpadRejectsTooShortBuffer() {
        XCTAssertThrowsError(try Padding.unpad(Data([0x01, 0x00, 0x00])))
    }

    func testUnpadRejectsUnknownVersion() {
        var bad = Data([0x02, 0x00, 0x00, 0x00, 0x00])
        bad.append(Data(repeating: 0, count: 4 * 1024 - 5))
        XCTAssertThrowsError(try Padding.unpad(bad))
    }

    func testUnpadRejectsDeclaredLengthExceedingBuffer() {
        // declares 1 MiB of plaintext inside a 4 KiB buffer
        var bad = Data([0x01, 0x00, 0x10, 0x00, 0x00])
        bad.append(Data(repeating: 0, count: 4 * 1024 - 5))
        XCTAssertThrowsError(try Padding.unpad(bad))
    }

    // MARK: sealPaddedV1 — pad-then-encrypt helper used by all share sites

    func testSealPaddedV1EqualsEncryptOfPaddedPlaintext() throws {
        let key = Data(repeating: 0x01, count: Crypto.keyLen)
        let iv = Data(repeating: 0x02, count: Crypto.ivLen)
        let plain = Data("top secret".utf8)
        let sealed = try Crypto.sealPaddedV1(key: key, iv: iv, plaintext: plain)
        let expected = try Crypto.aesGcmEncrypt(key: key, iv: iv, plaintext: Padding.pad(plain))
        XCTAssertEqual(sealed, expected)
    }

    func testSealPaddedV1CiphertextIsBucketPlusTag() throws {
        let key = Data(repeating: 0x03, count: Crypto.keyLen)
        let iv = Data(repeating: 0x04, count: Crypto.ivLen)
        let sealed = try Crypto.sealPaddedV1(key: key, iv: iv, plaintext: Data("hi".utf8))
        XCTAssertEqual(sealed.count, 4 * 1024 + Crypto.tagLen)
    }

    // MARK: Data-slice safety — Swift Data subscripts are not always 0-based

    func testUnpadHandlesSlicedDataWithNonZeroStartIndex() throws {
        let plain = Data("sliced payload".utf8)
        let padded = Padding.pad(plain)
        // Prepend bytes then drop them → a Data slice whose startIndex != 0.
        let sliced = (Data([0xff, 0xfe]) + padded).dropFirst(2)
        XCTAssertNotEqual(sliced.startIndex, 0, "precondition: slice must have non-zero startIndex")
        let back = try Padding.unpad(sliced)
        XCTAssertEqual(back, plain)
    }

    // MARK: bucket math at the text-cap edge
    //
    // `pad` is policy-free: it pads ANY length to the next bucket and never
    // rejects. These assertions document WHY the text cap sits exactly at
    // 1 MiB - 5 — one more byte crosses from the 1 MiB bucket into the 2 MiB
    // bucket, which would blow the server's text payload cap. Cap *enforcement*
    // is tested separately via `Crypto.textPlaintextFitsCap`.

    func testPadBucketCrossesIntoTwoMiBOneByteAboveTextCap() throws {
        let maxPlain = Data(repeating: 0x7a, count: Crypto.maxTextPlaintextBytes) // 1 MiB - 5
        let paddedMax = Padding.pad(maxPlain)
        XCTAssertEqual(paddedMax.count, 1024 * 1024) // tight fit, stays in 1 MiB bucket
        XCTAssertEqual(try Padding.unpad(paddedMax), maxPlain)

        let overByOne = Data(repeating: 0x7a, count: Crypto.maxTextPlaintextBytes + 1)
        let paddedOver = Padding.pad(overByOne)
        XCTAssertEqual(paddedOver.count, 2 * 1024 * 1024) // one byte over → 2 MiB bucket
        XCTAssertEqual(try Padding.unpad(paddedOver), overByOne)
    }

    // MARK: text-cap enforcement predicate (used by both app share guards)

    func testTextPlaintextFitsCapBoundary() {
        XCTAssertTrue(Crypto.textPlaintextFitsCap(0))
        XCTAssertTrue(Crypto.textPlaintextFitsCap(Crypto.maxTextPlaintextBytes))
        XCTAssertFalse(Crypto.textPlaintextFitsCap(Crypto.maxTextPlaintextBytes + 1))
    }

    // MARK: max-text-plaintext ties to the server's text payload cap

    func testMaxTextPlaintextPaddedAndSealedFitsServerCap() {
        // The server's finalize step rejects a text ciphertext larger than
        // MAX_TEXT_PAYLOAD (1,126,400). The largest plaintext we allow, once
        // padded + GCM-tagged, must fit — mirrors web's MAX_TEXT_PLAINTEXT.
        let serverTextPayloadCap = 1_126_400
        let maxPlain = Data(count: Crypto.maxTextPlaintextBytes)
        let sealedLen = Padding.pad(maxPlain).count + Crypto.tagLen
        XCTAssertLessThanOrEqual(sealedLen, serverTextPayloadCap)
        // tight fit: it lands exactly in the 1 MiB bucket, not a larger one
        XCTAssertEqual(Padding.pad(maxPlain).count, 1024 * 1024)
    }
}
