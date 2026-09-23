import SwiftUI
import LocalAuthentication
import LinkryptCore

/// Thin app glue around the pure `LockController`. The controller owns ALL lock
/// decisions and race semantics (events → `[LockAction]`); `AppLock` only
/// performs those actions — runs `LAContext`, reads `NSApp.isActive`, fires
/// `onLock` to dismiss the hotkey panel — and mirrors the controller's
/// `isLocked`/`isAuthenticating` for SwiftUI.
@MainActor
@Observable
final class AppLock {
    private(set) var isLocked = false
    private(set) var isAuthenticating = false
    var lastError: String?

    private let prefs: Preferences
    private var controller = LockController()
    /// Kept so an `.invalidateAuth` action can cancel the in-flight prompt.
    private var context: LAContext?
    /// Runs when the lock transitions into the locked state.
    var onLock: (() -> Void)?

    /// The app's one lock, for code paths with no environment access (the
    /// models' NSSave/NSOpenPanel helpers). Weak so previews/tests never pin it.
    private(set) static weak var current: AppLock?

    init(prefs: Preferences) { self.prefs = prefs; AppLock.current = self }

    /// Runs a save/open panel modally INSIDE the lock boundary. Refuses while
    /// locked, a lock that lands mid-panel aborts it (see `perform`), and the
    /// result is re-checked after return so a stale `.OK` can never reach a
    /// decrypted-file write or a picked-file read. `NSOpenPanel` is a subclass.
    static func runModal(_ panel: NSSavePanel) -> NSApplication.ModalResponse {
        guard current?.isLocked != true else { return .abort }
        let r = panel.runModal()
        return current?.isLocked == true ? .abort : r
    }

    // MARK: - Lifecycle entry points (forward to the controller, perform actions)

    func lockIfEnabled(hasSession: Bool) {
        perform(controller.lockIfEnabled(requireBiometric: prefs.requireBiometric, hasSession: hasSession))
    }

    /// `didResignActive` only (soft) — the auth dialog's own resign is ignored
    /// inside the controller, so presenting Touch ID no longer cancels itself.
    func onResignActive(hasSession: Bool, now: Date = Date()) {
        perform(controller.onAppResign(requireBiometric: prefs.requireBiometric, hasSession: hasSession, now: now))
    }

    /// `screensDidSleep` / `sessionDidResignActive` (hard security) — always
    /// locks and kills any in-flight auth, even mid-prompt.
    func onSecurityResign(hasSession: Bool, now: Date = Date()) {
        perform(controller.onSecurityResign(requireBiometric: prefs.requireBiometric, hasSession: hasSession, now: now))
    }

    func onBecomeActive(now: Date = Date()) {
        perform(controller.onBecomeActive(autoLockMinutes: prefs.autoLockMinutes, isActive: NSApp.isActive, now: now))
    }

    /// LockView's manual Unlock button — re-arms the gate and re-presents.
    func unlock() {
        perform(controller.onManualUnlock(isActive: NSApp.isActive))
    }

    // MARK: - Action performer

    private func perform(_ actions: [LockAction]) {
        for action in actions {
            switch action {
            case let .presentAuth(epoch):
                presentAuth(epoch: epoch)
            case .invalidateAuth:
                context?.invalidate()
            case .dismissHotkeyPanel:               // = "lock engaged"
                onLock?()
                // A native save/open panel is its own window and ignores the
                // SwiftUI LockGate — take it down with the lock. `NSApp` is
                // still nil during `LinkryptApp.init` (the launch-time
                // lockIfEnabled lands here) — force-unwrapping it would crash
                // every Touch-ID-enabled launch.
                if let app = NSApp, app.modalWindow != nil { app.abortModal() }
            }
        }
        // Mirror the controller's state for SwiftUI after performing.
        isLocked = controller.isLocked
        isAuthenticating = controller.isAuthenticating
    }

    private func presentAuth(epoch: Int) {
        lastError = nil
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Enter Password"
        context = ctx
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            lastError = "Biometric/password unlock isn't available on this Mac."
            perform(controller.onAuthCompleted(epoch: epoch, ok: false, isActive: NSApp.isActive, now: Date()))
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Linkrypt") { ok, err in
            Task { @MainActor in
                self.perform(self.controller.onAuthCompleted(epoch: epoch, ok: ok, isActive: NSApp.isActive, now: Date()))
                self.lastError = ok ? nil : err?.localizedDescription
            }
        }
    }
}
