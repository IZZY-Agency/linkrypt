import Foundation
import Observation
import AppKit
import LinkryptCore

/// Drives the respond-to-a-request flow: paste link → /info → compose text/file
/// → encrypt + submit. Single-submit guard (busy).
@MainActor
@Observable
final class RespondModel {
    enum Phase: Equatable {
        case idle
        case loadingInfo
        case ready(label: String?)
        case submitting
        case done
        case error(String)
    }

    var link: String = ""
    var text: String = ""
    private(set) var phase: Phase = .idle
    private(set) var pickedFile: URL?
    private var parsedId: String?
    private var busy = false
    private var generation = 0

    func prefillFromClipboard() {
        if link.isEmpty, let s = NSPasteboard.general.string(forType: .string), RequestLink.parse(s) != nil {
            link = s
        }
    }

    /// The user edited the request link — drop the loaded id + ready-state so a
    /// later `submit` can NEVER deliver to a stale request's owner, and discard
    /// any in-flight `loadInfo` (generation bump). Wired to `.onChange(of: link)`.
    func linkChanged() {
        generation &+= 1
        parsedId = nil
        pickedFile = nil
        if phase != .idle { phase = .idle }
    }

    func loadInfo(using client: SubmitClient?) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        generation &+= 1; let gen = generation
        parsedId = nil
        guard let parsed = RequestLink.parse(link) else { phase = .error("Not a valid request link."); return }
        guard let client else { phase = .error("Not authenticated."); return }
        phase = .loadingInfo
        do {
            let info = try await client.info(id: parsed.id)
            guard gen == generation else { return }   // link edited mid-load → drop the stale result
            parsedId = parsed.id                       // only arm the id once the load is confirmed current
            phase = .ready(label: info.label)
        }
        catch let e as SubmitError { if gen == generation { phase = .error(Self.message(e)) } }
        catch { if gen == generation { phase = .error("\(error)") } }
    }

    func pickFile() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if AppLock.runModal(panel) == .OK { pickedFile = panel.url }
    }

    func submit(using client: SubmitClient?, putR2: @escaping @Sendable (String, Data) async throws -> Void) async {
        guard !busy, let id = parsedId, let client else { return }
        busy = true; defer { busy = false }
        phase = .submitting
        do {
            if let file = pickedFile {
                try await client.submitFile(id: id, fileURL: file, putR2: putR2)
            } else {
                guard !text.isEmpty else { phase = .error("Type something to send."); return }
                try await client.submitText(id: id, type: "text", plaintext: Data(text.utf8))
            }
            phase = .done
        } catch let e as SubmitError { phase = .error(Self.message(e)) }
        catch { phase = .error("\(error)") }
    }

    private static func message(_ e: SubmitError) -> String {
        switch e {
        case .gone: return "This request link is no longer available."
        case .unauthorized: return "Token rejected. Mint a fresh one at /app/tokens."
        case .forbidden: return "Forbidden — your token may lack shares:write."
        case .rateLimited: return "Too many submissions. Try again shortly."
        case .planLimit: return "The owner's plan limit was reached."
        case .network(let m): return "Network error: \(m)"
        case .server(let s): return "Server error (\(s))."
        case .decoding(let m): return "Unexpected response: \(m)"
        }
    }
}
