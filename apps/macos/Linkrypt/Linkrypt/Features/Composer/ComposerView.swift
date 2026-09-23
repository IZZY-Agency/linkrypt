import SwiftUI
import LinkryptCore
import UniformTypeIdentifiers
import AppKit

struct ComposerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var initialFile: URL? = nil          // pre-selected file (dock drop)
    /// Called once the share exists (id, recipient URL, email-delivery warning
    /// if the link couldn't be emailed). The composer then dismisses itself —
    /// the presenter shows the QR / link sheet in its place, not on top of it.
    let onCreated: (String, String, String?) -> Void

    enum Tab: Hashable { case text, file }
    @State private var tab: Tab = .text
    @State private var plaintext = ""
    @State private var label = ""
    @State private var expiresIn = "24h"
    @State private var maxOpens = 1
    @State private var passphrase = ""
    @State private var usePassphrase = false
    @State private var notifyOnOpen = false
    @State private var emailRecipient = false
    @State private var recipientEmail = ""
    @State private var pickedFile: URL?
    @State private var busy = false
    @State private var error: String?
    @State private var warning: String?

    /// Every option the UI knows; filtered through `model.limits` at render
    /// time so a Free account never sees "1 hour" / "5 opens" the server 402s.
    private static let allExpiries: [(String, LocalizedStringKey)] = [
        ("1h", "1 hour"), ("24h", "24 hours"), ("7d", "7 days"), ("30d", "30 days"),
    ]
    private static let allOpens: [(Int, LocalizedStringKey)] = [
        (1, "1 then burn"), (2, "2"), (3, "3"), (4, "4"),
        (5, "5"), (10, "10"), (25, "25"), (50, "50"), (100, "100"),
    ]
    private var expiryOptions: [(String, LocalizedStringKey)] {
        let allowed = model.limits.filter(expiries: Self.allExpiries.map(\.0))
        return Self.allExpiries.filter { allowed.contains($0.0) }
    }
    private var opensOptions: [(Int, LocalizedStringKey)] {
        let allowed = model.limits.filter(opens: Self.allOpens.map(\.0))
        return Self.allOpens.filter { allowed.contains($0.0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                Text("// COMPOSE SHARE").font(LK.mono(10)).tracking(1.5).foregroundStyle(LK.fgMuted)
                Text("Encrypt & share").font(LK.sans(22, weight: .semibold)).foregroundStyle(LK.fg)
                LKSegmented(selection: $tab, items: [(.text, "text"), (.file, "file")], shortcutModifiers: .command)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 14)

            Rectangle().fill(LK.borderSoft).frame(height: 1)

            // ── Body ──────────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if tab == .text {
                        LKPanel(label: "Secret · plaintext", focused: true, padding: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Spacer()
                                    LKButton(title: "load file…") { loadFile() }
                                }
                                TextEditor(text: $plaintext)
                                    .font(LK.mono(12.5))
                                    .foregroundStyle(LK.fg)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 180)
                            }
                        }
                    } else {
                        LKPanel(label: "File · encrypted on device", padding: 16) {
                            HStack(spacing: 12) {
                                Text(pickedFile?.lastPathComponent ?? "no file chosen")
                                    .font(LK.sans(13))
                                    .foregroundStyle(pickedFile == nil ? LK.fgMuted : LK.fg)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                LKButton(title: "choose…") { pickFile() }
                            }
                        }
                    }

                    LKPanel(label: "Label · sent to recipient", padding: 12) {
                        TextField("optional", text: $label)
                            .textFieldStyle(.plain).font(LK.sans(13)).foregroundStyle(LK.fg)
                    }

                    HStack(spacing: 12) {
                        LKPanel(label: "Expires", padding: 10) {
                            LKDropdown(selection: $expiresIn, options: expiryOptions)
                        }
                        LKPanel(label: "Max opens", padding: 10) {
                            LKDropdown(selection: $maxOpens, options: opensOptions)
                        }
                    }

                    VStack(spacing: 10) {
                        // A toggle the user already switched ON stays visible even if
                        // the plan (loaded later) doesn't include it, so they can turn it
                        // off themselves — submit() refuses meanwhile. Never silently drop
                        // a protection the user chose.
                        if model.limits.allows(feature: \.passphrase) || usePassphrase {
                            LKToggle(isOn: $usePassphrase, title: "Passphrase 2FA", hint: "Argon2id · 64 MiB")
                            if usePassphrase {
                                styledField("passphrase", text: $passphrase, secure: true)
                            }
                        } else {
                            planLockedRow("Passphrase 2FA")
                        }
                        if model.limits.allows(feature: \.emailRecipient) || emailRecipient {
                            LKToggle(isOn: $emailRecipient, title: "Email the link to a recipient",
                                     hint: "delivered via the server (not zero-knowledge)")
                                .onChange(of: emailRecipient) { _, on in if !on { recipientEmail = "" } }
                            if emailRecipient {
                                styledField("recipient email", text: $recipientEmail, secure: false)
                            }
                        } else {
                            planLockedRow("Email the link to a recipient")
                        }
                        if model.limits.allows(feature: \.notifyOnOpen) || notifyOnOpen {
                            LKToggle(isOn: $notifyOnOpen, title: "Notify me on open", hint: "push when the share is read")
                        } else {
                            planLockedRow("Notify me on open")
                        }
                    }

                    if let error { Text("× \(error)").font(LK.mono(11)).foregroundStyle(LK.err) }
                    if let warning { Text("⚠ \(warning)").font(LK.mono(11)).foregroundStyle(LK.amber)
                        .fixedSize(horizontal: false, vertical: true) }
                }
                .padding(24)
            }

            Rectangle().fill(LK.borderSoft).frame(height: 1)

            // ── Footer ────────────────────────────────────────────────
            HStack {
                Text("key never leaves this device").font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                Spacer()
                LKButton(title: "cancel") { dismiss() }
                LKButton(title: busy ? "sealing…" : "encrypt & share",
                         primary: true, arrow: true, disabledLook: busy) {
                    Task { await share() }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(LK.bgElev)
        }
        .frame(width: 720, height: 700).lockGated()   // sheet = own window; see LockGate
        .background(LK.bg)
        .onAppear {
            if let initialFile, pickedFile == nil {     // dock-drop pre-fill (one-shot)
                tab = .file
                pickedFile = initialFile
            }
            clampToPlan()
        }
        .onChange(of: model.limits) { _, _ in clampToPlan() }
    }

    @ViewBuilder
    private func styledField(_ placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure { SecureField(placeholder, text: text) }
            else { TextField(placeholder, text: text) }
        }
        .textFieldStyle(.plain)
        .font(LK.mono(12)).foregroundStyle(LK.fg)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(LK.bg)
        .overlay(Rectangle().stroke(LK.border, lineWidth: 1))
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if AppLock.runModal(panel) == .OK { pickedFile = panel.url }
    }

    /// Load a .env / text file's contents into the secret box. Preflights the
    /// on-disk size BEFORE reading so a huge file never loads into memory; then
    /// strict-decodes via `SecretFile.decode`.
    /// A feature the plan doesn't include: shown, not offered (mirrors the web
    /// composer, which hides Pro-only controls on Free).
    private func planLockedRow(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Text(title).font(LK.sans(13)).foregroundStyle(LK.fgMuted)
            Spacer()
            Text("Pro plan").font(LK.mono(9)).tracking(1).foregroundStyle(LK.amber)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(Rectangle().stroke(LK.amber.opacity(0.5), lineWidth: 1))
        }
    }

    /// Keep the dropdown selections inside the plan (defaults / a plan change
    /// while the sheet is open) so they never show an empty label and the
    /// request can't trip the server's expiry / max_opens gates. Feature
    /// toggles are deliberately NOT touched here — see the toggle rows.
    private func clampToPlan() {
        expiresIn = model.limits.clamp(expiry: expiresIn, candidates: Self.allExpiries.map(\.0))
        maxOpens = model.limits.clamp(opens: maxOpens, candidates: Self.allOpens.map(\.0))
    }

    /// A protection the user switched on that the (later-loaded) plan doesn't
    /// include. Refuse rather than downgrade the share behind their back.
    private var planBlockedFeature: String? {
        if usePassphrase, !model.limits.allows(feature: \.passphrase) {
            return "Passphrase 2FA isn't included in your plan — turn it off to continue."
        }
        if emailRecipient, !model.limits.allows(feature: \.emailRecipient) {
            return "Email delivery isn't included in your plan — turn it off to continue."
        }
        if notifyOnOpen, !model.limits.allows(feature: \.notifyOnOpen) {
            return "Open notifications aren't included in your plan — turn them off to continue."
        }
        return nil
    }

    private func loadFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard AppLock.runModal(panel) == .OK, let url = panel.url else { return }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        guard size <= Crypto.maxTextPlaintextBytes else {
            error = "File too large (1 MiB max for a text share)."; return
        }
        guard let data = try? Data(contentsOf: url) else {
            error = "Couldn't read that file."; return
        }
        switch SecretFile.decode(data) {
        case .success(let text): plaintext = text; error = nil
        case .failure(.tooLarge): error = "File too large (1 MiB max for a text share)."
        case .failure(.notUTF8): error = "Not a UTF-8 text file."
        }
    }

    private func share() async {
        guard !busy else { return }            // prevent double-submit
        guard let client = model.client else { return }
        if let blocked = planBlockedFeature { error = blocked; return }
        busy = true; error = nil; warning = nil; defer { busy = false }
        do {
            let key = Crypto.randomBytes(32), iv = Crypto.randomBytes(12)
            var salt: Data?; var hash: String?
            if usePassphrase, !passphrase.isEmpty {
                let s = Crypto.randomBytes(16)
                let pass = passphrase
                // Argon2id is memory-hard (~0.5s at 64 MiB) — derive off the
                // main actor so the window doesn't beachball while sealing.
                let derived = try await Task.detached(priority: .userInitiated) {
                    try Crypto.argon2id(passphrase: pass, salt: s)
                }.value
                salt = s; hash = Base64URL.encode(derived)
            }
            let email = recipientEmail.isEmpty ? nil : recipientEmail

            let id: String
            if tab == .text {
                let pt = Data(plaintext.utf8)
                guard Crypto.textPlaintextFitsCap(pt.count) else { error = "text too large (1 MiB max). Use a file share instead."; return }
                let ct = try Crypto.sealPaddedV1(key: key, iv: iv, plaintext: pt)
                let req = CreateShareRequest(type: .text, size: ct.count, rawSize: pt.count,
                    expiresIn: expiresIn, maxOpens: maxOpens, label: label.isEmpty ? nil : label,
                    filename: nil, recipientEmail: email, notifyOnOpen: notifyOnOpen,
                    passphraseSalt: salt.map(Base64URL.encode), passphraseHash: hash,
                    passphraseKdf: hash != nil ? .argon2id : nil, paddingVersion: .v1)
                let resp = try await client.createShare(req)
                try await client.finalizeText(id: resp.id, ciphertext: ct)
                id = resp.id
            } else {
                guard let fileURL = pickedFile else { error = "choose a file"; return }
                // Preflight the on-disk size BEFORE reading so an oversized
                // (e.g. dropped multi-GB) file can't be loaded into memory.
                let onDisk = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
                guard onDisk <= 100 * 1024 * 1024 else { error = "file too large (100 MiB max)"; return }
                let raw = try Data(contentsOf: fileURL)
                guard raw.count <= 100 * 1024 * 1024 else { error = "file too large (100 MiB max)"; return }
                let ct = try Crypto.sealPaddedV1(key: key, iv: iv, plaintext: raw)
                let req = CreateShareRequest(type: .file, size: ct.count, rawSize: raw.count,
                    expiresIn: expiresIn, maxOpens: maxOpens, label: label.isEmpty ? nil : label,
                    filename: fileURL.lastPathComponent, recipientEmail: email, notifyOnOpen: notifyOnOpen,
                    passphraseSalt: salt.map(Base64URL.encode), passphraseHash: hash,
                    passphraseKdf: hash != nil ? .argon2id : nil, paddingVersion: .v1)
                let resp = try await client.createShare(req)
                guard let uploadUrl = resp.uploadUrl else { error = "no upload url"; return }
                try await client.putR2(uploadUrl: uploadUrl, ciphertext: ct)
                try await client.finalizeFile(id: resp.id)
                id = resp.id
            }

            let url = ShareLink.recipientURL(baseURL: model.baseURL, lang: model.prefs.languageCode, id: id, key: key, iv: iv)
            model.linkCache.store(id: id, url: url)
            // NOTE: The recipient URL including the #fragment (key+iv) is sent to the
            // server for email delivery — this flow is NOT zero-knowledge from the
            // server's perspective. Documented trade-off.
            if let email {
                do {
                    try await client.emailLink(id: id, url: url, recipientEmail: email, lang: model.prefs.languageCode)
                } catch APIError.planLimit(let limit, let upgrade) {
                    warning = "Share created, but emailing the link failed: plan limit (\(limit)). Upgrade at \(model.baseURL)\(upgrade)"
                } catch APIError.forbidden(let msg) {
                    warning = "Share created, but emailing the link failed: \(msg)"
                } catch APIError.insufficientScope(let missing) {
                    warning = "Share created, but emailing the link failed: token is missing scope(s): \(missing.joined(separator: ", "))"
                } catch {
                    warning = "Share created, but emailing the link failed: \(error)"
                }
            }
            onCreated(id, url, warning)
            dismiss()                                  // presenter shows the detail sheet
            Task { await model.refresh() }
        } catch APIError.planLimit(let limit, let upgrade) {
            error = "Plan limit (\(limit)). Upgrade: \(model.baseURL)\(upgrade)"
        } catch { self.error = "\(error)" }
    }
}
