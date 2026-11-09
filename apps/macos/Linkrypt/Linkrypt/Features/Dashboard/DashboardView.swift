import SwiftUI
import AppKit
import LinkryptCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    struct ComposerLaunch: Identifiable { let id = UUID(); let initialFiles: [URL] }
    @State private var composerLaunch: ComposerLaunch?
    /// A share the composer just created. Stashed in `pendingCreated` while the
    /// composer sheet animates out, then moved to `createdShare` in its
    /// `onDismiss` — presenting a second sheet while the first is still
    /// dismissing is dropped by SwiftUI.
    struct CreatedShare: Identifiable { let id: String; let url: String; let warning: String? }
    @State private var pendingCreated: CreatedShare?
    @State private var createdShare: CreatedShare?
    @State private var showReceive = false
    enum Workspace { case shares, requests }
    @State private var workspace: Workspace = .shares
    @State private var showNewRequest = false
    @State private var showInbox = false
    @State private var showRespond = false
    @State private var filter: String = "all"

    // Keyboard model (j/k move · ⏎ open · y copy · d revoke)
    @State private var selectedID: String?
    @State private var armedRevokeID: String?   // first `d` arms, second confirms
    @State private var detailRow: ShareRow?      // drives the detail sheet (⏎)
    @State private var flash: LocalizedStringKey?   // transient status-bar feedback (catalog key, may interpolate)
    @State private var revoking: Set<String> = []   // in-flight revokes: a second `d d` must not double-fire
    @State private var chord = NavChord.State()  // sidebar `g x` chords
    @FocusState private var tableFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(LK.borderSoft).frame(width: 1)
            switch workspace {
            case .shares: content
            case .requests: RequestsView(onNewRequest: { showNewRequest = true }, onKeyHandled: { chord.disarm() })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LK.bg)
        // Ancestor handler: runs for keys the focused table (shares or requests)
        // returned `.ignored` for, so `j/k/y/d` keep priority and `g x` works
        // in both workspaces. Sheets are separate key windows → chords can't
        // fire under them.
        .onKeyPress(action: handleChord)
        .task { await model.refresh(); tableFocused = true }
        // The view now survives the lock (LockGate), so the mount-time refresh
        // above no longer re-runs on unlock — refresh explicitly instead.
        .onChange(of: lock.isLocked) { _, locked in
            if !locked { Task { await model.refresh() } }
        }
        .task { tryConsumeDrop(); tryConsumeNewShare() }
        .onChange(of: model.pendingDroppedFiles) { _, _ in tryConsumeDrop() }
        .onChange(of: model.pendingNewShare) { _, _ in tryConsumeNewShare() }
        .onChange(of: composerLaunch?.id) { _, _ in tryConsumeDrop() }
        .onChange(of: createdShare?.id) { _, _ in tryConsumeDrop() }
        .onChange(of: detailRow?.id) { _, _ in tryConsumeDrop() }
        .onChange(of: showReceive) { _, _ in tryConsumeDrop() }
        .onChange(of: showNewRequest) { _, _ in tryConsumeDrop() }
        .onChange(of: showInbox) { _, _ in tryConsumeDrop() }
        .onChange(of: showRespond) { _, _ in tryConsumeDrop() }
        .sheet(item: $composerLaunch, onDismiss: {
            if let c = pendingCreated { pendingCreated = nil; createdShare = c }
        }) { launch in
            ComposerView(initialFiles: launch.initialFiles, onCreated: { id, url, warning in
                pendingCreated = CreatedShare(id: id, url: url, warning: warning)
            })
            .environment(model)
        }
        .sheet(item: $createdShare) { c in
            // Fresh share: QR + link, with any email-delivery warning. Stays
            // open on revoke so the "✓ revoked" confirmation is visible.
            ShareDetailView(url: c.url, id: c.id, row: model.shares.first { $0.id == c.id },
                            onRevoke: { await performRevoke(id: c.id) }, notice: c.warning)
        }
        .sheet(isPresented: $showReceive) { ReceiveView() }
        .sheet(isPresented: $showNewRequest) { NewRequestView() }
        .sheet(isPresented: $showInbox) { InboxView() }
        .sheet(isPresented: $showRespond) { RespondView() }
        .sheet(item: $detailRow) { row in
            ShareDetailView(url: model.linkCache.url(for: row.id), id: row.id, row: row, onRevoke: {
                // Close the sheet only on success; a failure stays visible in it.
                let failure = await performRevoke(id: row.id)
                if failure == nil { flash = "revoked \(row.id)"; detailRow = nil }
                return failure
            })
            .onDisappear { tableFocused = true }
        }
    }

    // MARK: Sidebar

    /// Open the composer for a dock-dropped file — only when idle (no sheet
    /// already up), so a drop arriving during another sheet is held in
    /// `pendingDroppedFiles` and consumed when that sheet dismisses.
    /// No sheet up — the only state in which a new sheet can be presented.
    private var isIdle: Bool {
        composerLaunch == nil && createdShare == nil && detailRow == nil
            && !showReceive && !showNewRequest && !showInbox && !showRespond
    }

    private func tryConsumeDrop() {
        guard !model.pendingDroppedFiles.isEmpty, isIdle else { return }
        let urls = model.pendingDroppedFiles
        model.pendingDroppedFiles = []
        composerLaunch = ComposerLaunch(initialFiles: urls)
    }

    /// ⌘N while a sheet is already up is dropped, not queued — opening the
    /// composer later, when that sheet closes, would be a surprise.
    private func tryConsumeNewShare() {
        guard model.pendingNewShare else { return }
        model.pendingNewShare = false
        guard isIdle else { return }
        composerLaunch = ComposerLaunch(initialFiles: [])
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 26)   // clear the traffic-light strip

            sectionHeader("WORKSPACE", topPad: 0)
            navItem("Shares", hint: "g s", active: workspace == .shares, count: model.shares.count) { workspace = .shares }
            navItem("Requests", hint: "g r", active: workspace == .requests, count: model.requests.count) { workspace = .requests }

            sectionHeader("OUTGOING")
            navItem("New share", hint: "g n") { composerLaunch = ComposerLaunch(initialFiles: []) }
            navItem("New request", hint: "g N") { showNewRequest = true }

            sectionHeader("INCOMING")
            navItem("Open a share", hint: "g v") { showReceive = true }
            navItem("Answer a request", hint: "g p") { showRespond = true }
            navItem("Request inbox", hint: "g i") { showInbox = true }

            sectionHeader("ACCOUNT")
            navItem("Audit log", hint: "g a") { openWeb("/app/audit") }
            navItem("API tokens", hint: "g t") { openWeb("/app/tokens") }
            navItem("Settings", hint: "⌘,") { openSettings() }
            navItem("About", hint: "") { openWindow(id: "about") }

            Spacer()
            Rectangle().fill(LK.borderSoft).frame(height: 1)
            accountFooter
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LK.bgElev)
    }

    private func navItem(_ label: LocalizedStringKey, hint: String, active: Bool = false,
                         count: Int? = nil, disabled: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("▸").foregroundStyle(active ? LK.amber : .clear).frame(width: 8)
                Text(label)
                    .font(LK.mono(12))
                    .foregroundStyle(disabled ? LK.fgDim : (active ? LK.fg : LK.fgBody))
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)").font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                }
                Text(verbatim: hint).font(LK.mono(9)).foregroundStyle(LK.fgDim)
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(active ? LK.amber.opacity(0.08) : Color.clear)
            .overlay(alignment: .leading) {
                Rectangle().fill(active ? LK.amber : .clear).frame(width: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func sectionHeader(_ title: LocalizedStringKey, topPad: CGFloat = 14) -> some View {
        Text(title)
            .font(LK.mono(9)).tracking(1.6).foregroundStyle(LK.fgMuted)
            .padding(.horizontal, 16).padding(.top, topPad).padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountLabel: String { model.who?.email ?? model.who?.userId ?? "account" }
    private var accountInitial: String {
        guard let email = model.who?.email, !email.isEmpty else { return "lk" }
        return String(email.prefix(1)).lowercased()
    }

    private var accountFooter: some View {
        HStack(spacing: 8) {
            Text(accountInitial)
                .font(LK.mono(10)).foregroundStyle(LK.amber)
                .frame(width: 22, height: 22)
                .background(Circle().fill(LK.surface2))
                .overlay(Circle().stroke(LK.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(accountLabel)
                    .font(LK.mono(11)).foregroundStyle(LK.fg)
                    .lineLimit(1).truncationMode(.middle)
                Button { model.logout() } label: {
                    Text("logout").font(LK.mono(9)).foregroundStyle(LK.fgMuted)
                        .underline().contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(LK.borderSoft).frame(height: 1)
            table
            Rectangle().fill(LK.borderSoft).frame(height: 1)
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LK.bg)
        .focusable()
        .focusEffectDisabled()
        .focused($tableFocused)
        .onKeyPress { press in
            // Belt-and-braces with LockGate: `y` copies a link — never while locked.
            guard !lock.isLocked else { return .ignored }
            let r = handleKey(press)
            if r == .handled { chord.disarm() }   // consumed keys never reach handleChord
            return r
        }
        .onChange(of: filter) { _, _ in armedRevokeID = nil; flash = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: 22)   // clear titlebar drag strip
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("// ACTIVE SHARES")
                        .font(LK.mono(10)).tracking(1.5).foregroundStyle(LK.fgMuted)
                    Text("\(counts.active) active")
                        .font(LK.sans(24, weight: .semibold)).foregroundStyle(LK.fg)
                    + Text(verbatim: " · ").font(LK.sans(15)).foregroundStyle(LK.fgMuted)
                    + Text("\(counts.opened) opened").font(LK.sans(15)).foregroundStyle(LK.fgMuted)
                    + Text(verbatim: " · ").font(LK.sans(15)).foregroundStyle(LK.fgMuted)
                    + Text("\(counts.closed) closed").font(LK.sans(15)).foregroundStyle(LK.fgMuted)
                }
                Spacer()
                LKButton(title: "+ new share", primary: true, arrow: true) { composerLaunch = ComposerLaunch(initialFiles: []) }
            }
            // filter strip
            HStack(spacing: 8) {
                ForEach(["all", "active", "opened", "burned", "expired", "revoked"], id: \.self) { f in
                    let on = filter == f
                    Button { filter = f } label: {
                        Text(f).font(LK.mono(11))
                            .foregroundStyle(on ? LK.amber : LK.fgMuted)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(on ? LK.amber.opacity(0.08) : Color.clear)
                            .overlay(Rectangle().stroke(on ? LK.amber : LK.border, lineWidth: 1))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    Text("⟳ sync").font(LK.mono(10)).foregroundStyle(LK.fgMuted).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 14)
    }

    private var table: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // column header
                    HStack(spacing: 16) {
                        Text("ID").frame(width: 96, alignment: .leading)
                        Text("LABEL").frame(maxWidth: .infinity, alignment: .leading)
                        Text("OPENS").frame(width: 70, alignment: .leading)
                        Text("EXPIRES").frame(width: 90, alignment: .leading)
                        Text("STATE").frame(width: 84, alignment: .trailing)
                        Text("").frame(width: 24)
                    }
                    .font(LK.mono(9)).tracking(1.4).foregroundStyle(LK.fgMuted)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(LK.borderSoft).frame(height: 1) }

                    ForEach(filteredShares) { row in
                        shareRow(row).id(row.id)
                        Rectangle().fill(LK.borderSoft).frame(height: 1)
                    }

                    if filteredShares.isEmpty {
                        Text(model.shares.isEmpty ? "No shares yet. Create one with [ + new share ]." : "No shares match this filter.")
                            .font(LK.mono(11)).foregroundStyle(LK.fgMuted)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func shareRow(_ r: ShareRow) -> some View {
        let cachedURL = model.linkCache.url(for: r.id)
        let selected = r.id == selectedID
        let armed = r.id == armedRevokeID
        return HStack(spacing: 16) {
            Text("\(r.type == "file" ? "⊞" : "∎") \(r.id)")
                .font(LK.mono(11)).foregroundStyle(LK.amber)
                .frame(width: 96, alignment: .leading)
            Text(r.label ?? r.filename ?? "—")
                .font(LK.sans(13)).foregroundStyle(LK.fg).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(r.opensUsed) / \(r.maxOpens)")
                .font(LK.mono(11)).foregroundStyle(LK.fgBody)
                .frame(width: 70, alignment: .leading)
            Text(expiresText(r))
                .font(LK.mono(11)).foregroundStyle(LK.fgBody)
                .frame(width: 90, alignment: .leading)
            if armed {
                Text("revoke? d ✓ · esc ✕")
                    .font(LK.mono(10)).foregroundStyle(LK.err)
                    .frame(width: 108 + 24, alignment: .trailing)
            } else {
                HStack { Spacer(); LKPill(kind: status(of: r)) }.frame(width: 84)
                Button { if let u = cachedURL { Clipboard.copy(u); flash = "copied link" } } label: {
                    Text("⧉").foregroundStyle(cachedURL == nil ? LK.fgDim : LK.amber).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(cachedURL == nil).frame(width: 24)
                .help(cachedURL == nil ? "Link only available right after creation, on the device that created it" : "Copy link")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(rowBackground(selected: selected, armed: armed))
        .overlay(alignment: .leading) {
            Rectangle().fill(armed ? LK.err : (selected ? LK.amber : .clear)).frame(width: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedID = r.id; armedRevokeID = nil; flash = nil }
    }

    private func rowBackground(selected: Bool, armed: Bool) -> Color {
        if armed { return LK.err.opacity(0.08) }
        if selected { return LK.amber.opacity(0.06) }
        return .clear
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            if let flash {
                Text(flash).font(LK.mono(10)).foregroundStyle(LK.amber)
            } else {
                keyHint("j/k", "move")
                keyHint("⏎", "open")
                keyHint("y", "copy")
                keyHint("d", "revoke")
            }
            Spacer()
            Text("\(filteredShares.count) shown").font(LK.mono(10)).foregroundStyle(LK.fgMuted)
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
        .background(LK.bgElev)
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(LK.mono(10)).foregroundStyle(LK.fgBody)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(Rectangle().stroke(LK.border, lineWidth: 1))
            Text(label).font(LK.mono(10)).foregroundStyle(LK.fgMuted)
        }
    }

    // MARK: keyboard model

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.characters {
        case "j": select(DashboardNav.next(after: selectedID, in: filteredIDs)); return .handled
        case "k": select(DashboardNav.previous(before: selectedID, in: filteredIDs)); return .handled
        case "y": copySelected(); return .handled
        case "d": pressRevoke(); return .handled
        default: break
        }
        switch press.key {
        case .return: openSelected(); return .handled
        case .escape:
            if armedRevokeID != nil || flash != nil { armedRevokeID = nil; flash = nil; return .handled }
            return .ignored
        default: return .ignored
        }
    }

    private func select(_ id: String?) {
        guard let id else { return }   // clamped ends / empty list → keep current
        selectedID = id
        armedRevokeID = nil
        flash = nil
    }

    /// Selection restricted to the visible (filtered) rows. A selection that
    /// was filtered out or removed after refresh resolves to nil, so no action
    /// can ever target an off-screen row (e.g. silently revoke a hidden share).
    private var visibleSelectedID: String? { DashboardNav.resolve(selectedID, in: filteredIDs) }

    private func selectedRow() -> ShareRow? {
        guard let id = visibleSelectedID else { return nil }
        return filteredShares.first { $0.id == id }
    }

    private func openSelected() {
        guard let row = selectedRow() else { return }
        armedRevokeID = nil
        detailRow = row
    }

    private func copySelected() {
        guard let id = visibleSelectedID else { flash = "select a share first (j/k)"; return }
        if let u = model.linkCache.url(for: id) {
            Clipboard.copy(u); flash = "copied link"
        } else {
            flash = "no link on this device"
        }
    }

    private func pressRevoke() {
        guard let id = visibleSelectedID else { flash = "select a share first (j/k)"; return }
        if armedRevokeID == id {
            armedRevokeID = nil
            revoke(id: id)
        } else {
            armedRevokeID = id   // arm; a second `d` confirms, esc cancels
            flash = nil
        }
    }

    private func revoke(id: String) {
        Task {
            let ok: LocalizedStringKey = "revoked \(id)"
            flash = await performRevoke(id: id) ?? ok
        }
    }

    /// Single revoke per id at a time (a repeated `d d` while the first request
    /// is in flight would otherwise 404 and overwrite the success flash). The
    /// outcome is returned immediately; the list refresh runs on its own.
    private func performRevoke(id: String) async -> LocalizedStringKey? {
        guard !revoking.contains(id) else { return nil }
        revoking.insert(id); defer { revoking.remove(id) }
        let failure = await RevokeFailure.perform(client: model.client, id: id)
        Task { await model.refresh() }
        return failure
    }

    // MARK: helpers

    private var filteredShares: [ShareRow] {
        guard filter != "all" else { return model.shares }
        return model.shares.filter { status(of: $0) == filter }
    }

    private var filteredIDs: [String] { filteredShares.map(\.id) }

    private var counts: (active: Int, opened: Int, closed: Int) {
        var a = 0, o = 0, c = 0
        for s in model.shares {
            switch status(of: s) {
            case "active": a += 1
            case "opened": o += 1
            default: c += 1
            }
        }
        return (a, o, c)
    }

    private func status(of r: ShareRow) -> String {
        if r.revokedAt != nil { return "revoked" }
        if r.burnedAt != nil { return "burned" }
        if r.opensUsed > 0 { return "opened" }   // an opened share stays "opened" even past expiry
        if let exp = r.expiresAt, exp < Int(Date().timeIntervalSince1970) { return "expired" }
        return "active"
    }

    private func expiresText(_ r: ShareRow) -> String {
        guard let exp = r.expiresAt else { return "—" }
        let secs = exp - Int(Date().timeIntervalSince1970)
        if secs <= 0 { return "past" }
        let h = secs / 3600
        if h >= 24 { return "\(h / 24)d \(h % 24)h" }
        if h >= 1 { return "\(h)h \((secs % 3600) / 60)m" }
        return "\(secs / 60)m"
    }

    // MARK: sidebar chords (`g s` · `g r` · `g n` · `g N` · `g v` · `g p` · `g i` · `g a` · `g t`)

    private func handleChord(_ press: KeyPress) -> KeyPress.Result {
        guard !lock.isLocked else { return .ignored }   // see LockGate
        // Plain keys only (shift is part of `N`); ⌘/⌥/⌃ combos belong to the menus.
        guard press.modifiers.isSubset(of: [.shift]),
              press.characters.count == 1, let ch = press.characters.first else { return .ignored }
        switch chord.press(ch) {
        case .ignored: return .ignored
        case .armed, .cancelled: return .handled
        case .fired(let action): perform(action); return .handled
        }
    }

    private func perform(_ action: NavChord.Action) {
        switch action {
        case .shares: workspace = .shares
        case .requests: workspace = .requests
        case .newShare: composerLaunch = ComposerLaunch(initialFiles: [])
        case .newRequest: showNewRequest = true
        case .openShare: showReceive = true
        case .answerRequest: showRespond = true
        case .inbox: showInbox = true
        case .auditLog: openWeb("/app/audit")
        case .apiTokens: openWeb("/app/tokens")
        }
    }

    private func openWeb(_ path: String) {
        if let u = URL(string: "\(model.baseURL)\(path)") { NSWorkspace.shared.open(u) }
    }
}
