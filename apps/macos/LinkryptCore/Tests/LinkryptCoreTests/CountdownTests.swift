import XCTest
@testable import LinkryptCore

final class CountdownTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - remainingFraction

    func testFullAtStart() {
        XCTAssertEqual(Countdown.remainingFraction(now: t0, deadline: t0.addingTimeInterval(5), total: 5),
                       1.0, accuracy: 0.0001)
    }

    func testHalfwayIsHalf() {
        XCTAssertEqual(Countdown.remainingFraction(now: t0.addingTimeInterval(2.5),
                                                   deadline: t0.addingTimeInterval(5), total: 5),
                       0.5, accuracy: 0.0001)
    }

    func testZeroAtDeadline() {
        XCTAssertEqual(Countdown.remainingFraction(now: t0.addingTimeInterval(5),
                                                   deadline: t0.addingTimeInterval(5), total: 5), 0)
    }

    /// The timeline keeps ticking after the deadline until the close lands;
    /// the bar must clamp at empty rather than go negative.
    func testClampsToZeroPastDeadline() {
        XCTAssertEqual(Countdown.remainingFraction(now: t0.addingTimeInterval(99),
                                                   deadline: t0.addingTimeInterval(5), total: 5), 0)
    }

    /// A clock jump backwards must not produce a fraction above 1.
    func testClampsToOneIfClockJumpsBackwards() {
        XCTAssertEqual(Countdown.remainingFraction(now: t0.addingTimeInterval(-99),
                                                   deadline: t0.addingTimeInterval(5), total: 5), 1.0)
    }

    func testZeroTotalIsEmptyNotDivideByZero() {
        XCTAssertEqual(Countdown.remainingFraction(now: t0, deadline: t0, total: 0), 0)
        XCTAssertEqual(Countdown.remainingFraction(now: t0, deadline: t0, total: -5), 0)
    }

    // MARK: - litCells

    func testAllCellsLitWhenFull() {
        XCTAssertEqual(Countdown.litCells(fraction: 1.0, cells: 10), 10)
    }

    func testNoCellsLitWhenEmpty() {
        XCTAssertEqual(Countdown.litCells(fraction: 0, cells: 10), 0)
    }

    func testHalfLightsHalf() {
        XCTAssertEqual(Countdown.litCells(fraction: 0.5, cells: 10), 5)
    }

    /// Rounds up so the bar doesn't look empty while time still remains.
    func testRoundsUpSoASliverStaysVisible() {
        XCTAssertEqual(Countdown.litCells(fraction: 0.01, cells: 10), 1)
        XCTAssertEqual(Countdown.litCells(fraction: 0.51, cells: 10), 6)
    }

    func testNeverExceedsCellCount() {
        XCTAssertEqual(Countdown.litCells(fraction: 2.0, cells: 10), 10)
    }

    func testNonPositiveCellsIsZero() {
        XCTAssertEqual(Countdown.litCells(fraction: 1.0, cells: 0), 0)
        XCTAssertEqual(Countdown.litCells(fraction: 1.0, cells: -3), 0)
    }

    /// Walking a real 5s countdown drains monotonically, 10 → 0.
    func testDrainsMonotonically() {
        let deadline = t0.addingTimeInterval(5)
        var last = 11
        for step in stride(from: 0.0, through: 5.0, by: 0.1) {
            let f = Countdown.remainingFraction(now: t0.addingTimeInterval(step),
                                                deadline: deadline, total: 5)
            let lit = Countdown.litCells(fraction: f, cells: 10)
            XCTAssertLessThanOrEqual(lit, last)
            last = lit
        }
        XCTAssertEqual(last, 0)
    }
}
