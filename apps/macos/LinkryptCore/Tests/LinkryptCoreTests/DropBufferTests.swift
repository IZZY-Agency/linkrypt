import XCTest
@testable import LinkryptCore

final class DropBufferTests: XCTestCase {
    private let a = URL(fileURLWithPath: "/tmp/a")
    private let b = URL(fileURLWithPath: "/tmp/b")

    func testBuffersBeforeReadyThenFlushesOnce() {
        let buf = DropBuffer()
        buf.receive([a])
        var delivered: [URL] = []
        buf.onReady { delivered.append(contentsOf: $0) }
        XCTAssertEqual(delivered, [a])
    }

    func testDeliversDirectlyAfterReady() {
        let buf = DropBuffer()
        var delivered: [URL] = []
        buf.onReady { delivered.append(contentsOf: $0) }
        buf.receive([b])
        XCTAssertEqual(delivered, [b])
    }

    func testFlushClearsBufferSoSecondReadyGetsNothing() {
        let buf = DropBuffer()
        buf.receive([a])
        buf.onReady { _ in }                 // flushes + clears
        var second: [URL] = []
        buf.onReady { second.append(contentsOf: $0) }
        XCTAssertEqual(second, [])
    }
}
