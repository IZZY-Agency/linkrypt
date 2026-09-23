import Foundation
import Observation
import AppKit
import LinkryptCore

/// Drives the open-a-link flow: parse → /meta → (passphrase) → decrypt → reveal.
/// Decrypt/parse/passphrase delegate to the tested LinkryptCore recipient core;
/// NSPasteboard / NSSavePanel are AppKit glue. `Clipboard.copy` (via LKMonoField)
/// uses the launch-configured global Preferences, so no prefs dependency here.
///
/// Concurrency safety (no double-consume of an open): `inFlight` blocks a second
/// open/submit while one is running — even across a `linkChanged()` reset — and a
/// `generation` token drops any result whose link was edited mid-flight.
@MainActor
@Observable
final class ReceiveModel {
    enum Phase: Equatable {
        case idle, loading, passphrase
        case revealedText(String)
        case savedFile(String)
        /// The lock aborted the save panel (or the user cancelled it). The open
        /// is already spent, so the decrypted bytes are held in memory until an
        /// explicit "Save file…" — never lose a burn-on-open file to the lock.
        case pendingSave(String)
        case error(String)
    }

    var link: String = ""
    var passphrase: String = ""
    private(set) var phase: Phase = .idle
    private(set) var opensRemaining: Int?
    private(set) var errorText: String?     // inline (e.g. wrong passphrase, retry in place)

    private var inFlight = false
    private var generation = 0
    private var parsed: ShareLink.ParsedShareLink?
    private var client: RecipientClient?
    private var pendingSalt: String?
    private var pendingKdf: PassphraseKdf?
    /// Decrypted file bytes awaiting `saveAgain()` (see `Phase.pendingSave`).
    private var pendingData: Data?

    /// Pre-fill from the clipboard if it holds a valid Linkrypt link.
    func prefillFromClipboard() {
        if link.isEmpty, let s = NSPasteboard.general.string(forType: .string), ShareLink.parse(s) != nil {
            link = s
        }
    }

    /// The user edited the link — invalidate any in-flight result and drop state
    /// tied to the previous link. Does NOT clear `inFlight`, so a request already
    /// on the wire can't be joined by a second consuming open.
    func linkChanged() {
        guard phase != .idle || errorText != nil || pendingSalt != nil else { return }
        generation &+= 1
        phase = .idle; errorText = nil; opensRemaining = nil
        passphrase = ""; parsed = nil; client = nil; pendingSalt = nil; pendingKdf = nil
        pendingData = nil
    }

    func open() async {
        guard !inFlight else { return }                 // no duplicate consuming GETs
        inFlight = true; defer { inFlight = false }
        generation &+= 1; let gen = generation
        errorText = nil; opensRemaining = nil; passphrase = ""
        parsed = nil; client = nil; pendingSalt = nil; pendingKdf = nil
        guard let p = ShareLink.parse(link) else { setPhase(.error("Not a valid Linkrypt link."), gen); return }
        parsed = p
        let c = RecipientClient(baseURL: p.baseURL); client = c
        setPhase(.loading, gen)
        do {
            let meta = try await c.meta(id: p.id)
            await handle(meta, gen: gen, parsed: p, client: c)
        } catch let e as RecipientError { setPhase(.error(Self.message(e)), gen) }
        catch { setPhase(.error("\(error)"), gen) }
    }

    func submitPassphrase() async {
        guard !inFlight, let p = parsed, let c = client, let salt = pendingSalt, let kdf = pendingKdf,
              let saltData = Base64URL.decode(salt) else { return }
        inFlight = true; defer { inFlight = false }
        generation &+= 1; let gen = generation
        errorText = nil
        let pass = passphrase; passphrase = ""           // clear the raw passphrase ASAP
        setPhase(.loading, gen)
        do {
            // Argon2id is memory-hard (~0.5s) — derive off the main actor.
            let attempt = try await Self.deriveAttempt(passphrase: pass, salt: saltData, kdf: kdf)
            let meta = try await c.submitPassphrase(id: p.id, attempt: attempt)
            await handle(meta, gen: gen, parsed: p, client: c)
        } catch RecipientError.passphraseInvalid {
            // A wrong passphrase doesn't consume an open — retry in place.
            guard gen == generation else { return }
            errorText = "Wrong passphrase — try again."; phase = .passphrase
        } catch let e as RecipientError { setPhase(.error(Self.message(e)), gen) }
        catch { setPhase(.error("\(error)"), gen) }
    }

