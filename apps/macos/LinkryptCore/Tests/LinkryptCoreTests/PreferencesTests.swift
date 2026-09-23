import XCTest
@testable import LinkryptCore

final class PreferencesTests: XCTestCase {
    func testDefaultsWhenStoreEmpty() {
        let s = PreferencesState(store: InMemoryKeyValueStore())
        XCTAssertFalse(s.burnClipboard)
        XCTAssertEqual(s.burnClipboardSeconds, 60)
        XCTAssertTrue(s.persistLinks)
    }

    func testRoundTripThroughStore() {
        let store = InMemoryKeyValueStore()
        do {
            let s = PreferencesState(store: store)
            s.burnClipboard = true
            s.burnClipboardSeconds = 30
            s.persistLinks = false
        }
        let reloaded = PreferencesState(store: store)
        XCTAssertTrue(reloaded.burnClipboard)
        XCTAssertEqual(reloaded.burnClipboardSeconds, 30)
        XCTAssertFalse(reloaded.persistLinks)
    }

    func testSecurityDefaults() {
        let s = PreferencesState(store: InMemoryKeyValueStore())
        XCTAssertFalse(s.requireBiometric)
        XCTAssertEqual(s.autoLockMinutes, 5)
    }

    func testSecurityRoundTrip() {
        let store = InMemoryKeyValueStore()
        do { let s = PreferencesState(store: store); s.requireBiometric = true; s.autoLockMinutes = 1 }
        let r = PreferencesState(store: store)
        XCTAssertTrue(r.requireBiometric)
        XCTAssertEqual(r.autoLockMinutes, 1)
    }

    func testAutoLockMinutesClampsNegative() {
        let store = InMemoryKeyValueStore()
        store.setInt(-30, PreferencesState.Key.autoLockMinutes)
        XCTAssertEqual(PreferencesState(store: store).autoLockMinutes, 0)
    }

    func testKeyValueStoreString() {
        let s = InMemoryKeyValueStore()
        XCTAssertEqual(s.string("k", default: "d"), "d")
        s.setString("v", "k")
        XCTAssertEqual(s.string("k", default: "d"), "v")
    }
    func testAppLanguageDefaultsToSystem() {
        let st = PreferencesState(store: InMemoryKeyValueStore())
        XCTAssertEqual(st.appLanguage, .system)
    }
    func testAppLanguageRoundTrips() {
        let st = PreferencesState(store: InMemoryKeyValueStore())
        st.appLanguage = .uk
        XCTAssertEqual(st.appLanguage, .uk)
    }
    func testAppLanguageUnknownStoredValueFallsBackToSystem() {
        let store = InMemoryKeyValueStore()
        store.setString("klingon", PreferencesState.Key.appLanguage)
        let st = PreferencesState(store: store)
        XCTAssertEqual(st.appLanguage, .system)
    }

    // MARK: - General (About/Settings window)

    func testGeneralDefaults() {
        let s = PreferencesState(store: InMemoryKeyValueStore())
        XCTAssertFalse(s.launchHidden)
        XCTAssertTrue(s.showInDock)
        XCTAssertTrue(s.globalHotkeyEnabled)
    }

    func testGeneralRoundTrip() {
        let store = InMemoryKeyValueStore()
        do {
            let s = PreferencesState(store: store)
            s.launchHidden = true
            s.showInDock = false
            s.globalHotkeyEnabled = false
        }
        let r = PreferencesState(store: store)
        XCTAssertTrue(r.launchHidden)
        XCTAssertFalse(r.showInDock)
        XCTAssertFalse(r.globalHotkeyEnabled)
    }

    // MARK: - Quick-share defaults (⌥⇧V overlay + menu-bar button)

    /// Defaults must equal what the overlay and menu bar hardcoded before the
    /// preference existed, so existing users see no behaviour change.
    func testQuickShareDefaultsMatchPreviousHardcodedPreset() {
        let s = PreferencesState(store: InMemoryKeyValueStore())
        XCTAssertEqual(s.quickShareExpiry, "24h")
        XCTAssertEqual(s.quickShareMaxOpens, 1)
    }

    func testQuickShareRoundTrip() {
        let store = InMemoryKeyValueStore()
        do { let s = PreferencesState(store: store); s.quickShareExpiry = "7d"; s.quickShareMaxOpens = 5 }
        let r = PreferencesState(store: store)
        XCTAssertEqual(r.quickShareExpiry, "7d")
        XCTAssertEqual(r.quickShareMaxOpens, 5)
    }

    /// A tampered/stale UserDefaults value that isn't one of the overlay's
    /// presets must resolve to the default, never reach the server as-is.
    func testQuickShareUnknownStoredValuesFallBackToDefaults() {
        let store = InMemoryKeyValueStore()
        store.setString("90d", PreferencesState.Key.quickShareExpiry)
        store.setInt(0, PreferencesState.Key.quickShareMaxOpens)
        let s = PreferencesState(store: store)
        XCTAssertEqual(s.quickShareExpiry, "24h")
        XCTAssertEqual(s.quickShareMaxOpens, 1)
    }
}
