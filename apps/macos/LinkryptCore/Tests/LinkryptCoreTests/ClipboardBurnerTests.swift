import XCTest
@testable import LinkryptCore

final class ClipboardBurnerTests: XCTestCase {
    func testClearsWhenChangeCountUnchanged() {
        XCTAssertTrue(ClipboardBurner.shouldClear(original: 7, current: 7))
    }
    func testDoesNotClearWhenChangeCountChanged() {
        // a later copy (incl. re-copying the same string) bumps changeCount
        XCTAssertFalse(ClipboardBurner.shouldClear(original: 7, current: 8))
    }
}
