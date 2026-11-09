import XCTest
@testable import LinkryptCore

private struct BundleFixture: Decodable {
    struct Entry: Decodable { let name: String; let dataHex: String; let dosTime: UInt16; let dosDate: UInt16 }
    struct Bundle: Decodable { let id: String; let entries: [Entry]; let expectedHex: String }
    struct NameCase: Decodable { let `in`: String; let out: String }
    struct UniqueCase: Decodable { let `in`: [String]; let out: [String] }
    struct Dos: Decodable { let y: Int; let mo: Int; let d: Int; let h: Int; let mi: Int; let s: Int; let time: UInt16; let date: UInt16 }
    let format: String
    let bundles: [Bundle]
    let canonicalName: [NameCase]
    let uniqueNames: [UniqueCase]
    let dos: [Dos]
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

final class FileBundleTests: XCTestCase {
    private let paris = TimeZone(identifier: "Europe/Paris")!

    private func fixture() throws -> BundleFixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bundle-golden-v1.json")
        return try JSONDecoder().decode(BundleFixture.self, from: Data(contentsOf: url))
    }

    private func entries(_ b: BundleFixture.Bundle) -> [FileBundle.Entry] {
        b.entries.map { FileBundle.Entry(name: $0.name, data: hexToData($0.dataHex), dosTime: $0.dosTime, dosDate: $0.dosDate) }
    }

    func testFormatMarkerAndFilename() throws {
        let f = try fixture()
        XCTAssertEqual(f.format, FileBundle.marker)
        XCTAssertEqual(FileBundle.filename(count: 3), "linkrypt-3-files.zip")
        XCTAssertEqual(FileBundle.maxEntries, 100)
        XCTAssertEqual(FileBundle.maxBytes, 1_073_741_824)
    }

    func testCanonicalNameVectors() throws {
        for c in try fixture().canonicalName {
            XCTAssertEqual(Array(FileBundle.canonicalName(c.in).utf8), Array(c.out.utf8), "input \(c.in.unicodeScalars.map { $0.value })")
        }
    }

    func testUniqueNamesVectors() throws {
        for c in try fixture().uniqueNames {
            XCTAssertEqual(FileBundle.uniqueNames(c.in).map { Array($0.utf8) }, c.out.map { Array($0.utf8) }, "input \(c.in)")
        }
    }

    func testCanonicalNameIdempotentAndBounded() throws {
        let f = try fixture()
        let inputs = f.canonicalName.map(\.in) + f.uniqueNames.flatMap(\.in) + f.canonicalName.map(\.out)
        for raw in inputs {
            let once = FileBundle.canonicalName(raw)
            XCTAssertEqual(Array(FileBundle.canonicalName(once).utf8), Array(once.utf8))
            XCTAssertLessThanOrEqual(once.utf8.count, 255)
            XCTAssertFalse(once.isEmpty)
        }
    }

    func testBuildMatchesGoldenBytes() throws {
        for b in try fixture().bundles {
            let out = try FileBundle.build(entries(b))
            XCTAssertEqual(dataToHex(out), b.expectedHex, "bundle \(b.id)")
        }
    }

    func testSizeEqualsBuildLength() throws {
        for b in try fixture().bundles {
            let es = entries(b)
            let predicted = FileBundle.size(names: es.map(\.name), sizes: es.map(\.data.count))
            XCTAssertEqual(predicted, try FileBundle.build(es).count, "bundle \(b.id)")
        }
    }

