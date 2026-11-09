import Foundation

/// Canonical multi-file bundle ("linkrypt-bundle/1"): several files packed into
/// one uncompressed, byte-deterministic ZIP archive. The web client implements
/// the same format and both must reproduce the shared golden fixture exactly.
public enum FileBundle {
    public static let marker = "linkrypt-bundle/1"
    public static let maxEntries = 100
    public static let maxBytes = 1_073_741_824

    public struct Entry: Sendable {
        public let name: String
        public let data: Data
        public let dosTime: UInt16
        public let dosDate: UInt16
        public init(name: String, data: Data, dosTime: UInt16, dosDate: UInt16) {
            self.name = name; self.data = data; self.dosTime = dosTime; self.dosDate = dosDate
        }
    }

    public enum BuildError: Error, Equatable { case count, name, duplicate, size }

    /// Server-side filename of a bundle with `count` files.
    public static func filename(count: Int) -> String { "linkrypt-\(count)-files.zip" }

    // MARK: - Names

    /// The only "whitespace" used in naming (never Foundation character sets).
    private static let whitespace: Set<UInt32> = Set<UInt32>(
        [0x0020, 0x0085, 0x00A0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]
            + Array(0x2000...0x200A))

    private static func isWS(_ s: Unicode.Scalar) -> Bool { whitespace.contains(s.value) }

    private static func isStripped(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return v <= 0x1F || v == 0x7F || (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v)
            || v == 0x2F || v == 0x5C
            // Invisible marks: Arabic letter mark, zero-width space, LRM, RLM, word joiner.
            // ZWNJ (U+200C) and ZWJ (U+200D) are kept: scripts need them.
            || v == 0x061C || v == 0x200B || v == 0x200E || v == 0x200F || v == 0x2060
    }

