import XCTest
@testable import LinkryptCore

/// Security-critical race tests for the pure `LockController`. Every `now:` is a
/// FIXED date (base + offsets) so the freshness-window assertions are
/// deterministic — never `Date()`.
final class LockControllerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)
    private func t(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

    /// Extract the epoch from a `.presentAuth` action in a result list (or nil).
    private func presentedEpoch(_ actions: [LockAction]) -> Int? {
        for a in actions { if case let .presentAuth(epoch) = a { return epoch } }
        return nil
    }

    private func countPresents(_ actions: [LockAction]) -> Int {
        actions.filter { if case .presentAuth = $0 { return true } else { return false } }.count
    }

    // 1. lock → become-active → exactly one .presentAuth; onAuthCompleted(ok, active) → unlocked, no further present.
    func testLockThenActivatePresentsOnceThenUnlocks() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        XCTAssertTrue(c.isLocked)

        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        XCTAssertEqual(countPresents(a), 1)
        XCTAssertTrue(c.isAuthenticating)
        guard let epoch = presentedEpoch(a) else { return XCTFail("no presentAuth") }

        let b = c.onAuthCompleted(epoch: epoch, ok: true, isActive: true, now: t(0.1))
        XCTAssertFalse(c.isLocked)
        XCTAssertFalse(c.isAuthenticating)
        XCTAssertEqual(countPresents(b), 0)

        // a subsequent become-active must not re-present (not locked anymore)
        let d = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0.2))
        XCTAssertEqual(countPresents(d), 0)
    }

    // 2a. callback-before-become (success): exactly one present, ends unlocked.
    func testSuccessCallbackBeforeBecomeActiveEndsUnlocked() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        let epoch = presentedEpoch(a)!
        XCTAssertEqual(countPresents(a), 1)

        // callback arrives while active, BEFORE any extra become-active
        let b = c.onAuthCompleted(epoch: epoch, ok: true, isActive: true, now: t(0.1))
        XCTAssertFalse(c.isLocked)
        XCTAssertEqual(countPresents(b), 0)

        // the dialog-dismiss become-active then fires — must not re-present
        let d = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0.2))
        XCTAssertEqual(countPresents(d), 0)
        XCTAssertFalse(c.isLocked)
    }

    // 2b. become-before-callback (success, momentarily inactive at callback time):
    //     exactly one present, ends unlocked.
    func testSuccessBecomeActiveBeforeCallbackEndsUnlocked() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        let epoch = presentedEpoch(a)!
        XCTAssertEqual(countPresents(a), 1)

        // success lands while momentarily inactive → stashed as pendingUnlock
        let b = c.onAuthCompleted(epoch: epoch, ok: true, isActive: false, now: t(0.1))
        XCTAssertTrue(c.isLocked)
        XCTAssertEqual(countPresents(b), 0)

        // immediate dialog-dismiss reactivation (within window) consumes it
        let d = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0.2))
        XCTAssertFalse(c.isLocked)
        XCTAssertEqual(countPresents(d), 0)
    }

    // 3. cancel (ok:false) → suppressed; next become-active → NO present; onManualUnlock → present again.
    func testCancelSuppressesUntilManualUnlock() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        let epoch = presentedEpoch(a)!

        let b = c.onAuthCompleted(epoch: epoch, ok: false, isActive: true, now: t(0.1))
        XCTAssertTrue(c.isLocked)
        XCTAssertFalse(c.isAuthenticating)
        XCTAssertEqual(countPresents(b), 0)

        // dialog-dismiss become-active must NOT re-present (suppressed)
        let d = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0.2))
        XCTAssertEqual(countPresents(d), 0)
        XCTAssertTrue(c.isLocked)

        // manual Unlock button re-arms and presents again
        let e = c.onManualUnlock(isActive: true)
        XCTAssertEqual(countPresents(e), 1)
        XCTAssertTrue(c.isAuthenticating)
    }

    // 4. success-inactive, immediate return (within window) → reveal, no present.
    func testSuccessInactiveImmediateReturnReveals() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        let epoch = presentedEpoch(a)!

        let b = c.onAuthCompleted(epoch: epoch, ok: true, isActive: false, now: t(0))
        XCTAssertTrue(c.isLocked)
        XCTAssertEqual(countPresents(b), 0)

        // return well within pendingUnlockWindow (2s)
        let d = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0.5))
        XCTAssertFalse(c.isLocked)
        XCTAssertEqual(countPresents(d), 0)
    }

    // 5. success-inactive, STALE return (beyond pendingUnlockWindow) → NOT revealed,
    //    still locked, one present emitted. (fixed dates spaced > window apart)
    func testSuccessInactiveStaleReturnDoesNotReveal() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        let epoch = presentedEpoch(a)!

        // success landed while inactive at t(0)
        let b = c.onAuthCompleted(epoch: epoch, ok: true, isActive: false, now: t(0))
        XCTAssertTrue(c.isLocked)
        XCTAssertEqual(countPresents(b), 0)

        // return far beyond the 2s window (10s later) → pending dropped, NOT revealed
        let d = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(10))
        XCTAssertTrue(c.isLocked)
        XCTAssertEqual(countPresents(d), 1)   // re-prompts a fresh, safe Touch ID
    }

    // 6. onSecurityResign during auth → .invalidateAuth, locked, pendingUnlock cleared,
    //    later stale onAuthCompleted(oldEpoch) → [], no reveal.
    func testSecurityResignDuringAuthInvalidatesAndDropsStaleCallback() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        let oldEpoch = presentedEpoch(a)!
        XCTAssertTrue(c.isAuthenticating)

        // screen sleeps / session resigns mid-prompt
        let b = c.onSecurityResign(requireBiometric: true, hasSession: true, now: t(0.1))
        XCTAssertTrue(b.contains(.invalidateAuth))
        XCTAssertTrue(c.isLocked)
        XCTAssertFalse(c.isAuthenticating)

        // the now-stale evaluatePolicy callback returns success → must be ignored
        let d = c.onAuthCompleted(epoch: oldEpoch, ok: true, isActive: true, now: t(0.2))
        XCTAssertEqual(d, [])
        XCTAssertTrue(c.isLocked)

        // and even an active return must not silently reveal (no pendingUnlock)
        let e = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0.3))
        XCTAssertTrue(c.isLocked)
        XCTAssertEqual(countPresents(e), 1)   // re-arm presents a fresh prompt
    }

    // 7. onAppResign while authenticating → [], no state change (the auth dialog's own resign).
    func testAppResignWhileAuthenticatingIsNoOp() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        _ = presentedEpoch(a)!
        XCTAssertTrue(c.isAuthenticating)

        let b = c.onAppResign(requireBiometric: true, hasSession: true, now: t(0.1))
        XCTAssertEqual(b, [])
        XCTAssertTrue(c.isAuthenticating)
        XCTAssertTrue(c.isLocked)
    }

    // 8. repeated onBecomeActive within one auth epoch (isAuthenticating true) → never a second present.
    func testRepeatedBecomeActiveDuringAuthNeverRePresents() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        XCTAssertEqual(countPresents(a), 1)
        XCTAssertTrue(c.isAuthenticating)

        for i in 1...5 {
            let r = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(Double(i) * 0.01))
            XCTAssertEqual(countPresents(r), 0, "iteration \(i) must not re-present")
        }
        XCTAssertTrue(c.isAuthenticating)
    }

    // 9. cancel then onAppResign / onSecurityResign then return → re-arms, presents once.
    func testCancelThenAppResignReArmsAndPresentsOnce() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        let epoch = presentedEpoch(a)!
        _ = c.onAuthCompleted(epoch: epoch, ok: false, isActive: true, now: t(0.1))   // cancel → suppressed

        // genuine switch-away re-arms the gate (not authenticating now)
        let b = c.onAppResign(requireBiometric: true, hasSession: true, now: t(1))
        XCTAssertEqual(countPresents(b), 0)

        let d = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(2))
        XCTAssertEqual(countPresents(d), 1)
        XCTAssertTrue(c.isAuthenticating)
    }

    func testCancelThenSecurityResignReArmsAndPresentsOnce() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        let epoch = presentedEpoch(a)!
        _ = c.onAuthCompleted(epoch: epoch, ok: false, isActive: true, now: t(0.1))   // cancel → suppressed

        let b = c.onSecurityResign(requireBiometric: true, hasSession: true, now: t(1))
        XCTAssertEqual(countPresents(b), 0)   // not authenticating, so no invalidate

        let d = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(2))
        XCTAssertEqual(countPresents(d), 1)
    }

    // 10. launch lockIfEnabled → first become-active presents exactly once.
    func testLaunchLockFirstActivatePresentsOnce() {
        var c = LockController()
        let l = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        XCTAssertEqual(countPresents(l), 0)   // not active yet → no present at lock time
        XCTAssertTrue(c.isLocked)

        let a = c.onBecomeActive(autoLockMinutes: 15, isActive: true, now: t(0))
        XCTAssertEqual(countPresents(a), 1)   // launch-lock never auto-reveals, so it prompts
        XCTAssertTrue(c.isLocked)
        XCTAssertTrue(c.isAuthenticating)
    }

    // 11a. stale epoch: onAuthCompleted with an old epoch → [].
    func testStaleEpochAuthCompletedIgnored() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        let epoch = presentedEpoch(a)!

        // a callback with a stale (older) epoch is dropped entirely
        let r = c.onAuthCompleted(epoch: epoch - 1, ok: true, isActive: true, now: t(0.1))
        XCTAssertEqual(r, [])
        XCTAssertTrue(c.isLocked)
        XCTAssertTrue(c.isAuthenticating)   // the real in-flight auth is untouched
    }

    // 11b. canEvaluatePolicy==false path = onAuthCompleted(ok:false) → suppressed, no present until rearm.
    func testCanEvaluatePolicyFalsePathSuppressesUntilRearm() {
        var c = LockController()
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)
        let a = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0))
        let epoch = presentedEpoch(a)!

        // glue feeds ok:false when canEvaluatePolicy is false
        let b = c.onAuthCompleted(epoch: epoch, ok: false, isActive: true, now: t(0.1))
        XCTAssertEqual(countPresents(b), 0)
        XCTAssertFalse(c.isAuthenticating)
        XCTAssertTrue(c.isLocked)

        // no auto-present until a manual rearm
        let d = c.onBecomeActive(autoLockMinutes: 0, isActive: true, now: t(0.2))
        XCTAssertEqual(countPresents(d), 0)

        let e = c.onManualUnlock(isActive: true)
        XCTAssertEqual(countPresents(e), 1)
    }

    // Security: a hard security lock (screen sleep / session change)
    // must NOT be undone by the soft grace window — waking inside `autoLockMinutes`
    // after a security resign must STAY locked and require fresh Touch ID.
    func testSecurityResignIsNotConsumedByGraceWindowOnWake() {
        var c = LockController()
        _ = c.onSecurityResign(requireBiometric: true, hasSession: true, now: t(0))
        XCTAssertTrue(c.isLocked)
        // Wake 60s later with a 5-minute grace — well inside the window.
        let wake = c.onBecomeActive(autoLockMinutes: 5, isActive: true, now: t(60))
        XCTAssertTrue(c.isLocked, "security lock must not auto-reveal through the grace window")
        XCTAssertEqual(countPresents(wake), 1, "fresh Touch ID required after a security lock")
    }

    // Security: a cancelled/launch lock (`inactiveSince == nil`) must NOT be downgraded
    // to a grace-eligible lock by a resign while already locked. Otherwise: launch lock
    // → cancel Face ID → background → return within autoLockMinutes auto-unlocks with no
    // authentication.
    func testCancelledAuthLockStaysLockedAcrossBackgroundReturnWithinGrace() {
        var c = LockController()
        let t = Date(timeIntervalSince1970: 10_000)
        _ = c.lockIfEnabled(requireBiometric: true, hasSession: true)      // launch lock (no grace)
        XCTAssertTrue(c.isLocked)
        let present = c.onBecomeActive(autoLockMinutes: 5, isActive: true, now: t)
        guard case let .presentAuth(epoch) = present.first(where: { if case .presentAuth = $0 { return true } else { return false } }) else {
            return XCTFail("expected presentAuth on first activation")
        }
        _ = c.onAuthCompleted(epoch: epoch, ok: false, isActive: true, now: t)  // user CANCELS → stays locked
        XCTAssertTrue(c.isLocked)
        // background, then return within the 5-minute grace window
        _ = c.onAppResign(requireBiometric: true, hasSession: true, now: t.addingTimeInterval(10))
        let back = c.onBecomeActive(autoLockMinutes: 5, isActive: true, now: t.addingTimeInterval(20))
        // MUST stay locked (a cancelled/launch lock is NOT grace-eligible) and re-present.
        XCTAssertTrue(c.isLocked, "a no-grace lock must not be downgraded to a grace lock by a resign")
        XCTAssertTrue(back.contains { if case .presentAuth = $0 { return true } else { return false } },
                      "should re-present after the resign re-arms the gate")
    }
}
