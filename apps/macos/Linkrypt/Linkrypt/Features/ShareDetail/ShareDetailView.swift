import SwiftUI
import CoreImage.CIFilterBuiltins
import LinkryptCore
import AppKit

struct ShareDetailView: View {
    /// Full recipient URL incl. #fragment, or nil when there is no on-device
    /// link (the share was created elsewhere — `/api/cli/list` returns no key
    /// material, so the fragment can't be reconstructed).
    let url: String?
    let id: String
    /// Row metadata for the link-less view (label / opens / expiry / status).
    var row: ShareRow? = nil
    /// Performs the revoke; returns nil on success or the error text to show
    /// IN THIS SHEET (a message set on the presenting view is hidden behind it).
    var onRevoke: (() async -> LocalizedStringKey?)? = nil
    /// Non-fatal outcome from creation (e.g. the link couldn't be emailed) —
    /// shown here because the composer that produced it is already closed.
    var notice: String? = nil

    private enum RevokeState: Equatable { case idle, busy, done, failed(LocalizedStringKey) }
    @State private var revokeState: RevokeState = .idle

    var body: some View {
        VStack(spacing: 20) {
            if let url {
                sealedBadge
                if let qr = qrImage(from: url) {
                    Image(nsImage: qr).interpolation(.none).resizable()
                        .frame(width: 180, height: 180)
                        .padding(12).background(LK.bgElev)
                        .overlay(Rectangle().stroke(LK.border, lineWidth: 1))
                }
                LKMonoField(value: url)
            } else {
                noLinkNote
            }

            if let row { metadataBlock(row) }

            if let notice {
                Text(verbatim: "⚠ \(notice)").font(LK.mono(11)).foregroundStyle(LK.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let url { LKButton(title: "share…") { presentShareSheet(url) } }
                if let onRevoke, revokeState != .done {
                    LKButton(title: revokeState == .busy ? "revoking…" : "revoke now",
                             disabledLook: revokeState == .busy) {
                        guard revokeState != .busy else { return }
                        revokeState = .busy
                        Task {
                            if let e = await onRevoke() { revokeState = .failed(e) } else { revokeState = .done }
                        }
                    }
                }
            }
            switch revokeState {
            case .failed(let e):
                (Text(verbatim: "× ") + Text(e)).font(LK.mono(11)).foregroundStyle(LK.err)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            case .done:
                Text("✓ revoked — the link no longer opens").font(LK.mono(11)).foregroundStyle(LK.ok)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .idle, .busy:
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("BURNS WHEN").font(LK.mono(10)).tracking(1.4).foregroundStyle(LK.fgMuted)
                Text("· opened up to its max · or it expires · or 10 wrong passphrases")
                    .font(LK.mono(12)).foregroundStyle(LK.fgBody)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().stroke(LK.borderHi, style: StrokeStyle(lineWidth: 1, dash: [4])))
            Spacer()
        }
        .padding(20).frame(width: 420).background(LK.bg).lockGated()   // see LockGate
    }

    private var sealedBadge: some View {
        HStack(spacing: 10) {
            Text("✓").foregroundStyle(LK.ok)
            Text("sealed · key in url fragment only").font(LK.mono(11)).foregroundStyle(LK.ok)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(LK.ok.opacity(0.04))
        .overlay(Rectangle().frame(width: 2), alignment: .leading).foregroundStyle(LK.ok)
    }

    private var noLinkNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("⛌").foregroundStyle(LK.fgMuted)
                Text("no link on this device").font(LK.mono(11)).foregroundStyle(LK.fgBody)
            }
            Text("Links carry the decryption key in the URL fragment, which only exists on the device that created the share. You can still inspect or revoke it here.")
                .font(LK.mono(11)).foregroundStyle(LK.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(LK.bgElev)
        .overlay(Rectangle().stroke(LK.border, lineWidth: 1))
    }

    private func metadataBlock(_ r: ShareRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metaRow("ID", "\(r.type == "file" ? "⊞" : "∎") \(r.id)")
            if let label = r.label ?? r.filename { metaRow("LABEL", label) }
            metaRow("OPENS", "\(r.opensUsed) / \(r.maxOpens)")
            metaRow("STATUS", statusText(r))
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(LK.borderSoft, lineWidth: 1))
    }

    private func metaRow(_ k: String, _ v: String) -> some View {
        HStack(spacing: 12) {
            Text(k).font(LK.mono(9)).tracking(1.4).foregroundStyle(LK.fgMuted)
                .frame(width: 56, alignment: .leading)
            Text(v).font(LK.mono(12)).foregroundStyle(LK.fg).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func statusText(_ r: ShareRow) -> String {
        if r.revokedAt != nil { return "revoked" }
        if r.burnedAt != nil { return "burned" }
        if r.opensUsed > 0 { return "opened" }
        if let exp = r.expiresAt, exp < Int(Date().timeIntervalSince1970) { return "expired" }
        return "active"
    }

    private func qrImage(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let ci = filter.outputImage else { return nil }
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size); img.addRepresentation(rep)
        return img
    }

    private func presentShareSheet(_ string: String) {
        guard let window = NSApp.keyWindow, let view = window.contentView else { return }
        let picker = NSSharingServicePicker(items: [string])
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }
}
