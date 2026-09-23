import Foundation

/// Platform-neutral mirror of `SMAppService.Status` (ServiceManagement is
/// macOS-only; this package also builds for iOS). The app maps the system
/// status onto this and the Settings toggle reads the derived flags below.
public enum LoginItemStatus: Sendable, Equatable {
    /// Never registered, or the user turned it off.
    case notRegistered
    /// Registered and eligible to launch at login.
    case enabled
    /// Registered, but macOS is holding it until the user approves it in
    /// System Settings › General › Login Items.
    case requiresApproval
    /// Apple documents this as "the framework couldn't find the service", but
    /// on macOS 27.0 (26A5425a) `mainApp.status` is `.notFound` for a bundle
    /// that has NEVER registered — from any location (verified 2026-09-04 with
    /// a probe app: never-registered → notFound, register() → enabled,
    /// unregister() → notRegistered). So it is the initial state, not an
    /// error, and reads as plain OFF. A real failure surfaces as `register()`
    /// throwing.
    case notFound

    /// What the toggle shows. `requiresApproval` reads as ON: the user asked
    /// for it; only the OS-side approval is outstanding.
    public var isOn: Bool {
        switch self {
        case .enabled, .requiresApproval: return true
        case .notRegistered, .notFound: return false
        }
    }

    /// Show the "approve in System Settings" hint + deep link.
    public var needsApproval: Bool { self == .requiresApproval }
}
