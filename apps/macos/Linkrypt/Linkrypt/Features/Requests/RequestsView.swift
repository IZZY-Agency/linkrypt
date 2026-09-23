import SwiftUI
import AppKit
import LinkryptCore

struct RequestsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    var onNewRequest: () -> Void
    /// Fired when this table consumed a key (see DashboardView chord disarm).
    var onKeyHandled: () -> Void = {}

    @State private var filter: String = "all"
    @State private var selectedID: String?
    @State private var armedRevokeID: String?   // first `d` arms, second confirms
    @State private var flash: String?
    @FocusState private var tableFocused: Bool

    private let filters = ["all", "pending", "submitted", "expired", "burned", "revoked"]

    var body: some View {
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
            guard !lock.isLocked else { return .ignored }   // see LockGate
            let r = handleKey(press)
            if r == .handled { onKeyHandled() }
            return r
        }
        .task { tableFocused = true }
        .onChange(of: filter) { _, _ in armedRevokeID = nil; flash = nil }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: 22)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("// REQUEST LINKS")
                        .font(LK.mono(10)).tracking(1.5).foregroundStyle(LK.fgMuted)
                    Text("\(counts.pending) pending")
                        .font(LK.sans(24, weight: .semibold)).foregroundStyle(LK.fg)
                    + Text(verbatim: " · ").font(LK.sans(15)).foregroundStyle(LK.fgMuted)
                    + Text("\(counts.submitted) submitted").font(LK.sans(15)).foregroundStyle(LK.fgMuted)
                    + Text(verbatim: " · ").font(LK.sans(15)).foregroundStyle(LK.fgMuted)
                    + Text("\(counts.closed) closed").font(LK.sans(15)).foregroundStyle(LK.fgMuted)
                }
                Spacer()
                LKButton(title: "+ new request", primary: true, arrow: true) { onNewRequest() }
            }
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { f in
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

    // MARK: Table

    private var table: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Text("ID").frame(width: 96, alignment: .leading)
                        Text("LABEL").frame(maxWidth: .infinity, alignment: .leading)
                        Text("USED").frame(width: 70, alignment: .leading)
                        Text("EXPIRES").frame(width: 90, alignment: .leading)
                        Text("STATE").frame(width: 92, alignment: .trailing)
                        Text("").frame(width: 24)
                    }
                    .font(LK.mono(9)).tracking(1.4).foregroundStyle(LK.fgMuted)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(LK.borderSoft).frame(height: 1) }

                    ForEach(filteredRequests) { row in
                        requestRow(row).id(row.id)
                        Rectangle().fill(LK.borderSoft).frame(height: 1)
                    }

                    if filteredRequests.isEmpty {
                        Text(model.requests.isEmpty
                             ? "No request links yet. Create one with [ + new request ]."
                             : "No requests match this filter.")
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

    private func requestRow(_ r: RequestRow) -> some View {
        let selected = r.id == selectedID
        let armed = r.id == armedRevokeID
        return HStack(spacing: 16) {
            Text("✉ \(r.id)")
                .font(LK.mono(11)).foregroundStyle(LK.amber)
                .frame(width: 96, alignment: .leading)
            Text(r.label ?? "—")
                .font(LK.sans(13)).foregroundStyle(LK.fg).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(r.submissionsUsed) / \(r.maxSubmissions)")
                .font(LK.mono(11)).foregroundStyle(LK.fgBody)
                .frame(width: 70, alignment: .leading)
            Text(expiresText(r))
                .font(LK.mono(11)).foregroundStyle(LK.fgBody)
                .frame(width: 90, alignment: .leading)
            if armed {
                Text("revoke? d ✓ · esc ✕")
                    .font(LK.mono(10)).foregroundStyle(LK.err)
                    .frame(width: 92 + 24, alignment: .trailing)
            } else {
                HStack { Spacer(); LKPill(kind: RequestStatus.of(r, now: nowSec)) }.frame(width: 92)
                // Keyless URL — always copyable (rebuilt from the id, no link cache).
                Button { Clipboard.copy(requestURL(r)); flash = "copied link" } label: {
                    Text("⧉").foregroundStyle(LK.amber).contentShape(Rectangle())
                }
                .buttonStyle(.plain).frame(width: 24)
                .help("Copy the request link")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(armed ? LK.err.opacity(0.08) : (selected ? LK.amber.opacity(0.06) : .clear))
        .overlay(alignment: .leading) {
            Rectangle().fill(armed ? LK.err : (selected ? LK.amber : .clear)).frame(width: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedID = r.id; armedRevokeID = nil; flash = nil }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            if let flash {
                Text(LocalizedStringKey(flash)).font(LK.mono(10)).foregroundStyle(LK.amber)
            } else {
                keyHint("j/k", "move"); keyHint("⏎", "open"); keyHint("y", "copy"); keyHint("d", "revoke")
            }
            Spacer()
            Text("\(filteredRequests.count) shown").font(LK.mono(10)).foregroundStyle(LK.fgMuted)
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

    // MARK: Keyboard

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
        guard let id else { return }
        selectedID = id; armedRevokeID = nil; flash = nil
    }

    private var visibleSelectedID: String? { DashboardNav.resolve(selectedID, in: filteredIDs) }

    private func selectedRow() -> RequestRow? {
        guard let id = visibleSelectedID else { return nil }
        return filteredRequests.first { $0.id == id }
    }

    private func openSelected() {
        guard let r = selectedRow() else { return }
        armedRevokeID = nil
        if let u = URL(string: requestURL(r)) { NSWorkspace.shared.open(u) }
    }

    private func copySelected() {
        guard let r = selectedRow() else { flash = "select a request first (j/k)"; return }
        Clipboard.copy(requestURL(r)); flash = "copied link"
    }

    private func pressRevoke() {
        guard let id = visibleSelectedID else { flash = "select a request first (j/k)"; return }
        if armedRevokeID == id {
            armedRevokeID = nil
            revoke(id: id)
        } else {
            armedRevokeID = id; flash = nil
        }
    }

    private func revoke(id: String) {
        Task {
            do {
                try await model.client?.revokeRequest(id: id)
                flash = "revoked \(id)"
            } catch APIError.forbidden(let m) {
                flash = "revoke failed — token lacks shares:revoke (\(m))"
            } catch APIError.insufficientScope(let missing) {
                flash = "revoke failed — missing scope: \(missing.joined(separator: ", "))"
            } catch {
                flash = "revoke failed: \(error)"
            }
            await model.refresh()
        }
    }

    // MARK: Helpers

    private var nowSec: Int { Int(Date().timeIntervalSince1970) }

    private func requestURL(_ r: RequestRow) -> String {
        ShareLink.requestURL(baseURL: model.baseURL, lang: model.prefs.languageCode, id: r.id)
    }

    private var filteredRequests: [RequestRow] {
        guard filter != "all" else { return model.requests }
        return model.requests.filter { RequestStatus.of($0, now: nowSec) == filter }
    }

    private var filteredIDs: [String] { filteredRequests.map(\.id) }

    private var counts: (pending: Int, submitted: Int, closed: Int) {
        var p = 0, s = 0, c = 0
        for r in model.requests {
            switch RequestStatus.of(r, now: nowSec) {
            case "pending": p += 1
            case "submitted": s += 1
            default: c += 1   // expired / burned / revoked
            }
        }
        return (p, s, c)
    }

    private func expiresText(_ r: RequestRow) -> String {
        guard let exp = r.expiresAt else { return "—" }
        let secs = exp - nowSec
        if secs <= 0 { return "past" }
        let h = secs / 3600
        if h >= 24 { return "\(h / 24)d \(h % 24)h" }
        if h >= 1 { return "\(h)h \((secs % 3600) / 60)m" }
        return "\(secs / 60)m"
    }
}