    func testCrc32CheckValue() {
        XCTAssertEqual(FileBundle.crc32(Data("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(FileBundle.crc32(Data()), 0)
    }

    private func parisDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = paris
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    func testDosDateTimeVectors() throws {
        for v in try fixture().dos {
            let r = FileBundle.dosDateTime(parisDate(v.y, v.mo, v.d, v.h, v.mi, v.s), timeZone: paris)
            XCTAssertEqual(r.time, v.time, "time \(v.y)-\(v.mo)-\(v.d)")
            XCTAssertEqual(r.date, v.date, "date \(v.y)-\(v.mo)-\(v.d)")
        }
    }

    func testDosDateTimeBCClampsToMinimum() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = paris
        let bc = cal.date(from: DateComponents(era: 0, year: 2000, month: 6, day: 1))!
        let r = FileBundle.dosDateTime(bc, timeZone: paris)
        XCTAssertEqual(r.time, 0)
        XCTAssertEqual(r.date, 33)
    }

    func testImplementationNeverReadsCalendarCurrent() throws {
        let src = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LinkryptCore/FileBundle.swift")
        let text = try String(contentsOf: src, encoding: .utf8)
        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(text.contains("Calendar.current"))
        XCTAssertFalse(text.contains("autoupdatingCurrent"))
        XCTAssertFalse(text.contains("Locale.current"))
    }

    func testNFDNamesAreNormalisedAndRejectedByBuild() {
        let nfd = "e\u{301}.txt", nfc = "\u{e9}.txt"
        XCTAssertEqual(Array(FileBundle.canonicalName(nfd).utf8), Array(nfc.utf8))
        XCTAssertEqual(FileBundle.uniqueNames([nfc, nfd]).map { Array($0.utf8) },
                       [Array(nfc.utf8), Array("\u{e9} (2).txt".utf8)])
        XCTAssertEqual(FileBundle.uniqueNames([nfd, nfd]).map { Array($0.utf8) },
                       [Array(nfc.utf8), Array("\u{e9} (2).txt".utf8)])
        let es = [FileBundle.Entry(name: nfd, data: Data(), dosTime: 0, dosDate: 33),
                  FileBundle.Entry(name: "b.txt", data: Data(), dosTime: 0, dosDate: 33)]
        XCTAssertThrowsError(try FileBundle.build(es)) { XCTAssertEqual($0 as? FileBundle.BuildError, .name) }
    }

    func testFoldKeyFinalSigma() {
        XCTAssertEqual(FileBundle.foldKey("\u{39F}\u{394}\u{39F}\u{3A3}"), Array("\u{3BF}\u{3B4}\u{3BF}\u{3C3}".utf8))
        XCTAssertEqual(FileBundle.foldKey("\u{3BF}\u{3B4}\u{3BF}\u{3C2}"), Array("\u{3BF}\u{3B4}\u{3BF}\u{3C3}".utf8))
        let es = [FileBundle.Entry(name: "\u{3BF}\u{3B4}\u{3BF}\u{3C2}", data: Data(), dosTime: 0, dosDate: 33),
                  FileBundle.Entry(name: "\u{3BF}\u{3B4}\u{3BF}\u{3C3}", data: Data(), dosTime: 0, dosDate: 33)]
        XCTAssertThrowsError(try FileBundle.build(es)) { XCTAssertEqual($0 as? FileBundle.BuildError, .duplicate) }
    }

    func testValidationPrecedence() {
        func e(_ n: String) -> FileBundle.Entry { FileBundle.Entry(name: n, data: Data(), dosTime: 0, dosDate: 33) }
        XCTAssertThrowsError(try FileBundle.build([e("a/b")])) { XCTAssertEqual($0 as? FileBundle.BuildError, .count) }
        XCTAssertThrowsError(try FileBundle.build([e("a/b"), e("a/b")])) { XCTAssertEqual($0 as? FileBundle.BuildError, .name) }
        XCTAssertThrowsError(try FileBundle.build([e("x"), e("X"), e("a/b")])) { XCTAssertEqual($0 as? FileBundle.BuildError, .duplicate) }
    }

    func testSizeIsExactEvenPastTheCap() {
        let m = FileBundle.maxBytes
        XCTAssertEqual(FileBundle.size(names: ["a", "b"], sizes: [m, m]), 2 * m + 2 * (30 + 46 + 2 * 1) + 39)
    }

    func testFoldV2CollisionsAreDuplicates() throws {
        let a = "\u{130}\u{316}.txt", b = "i\u{316}\u{307}.txt"
        XCTAssertEqual(FileBundle.uniqueNames([a, b]).map { Array($0.utf8) }, [Array(a.utf8), Array("i\u{316}\u{307} (2).txt".utf8)])
        let es = [a, b].map { FileBundle.Entry(name: $0, data: Data(), dosTime: 0, dosDate: 33) }
        XCTAssertThrowsError(try FileBundle.build(es)) { XCTAssertEqual($0 as? FileBundle.BuildError, .duplicate) }
    }

    func testRulesV3Explicit() throws {
        let k = { (s: String) in FileBundle.foldKey(s) }
        XCTAssertEqual(k("\u{1E9E}.txt"), k("ss.txt"))
        XCTAssertEqual(k("\u{DF}.txt"), k("ss.txt"))
        let es = ["\u{1E9E}.txt", "ss.txt"].map { FileBundle.Entry(name: $0, data: Data(), dosTime: 0, dosDate: 33) }
        XCTAssertThrowsError(try FileBundle.build(es)) { XCTAssertEqual($0 as? FileBundle.BuildError, .duplicate) }
        let c = { (s: String) in Array(FileBundle.canonicalName(s).utf8) }
        XCTAssertEqual(c("COM\u{B9}.txt"), Array("_COM\u{B9}.txt".utf8))
        XCTAssertEqual(c("CON .txt"), Array("_CON .txt".utf8))
        XCTAssertEqual(c("COM\u{2074}.txt"), Array("COM\u{2074}.txt".utf8))
        XCTAssertEqual(c("a\u{200B}b.txt"), Array("ab.txt".utf8))
    }

    func testFoldKeyIsInternalBytes() throws {
        // The key is a byte string: comparing two keys can never fall back to
        // Swift `String ==` (canonical equivalence).
        let key: [UInt8] = FileBundle.foldKey("Report.PDF")
        XCTAssertEqual(key, Array("report.pdf".utf8))
        // Standard NFC (decompose, then compose): Hangul LV + T composes to one syllable.
        XCTAssertEqual(FileBundle.foldKey("\u{AC00}\u{11A8}"), Array("\u{AC01}".utf8))
        let src = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LinkryptCore/FileBundle.swift")
        let text = try String(contentsOf: src, encoding: .utf8)
        XCTAssertFalse(text.contains("public static func foldKey"), "foldKey stays internal to the package")
    }

    func testReservedNameEdgeCases() {
        let c = { (s: String) in Array(FileBundle.canonicalName(s).utf8) }
        // Only ASCII letters fold when matching device names: fullwidth "ｃｏｎ"
        // (U+FF43 U+FF4F U+FF4E) and the long s "ſ" (U+017F) are ordinary names.
        XCTAssertEqual(c("\u{FF43}\u{FF4F}\u{FF4E}.txt"), Array("\u{FF43}\u{FF4F}\u{FF4E}.txt".utf8))
        XCTAssertEqual(c("\u{17F}on.txt"), Array("\u{17F}on.txt".utf8))
        // A trailing dot is stripped first, then the device part ("CON ") is
        // matched without its trailing whitespace; the result is stable.
        let once = FileBundle.canonicalName("CON .txt.")
        XCTAssertEqual(Array(once.utf8), Array("_CON .txt".utf8))
        XCTAssertEqual(c(once), Array(once.utf8))
        // CONIN$ and CONOUT$ are reserved in any ASCII case; near misses are not.
        XCTAssertEqual(c("CONIN$.txt"), Array("_CONIN$.txt".utf8))
        XCTAssertEqual(c("conout$"), Array("_conout$".utf8))
        XCTAssertEqual(c("CoNoUt$.log"), Array("_CoNoUt$.log".utf8))
        XCTAssertEqual(c("CONIN.txt"), Array("CONIN.txt".utf8))
        XCTAssertEqual(c("CONOUT$$.txt"), Array("CONOUT$$.txt".utf8))
    }

    func testSizeGuards() {
        XCTAssertThrowsError(try FileBundle.assertFits(names: ["a"], sizes: [1, 2])) { XCTAssertEqual($0 as? FileBundle.BuildError, .size) }
        XCTAssertThrowsError(try FileBundle.assertFits(names: ["a", "b"], sizes: [-1, 5])) { XCTAssertEqual($0 as? FileBundle.BuildError, .size) }
        XCTAssertThrowsError(try FileBundle.assertFits(names: ["a", "b"], sizes: [Int.max, Int.max])) { XCTAssertEqual($0 as? FileBundle.BuildError, .size) }
        XCTAssertGreaterThan(FileBundle.size(names: ["a"], sizes: [Int.max]), FileBundle.maxBytes)
        XCTAssertGreaterThan(FileBundle.size(names: ["a"], sizes: [-3]), FileBundle.maxBytes)
    }

    func testBuildErrors() {
        let one = [FileBundle.Entry(name: "a.txt", data: Data(), dosTime: 0, dosDate: 33)]
        XCTAssertThrowsError(try FileBundle.build(one)) { XCTAssertEqual($0 as? FileBundle.BuildError, .count) }
        let many = (0..<101).map { FileBundle.Entry(name: "f\($0).txt", data: Data(), dosTime: 0, dosDate: 33) }
        XCTAssertThrowsError(try FileBundle.build(many)) { XCTAssertEqual($0 as? FileBundle.BuildError, .count) }
        let bad = [one[0], FileBundle.Entry(name: "a/b.txt", data: Data(), dosTime: 0, dosDate: 33)]
        XCTAssertThrowsError(try FileBundle.build(bad)) { XCTAssertEqual($0 as? FileBundle.BuildError, .name) }
        let dup = [one[0], FileBundle.Entry(name: "A.TXT", data: Data(), dosTime: 0, dosDate: 33)]
        XCTAssertThrowsError(try FileBundle.build(dup)) { XCTAssertEqual($0 as? FileBundle.BuildError, .duplicate) }
        XCTAssertThrowsError(try FileBundle.assertFits(names: ["a", "b"], sizes: [FileBundle.maxBytes, 1])) {
            XCTAssertEqual($0 as? FileBundle.BuildError, .size)
        }
        XCTAssertNoThrow(try FileBundle.assertFits(names: ["a", "b"], sizes: [1, 1]))
    }
}
