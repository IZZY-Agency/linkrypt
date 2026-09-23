import Foundation

/// Pure state machine for the app lock. All transitions live here so the app's
/// `AppLock` wrapper carries only LAContext + lifecycle glue.
///
/// Model ("deactivation + grace"): content is hidden (locked) the moment the
/// app goes inactive. On return, it auto-reveals WITHOUT Touch ID if the user
/// came back within `autoLockMinutes` (a brief switch); after the grace window
/// (or `autoLockMinutes == 0`), it stays locked and Touch ID is required.
public struct LockStateMachine: Equatable {
    public private(set) var isLocked = false
    private var inactiveSince: Date?

    public init() {}

    /// Lock now if biometric is enabled and a session exists (launch arm).
    /// `inactiveSince` stays nil so the first activation does NOT auto-reveal.
    public mutating func lockIfEnabled(requireBiometric: Bool, hasSession: Bool) {
        if requireBiometric && hasSession { isLocked = true }
    }

    /// Hard lock from a security event (screen sleep / session change). Forces
    /// `inactiveSince = nil` like the launch arm, so the next activation can NOT
    /// auto-reveal through the grace window — fresh Touch ID is required even if
    /// the wake lands within `autoLockMinutes`.
    public mutating func forceLock(requireBiometric: Bool, hasSession: Bool) {
        guard requireBiometric, hasSession else { return }
        isLocked = true
        inactiveSince = nil
    }

    /// App went inactive — hide content immediately and record when, so the
    /// return can decide whether to auto-reveal.
    public mutating func onResignActive(requireBiometric: Bool, hasSession: Bool, now: Date) {
        guard requireBiometric, hasSession else { return }
        // Only a fresh lock-from-unlocked is grace-eligible. A resign while ALREADY
        // locked (launch / security / cancelled-auth lock — `inactiveSince == nil`)
        // must NOT start a grace window, or the lock becomes bypassable: cancel →
        // background → return-within-grace would auto-unlock with no authentication.
        guard !isLocked else { return }
        inactiveSince = now
        isLocked = true
    }

    /// App became active again — auto-reveal only if within the grace window.
    /// Launch-lock (nil `inactiveSince`) never auto-reveals.
    public mutating func onBecomeActive(autoLockMinutes: Int, now: Date) {
        guard isLocked, inactiveSince != nil else { return }
        if !AppLockPolicy.shouldLock(inactiveSince: inactiveSince, now: now, graceMinutes: autoLockMinutes) {
            isLocked = false
            inactiveSince = nil
        }
    }

    /// Manual Touch ID / password success.
    public mutating func onUnlockSucceeded() {
        isLocked = false
        inactiveSince = nil
    }
}
