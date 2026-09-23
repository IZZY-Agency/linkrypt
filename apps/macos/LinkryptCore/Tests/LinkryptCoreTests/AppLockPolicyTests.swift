import XCTest
@testable import LinkryptCore

final class AppLockPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testLocksWhenInactiveAtLeastGrace() {
        XCTAssertTrue(AppLockPolicy.shouldLock(inactiveSince: t0, now: t0.addingTimeInterval(300), graceMinutes: 5))
    }
    func testDoesNotLockBeforeGrace() {
        XCTAssertFalse(AppLockPolicy.shouldLock(inactiveSince: t0, now: t0.addingTimeInterval(299), graceMinutes: 5))
    }
    func testZeroGraceLocksOnAnyReturn() {
        XCTAssertTrue(AppLockPolicy.shouldLock(inactiveSince: t0, now: t0, graceMinutes: 0))
    }
    func testClockSkewNeverUnderflows() {
        XCTAssertFalse(AppLockPolicy.shouldLock(inactiveSince: t0, now: t0.addingTimeInterval(-100), graceMinutes: 1))
        XCTAssertTrue(AppLockPolicy.shouldLock(inactiveSince: t0, now: t0.addingTimeInterval(-100), graceMinutes: 0))
    }
    func testNilInactiveSinceDoesNotLock() {
        XCTAssertFalse(AppLockPolicy.shouldLock(inactiveSince: nil, now: t0, graceMinutes: 0))
    }
}
