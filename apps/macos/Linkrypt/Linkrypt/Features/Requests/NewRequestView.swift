import SwiftUI
import LinkryptCore
import AppKit

/// Owner-side: create a keyless request link. No crypto here — the submitter
/// generates the key at submit time. On success the sheet swaps to an inline
/// result panel showing the (always re-copyable) keyless URL.
struct NewRequestView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var expiresIn = "24h"
    @State private var busy = false
    @State private var error: String?
    @State private var resultURL: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(LK.borderSoft).frame(height: 1)
            if let url = resultURL { resultPanel(url) } else { form }
        }
        .frame(width: 560, height: 440).lockGated()   // see LockGate
        .background(LK.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("// REQUEST A SECRET").font(LK.mono(10)).tracking(1.5).foregroundStyle(LK.fgMuted)
            Text(resultURL == nil ? "Request a secret" : "Request link ready")
                .font(LK.sans(22, weight: .semibold)).foregroundStyle(LK.fg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 14)
    }

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LKPanel(label: "Label · shown to the submitter", padding: 12) {
                        TextField("optional", text: $label)
                            .textFieldStyle(.plain).font(LK.sans(13)).foregroundStyle(LK.fg)
                    }
                    LKPanel(label: "Expires", padding: 10) {
                        LKDropdown(selection: $expiresIn, options: [
                            ("1h", "1 hour"), ("24h", "24 hours"),
                            ("7d", "7 days"), ("30d", "30 days"),
                        ])
                    }
                    Text("1 submission, then the link closes.")
                        .font(LK.mono(11)).foregroundStyle(LK.fgMuted)
                    if let error {
                        Text("× \(error)").font(LK.mono(11)).foregroundStyle(LK.err)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
            Rectangle().fill(LK.borderSoft).frame(height: 1)
            HStack {
                Spacer()
                LKButton(title: "cancel") { dismiss() }
                LKButton(title: busy ? "creating…" : "create request link",
                         primary: true, arrow: true, disabledLook: busy) {
                    Task { await create() }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(LK.bgElev)
        }
    }

    private func resultPanel(_ url: String) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Anyone with this link can send you one encrypted submission.")
                        .font(LK.sans(13)).foregroundStyle(LK.fgBody)
                        .fixedSize(horizontal: false, vertical: true)
                    LKPanel(label: "Request link · keyless", padding: 12) {
                        Text(url).font(LK.mono(12)).foregroundStyle(LK.fg)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Copied to clipboard.").font(LK.mono(11)).foregroundStyle(LK.ok)
                }
                .padding(24)
            }
            Rectangle().fill(LK.borderSoft).frame(height: 1)
            HStack {
                LKButton(title: "create another") {
                    resultURL = nil; label = ""; error = nil
                }
                Spacer()
                LKButton(title: "copy") { Clipboard.copy(url) }
                LKButton(title: "done", primary: true) { dismiss() }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(LK.bgElev)
        }
    }

    private func create() async {
        guard !busy else { return }
        guard let client = model.client else { error = "Not authenticated."; return }
        busy = true; error = nil; defer { busy = false }
        do {
            let made = try await client.createRequest(
                CreateRequestRequest(label: label.isEmpty ? nil : label, expiresIn: expiresIn))
            let url = ShareLink.requestURL(baseURL: model.baseURL, lang: model.prefs.languageCode, id: made.id)
            Clipboard.copy(url)            // burn-aware (NOT copyToPasteboard)
            resultURL = url
            await model.refresh()
        } catch APIError.planLimit(let limit, let upgrade) {
            error = "Plan limit (\(limit)). Upgrade: \(model.baseURL)\(upgrade)"
        } catch APIError.forbidden(let m) {
            error = "Forbidden — your token may lack shares:write. (\(m))"
        } catch APIError.insufficientScope(let missing) {
            error = "Token is missing scope(s): \(missing.joined(separator: ", "))"
        } catch {
            self.error = "\(error)"
        }
    }
}