    /// Windows reserved device names (compared as ASCII-upper-cased UTF-8 bytes),
    /// including the superscript digits U+00B9, U+00B2, U+00B3. U+2074 is not reserved.
    private static let reserved: Set<[UInt8]> = Set(
        (["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"]
            + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }
            + ["\u{B9}", "\u{B2}", "\u{B3}"].flatMap { ["COM\($0)", "LPT\($0)"] })
            .map { Array($0.utf8) })

    /// UTF-8 bytes with ASCII lower-case letters folded to upper case.
    private static func asciiUpperBytes(_ scalars: ArraySlice<Unicode.Scalar>) -> [UInt8] {
        var out: [UInt8] = []
        for s in scalars {
            for b in String(s).utf8 { out.append((0x61...0x7A).contains(b) ? b - 32 : b) }
        }
        return out
    }

    private static func utf8Len(_ s: Unicode.Scalar) -> Int { String(s).utf8.count }
    private static func utf8Len(_ s: ArraySlice<Unicode.Scalar>) -> Int { s.reduce(0) { $0 + utf8Len($1) } }

    /// Index where the extension (dot included) starts, or `scalars.count` when none.
    private static func extensionStart(_ scalars: [Unicode.Scalar]) -> Int {
        guard let dot = scalars.lastIndex(of: "."), dot > 0 else { return scalars.count }
        return utf8Len(scalars[dot...]) <= 64 ? dot : scalars.count
    }

    private static func stripTrailing(_ scalars: inout [Unicode.Scalar]) {
        while let last = scalars.last, isWS(last) || last == "." { scalars.removeLast() }
    }

    private static func pass(_ input: String) -> String {
        // (a) strip, (b) replace
        var scalars: [Unicode.Scalar] = []
        for s in input.unicodeScalars where !isStripped(s) {
            scalars.append("<>:\"|?*".unicodeScalars.contains(s) ? "_" : s)
        }
        // (c) NFC
        var out = Array(nfc(String(String.UnicodeScalarView(scalars))).unicodeScalars)
        // (d) leading WS, trailing WS/dot
        while let first = out.first, isWS(first) { out.removeFirst() }
        stripTrailing(&out)
        // (e) reserved device names
        // The part before the first dot, minus trailing whitespace, names the device.
        var deviceEnd = out.firstIndex(of: ".") ?? out.count
        while deviceEnd > 0, isWS(out[deviceEnd - 1]) { deviceEnd -= 1 }
        if reserved.contains(asciiUpperBytes(out[0..<deviceEnd])) { out.insert("_", at: 0) }
        // (f) truncate to 255 bytes, keeping the extension
        let extStart = extensionStart(out)
        let extLen = utf8Len(out[extStart...])
        var stem = Array(out[0..<extStart])
        var stemLen = utf8Len(stem[...])
        while stemLen + extLen > 255, let last = stem.popLast() { stemLen -= utf8Len(last) }
        out = stem + Array(out[extStart...])
        // (g) strip trailing again
        stripTrailing(&out)
        // (h) degenerate names
        if out.isEmpty || out == ["."] || out == [".", "."] { return "file" }
        return String(String.UnicodeScalarView(out))
    }

    /// Standard Unicode NFC. Foundation's precomposed mapping alone leaves some
    /// input un-normalised (Hangul LV + T jamo, Tibetan U+0F73); decomposing
    /// first gives the same result as JavaScript's `normalize('NFC')`.
    private static func nfc(_ s: String) -> String {
        s.decomposedStringWithCanonicalMapping.precomposedStringWithCanonicalMapping
    }

    /// Exact code-point equality. Swift `String ==` is canonical equivalence
    /// (NFC equals NFD), which is not what name checks need.
    private static func sameScalars(_ a: String, _ b: String) -> Bool {
        a.utf8.elementsEqual(b.utf8)
    }

    /// Case- and normalization-insensitive comparison key (v3):
    /// lower, upper, lower, final sigma folded to sigma, then NFC. Approximates
    /// APFS matching (ss / sharp s / capital sharp s collide). The key is the
    /// UTF-8 bytes, so keys are only ever compared byte for byte.
    static func foldKey(_ name: String) -> [UInt8] {
        var out = String.UnicodeScalarView()
        for s in name.lowercased().uppercased().lowercased().unicodeScalars {
            out.append(s.value == 0x03C2 ? Unicode.Scalar(0x03C3)! : s)
        }
        return Array(nfc(String(out)).utf8)
    }

    /// Portable, deterministic file name (repeats the pass until stable).
    public static func canonicalName(_ raw: String) -> String {
        var cur = raw
        for _ in 0..<8 {
            let next = pass(cur)
            if sameScalars(next, cur) { return cur }
            cur = next
        }
        return cur
    }

    /// Canonicalises every name and de-duplicates case-insensitively with ` (2)`, ` (3)` ...
    public static func uniqueNames(_ raw: [String]) -> [String] {
        var used = Set<[UInt8]>()
        var result: [String] = []
        for r in raw {
            let name = canonicalName(r)
            var chosen = name
            if used.contains(foldKey(name)) {
                let scalars = Array(name.unicodeScalars)
                let extStart = extensionStart(scalars)
                let ext = Array(scalars[extStart...])
                let stem = Array(scalars[0..<extStart])
                var n = 2
                while true {
                    let suffix = Array(" (\(n))".unicodeScalars)
                    var s = stem
                    var total = utf8Len(s[...]) + utf8Len(suffix[...]) + utf8Len(ext[...])
                    while total > 255, let last = s.popLast() { total -= utf8Len(last) }
                    let cand = String(String.UnicodeScalarView(s + suffix + ext))
                    if !used.contains(foldKey(cand)) { chosen = cand; break }
                    n += 1
                }
            }
            used.insert(foldKey(chosen))
            result.append(chosen)
        }
        return result
    }

    // MARK: - CRC-32 and DOS time

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { buf in
            for b in buf { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFFFFFF
    }

    /// MS-DOS time/date in `timeZone` on the Gregorian calendar (never the
    /// system calendar), clamped to 1980-01-01 00:00:00 ... 2107-12-31 23:59:58.
    public static func dosDateTime(_ date: Date, timeZone: TimeZone = .current) -> (time: UInt16, date: UInt16) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)
        let year = c.year ?? 1980
        if (c.era ?? 1) == 0 || year < 1980 { return (0, 33) }
        if year > 2107 { return (49021, 65439) }
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let d = UInt16((year - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, d)
    }

    // MARK: - Writer

    /// Exact byte length of the bundle for the given names and data sizes.
    /// Negative sizes or arithmetic overflow saturate to `Int.max` (never traps),
    /// so `assertFits` rejects them.
    public static func size(names: [String], sizes: [Int]) -> Int {
        precondition(names.count == sizes.count, "names and sizes must pair up")
        var total = 22 + marker.utf8.count
        let saturated = Int.max
        for (n, s) in zip(names, sizes) {
            if s < 0 { return saturated }
            let (add, o1) = (30 + 46 + 2 * n.utf8.count).addingReportingOverflow(s)
            let (sum, o2) = total.addingReportingOverflow(add)
            if o1 || o2 { return saturated }
            total = sum
        }
        return total
    }

    public static func assertFits(names: [String], sizes: [Int]) throws {
        guard names.count == sizes.count else { throw BuildError.size }
        if size(names: names, sizes: sizes) > maxBytes { throw BuildError.size }
    }

    public static func build(_ entries: [Entry]) throws -> Data {
        guard entries.count >= 2, entries.count <= maxEntries else { throw BuildError.count }
        var seen = Set<[UInt8]>()
        for e in entries {
            guard sameScalars(canonicalName(e.name), e.name) else { throw BuildError.name }
            guard seen.insert(foldKey(e.name)).inserted else { throw BuildError.duplicate }
        }
        let total = size(names: entries.map(\.name), sizes: entries.map(\.data.count))
        guard total <= maxBytes else { throw BuildError.size }

        var out = Data(count: total)
        var pos = 0
        func u16(_ v: UInt16) { out[pos] = UInt8(v & 0xFF); out[pos + 1] = UInt8(v >> 8); pos += 2 }
        func u32(_ v: UInt32) { u16(UInt16(v & 0xFFFF)); u16(UInt16(v >> 16)) }
        func raw(_ d: Data) { out.replaceSubrange(pos..<pos + d.count, with: d); pos += d.count }

        var offsets: [UInt32] = []
        var crcs: [UInt32] = []
        for e in entries {
            let name = Data(e.name.utf8)
            let crc = crc32(e.data)
            offsets.append(UInt32(pos)); crcs.append(crc)
            u32(0x04034B50); u16(20); u16(0x0800); u16(0)
            u16(e.dosTime); u16(e.dosDate); u32(crc)
            u32(UInt32(e.data.count)); u32(UInt32(e.data.count))
            u16(UInt16(name.count)); u16(0)
            raw(name); raw(e.data)
        }
        let cdStart = pos
        for (i, e) in entries.enumerated() {
            let name = Data(e.name.utf8)
            u32(0x02014B50); u16(0x031E); u16(20); u16(0x0800); u16(0)
            u16(e.dosTime); u16(e.dosDate); u32(crcs[i])
            u32(UInt32(e.data.count)); u32(UInt32(e.data.count))
            u16(UInt16(name.count)); u16(0); u16(0); u16(0); u16(0)
            u32(0x81A4_0000); u32(offsets[i])
            raw(name)
        }
        let cdSize = pos - cdStart
        u32(0x06054B50); u16(0); u16(0)
        u16(UInt16(entries.count)); u16(UInt16(entries.count))
        u32(UInt32(cdSize)); u32(UInt32(cdStart))
        u16(UInt16(marker.utf8.count))
        raw(Data(marker.utf8))
        return out
    }
}
