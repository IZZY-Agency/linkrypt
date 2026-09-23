import Foundation
import LinkryptCore

/// UserDefaults-backed `KeyValueStore` for the app.
final class UserDefaultsKeyValueStore: KeyValueStore {
    private let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    func bool(_ key: String, default def: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? def : defaults.bool(forKey: key)
    }
    func setBool(_ value: Bool, _ key: String) { defaults.set(value, forKey: key) }
    func int(_ key: String, default def: Int) -> Int {
        defaults.object(forKey: key) == nil ? def : defaults.integer(forKey: key)
    }
    func setInt(_ value: Int, _ key: String) { defaults.set(value, forKey: key) }
    func string(_ key: String, default def: String) -> String {
        defaults.object(forKey: key) == nil ? def : (defaults.string(forKey: key) ?? def)
    }
    func setString(_ value: String, _ key: String) { defaults.set(value, forKey: key) }
}

/// Observable wrapper SwiftUI binds to. Reads/writes go through `PreferencesState`
/// so defaults/keys live in LinkryptCore (and are unit-tested there).
@MainActor
@Observable
final class Preferences {
    private let state: PreferencesState

    /// Stored so `@Observable` tracks mutations and invalidates scene roots on
    /// language change. A computed forward to `state` would NOT fire observation.
    var appLanguage: AppLanguage {
        didSet {
            state.appLanguage = appLanguage
            Preferences.applyAppleLanguages(appLanguage)
        }
    }

    /// Locale injected into the SwiftUI environment. `system` → OS default.
    var resolvedLocale: Locale {
        appLanguage == .system ? .autoupdatingCurrent : Locale(identifier: appLanguage.rawValue)
    }

    /// Clamped BCP-47 code for recipient links / emails (the server serves en/fr/uk).
    var languageCode: String {
        AppLanguage.resolveCode(appLanguage, preferred: Locale.preferredLanguages,
                                supported: Preferences.linkLanguages)
    }

    static let linkLanguages = ["en", "fr", "uk"]   // the languages linkrypt.sh serves

    private static func applyAppleLanguages(_ lang: AppLanguage) {
        let d = UserDefaults.standard
        if lang == .system { d.removeObject(forKey: "AppleLanguages") }
        else { d.set([lang.rawValue], forKey: "AppleLanguages") }
    }

    // These MUST be stored (not computed forwards to `state`): `@Observable`
    // only tracks the wrapper's own stored properties, so a computed forward
    // would persist to UserDefaults but never re-render the Settings controls
    // (the toggles would appear not to flip).
    // `didSet` mirrors the durable value into `PreferencesState`.
    var burnClipboard: Bool { didSet { state.burnClipboard = burnClipboard } }
    var burnClipboardSeconds: Int { didSet { state.burnClipboardSeconds = burnClipboardSeconds } }
    var persistLinks: Bool { didSet { state.persistLinks = persistLinks } }
    var requireBiometric: Bool { didSet { state.requireBiometric = requireBiometric } }
    var autoLockMinutes: Int {
        didSet {
            if autoLockMinutes < 0 { autoLockMinutes = 0; return }   // preserve the ≥0 invariant (re-fires didSet, then mirrors)
            state.autoLockMinutes = autoLockMinutes
        }
    }
    // General (Settings › General). Side effects (activation policy, hotkey
    // registration) are applied by the Settings toggles, not here — this type
    // stays AppKit-free.
    var launchHidden: Bool { didSet { state.launchHidden = launchHidden } }
    var showInDock: Bool { didSet { state.showInDock = showInDock } }
    var globalHotkeyEnabled: Bool { didSet { state.globalHotkeyEnabled = globalHotkeyEnabled } }
    // Quick-share defaults (⌥⇧V overlay + menu-bar button). Clamped to the
    // overlay presets by `PreferencesState` on read.
    var quickShareExpiry: String { didSet { state.quickShareExpiry = quickShareExpiry } }
    var quickShareMaxOpens: Int { didSet { state.quickShareMaxOpens = quickShareMaxOpens } }

    init(store: any KeyValueStore = UserDefaultsKeyValueStore()) {
        self.state = PreferencesState(store: store)
        // Seed stored props from the durable state. `didSet` does NOT fire for
        // these initial assignments, so there's no redundant write-back.
        self.appLanguage = state.appLanguage
        self.burnClipboard = state.burnClipboard
        self.burnClipboardSeconds = state.burnClipboardSeconds
        self.persistLinks = state.persistLinks
        self.requireBiometric = state.requireBiometric
        self.autoLockMinutes = state.autoLockMinutes
        self.launchHidden = state.launchHidden
        self.showInDock = state.showInDock
        self.globalHotkeyEnabled = state.globalHotkeyEnabled
        self.quickShareExpiry = state.quickShareExpiry
        self.quickShareMaxOpens = state.quickShareMaxOpens
    }
}
