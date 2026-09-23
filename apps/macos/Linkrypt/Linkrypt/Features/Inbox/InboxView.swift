import SwiftUI
import AppKit
import LinkryptCore

struct InboxView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = InboxModel()

    private var busy: Bool { if case .loading = model.phase { return true } else { return false } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("// REQUEST INBOX").font(LK.mono(10)).tracking(1.5).foregroundStyle(LK.fgMuted)
                Text("Read a submission").font(LK.sans(22, weight: .semibold)).foregroundStyle(LK.fg)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 14)
            Rectangle().fill(LK.borderSoft).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LKPanel(label: "Inbox link · from your email", padding: 12) {
                        TextField("https://…/app/inbox/…#k=…", text: $model.link)
                            .textFieldStyle(.plain).font(LK.mono(12)).foregroundStyle(LK.fg)
                    }
                    Text("Opening decrypts the submission locally and burns it on the server.")
                        .font(LK.mono(10)).foregroundStyle(LK.fgMuted)

                    switch model.phase {
                    case .revealedText(let text):
                        LKPanel(label: "Submission · destroyed on the server", padding: 12) {
                            Text(text).font(LK.mono(12)).foregroundStyle(LK.fg)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                        LKButton(title: "copy") { Clipboard.copy(text) }
                    case .savedFile(let name):
                        Text("✓ saved \(name) · destroyed on the server").font(LK.mono(11)).foregroundStyle(LK.ok)
                    case .error(let e):
                        Text("× \(e)").font(LK.mono(11)).foregroundStyle(LK.err)
                            .fixedSize(horizontal: false, vertical: true)
                    case .idle, .loading:
                        EmptyView()
                    }
                }
                .padding(24)
            }
            Rectangle().fill(LK.borderSoft).frame(height: 1)
            HStack {
                Text("key never leaves this device").font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                Spacer()
                LKButton(title: "close") { dismiss() }
                LKButton(title: busy ? "opening…" : "open", primary: true, arrow: true, disabledLook: busy) {
                    Task { await model.open(using: app.inboxClient) }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(LK.bgElev)
        }
        .frame(width: 640, height: 560).lockGated()   // see LockGate
        .background(LK.bg)
        .onAppear { model.prefillFromClipboard() }
        .onChange(of: model.link) { _, _ in model.linkChanged() }
    }
}
