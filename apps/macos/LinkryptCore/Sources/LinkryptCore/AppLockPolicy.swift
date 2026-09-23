import Foundation

/// Auto-lock decision for the "deactivation + grace" model: lock when the app
/// becomes active again after being inactive for at least `graceMinutes`. Pure
/// (caller injects `now`/`inactiveSince`) so it's unit-testable.
public enum AppLockPolicy {
    public static func shouldLock(inactiveSince: Date?, now: Date, graceMinutes: Int) -> Bool {
        guard let inactiveSince else { return false }
        let elapsed = max(0, now.timeIntervalSince(inactiveSince)) // guard clock skew
        return elapsed >= Double(graceMinutes) * 60
    }
}
