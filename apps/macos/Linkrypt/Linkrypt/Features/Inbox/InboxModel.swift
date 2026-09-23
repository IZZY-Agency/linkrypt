import Foundation
import Observation
import AppKit
import LinkryptCore

/// Drives the owner inbox: parse inbox link → bearer /meta → decrypt (raw
/// AES-GCM, no unpad) → reveal/save → ack-burn. inFlight + generation guard
/// the same way ReceiveModel does (no double-consume; drop edited-mid-flight).
@MainActor
@Observable
final class InboxModel {
    enum Phase: Equatable {
        case idle, loading
        case revealedText(String)   // text and note (note shown as source)
        case savedFile(String)
        case error(String)
    }

    var link: String = ""
    private(set) var phase: Phase = .idle

    private var inFlight = false
    private var generation = 0

    func prefillFromClipboard() {
        if link.isEmpty, let s = NSPasteboard.general.string(forType: .string), InboxLink.parse(s) != nil {
            link = s
        }
    }

    func linkChanged() {
        guard phase != .idle else { return }
        generation &+= 1
        phase = .idle
    }

    func open(using client: InboxClient?) async {
        guard !inFlight else { return }
        inFlight = true; defer { inFlight = false }
        generation &+= 1; let gen = generation
        guard let parsed = InboxLink.parse(link) else { setPhase(.error("Not a valid inbox link."), gen); return }
        guard let client else { setPhase(.error("Not authenticated."), gen); return }
        setPhase(.loading, gen)
        do {
            let meta = try await client.meta(id: parsed.id)
            await reveal(meta, id: parsed.id, key: parsed.key, iv: parsed.iv, client: client, gen: gen)
        } catch let e as InboxError { setPhase(.error(Self.message(e)), gen) }
        catch { setPhase(.error("\(error)"), gen) }
    }

    private func reveal(_ meta: InboxMeta, id: String, key: Data, iv: Data,
                        client: InboxClient, gen: Int) async {
        let ctBytes: Data
        if let ct = meta.ciphertext {
            guard let b = Base64URL.decode(ct) else { setPhase(.error("Corrupt submission."), gen); return }
            ctBytes = b
        } else if let dl = meta.downloadUrl {
            do { ctBytes = try await client.fetchFileCiphertext(from: dl) }
            catch { setPhase(.error("Couldn't download the encrypted file."), gen); return }
        } else {
            setPhase(.error("Empty submission."), gen); return
        }

        let pt: Data
        do { pt = try await Self.decryptOffMain(ciphertext: ctBytes, key: key, iv: iv) }
        catch { setPhase(.error("Couldn't decrypt — the inbox link may be corrupted."), gen); return }

        if meta.contentType == "file" {
            switch await Self.saveFile(pt, suggestedName: meta.filename ?? "submission.bin") {
            // Only burn if the saved phase was actually applied (link not edited
            // mid-flight). Otherwise a stale result would destroy a submission
            // the owner never saw.
            case .saved(let name): if setPhase(.savedFile(name), gen) { await ackBurn(id: id, client: client) }
            case .cancelled: setPhase(.error("Save cancelled."), gen)   // not burned — owner can retry
            case .failed(let m): setPhase(.error("Couldn't save the file (\(m))."), gen)
            }
        } else if setPhase(.revealedText(String(decoding: pt, as: UTF8.self)), gen) {
            await ackBurn(id: id, client: client)
        }
    }

    /// Fire the burn after a successful reveal/save. Best-effort; the server is
    /// idempotent, so a failure here just leaves the submission for a retry.
    private func ackBurn(id: String, client: InboxClient) async {
        try? await client.ack(id: id)
    }

    /// Apply a phase only if this flow is still current (link not edited / no
    /// newer open). Returns whether it was applied — callers gate the
    /// destructive ack-burn on this so a stale result can't burn an unread
    /// submission.
    @discardableResult
    private func setPhase(_ p: Phase, _ gen: Int) -> Bool {
        guard gen == generation else { return false }
        phase = p
        return true
    }

    private enum SaveResult { case saved(String), cancelled, failed(String) }
    @MainActor private static func saveFile(_ data: Data, suggestedName: String) async -> SaveResult {
        let panel = NSSavePanel(); panel.nameFieldStringValue = suggestedName
        guard AppLock.runModal(panel) == .OK, let url = panel.url else { return .cancelled }   // not burned on cancel/lock — owner retries
        do { try await writeData(data, to: url); return .saved(url.lastPathComponent) }
        catch { return .failed(error.localizedDescription) }
    }
    nonisolated private static func decryptOffMain(ciphertext: Data, key: Data, iv: Data) async throws -> Data {
        try Crypto.aesGcmDecrypt(key: key, iv: iv, ciphertext: ciphertext)
    }
    nonisolated private static func writeData(_ data: Data, to url: URL) async throws { try data.write(to: url) }

    private static func message(_ e: InboxError) -> String {
        switch e {
        case .gone: return "This submission is no longer available (already read, expired, or revoked)."
        case .unauthorized: return "Token rejected. Mint a fresh one at /app/tokens."
        case .forbidden: return "Forbidden — your token may lack shares:read, or this isn't your submission."
        case .network(let m): return "Network error: \(m)"
        case .server(let s): return "Server error (\(s))."
        case .decoding(let m): return "Unexpected response: \(m)"
        }
    }
}
