import SwiftUI
import AppKit
import LinkryptCore

struct RespondView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = RespondModel()

    private var busy: Bool {
        switch model.phase { case .loadingInfo, .submitting: return true; default: return false }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("// ANSWER A REQUEST").font(LK.mono(10)).tracking(1.5).foregroundStyle(LK.fgMuted)
                Text("Send an encrypted reply").font(LK.sans(22, weight: .semibold)).foregroundStyle(LK.fg)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 14)
            Rectangle().fill(LK.borderSoft).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LKPanel(label: "Request link", padding: 12) {
                        HStack {
                            TextField("https://…/r/…", text: $model.link)
                                .textFieldStyle(.plain).font(LK.mono(12)).foregroundStyle(LK.fg)
                            LKButton(title: "load") { Task { await model.loadInfo(using: app.submitClient) } }
                        }
                    }
                    switch model.phase {
                    case .ready(let label):
                        Text("Requesting: \(label ?? "—")").font(LK.mono(11)).foregroundStyle(LK.fgMuted)
                        LKPanel(label: "Secret · plaintext (or pick a file)", padding: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Spacer()
                                    if let f = model.pickedFile {
                                        LKButton(verbatim: f.lastPathComponent) { model.pickFile() }
                                    } else {
                                        LKButton(title: "pick file…") { model.pickFile() }
                                    }
                                }
                                TextEditor(text: $model.text).font(LK.mono(12.5)).foregroundStyle(LK.fg)
                                    .scrollContentBackground(.hidden).frame(minHeight: 140)
                            }
                        }
                    case .done:
                        Text("✓ sent — the owner has been emailed.").font(LK.mono(11)).foregroundStyle(LK.ok)
                    case .error(let e):
                        Text("× \(e)").font(LK.mono(11)).foregroundStyle(LK.err).fixedSize(horizontal: false, vertical: true)
                    case .idle, .loadingInfo, .submitting:
                        EmptyView()
                    }
                }
                .padding(24)
            }
            Rectangle().fill(LK.borderSoft).frame(height: 1)
            HStack {
                Text("encrypted on this device").font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                Spacer()
                LKButton(title: "close") { dismiss() }
                if case .ready = model.phase {
                    LKButton(title: busy ? "sending…" : "encrypt & send", primary: true, arrow: true, disabledLook: busy) {
                        Task { await model.submit(using: app.submitClient, putR2: { url, data in
                            try await app.client?.putR2(uploadUrl: url, ciphertext: data)
                        }) }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(LK.bgElev)
        }
        .frame(width: 680, height: 600).lockGated()   // see LockGate
        .background(LK.bg)
        .onAppear { model.prefillFromClipboard() }
        .onChange(of: model.link) { _, _ in model.linkChanged() }
    }
}
