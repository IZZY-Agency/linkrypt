import SwiftUI
import LinkryptCore

/// Settings scene (⌘, / app menu / menu-bar ⚙ / sidebar). Three tabs so the
/// window stays a fixed size; each panel is one preference group.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var prefs
    @Environment(LoginItemController.self) private var loginItem
    @Environment(AppLock.self) private var lock
    @Environment(\.openWindow) private var openWindow
    enum Tab: Hashable { case general, sharing, security }
    @State private var tab: Tab = .general
    @State private var error: String?
    @State private var confirmClear = false
    @State private var hotkeyFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("// SETTINGS").font(LK.mono(10)).tracking(1.5).foregroundStyle(LK.fgMuted)
            if lock.isLocked {
                // Same boundary as the main window: nothing here (Touch ID off,
                // link persistence, clear cache…) is reachable behind the lock.
                locked
            } else {
                LKSegmented(selection: $tab, items: [
                    (.general, "General"), (.sharing, "Sharing"), (.security, "Security"),
                ])
                switch tab {
                case .general: general
                case .sharing: sharing
                case .security: security
                }
            }
            Spacer()
        }
        .padding(20).frame(width: 460, height: 620).background(LK.bg)
        .onAppear {
            loginItem.refresh()
            hotkeyFailed = prefs.globalHotkeyEnabled && !HotkeyRegistration.isRegistered
        }
        .confirmationDialog("Clear all cached links?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) {
                guard !lock.isLocked else { return }   // dialog outlives the locked branch
                do { try model.linkCache.clearAll(); error = nil }
                catch { self.error = "Couldn't clear the Keychain — links remain. (\(error))" }
            }
        } message: {
            Text("Removes every copy-link from this device. They can't be recovered.")
        }
    }

    // MARK: Locked

    private var locked: some View {
        LKPanel(label: "Locked", padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Linkrypt is locked").font(LK.sans(13)).foregroundStyle(LK.fg)
                Text("Unlock from the main window to change settings.")
                    .font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                LKButton(title: "open the app", arrow: true) { MainWindow.open(openWindow) }
            }
        }
    }

    // MARK: General

    private var general: some View {
        @Bindable var prefs = prefs
        return VStack(alignment: .leading, spacing: 18) {
            // ── Startup ───────────────────────────────────────────────
            LKPanel(label: "Startup", padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    LKToggle(isOn: Binding(get: { loginItem.status.isOn }, set: { loginItem.setEnabled($0) }),
                             title: "Start at login",
                             hint: "open Linkrypt when you sign in to your Mac")
                    if loginItem.status.needsApproval {
                        Text("Waiting for your approval in System Settings › General › Login Items.")
                            .font(LK.mono(10)).foregroundStyle(LK.amber)
                            .fixedSize(horizontal: false, vertical: true)
                        LKButton(title: "open login items", arrow: true) { loginItem.openSystemSettings() }
                    }
                    if let e = loginItem.lastError {
                        Text("× \(e)").font(LK.mono(10)).foregroundStyle(LK.err)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LKToggle(isOn: $prefs.launchHidden, title: "Launch hidden",
                             hint: "start in the menu bar only; open the dashboard from there")
                    Text("Login-item changes need a stable app location (e.g. /Applications). Launch hidden applies from the next start.")
                        .font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // ── Dock & hotkey ─────────────────────────────────────────
            LKPanel(label: "Dock & hotkey", padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    LKToggle(isOn: Binding(get: { prefs.showInDock },
                                           set: { prefs.showInDock = $0; DockIcon.apply(show: $0) }),
                             title: "Show in Dock",
                             hint: "off = menu-bar utility (no Dock icon, no app menu)")
                    LKToggle(isOn: Binding(get: { prefs.globalHotkeyEnabled },
                                           set: { on in
                                               prefs.globalHotkeyEnabled = on
                                               hotkeyFailed = on && !HotkeyRegistration.setEnabled(on)
                                           }),
                             title: "Global hotkey ⌥⇧V",
                             hint: "seal the clipboard from any app")
                    if hotkeyFailed {
                        Text("× Couldn't register ⌥⇧V — another app may already use that shortcut.")
                            .font(LK.mono(10)).foregroundStyle(LK.err)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // ── Language ──────────────────────────────────────────────
            LKPanel(label: "Language", padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    LKDropdown(selection: $prefs.appLanguage, options: [
                        (.system, "System"),
                        (.en, "English"),
                        (.fr, "Français"),
                        (.uk, "Українська"),
                    ])
                    Text("Switches the app language immediately. System surfaces update on next launch.")
                        .font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                }
            }
        }
    }

    // MARK: Sharing

    private func clampQuickShareDefaults() {
        prefs.quickShareExpiry = model.limits.clamp(expiry: prefs.quickShareExpiry, candidates: PresetCycle.expiries)
        prefs.quickShareMaxOpens = model.limits.clamp(opens: prefs.quickShareMaxOpens, candidates: PresetCycle.opens)
    }

    private var sharing: some View {
        @Bindable var prefs = prefs
        return VStack(alignment: .leading, spacing: 18) {
            // ── Quick share ───────────────────────────────────────────
            LKPanel(label: "Quick share", padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Defaults for ⌥⇧V and the menu-bar “Encrypt clipboard now”.")
                        .font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        // A stored default the plan no longer accepts (e.g. "1h" on
                        // Free) would render as an empty dropdown — snap it back, on
                        // appear AND when limits land after the window is open.
                        .onAppear { clampQuickShareDefaults() }
                        .onChange(of: model.limits) { _, _ in clampQuickShareDefaults() }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EXPIRES").font(LK.mono(9)).tracking(1.2).foregroundStyle(LK.fgMuted)
                            LKDropdown(selection: $prefs.quickShareExpiry,
                                       options: model.limits.filter(expiries: PresetCycle.expiries)
                                           .map { ($0, LocalizedStringKey($0)) })
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("OPENS").font(LK.mono(9)).tracking(1.2).foregroundStyle(LK.fgMuted)
                            LKDropdown(selection: $prefs.quickShareMaxOpens,
                                       options: model.limits.filter(opens: PresetCycle.opens)
                                           .map { ($0, $0 == 1 ? "1 open" : "\($0) opens") })
                        }
                    }
                }
            }

            // ── Clipboard ─────────────────────────────────────────────
            LKPanel(label: "Clipboard", padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    LKToggle(isOn: $prefs.burnClipboard, title: "Burn copied links",
                             hint: "clear the clipboard after a delay (best-effort, while the app runs)")
                    if prefs.burnClipboard {
                        LKDropdown(selection: $prefs.burnClipboardSeconds, options: [
                            (30, "after 30s"), (60, "after 60s"), (120, "after 2 min"),
                        ])
                    }
                    Text("Doesn't recall links already read by a clipboard manager or iCloud Universal Clipboard.")
                        .font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // ── Links ─────────────────────────────────────────────────
            LKPanel(label: "Links", padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    LKToggle(isOn: Binding(get: { prefs.persistLinks }, set: { setPersist($0) }),
                             title: "Persist links across launches",
                             hint: "store copy-links in the Keychain so they survive a relaunch")
                    Button { confirmClear = true } label: {
                        Text("Clear cached links now").font(LK.mono(11)).foregroundStyle(LK.err)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Text("While off, cached links are kept only for this session and lost on quit — they can't be recovered from the server.")
                        .font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error {
                        Text("× \(error)").font(LK.mono(10)).foregroundStyle(LK.err)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Security

    private var security: some View {
        @Bindable var prefs = prefs
        return LKPanel(label: "Security", padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                LKToggle(isOn: $prefs.requireBiometric, title: "Require Touch ID",
                         hint: "lock the app; unlock with Touch ID or your Mac password")
                if prefs.requireBiometric {
                    LKDropdown(selection: $prefs.autoLockMinutes, options: [
                        (0, "lock when I switch away"), (1, "after 1 min away"),
                        (5, "after 5 min away"), (15, "after 15 min away"),
                    ])
                }
            }
        }
    }

    private func setPersist(_ on: Bool) {
        do {
            try model.linkCache.setPersistent(on)
            prefs.persistLinks = on
            error = nil
        } catch {
            // Surface the failure; leave the toggle reflecting the real state.
            self.error = "Couldn't update the Keychain — persistence unchanged. (\(error))"
        }
    }
}
