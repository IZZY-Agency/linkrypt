import Foundation

/// Owns the process-global ⌥⇧V registration so Settings › General can turn it
/// on/off at runtime. `GlobalHotkey` registers in `init` and unregisters in
/// `deinit`, so enabling/disabling is holding or dropping the instance.
@MainActor
enum HotkeyRegistration {
    private static var live: GlobalHotkey?
    private static var fire: (@Sendable () -> Void)?

    /// Call once at launch with the action, then `setEnabled` per the preference.
    static func configure(fire: @escaping @Sendable () -> Void) { self.fire = fire }

    /// Returns whether the hotkey is live afterwards. `setEnabled(true)` can
    /// return false when Carbon refuses the registration (shortcut owned by
    /// another app); the instance is dropped so `isRegistered` stays truthful.
    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        if on {
            if live != nil { return true }
            guard let fire else { return false }
            let hk = GlobalHotkey(onFire: fire)
            guard hk.isRegistered else { return false }
            live = hk
            return true
        } else {
            live = nil
            return false
        }
    }

    static var isRegistered: Bool { live != nil }
}
