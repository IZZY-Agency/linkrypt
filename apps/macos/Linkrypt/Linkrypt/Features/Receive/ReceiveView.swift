import SwiftUI
import LinkryptCore

/// Open a Linkrypt link in-app: paste/clipboard → decrypt locally → reveal text
/// or save a file. Lives inside RootView, so it's replaced by LockView when the
/// app is locked (no separate gating).
struct ReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = ReceiveModel()

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                Text("// OPEN A SHARE").font(LK.mono(10)).tracking(1.5).foregroundStyle(LK.fgMuted)
                Text("Open a secure link").font(LK.sans(22, weight: .semibold)).foregroundStyle(LK.fg)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 14)
            Rectangle().fill(LK.borderSoft).frame(height: 1)

            // ── Body ──────────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LKPanel(label: "Linkrypt link", padding: 12) {
                        TextField("https://…/s/…#k=…", text: $model.link)
                            .textFieldStyle(.plain).font(LK.mono(12)).foregroundStyle(LK.fg)
                    }
                    Text("⚠ Opening consumes one of the share's opens — it may burn after this.")
                        .font(LK.mono(10)).foregroundStyle(LK.amber)
                        .fixedSize(horizontal: false, vertical: true)

                    switch model.phase {
                    case .passphrase:
                        LKPanel(label: "Passphrase 2FA", padding: 12) {
                            SecureField("passphrase", text: $model.passphrase)
                                .textFieldStyle(.plain).font(LK.mono(12)).foregroundStyle(LK.fg)
                        }
                    case .revealedText(let text):
                        LKPanel(label: "Secret · decrypted on device", padding: 12) {
                            LKMonoField(value: text)
                        }
                    case .savedFile(let name):
                        Text("✓ Saved \(name)").font(LK.mono(11)).foregroundStyle(LK.ok)
                    case .pendingSave:
                        HStack(spacing: 12) {
                            Text("The open is spent — the file is decrypted in memory until you save it.")
                                .font(LK.mono(10)).foregroundStyle(LK.amber)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            LKButton(title: "Save file…", primary: true, arrow: false) { Task { await model.saveAgain() } }
                        }
                    case .loading:
                        Text("opening…").font(LK.mono(11)).foregroundStyle(LK.fgMuted)
                    case .idle, .error:
                        EmptyView()
                    }

                    if case .error(let e) = model.phase {
                        Text("× \(e)").font(LK.mono(11)).foregroundStyle(LK.err)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let inline = model.errorText {
                        Text("× \(inline)").font(LK.mono(11)).foregroundStyle(LK.err)
                    }
                    if let opens = model.opensRemaining {
                        Text("\(opens) opens remaining").font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                    }
                }
                .padding(24)
            }

            // ── Footer ────────────────────────────────────────────────
            Rectangle().fill(LK.borderSoft).frame(height: 1)
            HStack {
                Text("key never leaves this device").font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                Spacer()
                LKButton(title: "close") { dismiss() }
                let busy = model.phase == .loading
                if case .passphrase = model.phase {
                    LKButton(title: busy ? "unlocking…" : "unlock", primary: true, arrow: true, disabledLook: busy) {
                        Task { await model.submitPassphrase() }
                    }
                } else {
                    LKButton(title: busy ? "opening…" : "open", primary: true, arrow: true, disabledLook: busy) {
                        Task { await model.open() }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14).background(LK.bgElev)
        }
        .frame(width: 640, height: 560).background(LK.bg).lockGated()   // see LockGate
        .onAppear { model.prefillFromClipboard() }
        .onChange(of: model.link) { _, _ in model.linkChanged() }
    }
}
