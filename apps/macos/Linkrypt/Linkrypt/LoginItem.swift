import Foundation
import ServiceManagement
import LinkryptCore

/// Thin glue over `SMAppService.mainApp` (macOS 13+). The system is the source
/// of truth — nothing is persisted in UserDefaults. `refresh()` re-reads the
/// status when Settings appears and when the app re-activates, so an approval
/// or removal made in System Settings › Login Items shows up.
///
/// Note: the registration is bound to the bundle's path, so it only stays
/// valid when the app runs from a stable location (e.g. /Applications).
@MainActor
@Observable
final class LoginItemController {
    private(set) var status: LoginItemStatus = .notRegistered
    var lastError: String?

    init() { refresh() }

    /// Re-reads the system status and drops any stale error — an approval or
    /// repair made in System Settings supersedes a failure shown earlier.
    func refresh() {
        status = Self.map(SMAppService.mainApp.status)
        lastError = nil
    }

    /// `register()` may leave the item in `.requiresApproval`; the toggle then
    /// reads as ON with a hint (see `LoginItemStatus.isOn`). A never-registered
    /// app reports `.notFound` on macOS 27 — plain OFF, see `LoginItemStatus`.
    func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch {
            refresh()
            lastError = error.localizedDescription
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    static func map(_ s: SMAppService.Status) -> LoginItemStatus {
        switch s {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return .notRegistered
        @unknown default: return .notRegistered
        }
    }
}
