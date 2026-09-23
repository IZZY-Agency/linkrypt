import SwiftUI
import LinkryptCore

/// Full-screen lock. Presented by `LockGate` OVER the live content (which is
/// made invisible, non-interactive and hidden from accessibility) rather than
/// replacing it, so an open sheet / half-typed composer survives a Cmd-Tab.
/// Takes keyboard focus on appear so the dashboard's `j/k/y/d` and `g x`
/// handlers underneath can't see keystrokes while locked.
struct LockView: View {
    @Environment(AppLock.self) private var lock
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Text("🔒").font(.system(size: 40))
            Text("Linkrypt is locked").font(LK.sans(18, weight: .semibold)).foregroundStyle(LK.fg)
            Text("Unlock with Touch ID or your Mac password")
                .font(LK.mono(11)).foregroundStyle(LK.fgMuted)
            LKButton(title: lock.isAuthenticating ? "authenticating…" : "Unlock",
                     primary: true, arrow: false, disabledLook: lock.isAuthenticating) {
                lock.unlock()
            }
            if let e = lock.lastError {
                (Text(verbatim: "× ") + Text(LocalizedStringKey(e)))
                    .font(LK.mono(10)).foregroundStyle(LK.err)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LK.bg)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        // No auto-prompt here: LockView also appears on resign (app inactive).
        // The Touch ID prompt is driven by AppLock.onBecomeActive when the app
        // is frontmost + still locked; this button is the manual retry.
    }
}

/// Covers `content` with `LockView` while the app is locked WITHOUT tearing it
/// down. The old `if locked { LockView } else { content }` destroyed every
/// `@State` underneath (open sheets, the composer draft) on each deactivation,
/// so returning from a Cmd-Tab + Touch ID lost the "new share" dialog.
///
/// Kept-alive content is still a security boundary: opacity 0 (not drawn, so
/// nothing for a screenshot / Mission Control to show), hit-testing off,
/// disabled (no focus, no key equivalents, no text selection) and hidden from
/// accessibility. `LockView` grabs keyboard focus on top.
///
/// Sheets are separate NSWindows and are NOT covered by their presenter's
/// gate — every sheet-presented view applies `.lockGated()` at its own root.
struct LockGate: ViewModifier {
    @Environment(AppLock.self) private var lock

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(lock.isLocked ? 0 : 1)
                .allowsHitTesting(!lock.isLocked)
                .disabled(lock.isLocked)
                .accessibilityHidden(lock.isLocked)
            if lock.isLocked { LockView() }
        }
    }
}

extension View {
    /// See `LockGate`. Apply at the root of every window / sheet content view.
    func lockGated() -> some View { modifier(LockGate()) }
}
