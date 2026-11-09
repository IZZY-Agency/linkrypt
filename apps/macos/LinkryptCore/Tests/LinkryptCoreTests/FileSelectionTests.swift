import XCTest
@testable import LinkryptCore

final class FileSelectionTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    /// Creates a (sparse) file of exactly `size` bytes.
    @discardableResult
    private func make(_ name: String, size: Int = 0, in dir: URL? = nil) throws -> URL {
        let url = (dir ?? tmp).appendingPathComponent(name)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        try resize(url, to: size)
        return url
    }
    private func resize(_ url: URL, to size: Int) throws {
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        try h.truncate(atOffset: UInt64(size))
    }

    // MARK: rejection reasons
    func testRejectionReasons() throws {
        let file = try make("a.txt", size: 1)
        XCTAssertNil(DroppedFile.rejectionReason(file))
        XCTAssertEqual(DroppedFile.rejectionReason(tmp), .folder)
        let link = tmp.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertEqual(DroppedFile.rejectionReason(link), .unsupported)
        XCTAssertEqual(DroppedFile.rejectionReason(tmp.appendingPathComponent("nope")), .unsupported)
        XCTAssertEqual(DroppedFile.rejectionReason(URL(string: "https://example.com/x")!), .unsupported)
    }

    // MARK: add
    func testAddKeepsFilesInOrderAndReportsFolder() throws {
        let a = try make("a.txt", size: 1), b = try make("b.txt", size: 2)
        let dir = tmp.appendingPathComponent("d")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var sel = FileSelection()
        let rejected = sel.add([a, dir, b])
        XCTAssertEqual(sel.items.map(\.url), [a, b])
        XCTAssertEqual(sel.items.map(\.size), [1, 2])
        XCTAssertEqual(rejected.count, 1)
        XCTAssertEqual(rejected[0].url, dir)
        XCTAssertEqual(rejected[0].reason, .folder)
    }

    func testAddingSameURLTwiceKeepsBothAndDedupesNames() throws {
        let a = try make("a.txt", size: 1)
        var sel = FileSelection()
        _ = sel.add([a, a])
        XCTAssertEqual(sel.items.count, 2)
        XCTAssertEqual(sel.displayNames, ["a.txt", "a (2).txt"])
    }

    func testRemoveAndRemoveAll() throws {
        let a = try make("a.txt"), b = try make("b.txt")
        var sel = FileSelection()
        _ = sel.add([a, b])
        sel.remove(at: 0)
        XCTAssertEqual(sel.items.map(\.url), [b])
        sel.removeAll()
        XCTAssertTrue(sel.items.isEmpty)
    }

    func testSingleItemUsesRealFilenameAndSize() throws {
        let a = try make("My Report.pdf", size: 1234)
        var sel = FileSelection()
        _ = sel.add([a])
        XCTAssertEqual(sel.displayNames, ["My Report.pdf"])
        XCTAssertEqual(sel.payloadBytes, 1234)
    }

    // MARK: payload + problems
    func testPayloadBytesEqualsBundleSizeForTwoItems() throws {
        let a = try make("a.txt", size: 10), b = try make("b.txt", size: 20)
        var sel = FileSelection()
        _ = sel.add([a, b])
        XCTAssertEqual(sel.payloadBytes, FileBundle.size(names: ["a.txt", "b.txt"], sizes: [10, 20]))
    }

    func testBundleOverheadPushesSelectionOverPlanLimit() throws {
        let limit = 5_242_880
        let a = try make("a.bin", size: 2_621_440)
        let b = try make("b.bin", size: limit - 50 - 2_621_440)
        var sel = FileSelection()
        _ = sel.add([a, b])
        XCTAssertEqual(sel.problem(planMaxBytes: limit), .overPlan)
        XCTAssertNil(sel.problem(planMaxBytes: nil))
    }

    func testEmptyIsEmptyProblem() {
        XCTAssertEqual(FileSelection().problem(planMaxBytes: nil), .empty)
        XCTAssertEqual(FileSelection().livePreflight(planMaxBytes: nil), .failure(.empty))
    }

    func testMoreThanMaxEntriesIsTooMany() throws {
        var sel = FileSelection()
        let urls = try (0..<101).map { try make("f\($0).txt") }
        _ = sel.add(urls)
        XCTAssertEqual(sel.items.count, 101)
        XCTAssertEqual(sel.problem(planMaxBytes: nil), .tooMany)
    }

    func testOver1GiBBundleWithNilLimitIsOverBundleCap() throws {
        let a = try make("a.bin", size: 600_000_000), b = try make("b.bin", size: 600_000_000)
        var sel = FileSelection()
        _ = sel.add([a, b])
        XCTAssertEqual(sel.problem(planMaxBytes: nil), .overBundleCap)
    }

    func testSingleHugeFileWithNilLimitHasNoProblem() throws {
        let a = try make("huge.bin", size: 2 * 1_073_741_824)
        var sel = FileSelection()
        _ = sel.add([a])
        XCTAssertNil(sel.problem(planMaxBytes: nil))
        XCTAssertEqual(sel.problem(planMaxBytes: 5_242_880), .overPlan)
    }

    // MARK: live preflight
    func testLivePreflightSeesGrowthAfterAdd() throws {
        let limit = 1_048_576
        let a = try make("a.bin", size: 10), b = try make("b.bin", size: 10)
        var sel = FileSelection()
        _ = sel.add([a, b])
        XCTAssertEqual(sel.livePreflight(planMaxBytes: limit), .success([10, 10]))
        try resize(b, to: 2 * 1_048_576)
        XCTAssertNil(sel.problem(planMaxBytes: limit))
        XCTAssertEqual(sel.livePreflight(planMaxBytes: limit), .failure(.overPlan))
    }

    func testLivePreflightReportsDeletedFileAsUnreadable() throws {
        let a = try make("a.bin", size: 10), b = try make("b.bin", size: 10)
        var sel = FileSelection()
        _ = sel.add([a, b])
        try FileManager.default.removeItem(at: b)
        XCTAssertEqual(sel.livePreflight(planMaxBytes: nil), .failure(.unreadable))
    }

    // MARK: priority and edge cases
    func testBundleCapOutranksPlanLimit() throws {
        let a = try make("a.bin", size: 600_000_000), b = try make("b.bin", size: 600_000_000)
        var sel = FileSelection()
        _ = sel.add([a, b])
        XCTAssertEqual(sel.problem(planMaxBytes: 5 * 1_048_576), .overBundleCap)
    }

    func testTooManyOutranksPlanLimit() throws {
        var sel = FileSelection()
        _ = sel.add(try (0..<101).map { try make("f\($0).txt") })
        XCTAssertGreaterThan(sel.payloadBytes, 1000)
        XCTAssertEqual(sel.problem(planMaxBytes: 1000), .tooMany)
    }

    func testSingleFileOverTheFormatCapIsOverFormatCap() throws {
        let gib = 1_073_741_824
        var sel = FileSelection()
        _ = sel.add([try make("five.bin", size: 5 * gib)])
        XCTAssertEqual(sel.problem(planMaxBytes: nil), .overFormatCap)
        XCTAssertEqual(sel.problem(planMaxBytes: 5_242_880), .overFormatCap)   // outranks the plan limit
        XCTAssertEqual(sel.livePreflight(planMaxBytes: nil), .failure(.overFormatCap))

        var three = FileSelection()
        _ = three.add([try make("three.bin", size: 3 * gib)])
        XCTAssertNil(three.problem(planMaxBytes: nil))
    }

    func testFormatCapBoundaryIsExact() throws {
        var atCap = FileSelection()
        _ = atCap.add([try make("at.bin", size: Padding.maxPlaintext)])
        XCTAssertNil(atCap.problem(planMaxBytes: nil))
        var over = FileSelection()
        _ = over.add([try make("over.bin", size: Padding.maxPlaintext + 1)])
        XCTAssertEqual(over.problem(planMaxBytes: nil), .overFormatCap)
    }

    func testBundleCapOutranksFormatCap() throws {
        // Two or more files are capped at 1 GiB long before the format cap.
        var sel = FileSelection()
        _ = sel.add([try make("big.bin", size: 5 * 1_073_741_824), try make("small.bin", size: 1)])
        XCTAssertEqual(sel.problem(planMaxBytes: nil), .overBundleCap)
    }

    func testTooManyOutranksBundleCap() throws {
        // 101 sparse files of 11 MB each: more than 1 GiB together, and too many.
        var sel = FileSelection()
        _ = sel.add(try (0..<101).map { try make("f\($0).bin", size: 11_000_000) })
        XCTAssertGreaterThan(sel.payloadBytes, FileBundle.maxBytes)
        XCTAssertEqual(sel.problem(planMaxBytes: nil), .tooMany)
        XCTAssertEqual(sel.livePreflight(planMaxBytes: nil), .failure(.tooMany))
    }

    func testSingleItemLivePreflightSeesGrowth() throws {
        let limit = 1_048_576
        let a = try make("a.bin", size: 10)
        var sel = FileSelection()
        _ = sel.add([a])
        try resize(a, to: 2 * 1_048_576)
        XCTAssertNil(sel.problem(planMaxBytes: limit))
        XCTAssertEqual(sel.livePreflight(planMaxBytes: limit), .failure(.overPlan))
    }

    func testPayloadBytesForSizesMatchesAndFailsClosed() throws {
        let a = try make("a.txt", size: 10), b = try make("b.txt", size: 20)
        var sel = FileSelection()
        _ = sel.add([a, b])
        XCTAssertEqual(sel.payloadBytes(forSizes: [10, 20]), FileBundle.size(names: ["a.txt", "b.txt"], sizes: [10, 20]))
        XCTAssertEqual(sel.payloadBytes(forSizes: [10]), Int.max)
        XCTAssertEqual(sel.payloadBytes(forSizes: [10, 20, 30]), Int.max)
    }

    func testEmptySelectionPayloadIsZero() {
        XCTAssertEqual(FileSelection().payloadBytes, 0)
    }
}
