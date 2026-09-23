import SwiftUI
import AppKit
import LinkryptCore

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var token = ""
    @State private var busy = false

    var body: some View {
        ZStack {
            LK.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // ── Hero ──────────────────────────────────────────────
                VStack(spacing: 14) {
                    LKLock(size: 56)
                    Text("// ZERO-KNOWLEDGE SHARE")
                        .font(LK.mono(10)).tracking(1.5).foregroundStyle(LK.amber)
                    Text("Paste an API token to sign in.")
                        .font(LK.sans(22, weight: .semibold)).foregroundStyle(LK.fg)
                    Text("No passwords. We never see your shares — the key never leaves this device.")
                        .font(LK.sans(12)).foregroundStyle(LK.fgMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }

                // ── Token card ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 18) {
                    LKPanel(label: "API token", focused: true, padding: 12) {
                        HStack(spacing: 8) {
                            Text("▸").foregroundStyle(LK.amber).font(LK.mono(13))
                            SecureField("paste token from /app/tokens", text: $token)
                                .textFieldStyle(.plain)
                                .font(LK.mono(13))
                                .foregroundStyle(LK.fg)
                                .onSubmit { signIn() }
                        }
                    }

                    if let err = model.lastError {
                        (Text(verbatim: "× ") + Text(LocalizedStringKey(err)))
                            .font(LK.mono(11)).foregroundStyle(LK.err)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Button {
                            if let u = URL(string: "\(model.baseURL)/app/tokens") {
                                NSWorkspace.shared.open(u)
                            }
                        } label: {
                            Text("mint a token at /app/tokens")
                                .font(LK.mono(11)).foregroundStyle(LK.fgMuted)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Spacer()
                        LKButton(title: busy ? "validating…" : "sign in",
                                 primary: true, arrow: true,
                                 disabledLook: token.isEmpty || busy) {
                            signIn()
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 460)

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LK.bg)
    }

    private func signIn() {
        guard !token.isEmpty, !busy else { return }
        Task { busy = true; await model.login(token: token); busy = false }
    }
}
