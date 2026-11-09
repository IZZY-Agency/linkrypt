import XCTest
@testable import LinkryptCore

final class DroppedFileTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testRegularReadableFileIsAcceptable() throws {
        let f = tmp.appendingPathComponent("a.txt")
        try Data("hi".utf8).write(to: f)
        XCTAssertTrue(DroppedFile.isAcceptable(f))
    }
    func testDirectoryIsNotAcceptable() {
        XCTAssertFalse(DroppedFile.isAcceptable(tmp))
    }
    func testMissingFileIsNotAcceptable() {
        XCTAssertFalse(DroppedFile.isAcceptable(tmp.appendingPathComponent("nope.txt")))
    }
    func testNonFileURLIsNotAcceptable() {
        XCTAssertFalse(DroppedFile.isAcceptable(URL(string: "https://example.com/x")!))
    }
    func testSymlinkIsNotAcceptable() throws {
        let f = tmp.appendingPathComponent("real.txt")
        try Data("x".utf8).write(to: f)
        let link = tmp.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f)
        XCTAssertFalse(DroppedFile.isAcceptable(link))
    }

    func testFinderAliasIsNotAcceptable() throws {
        let f = tmp.appendingPathComponent("real2.txt")
        try Data("y".utf8).write(to: f)
        let alias = tmp.appendingPathComponent("alias.txt")
        let data = try f.bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(data, to: alias)   // a real Finder alias file
        XCTAssertFalse(DroppedFile.isAcceptable(alias))
    }

    func testPackageDirectoryIsRejectedAsFolder() throws {
        let pkg = tmp.appendingPathComponent("X.app")
        try FileManager.default.createDirectory(
            at: pkg.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        XCTAssertEqual(DroppedFile.rejectionReason(pkg), .folder)
        XCTAssertFalse(DroppedFile.isAcceptable(pkg))
    }

    func testRejectionReasonForAliasIsUnsupported() throws {
        let f = tmp.appendingPathComponent("real3.txt")
        try Data("z".utf8).write(to: f)
        let alias = tmp.appendingPathComponent("alias3.txt")
        try URL.writeBookmarkData(try f.bookmarkData(options: .suitableForBookmarkFile), to: alias)
        XCTAssertEqual(DroppedFile.rejectionReason(alias), .unsupported)
    }
}
