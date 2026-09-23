import AppKit

/// Settings › General › "Show in Dock" → activation policy. `.accessory` is a
/// menu-bar utility: no Dock tile, no app menu (About/Settings stay reachable
/// from the menu-bar popover header and the dashboard sidebar). Applied at
/// launch (`activate: false` — a login-item / "Launch hidden" start must not
/// steal focus from whatever the user is doing) and whenever the toggle
/// changes (`activate: true` — switching policy drops key/main status, so
/// re-activate to keep the Settings window in front).
@MainActor
enum DockIcon {
    static func apply(show: Bool, activate: Bool = true) {
        let want: NSApplication.ActivationPolicy = show ? .regular : .accessory
        guard NSApp.activationPolicy() != want else { return }
        NSApp.setActivationPolicy(want)
        if activate { NSApp.activate(ignoringOtherApps: true) }
    }
}
