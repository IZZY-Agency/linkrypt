import SwiftUI
import LinkryptCore
import UniformTypeIdentifiers
import AppKit

struct ComposerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLock.self) private var lock

    var initialFiles: [URL] = []         // pre-selected files (dock drop)
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
    @State private var selection = FileSelection()
    @State private var dropTargeted = false
    /// Accepted drops whose file URLs are still loading. Sending waits for them.
    @State private var pendingImports = 0
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
                                SecretTextEditor(text: $plaintext)
                                    .frame(minHeight: 180)
                            }
                        }
                    } else {
                        filePanel
                    }

                    LKPanel(label: "Label · sent to recipient", padding: 12) {
                        // Text only: a file dropped here goes to the file list, never into the label.
                        PlainTextField(placeholder: loc("optional"), text: $label,
                                       font: .systemFont(ofSize: 13), textColor: NSColor(LK.fg))
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
                                styledField(loc("passphrase"), text: $passphrase, secure: true)
                            }
                        } else {
                            planLockedRow("Passphrase 2FA")
                        }
                        if model.limits.allows(feature: \.emailRecipient) || emailRecipient {
                            LKToggle(isOn: $emailRecipient, title: "Email the link to a recipient",
                                     hint: "delivered via the server (not zero-knowledge)")
                                .onChange(of: emailRecipient) { _, on in if !on { recipientEmail = "" } }
                            if emailRecipient {
                                styledField(loc("recipient email"), text: $recipientEmail, secure: false)
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
                // A send in flight finishes (or fails) inside the sheet: closing it
                // mid-send would let the share be created after the user cancelled.
                LKButton(title: "cancel", disabledLook: busy) {
                    guard !busy else { return }
                    dismiss()
                }
                .disabled(busy)
                LKButton(title: busy ? "sealing…" : "encrypt & share",
                         primary: true, arrow: true, disabledLook: busy || pendingImports > 0) {
                    Task { await share() }
                }
                .disabled(pendingImports > 0)   // a drop is still loading; share() refuses too
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(LK.bgElev)
        }
        .frame(width: 720, height: 700)
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(
            isOpen: { !busy && !lock.isLocked },    // frozen while sending; closed while locked
            targeted: { dropTargeted = $0 },
            began: {
                // Synchronous, before any URL loads: a send now must wait for these files.
                pendingImports += 1
                tab = .file
            },
            finished: { delivery in
                pendingImports = max(0, pendingImports - 1)
                receiveDropped(delivery.urls, failedLoads: delivery.failed)
            }))
        .lockGated()   // sheet = own window; see LockGate
        .background(LK.bg)
        // No ⎋ / cancelOperation dismissal mid-send either. The success path's
        // own dismiss() is programmatic and unaffected.
        .interactiveDismissDisabled(busy)
        .onAppear {
            if !initialFiles.isEmpty, selection.items.isEmpty {   // dock-drop pre-fill (one-shot)
                tab = .file
                report(selection.add(initialFiles))
            }
            clampToPlan()
        }
        .onChange(of: model.limits) { _, _ in clampToPlan() }
    }

    private static let fieldFont: NSFont = NSFont(name: "JetBrains Mono", size: 12)
        ?? .monospacedSystemFont(ofSize: 12, weight: .regular)

    /// Neither field types a dropped file's path: the passphrase field forwards
    /// the files to the list, the plain field lets the drop reach the window.
    @ViewBuilder
    private func styledField(_ placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure {
                PassphraseField(placeholder: placeholder, text: text, font: Self.fieldFont, textColor: NSColor(LK.fg),
                                onFileDrop: { urls in receiveDropped(urls) })
            } else {
                PlainTextField(placeholder: placeholder, text: text, font: Self.fieldFont, textColor: NSColor(LK.fg))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(LK.bg)
        .overlay(Rectangle().stroke(LK.border, lineWidth: 1))
    }

    // MARK: - Files

    private var planMaxBytes: Int? { model.limits?.maxFileSizeBytes }

    /// Binary (1024-based) size in the in-app language, like the web client and
    /// the plan pages: "5 MB", "5.2 MB". `roundingUp` is for sizes over a limit,
    /// so they never display as the limit itself.
    private func formatBytes(_ n: Int, roundingUp: Bool = false) -> String {
        let scaled = ByteSize.tenths(n, roundingUp: roundingUp)
        let value = (Double(scaled.tenths) / 10).formatted(
            .number.precision(.fractionLength(0...1)).grouping(.never).locale(model.prefs.resolvedLocale))
        switch scaled.unit {
        case .bytes: return loc("\(value) B")
        case .kilobytes: return loc("\(value) KB")
        case .megabytes: return loc("\(value) MB")
        case .gigabytes: return loc("\(value) GB")
        }
    }

    /// A localized string in the app's chosen language (the `error` line holds
    /// plain strings, so the SwiftUI environment locale does not apply to it).
    private func loc(_ key: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(key, locale: model.prefs.resolvedLocale))
    }

    /// `payload` is the live payload size for `.overPlan` (never the size
    /// recorded when the files were added).
    private func message(for problem: FileSelection.Problem, payload: Int? = nil,
                         count: Int? = nil, limit planLimit: Int? = nil) -> String {
        switch problem {
        case .empty: return loc("no files chosen")
        case .tooMany: return loc("too many files (max 100 per share)")
        case .overBundleCap: return loc("files are too large together (max 1 GB per share)")
        case .overFormatCap: return loc("file too large (max 4 GB per share)")
        case .overPlan:
            let size = formatBytes(payload ?? selection.payloadBytes, roundingUp: true)
            let limit = formatBytes(planLimit ?? planMaxBytes ?? 0)
            return (count ?? selection.items.count) > 1
                ? loc("files are too large together (\(size); your plan allows \(limit))")
                : loc("file too large (\(size); your plan allows \(limit))")
        case .changed: return loc("a file changed after you picked it — remove it and add it again")
        case .unreadable: return loc("a file can no longer be read — remove it and add it again")
        }
    }

    /// Files dropped on the window, or forwarded by the passphrase field: added in
    /// order on the file tab, refusals reported. URLs load asynchronously, so a
    /// send may have started or the app locked meanwhile; nothing is added then,
    /// but nothing is lost silently either.
    private func receiveDropped(_ urls: [URL], failedLoads: Int = 0) {
        guard !busy, !lock.isLocked else {
            let count = urls.count + failedLoads
            error = busy ? loc("couldn't add \(count) files while sending") : loc("couldn't add \(count) items")
            return
        }
        tab = .file
        report(selection.add(urls), failedLoads: failedLoads)
    }

    /// Shows what `selection.add` refused, plus dropped items whose URL could not
    /// be loaded: nothing is dropped silently. Clears the line when nothing was refused.
    private func report(_ rejected: [(url: URL, reason: DroppedFile.Rejection)], failedLoads: Int = 0) {
        var lines: [String] = []
        if rejected.contains(where: { $0.reason == .folder }) {
            lines.append(loc("folders aren't supported — drop the files inside"))
        }
        let unsupported = rejected.filter { $0.reason == .unsupported }.map { $0.url.lastPathComponent }
        let names = unsupported.filter { !$0.isEmpty }
        if !names.isEmpty {
            let joined = names.joined(separator: ", ")
            lines.append(loc("can't share \(joined)"))
        }
        // Items with no name to show (failed loads, nameless URLs) are reported by count.
        let unnamed = failedLoads + (unsupported.count - names.count)
        if unnamed > 0 { lines.append(loc("couldn't add \(unnamed) items")) }
        error = lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private var filePanel: some View {
        let names = selection.displayNames
        let problem = selection.items.isEmpty ? nil : selection.problem(planMaxBytes: planMaxBytes)
        return LKPanel(label: "Files · encrypted on device", focused: dropTargeted, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                if selection.items.isEmpty {
                    HStack(spacing: 12) {
                        Text("no files chosen").font(LK.sans(13)).foregroundStyle(LK.fgMuted)
                        Spacer()
                        LKButton(title: "add files…", disabledLook: busy) { pickFiles() }
                    }
                    Text("or drop files on this window").font(LK.mono(10)).foregroundStyle(LK.fgDim)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(selection.items.enumerated()), id: \.offset) { i, item in
                                HStack(spacing: 12) {
                                    Text(verbatim: names[i]).font(LK.sans(13)).foregroundStyle(LK.fg)
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text(verbatim: formatBytes(item.size))
                                        .font(LK.mono(11)).foregroundStyle(LK.fgMuted)
                                    Button { if !busy { selection.remove(at: i) } } label: {
                                        HStack(spacing: 4) {
                                            Text("[").foregroundStyle(LK.borderHi)
                                            Text("×").foregroundStyle(LK.fgMuted)
                                            Text("]").foregroundStyle(LK.borderHi)
                                        }.font(LK.mono(12)).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain).disabled(busy)
                                    .accessibilityLabel("remove \(names[i])")
                                }
                                .padding(.vertical, 6)
                                if i < selection.items.count - 1 {
                                    Rectangle().fill(LK.borderSoft).frame(height: 1)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: min(CGFloat(selection.items.count) * 32, 200))

                    HStack(spacing: 6) {
                        Text("\(selection.items.count) files")
                        Text(verbatim: "· \(formatBytes(selection.payloadBytes, roundingUp: problem != nil))")
                        if let limit = planMaxBytes {
                            Text("of \(formatBytes(limit))")
                        }
                    }
                    .font(LK.mono(11)).foregroundStyle(problem == nil ? LK.fgMuted : LK.err)
                    if let problem {
                        Text(verbatim: message(for: problem)).font(LK.mono(11)).foregroundStyle(LK.err)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if selection.items.count >= 2 {
                        Text("Sent as one encrypted \(FileBundle.filename(count: selection.items.count)). File names are encrypted too.")
                            .font(LK.mono(10)).foregroundStyle(LK.fgMuted)
                    }
                    HStack(spacing: 12) {
                        Text("or drop files on this window").font(LK.mono(10)).foregroundStyle(LK.fgDim)
                        Spacer()
                        if selection.items.count >= 2 {
                            LKButton(title: "clear all", disabledLook: busy) {
                                guard !busy else { return }
                                selection.removeAll(); error = nil
                            }
                        }
                        LKButton(title: "add files…", disabledLook: busy) { pickFiles() }
                    }
                }
            }
        }
    }

    private func pickFiles() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        if AppLock.runModal(panel) == .OK { report(selection.add(panel.urls)) }
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
        // A drop is still loading its files: sending now would leave them out (or
        // send the text tab the drop is replacing). Refuse before any snapshot.
        if pendingImports > 0 { error = loc("adding files — try again in a moment"); return }
        guard let client = model.client else { return }
        if let blocked = planBlockedFeature { error = blocked; return }
        busy = true; error = nil; warning = nil; defer { busy = false }
        // Snapshot every input before the first await: edits, drops or tab
        // switches while sealing/uploading must not change what is sent.
        let sendTab = tab
        let sendPlaintext = plaintext
        let sendSelection = selection
        let sendLabel = label, sendExpiresIn = expiresIn, sendMaxOpens = maxOpens
        let sendNotify = notifyOnOpen
        let sendPassphrase = usePassphrase ? passphrase : ""
        let sendEmail = recipientEmail.isEmpty ? nil : recipientEmail
        let sendPlanMax = planMaxBytes
        let planLoaded = model.who != nil
        do {
            // Cheap checks first, so a share that will be refused never pays for
            // the Argon2 passphrase hash (about half a second at 64 MiB).
            var textPayload = Data()
            var liveSizes: [Int] = []
            if sendTab == .file {
                // A file send is checked against the plan limit: refuse until the plan is known.
                if !planLoaded {
                    error = loc("your plan is still loading — try again in a moment")
                    Task { await model.refresh() }      // so a retry can succeed once the plan arrives
                    return
                }
                // Preflight on-disk sizes BEFORE reading anything, so an oversized
                // selection never loads into memory and nothing hits the network.
                // Run the structural checks (count, bundle cap, format cap) with no
                // plan limit, then apply the plan limit to the exact live payload.
                switch sendSelection.livePreflight(planMaxBytes: nil) {
                case .failure(let problem):
                    error = message(for: problem); return
                case .success(let sizes):
                    let payload = sendSelection.payloadBytes(forSizes: sizes)
                    if let limit = sendPlanMax, payload > limit {
                        error = message(for: .overPlan, payload: payload,
                                        count: sendSelection.items.count, limit: limit); return
                    }
                    liveSizes = sizes
                }
            } else {
                textPayload = Data(sendPlaintext.utf8)
                guard Crypto.textPlaintextFitsCap(textPayload.count) else { error = "text too large (1 MiB max). Use a file share instead."; return }
            }

            let key = Crypto.randomBytes(32), iv = Crypto.randomBytes(12)
            var salt: Data?; var hash: String?
            if !sendPassphrase.isEmpty {
                let s = Crypto.randomBytes(16)
                let pass = sendPassphrase
                // Argon2id is memory-hard (~0.5s at 64 MiB) — derive off the
                // main actor so the window doesn't beachball while sealing.
                let derived = try await Task.detached(priority: .userInitiated) {
                    try Crypto.argon2id(passphrase: pass, salt: s)
                }.value
                salt = s; hash = Base64URL.encode(derived)
            }
            let email = sendEmail

            let id: String
            if sendTab == .text {
                let ct = try Crypto.sealPaddedV1(key: key, iv: iv, plaintext: textPayload)
                let req = CreateShareRequest(type: .text, size: ct.count, rawSize: textPayload.count,
                    expiresIn: sendExpiresIn, maxOpens: sendMaxOpens, label: sendLabel.isEmpty ? nil : sendLabel,
                    filename: nil, recipientEmail: email, notifyOnOpen: sendNotify,
                    passphraseSalt: salt.map(Base64URL.encode), passphraseHash: hash,
                    passphraseKdf: hash != nil ? .argon2id : nil, paddingVersion: .v1)
                let resp = try await client.createShare(req)
                try await client.finalizeText(id: resp.id, ciphertext: ct)
                id = resp.id
            } else {
                // Reading, packing and encrypting can take seconds for large files:
                // do it off the main actor. Only snapshot values cross over.
                let urls = sendSelection.items.map(\.url)
                let names = sendSelection.displayNames
                let sizes = liveSizes, planMax = sendPlanMax
                let sealed: SealedFile
                do {
                    sealed = try await Task.detached(priority: .userInitiated) {
                        try Self.packAndSeal(urls: urls, names: names, sizes: sizes, planMax: planMax, key: key, iv: iv)
                    }.value
                } catch let failure as PackFailure {
                    error = message(for: failure, limit: planMax); return
                }
                let req = CreateShareRequest(type: .file, size: sealed.ciphertext.count, rawSize: sealed.rawSize,
                    expiresIn: sendExpiresIn, maxOpens: sendMaxOpens, label: sendLabel.isEmpty ? nil : sendLabel,
                    filename: sealed.uploadName, recipientEmail: email, notifyOnOpen: sendNotify,
                    passphraseSalt: salt.map(Base64URL.encode), passphraseHash: hash,
                    passphraseKdf: hash != nil ? .argon2id : nil, paddingVersion: .v1)
                let resp = try await client.createShare(req)
                guard let uploadUrl = resp.uploadUrl else { error = "no upload url"; return }
                try await client.putR2(uploadUrl: uploadUrl, ciphertext: sealed.ciphertext)
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
        } catch PaddingError.plaintextTooLarge {
            error = message(for: .overFormatCap)   // backstop: the preflight refuses this before reading
        } catch { self.error = "\(error)" }
    }

    private func message(for failure: PackFailure, limit: Int?) -> String {
        switch failure {
        case .problem(let problem): return message(for: problem)
        case .overPlan(let payload): return message(for: .overPlan, payload: payload, count: 1, limit: limit)
        case .packFailed: return loc("couldn't pack these files — remove the last added file and try again")
        }
    }

    /// Reads the files, checks each against the size it was preflighted with,
    /// packs two or more into one bundle and seals the result. Runs off the main
    /// actor and touches nothing but its arguments.
    nonisolated private static func packAndSeal(urls: [URL], names: [String], sizes: [Int], planMax: Int?,
                                                key: Data, iv: Data) throws -> SealedFile {
        guard sizes.count == urls.count, names.count == urls.count else { throw PackFailure.problem(.changed) }
        let raw: Data
        let uploadName: String
        do {
            var contents: [Data] = []
            for (i, url) in urls.enumerated() {
                let data: Data
                do { data = try Data(contentsOf: url) }
                catch { throw PackFailure.problem(.unreadable) }
                guard data.count == sizes[i] else { throw PackFailure.problem(.changed) }
                contents.append(data)
            }
            if urls.count == 1 {
                raw = contents[0]
                if let limit = planMax, raw.count > limit { throw PackFailure.overPlan(payload: raw.count) }
                uploadName = urls[0].lastPathComponent
            } else {
                let entries = zip(names, zip(urls, contents)).map { name, pair in
                    let modified = (try? pair.0.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? Date()
                    let stamp = FileBundle.dosDateTime(modified)
                    return FileBundle.Entry(name: name, data: pair.1, dosTime: stamp.time, dosDate: stamp.date)
                }
                do { raw = try FileBundle.build(entries) }
                catch FileBundle.BuildError.size { throw PackFailure.problem(.overBundleCap) }
                // .count / .name / .duplicate cannot happen for a checked selection;
                // if one does, the composer says so plainly.
                catch is FileBundle.BuildError { throw PackFailure.packFailed }
                uploadName = FileBundle.filename(count: urls.count)
            }
        }   // per-file buffers are released here, before sealing
        let ciphertext = try Crypto.sealPaddedV1(key: key, iv: iv, plaintext: raw)
        return SealedFile(ciphertext: ciphertext, rawSize: raw.count, uploadName: uploadName)
    }
}

/// A file share ready to upload.
private struct SealedFile: Sendable {
    let ciphertext: Data
    let rawSize: Int
    let uploadName: String
}

/// Why packing stopped before anything reached the network.
private enum PackFailure: Error {
    /// `.unreadable`, `.changed` or `.overBundleCap`.
    case problem(FileSelection.Problem)
    /// The single file grew past the plan limit while it was read.
    case overPlan(payload: Int)
    /// FileBundle refused the entries for a reason other than size.
    case packFailed
}
