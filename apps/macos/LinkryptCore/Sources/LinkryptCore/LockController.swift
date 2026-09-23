import Foundation

/// Side effects the controller wants the (impure) glue to perform. Pure data so
/// every notification ordering is unit-testable.
public enum LockAction: Equatable {
    case presentAuth(epoch: Int)
    case invalidateAuth
    case dismissHotkeyPanel
}

/// Pure decision core for the app lock: events in → `[LockAction]` out. Owns the
/// `LockStateMachine`, the `AuthPromptGate`, and the auth lifecycle (the
/// in-flight flag, the inactive-success "pending unlock" + its freshness
/// deadline, and an epoch that drops stale `evaluatePolicy` callbacks). The
/// app's `AppLock` is a thin performer over this; all the race semantics live
/// here so they can be tested without an app target.
public struct LockController {
    public private(set) var isLocked = false
    public private(set) var isAuthenticating = false
    private var machine = LockStateMachine()
    private var gate = AuthPromptGate()
    /// An authenticated-but-inactive success, applied when the app is active.
    private var pendingUnlock = false
    /// Freshness deadline for `pendingUnlock` — covers ONLY the immediate
    /// dialog-dismiss reactivation race.
    private var pendingUnlockAt: Date?
    /// Bumped on every present/invalidate; stale auth callbacks are dropped.
    private var epoch = 0

    /// `pendingUnlock` is valid only for the activation that immediately follows
    /// the dialog dismissal (a sub-second false→true `NSApp.isActive` read).
    /// Beyond this it is dropped so a success that landed while the user
    /// genuinely switched away can NOT silently reveal on a much-later return.
    /// Kept tight (the dialog-dismiss reactivation is ~ms); the accepted
    /// tradeoff is that a real away shorter than this window could still consume
    /// the pending unlock.
    public static let pendingUnlockWindow: TimeInterval = 2

    public init() {}

    public mutating func lockIfEnabled(requireBiometric: Bool, hasSession: Bool) -> [LockAction] {
        machine.lockIfEnabled(requireBiometric: requireBiometric, hasSession: hasSession)
        return reconcile()
    }

    /// `didResignActive` ONLY (soft). The auth dialog's own resign is ignored so
    /// presenting Touch ID doesn't cancel itself.
    public mutating func onAppResign(requireBiometric: Bool, hasSession: Bool, now: Date) -> [LockAction] {
        if isAuthenticating { return [] }   // this is our Touch ID dialog, not a user switch
        machine.onResignActive(requireBiometric: requireBiometric, hasSession: hasSession, now: now)
        gate.onRearm()                      // genuine switch-away re-arms…
        pendingUnlock = false; pendingUnlockAt = nil   // …and abandons any pending success
        return reconcile()
    }

    /// `screensDidSleep` / `sessionDidResignActive` (HARD security — always lock
    /// and kill any in-flight auth, even mid-prompt).
    public mutating func onSecurityResign(requireBiometric: Bool, hasSession: Bool, now: Date) -> [LockAction] {
        machine.forceLock(requireBiometric: requireBiometric, hasSession: hasSession)   // no-grace lock: a security event always needs fresh auth
        var a: [LockAction] = []
        if isAuthenticating {
            isAuthenticating = false
            epoch &+= 1                     // any pending callback is now stale
            a.append(.invalidateAuth)
        }
        gate.onRearm()
        pendingUnlock = false; pendingUnlockAt = nil
        return a + reconcile()
    }

    public mutating func onBecomeActive(autoLockMinutes: Int, isActive: Bool, now: Date) -> [LockAction] {
        machine.onBecomeActive(autoLockMinutes: autoLockMinutes, now: now)
        if pendingUnlock {                  // a success that landed while momentarily inactive
            let fresh = pendingUnlockAt.map {
                let e = now.timeIntervalSince($0)
                return e >= 0 && e < Self.pendingUnlockWindow   // e>=0 guards a backward clock jump
            } ?? false
            if isActive && fresh { machine.onUnlockSucceeded() }   // consume ONLY on the immediate re-activation
            pendingUnlock = false; pendingUnlockAt = nil           // consumed OR expired → drop
        }
        return reconcile(isActive: isActive)
    }

    public mutating func onManualUnlock(isActive: Bool) -> [LockAction] {
        gate.onRearm()
        return reconcile(isActive: isActive)
    }

    public mutating func onAuthCompleted(epoch e: Int, ok: Bool, isActive: Bool, now: Date) -> [LockAction] {
        guard e == epoch else { return [] }   // stale (superseded by invalidate/new present)
        isAuthenticating = false
        if ok {
            if isActive { machine.onUnlockSucceeded() }            // reveal only while active…
            else { pendingUnlock = true; pendingUnlockAt = now }   // …else stash with a freshness deadline
        } else {
            gate.onAuthDismissed()            // cancel/fail → don't auto-re-prompt
        }
        return reconcile(isActive: isActive)
    }

    /// Emit `presentAuth`/`dismissHotkeyPanel` based on current state; updates
    /// `isLocked`/`isAuthenticating`.
    private mutating func reconcile(isActive: Bool = false) -> [LockAction] {
        var a: [LockAction] = []
        let wasLocked = isLocked
        isLocked = machine.isLocked
        if isLocked && !wasLocked { a.append(.dismissHotkeyPanel) }
        if gate.shouldAutoPrompt(isLocked: isLocked, isActive: isActive, isAuthenticating: isAuthenticating) {
            isAuthenticating = true
            epoch &+= 1
            a.append(.presentAuth(epoch: epoch))
        }
        return a
    }
}