    private func handle(_ meta: RecipientMeta, gen: Int,
                        parsed p: ShareLink.ParsedShareLink, client c: RecipientClient) async {
        switch meta {
        case let .passphraseRequired(salt, kdf, _, _, _, opens, _):
            guard gen == generation else { return }
            pendingSalt = salt; pendingKdf = kdf; opensRemaining = opens; phase = .passphrase
        case let .payload(type, _, filename, ciphertext, downloadUrl, padding, opens, _):
            if gen == generation { opensRemaining = opens }
            await reveal(type: type, filename: filename, ciphertext: ciphertext, downloadUrl: downloadUrl,
                         padding: padding, gen: gen, parsed: p, client: c)
        }
    }

    /// Everything here is POST-payload — an open has already been spent, so every
    /// failure path says so (a retry won't re-open the share).
    private func reveal(type: ShareType, filename: String?, ciphertext: String?, downloadUrl: String?,
                        padding: PaddingVersion, gen: Int,
                        parsed p: ShareLink.ParsedShareLink, client c: RecipientClient) async {
        let ctBytes: Data
        if let ct = ciphertext {
            guard let b = Base64URL.decode(ct) else {
                setPhase(.error("Corrupt payload — the open was already spent."), gen); return
            }
            ctBytes = b
        } else if let dl = downloadUrl {
            do { ctBytes = try await c.fetchCiphertext(from: dl) }   // presigned URL — in-memory only
            catch { setPhase(.error("Couldn't download the encrypted file — the open was already spent."), gen); return }
        } else {
            setPhase(.error("Empty payload — the open was already spent."), gen); return
        }

        let pt: Data
        do { pt = try await Self.decryptOffMain(ciphertext: ctBytes, key: p.key, iv: p.iv, padding: padding) }
        catch { setPhase(.error("Couldn't decrypt — the link may be corrupted. The open was already spent."), gen); return }

        if type == .file {
            let name = filename ?? "linkrypt-download"
            switch await Self.saveFile(pt, suggestedName: name) {
            case .saved(let saved): setPhase(.savedFile(saved), gen)
            // The open is spent either way — keep the bytes so the user can
            // still save after unlocking / changing their mind.
            case .locked, .cancelled:
                if setPhase(.pendingSave(name), gen) { pendingData = pt }
            case .failed(let m):
                if setPhase(.pendingSave(name), gen) { pendingData = pt; errorText = "Couldn't save the file (\(m)) — try again." }
            }
        } else {
            setPhase(.revealedText(String(decoding: pt, as: UTF8.self)), gen)
        }
    }

    /// Apply a phase only if this flow is still current (link not edited / no newer open).
    @discardableResult
    private func setPhase(_ p: Phase, _ gen: Int) -> Bool {
        guard gen == generation else { return false }
        phase = p
        return true
    }

    /// Re-present the save panel for bytes held by `Phase.pendingSave`.
    func saveAgain() async {
        guard !inFlight, case .pendingSave(let name) = phase, let data = pendingData else { return }
        inFlight = true; defer { inFlight = false }
        let gen = generation
        errorText = nil
        switch await Self.saveFile(data, suggestedName: name) {
        case .saved(let saved): if setPhase(.savedFile(saved), gen) { pendingData = nil }
        case .locked, .cancelled: break                       // still pending
        case .failed(let m): if gen == generation { errorText = "Couldn't save the file (\(m)) — try again." }
        }
    }

    private enum SaveResult { case saved(String), locked, cancelled, failed(String) }

    @MainActor
    private static func saveFile(_ data: Data, suggestedName: String) async -> SaveResult {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        let response = AppLock.runModal(panel)
        if response == .abort { return .locked }
        guard response == .OK, let url = panel.url else { return .cancelled }
        do { try await writeData(data, to: url); return .saved(url.lastPathComponent) }
        catch { return .failed(error.localizedDescription) }
    }

    // nonisolated async helpers run off the main actor automatically — keeps the
    // memory-hard KDF, decrypt, and large file writes from blocking the UI.
    nonisolated private static func deriveAttempt(passphrase: String, salt: Data,
                                                  kdf: PassphraseKdf) async throws -> String {
        try RecipientCrypto.passphraseAttempt(passphrase: passphrase, salt: salt, kdf: kdf)
    }
    nonisolated private static func decryptOffMain(ciphertext: Data, key: Data, iv: Data,
                                                   padding: PaddingVersion) async throws -> Data {
        try RecipientCrypto.decrypt(ciphertext: ciphertext, key: key, iv: iv, padding: padding)
    }
    nonisolated private static func writeData(_ data: Data, to url: URL) async throws {
        try data.write(to: url)
    }

    private static func message(_ e: RecipientError) -> String {
        switch e {
        case .gone: return "This share is no longer available (opened, expired, or revoked)."
        case .passphraseInvalid: return "Wrong passphrase — try again."
        case .rateLimited: return "Too many attempts. Try again shortly."
        case .network(let m): return "Network error: \(m)"
        case .server(let s): return "Server error (\(s))."
        case .decoding(let m): return "Unexpected response: \(m)"
        }
    }
}
