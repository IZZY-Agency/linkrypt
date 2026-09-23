import XCTest
@testable import LinkryptCore

final class LockStateMachineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    func testLaunchLockOnlyWhenEnabledAndSession() {
        var m = LockStateMachine()
        m.lockIfEnabled(requireBiometric: false, hasSession: true); XCTAssertFalse(m.isLocked)
        m.lockIfEnabled(requireBiometric: true, hasSession: false); XCTAssertFalse(m.isLocked)
        m.lockIfEnabled(requireBiometric: true, hasSession: true);  XCTAssertTrue(m.isLocked)
    }

    // Content must hide the moment the app goes inactive.
    func testResignLocksWhenEnabledAndSession() {
        var m = LockStateMachine()
        m.onResignActive(requireBiometric: true, hasSession: true, now: t0)
        XCTAssertTrue(m.isLocked)
    }
    func testResignDoesNotLockWhenDisabledOrNoSession() {
        var m = LockStateMachine()
        m.onResignActive(requireBiometric: false, hasSession: true, now: t0); XCTAssertFalse(m.isLocked)
        m.onResignActive(requireBiometric: true, hasSession: false, now: t0); XCTAssertFalse(m.isLocked)
    }

    // Returning within the grace window auto-reveals (no Touch ID).
    func testReturnWithinGraceAutoReveals() {
        var m = LockStateMachine()
        m.onResignActive(requireBiometric: true, hasSession: true, now: t0)
        m.onBecomeActive(autoLockMinutes: 5, now: t0.addingTimeInterval(10))
        XCTAssertFalse(m.isLocked)
    }
    // Returning after the grace window stays locked (Touch ID required).
    func testReturnAfterGraceStaysLocked() {
        var m = LockStateMachine()
        m.onResignActive(requireBiometric: true, hasSession: true, now: t0)
        m.onBecomeActive(autoLockMinutes: 5, now: t0.addingTimeInterval(300))
        XCTAssertTrue(m.isLocked)
    }
    // Grace 0 ("lock when I switch away") always requires Touch ID on return.
    func testZeroGraceAlwaysStaysLockedOnReturn() {
        var m = LockStateMachine()
        m.onResignActive(requireBiometric: true, hasSession: true, now: t0)
        m.onBecomeActive(autoLockMinutes: 0, now: t0.addingTimeInterval(1))
        XCTAssertTrue(m.isLocked)
    }
    // Launch-lock (no recorded deactivation) must NOT auto-reveal on first activate.
    func testLaunchLockStaysLockedOnActivate() {
        var m = LockStateMachine()
        m.lockIfEnabled(requireBiometric: true, hasSession: true)
        m.onBecomeActive(autoLockMinutes: 15, now: t0)
        XCTAssertTrue(m.isLocked)
    }

    func testUnlockSucceededClears() {
        var m = LockStateMachine()
        m.lockIfEnabled(requireBiometric: true, hasSession: true)
        m.onUnlockSucceeded()
        XCTAssertFalse(m.isLocked)
        // a subsequent switch-away re-locks
        m.onResignActive(requireBiometric: true, hasSession: true, now: t0)
        XCTAssertTrue(m.isLocked)
    }

    func testForceLockNoOpWhenDisabledOrNoSession() {
        var m = LockStateMachine()
        m.forceLock(requireBiometric: false, hasSession: true); XCTAssertFalse(m.isLocked)
        m.forceLock(requireBiometric: true, hasSession: false); XCTAssertFalse(m.isLocked)
    }

    func testForceLockIsNotConsumedByGraceWindow() {
        var m = LockStateMachine()
        m.forceLock(requireBiometric: true, hasSession: true)
        XCTAssertTrue(m.isLocked)
        // Even well inside the grace window, a force-lock (inactiveSince == nil)
        // never auto-reveals — unlike a soft onResignActive.
        m.onBecomeActive(autoLockMinutes: 15, now: t0.addingTimeInterval(60))
        XCTAssertTrue(m.isLocked)
    }
}
