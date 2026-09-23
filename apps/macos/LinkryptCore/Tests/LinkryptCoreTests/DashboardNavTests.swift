import XCTest
@testable import LinkryptCore

/// Selection movement for the dashboard `j`/`k` keyboard model. Pure logic so
/// the wrap/clamp/re-anchor rules are gated independently of the SwiftUI view.
final class DashboardNavTests: XCTestCase {
    private let rows = ["a", "b", "c"]

    // MARK: next (j — move down), clamps at the end

    func testNextOnEmptyListIsNil() {
        XCTAssertNil(DashboardNav.next(after: nil, in: []))
        XCTAssertNil(DashboardNav.next(after: "a", in: []))
    }

    func testNextWithNoSelectionPicksFirst() {
        XCTAssertEqual(DashboardNav.next(after: nil, in: rows), "a")
    }

    func testNextFromMiddleMovesDown() {
        XCTAssertEqual(DashboardNav.next(after: "b", in: rows), "c")
    }

    func testNextAtLastClampsToLast() {
        XCTAssertEqual(DashboardNav.next(after: "c", in: rows), "c")
    }

    func testNextWithAbsentSelectionReanchorsToFirst() {
        XCTAssertEqual(DashboardNav.next(after: "zz", in: rows), "a")
    }

    // MARK: previous (k — move up), clamps at the start

    func testPreviousOnEmptyListIsNil() {
        XCTAssertNil(DashboardNav.previous(before: nil, in: []))
        XCTAssertNil(DashboardNav.previous(before: "a", in: []))
    }

    func testPreviousWithNoSelectionPicksLast() {
        XCTAssertEqual(DashboardNav.previous(before: nil, in: rows), "c")
    }

    func testPreviousFromMiddleMovesUp() {
        XCTAssertEqual(DashboardNav.previous(before: "b", in: rows), "a")
    }

    func testPreviousAtFirstClampsToFirst() {
        XCTAssertEqual(DashboardNav.previous(before: "a", in: rows), "a")
    }

    func testPreviousWithAbsentSelectionReanchorsToLast() {
        XCTAssertEqual(DashboardNav.previous(before: "zz", in: rows), "c")
    }

    // MARK: resolve — selection restricted to the visible rows
    // Guards against acting on a row that was filtered out or removed.

    func testResolveNilSelectionIsNil() {
        XCTAssertNil(DashboardNav.resolve(nil, in: rows))
    }

    func testResolvePresentSelectionPassesThrough() {
        XCTAssertEqual(DashboardNav.resolve("b", in: rows), "b")
    }

    func testResolveAbsentSelectionIsNil() {
        XCTAssertNil(DashboardNav.resolve("zz", in: rows))
    }

    func testResolveAgainstEmptyListIsNil() {
        XCTAssertNil(DashboardNav.resolve("a", in: []))
    }
}
