import Foundation

/// The expiry / max-opens presets offered by the ⌥⇧V quick-share overlay, and
/// the rule for stepping through them from the keyboard (`e` / `o`).
///
/// Pure so the cycling order — including the wrap and the unknown-value
/// fallback — is unit-testable without an event loop or a live panel.
public enum PresetCycle {
    /// Must mirror the EXPIRES buttons in `HotkeyOverlay`.
    public static let expiries: [String] = ["1h", "24h", "7d"]
    /// Must mirror the OPENS buttons in `HotkeyOverlay`.
    public static let opens: [Int] = [1, 5]

    /// The next option after `current`, wrapping at the end.
    ///
    /// A `current` that isn't in `options` resolves to the first option, so a
    /// value set elsewhere can never leave the cycle stuck. Empty `options`
    /// returns `current` unchanged.
    public static func next<T: Equatable>(_ current: T, in options: [T]) -> T {
        guard let i = options.firstIndex(of: current) else { return options.first ?? current }
        return options[(i + 1) % options.count]
    }

    /// `value` if it is one of `options`, otherwise `def`. Used to sanitise a
    /// persisted preset before it is offered to the server.
    public static func clamp<T: Equatable>(_ value: T, to options: [T], default def: T) -> T {
        options.contains(value) ? value : def
    }
}
