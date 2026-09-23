import Foundation

/// Abstraction over a key/value backing store so `PreferencesState` is testable
/// without `UserDefaults`. The app injects a `UserDefaults`-backed impl.
public protocol KeyValueStore: AnyObject {
    func bool(_ key: String, default def: Bool) -> Bool
    func setBool(_ value: Bool, _ key: String)
    func int(_ key: String, default def: Int) -> Int
    func setInt(_ value: Int, _ key: String)
    func string(_ key: String, default def: String) -> String
    func setString(_ value: String, _ key: String)
}

public final class InMemoryKeyValueStore: KeyValueStore {
    private var bools: [String: Bool] = [:]
    private var ints: [String: Int] = [:]
    private var strings: [String: String] = [:]
    public init() {}
    public func bool(_ key: String, default def: Bool) -> Bool { bools[key] ?? def }
    public func setBool(_ value: Bool, _ key: String) { bools[key] = value }
    public func int(_ key: String, default def: Int) -> Int { ints[key] ?? def }
    public func setInt(_ value: Int, _ key: String) { ints[key] = value }
    public func string(_ key: String, default def: String) -> String { strings[key] ?? def }
    public func setString(_ value: String, _ key: String) { strings[key] = value }
}

/// Non-secret on-device preferences. Pure logic + keys/defaults; the app wraps
/// this in an `@Observable` over `UserDefaults`.
public final class PreferencesState {
    private let store: any KeyValueStore

    public enum Key {
        public static let burnClipboard = "pref.burnClipboard"
        public static let burnClipboardSeconds = "pref.burnClipboardSeconds"
        public static let persistLinks = "pref.persistLinks"
        public static let requireBiometric = "pref.requireBiometric"
        public static let autoLockMinutes = "pref.autoLockMinutes"
        public static let appLanguage = "pref.appLanguage"
        public static let launchHidden = "pref.launchHidden"
        public static let showInDock = "pref.showInDock"
        public static let globalHotkeyEnabled = "pref.globalHotkeyEnabled"
        public static let quickShareExpiry = "pref.quickShareExpiry"
        public static let quickShareMaxOpens = "pref.quickShareMaxOpens"
    }

    public init(store: any KeyValueStore) { self.store = store }

    public var requireBiometric: Bool {
        get { store.bool(Key.requireBiometric, default: false) }
        set { store.setBool(newValue, Key.requireBiometric) }
    }
    /// Grace minutes before auto-lock on return. Clamped ≥ 0 at the boundary so
    /// a corrupted/tampered UserDefaults value can't yield a negative grace.
    public var autoLockMinutes: Int {
        get { max(0, store.int(Key.autoLockMinutes, default: 5)) }
        set { store.setInt(max(0, newValue), Key.autoLockMinutes) }
    }

    public var burnClipboard: Bool {
        get { store.bool(Key.burnClipboard, default: false) }
        set { store.setBool(newValue, Key.burnClipboard) }
    }
    public var burnClipboardSeconds: Int {
        get { store.int(Key.burnClipboardSeconds, default: 60) }
        set { store.setInt(newValue, Key.burnClipboardSeconds) }
    }
    public var persistLinks: Bool {
        get { store.bool(Key.persistLinks, default: true) }
        set { store.setBool(newValue, Key.persistLinks) }
    }

    public var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: store.string(Key.appLanguage, default: "system")) ?? .system }
        set { store.setString(newValue.rawValue, Key.appLanguage) }
    }

    // MARK: General (Settings › General)

    /// Don't present the main window at launch — menu-bar item only. Read once
    /// at launch (scene launch behaviour), so changes apply on next start.
    public var launchHidden: Bool {
        get { store.bool(Key.launchHidden, default: false) }
        set { store.setBool(newValue, Key.launchHidden) }
    }
    /// `false` → accessory activation policy (no Dock icon, no app menu).
    public var showInDock: Bool {
        get { store.bool(Key.showInDock, default: true) }
        set { store.setBool(newValue, Key.showInDock) }
    }
    /// Whether the process-global ⌥⇧V hotkey is registered.
    public var globalHotkeyEnabled: Bool {
        get { store.bool(Key.globalHotkeyEnabled, default: true) }
        set { store.setBool(newValue, Key.globalHotkeyEnabled) }
    }

    // MARK: Quick-share defaults (⌥⇧V overlay + menu-bar "Encrypt clipboard now")

    /// Clamped to `PresetCycle.expiries` on read, so a stale/tampered value can
    /// never reach the server; the defaults equal the previously hardcoded preset.
    public var quickShareExpiry: String {
        get { PresetCycle.clamp(store.string(Key.quickShareExpiry, default: "24h"),
                                to: PresetCycle.expiries, default: "24h") }
        set { store.setString(newValue, Key.quickShareExpiry) }
    }
    public var quickShareMaxOpens: Int {
        get { PresetCycle.clamp(store.int(Key.quickShareMaxOpens, default: 1),
                                to: PresetCycle.opens, default: 1) }
        set { store.setInt(newValue, Key.quickShareMaxOpens) }
    }
}
