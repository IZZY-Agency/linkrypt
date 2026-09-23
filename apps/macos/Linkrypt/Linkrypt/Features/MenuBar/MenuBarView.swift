import SwiftUI
import LinkryptCore
import AppKit

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @Environment(Preferences.self) private var prefs
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var status: String?
    @State private var statusOK = true
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Text("▸").foregroundStyle(LK.amber)
                    Text("linkrypt").foregroundStyle(LK.fg)
                }.font(LK.mono(13))
                Spacer()
                // Glyphs, not words: the footer can't fit two more localized
                // labels at 340pt (fr/uk). Tooltips carry the names.
                if !lock.isLocked { headerGlyph("⚙", help: "Settings") { openSettings() } }
                headerGlyph("ⓘ", help: "About") { openAbout() }
                Text(model.client == nil ? "● OFFLINE" : "● ONLINE")
                    .font(LK.mono(9)).tracking(1)
                    .foregroundStyle(model.client == nil ? LK.fgDim : LK.ok)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            divider

            if lock.isLocked {
                sectionLabel("// locked")
                Button { NSApp.activate(ignoringOtherApps: true); openMainWindow() } label: {
                    HStack(spacing: 10) {
                        Text("🔒").foregroundStyle(LK.amber)
                        Text("Locked — open the app to unlock")
                            .font(LK.sans(12)).foregroundStyle(LK.fgBody)
                        Spacer()
                    }
                    .padding(10).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.horizontal, 14).padding(.bottom, 8)
            } else {
            // Paste to share
            sectionLabel("// paste to share")
            Button { runQuickShare() } label: {
                HStack(spacing: 10) {
                    Text("⌥⇧V").font(LK.mono(13)).foregroundStyle(LK.amber)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(busy ? "Encrypting…" : "Encrypt clipboard now")
                            .font(LK.sans(12)).foregroundStyle(LK.fg)
                        quickShareCaption.font(LK.mono(9)).foregroundStyle(LK.fgMuted)
                    }
                    Spacer()
                    Text("→").foregroundStyle(LK.amber)
                }
                .padding(10)
                .overlay(Rectangle().stroke(LK.amber, style: StrokeStyle(lineWidth: 1, dash: [4])))
                .background(LK.amber.opacity(0.04))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(busy || model.client == nil)
            .padding(.horizontal, 14).padding(.bottom, 4)

            if let status {
                Text(LocalizedStringKey(status)).font(LK.mono(10))
                    .foregroundStyle(statusOK ? LK.ok : LK.err)
                    .lineLimit(2).truncationMode(.middle)
                    .padding(.horizontal, 14).padding(.bottom, 6)
            }

            divider

            // Recent
            sectionLabel("// recent")
            if model.shares.isEmpty {
                Text(model.client == nil ? "Sign in from the main window." : "No shares yet.")
                    .font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                    .padding(.horizontal, 14).padding(.bottom, 8)
            } else {
                ForEach(model.shares.prefix(5)) { r in
                    let cached = model.linkCache.url(for: r.id)
                    Button { if let u = cached { copyToPasteboard(u); flash("✓ \(r.id) link copied") } } label: {
                        HStack(spacing: 8) {
                            Text("\(r.type == "file" ? "⊞" : "∎") \(r.id)")
                                .font(LK.mono(10)).foregroundStyle(LK.amber)
                            Text(r.label ?? r.filename ?? "—")
                                .font(LK.sans(12)).foregroundStyle(LK.fg).lineLimit(1)
                            Spacer()
                            Text(cached == nil ? "—" : "⧉")
                                .font(LK.mono(11)).foregroundStyle(cached == nil ? LK.fgDim : LK.amber)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(cached == nil)
                    .help(cached == nil ? "Link only available on the device that created it" : "Copy link")
                }
            }
            }  // end: not locked

            divider

            // Footer actions
            HStack(spacing: 0) {
                footerButton("dashboard") { openMainWindow() }
                footerButton("refresh") { Task { await model.refresh() } }
                Spacer()
                footerButton("quit ⌘Q") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
        }
        .frame(width: 340)
        .background(LK.bg)
        .task { await model.refresh() }
    }

    private var divider: some View { Rectangle().fill(LK.borderSoft).frame(height: 1) }

    /// "24h · 1 open · auto-burn" — mirrors Settings › Sharing › Quick share.
    /// The expiry token is a catalog key too ("24h" → fr "24 h", uk "24 год").
    private var quickShareCaption: Text {
        // Same clamp as AppModel.quickShareClipboard(): a stored "1h" on Free
        // is submitted as "24h", so the caption must promise "24h" too.
        let e = Text(LocalizedStringKey(model.limits.clamp(expiry: prefs.quickShareExpiry, candidates: PresetCycle.expiries)))
        let n = model.limits.clamp(opens: prefs.quickShareMaxOpens, candidates: PresetCycle.opens)
        return n == 1 ? Text("\(e) · 1 open · auto-burn") : Text("\(e) · \(n) opens · auto-burn")
    }

    private func headerGlyph(_ glyph: String, help: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: glyph).font(LK.mono(13)).foregroundStyle(LK.fgMuted)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "about")
    }

    private func sectionLabel(_ s: LocalizedStringKey) -> some View {
        Text(s).font(LK.mono(9)).tracking(1.4).foregroundStyle(LK.fgMuted)
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
    }

    private func footerButton(_ title: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(LK.mono(11)).foregroundStyle(LK.fgBody)
                .padding(.horizontal, 8).padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func runQuickShare() {
        busy = true
        Task {
            let url = await model.quickShareClipboard()
            busy = false
            if url != nil { flash("✓ link copied to clipboard") }
            else { flash("× \(model.lastError ?? "failed")", ok: false) }
        }
    }

    private func flash(_ msg: String, ok: Bool = true) {
        status = msg; statusOK = ok
    }

    private func openMainWindow() { MainWindow.open(openWindow) }
}
