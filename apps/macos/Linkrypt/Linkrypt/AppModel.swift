import SwiftUI
import LinkryptCore
import AppKit

/// One place that turns a failed `APIClient.revoke` into user-facing text.
/// Shared by the dashboard (`d` key + detail sheet) and the composer sheet.
/// Returns `LocalizedStringKey`s: the interpolations become `%@` / `%lld`
/// placeholders, so the templates are real catalog keys (fr/uk) and only
/// the dynamic server text stays verbatim.
enum RevokeFailure {
    /// nil on success, else the message to show.
    @MainActor
    static func perform(client: APIClient?, id: String) async -> LocalizedStringKey? {
        guard let client else { return "Not authenticated." }
        do { try await client.revoke(id: id); return nil }
        catch APIError.forbidden(let m) {
            // 403 covers "not the owner" and server-side gates too — don't
            // assert a scope problem; show what the server said.
            return "Revoke failed — the server refused (403: \(m)). If your token lacks the shares:revoke scope, mint a new one at /app/tokens."
        }
        catch APIError.insufficientScope(let missing) {
            return "Revoke failed — token is missing scope(s): \(missing.joined(separator: ", ")). Mint a token with revoke permission at /app/tokens."
        }
        catch APIError.unauthorized { return "Revoke failed — token rejected (401). Sign in again." }
        catch APIError.server(let status, let m) { return "Revoke failed — server error \(status): \(m)" }
        catch { return "Revoke failed: \(String(describing: error))" }
    }
}

@MainActor
@Observable
final class AppModel {
    enum Route { case login, dashboard }
    var route: Route = .login
    var baseURL: String = defaultBaseURL
    var who: WhoAmI?
    /// Effective plan limits from whoami (admin → internal). nil until loaded
    /// or on an older server — treated as unrestricted by the option filters.
    var limits: PlanLimits? { who?.limits }
    var shares: [ShareRow] = []
    var requests: [RequestRow] = []
    var lastError: String?
    var pendingDroppedFile: URL?     // a file dropped on the dock, awaiting the composer
    /// ⌘N (File › New share) pressed; the dashboard consumes it and opens the
    /// composer once it is idle. Same hand-off shape as `pendingDroppedFile`.
    var pendingNewShare = false

    static let defaultBaseURL = "https://linkrypt.sh"

    let tokenStore: any TokenStore
    let prefs: Preferences
    let linkCache: LinkCache
    weak var lock: AppLock?
    private(set) var client: APIClient?
    private(set) var inboxClient: InboxClient?
    private(set) var submitClient: SubmitClient?
    private var refreshGen = 0   // drops stale overlapping refreshes (see refresh())

    init(tokenStore: any TokenStore = KeychainTokenStore(), prefs: Preferences) {
        self.tokenStore = tokenStore
        self.prefs = prefs
        self.linkCache = LinkCache(persistent: prefs.persistLinks)
        if let token = tokenStore.read(account: AppModel.defaultBaseURL) {
            self.client = APIClient(baseURL: AppModel.defaultBaseURL, token: token)
            self.inboxClient = InboxClient(baseURL: AppModel.defaultBaseURL, token: token)
            self.submitClient = SubmitClient(baseURL: AppModel.defaultBaseURL, token: token)
            self.route = .dashboard
        }
    }

    func login(token: String) async {
        let c = APIClient(baseURL: baseURL, token: token)
        do {
            let who = try await c.login(requiring: ["shares:write", "shares:read"])
            try tokenStore.save(token: token, account: baseURL)
            self.client = c; self.inboxClient = InboxClient(baseURL: baseURL, token: token); self.submitClient = SubmitClient(baseURL: baseURL, token: token); self.who = who; self.route = .dashboard; self.lastError = nil
            await refresh()
        } catch APIError.insufficientScope(let missing) {
            lastError = "Token is missing scopes: \(missing.joined(separator: ", "))"
        } catch APIError.unauthorized {
            lastError = "Token rejected. Mint a fresh one at /app/tokens."
        } catch { lastError = "\(error)" }
    }

    func logout() {
        try? tokenStore.delete(account: baseURL)
        linkCache.clear()
        // Invalidate any in-flight refresh so a suspended list/whoami fetch from
        // the previous session can't publish into the next one (account switch).
        refreshGen &+= 1
        client = nil; inboxClient = nil; submitClient = nil; who = nil; shares = []; requests = []; route = .login
    }

    /// A file was dropped on the dock / opened via Finder. Stash it (if a real
    /// readable file) for the dashboard to open in the composer. Keep-first
    /// policy: while one drop is still pending (e.g. held behind another sheet),
    /// ignore later drops rather than silently overwrite the first — one share
    /// at a time.
    func receiveDroppedFile(_ url: URL?) {
        guard pendingDroppedFile == nil else { return }
        guard let url, DroppedFile.isAcceptable(url) else { return }
        pendingDroppedFile = url
    }

    func refresh() async {
        guard let c = client else { return }
        // Load lists concurrently; each best-effort so one failure doesn't blank
        // the other. Generation-tag the refresh so an older overlapping run can't
        // overwrite newer rows (actor reentrancy at the awaits).
        refreshGen &+= 1
        let gen = refreshGen
        async let s = c.listShares()
        async let r = c.listRequests()
        do { let v = try await s; if gen == refreshGen { shares = v } }
        catch { if gen == refreshGen { lastError = "\(error)" } }
        do { let v = try await r; if gen == refreshGen { requests = v } }
        catch { if gen == refreshGen { lastError = "\(error)" } }
        // Refresh account identity + plan limits (footer shows email; the
        // composer / ⌥⇧V / Settings filter their options by `limits`, so a plan
        // change must land on the next refresh, not the next relaunch).
        // Sequential and last so it can never delay the lists. The guards are
        // re-checked AFTER the await (actor reentrancy): drop the result if a
        // newer refresh superseded us (`gen`) or if the client was swapped by a
        // logout / account switch while we were suspended (`client === c`) —
        // never publish a stale account's email.
        if let v = try? await c.whoami(), gen == refreshGen, client === c { who = v }
    }

    /// Reads the current clipboard text, encrypts it, stores the link, and
    /// copies the resulting URL back to the clipboard. Returns the recipient URL
    /// on success (already copied to pasteboard), nil on failure (sets `lastError`).
    /// Uses the Settings › Sharing defaults (same ones the ⌥⇧V overlay starts on).
    @discardableResult
    func quickShareClipboard() async -> String? {
        // The stored defaults may predate a plan change (e.g. "1h" on Free) —
        // clamp to what the plan accepts so the menu-bar path can't 402.
        return await quickShareClipboardWith(
            expiry: limits.clamp(expiry: prefs.quickShareExpiry, candidates: PresetCycle.expiries),
            maxOpens: limits.clamp(opens: prefs.quickShareMaxOpens, candidates: PresetCycle.opens))
    }

    /// Same as `quickShareClipboard()` but with caller-supplied settings.
    /// `maxOpens` must be ≥ 1; the server rejects 0.  Returns recipient URL on success, nil on failure.
    ///
    /// `text` is the exact plaintext to seal. Callers that showed the user a
    /// preview MUST pass the snapshot they displayed — re-reading the pasteboard
    /// here would seal whatever was copied since (including this flow's own
    /// result URL), i.e. content the user never reviewed. Pass nil only from
    /// paths with no preview (the menu-bar item).
    func quickShareClipboardWith(expiry: String, maxOpens: Int, text: String? = nil) async -> String? {
        if lock?.isLocked == true { lastError = "Locked — unlock the app first."; return nil }
        guard let text = text ?? NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            lastError = "Clipboard is empty — copy some text first."
            return nil
        }
        // Preflight the same plaintext cap the composer enforces: a larger
        // payload would pad into a bigger bucket and be rejected at finalize
        // ("payload too large") with no recovery on this fire-and-forget path.
        guard Crypto.textPlaintextFitsCap(text.utf8.count) else {
            lastError = "Clipboard text is too large (1 MiB max). Use a file share instead."
            return nil
        }
        guard let client else {
            lastError = "Not authenticated."
            return nil
        }
        let safeOpens = max(1, maxOpens)
        let key = Crypto.randomBytes(32), iv = Crypto.randomBytes(12)
        do {
            let ct = try Crypto.sealPaddedV1(key: key, iv: iv, plaintext: Data(text.utf8))
            let req = CreateShareRequest(
                type: .text, size: ct.count, rawSize: text.utf8.count,
                expiresIn: expiry, maxOpens: safeOpens, label: "clipboard", filename: nil,
                recipientEmail: nil, notifyOnOpen: false,
                passphraseSalt: nil, passphraseHash: nil, passphraseKdf: nil,
                paddingVersion: .v1
            )
            let resp = try await client.createShare(req)
            try await client.finalizeText(id: resp.id, ciphertext: ct)
            let url = ShareLink.recipientURL(baseURL: baseURL, lang: prefs.languageCode, id: resp.id, key: key, iv: iv)
            linkCache.store(id: resp.id, url: url)
            // The lock check above only covers the moment before the first
            // await. Auto-lock / screen sleep / fast-user-switch can land while
            // the network calls are suspended, so re-check before putting a
            // key-bearing URL on the pasteboard — that would survive the lock.
            // The share itself is kept (cached, and listed in the dashboard).
            if lock?.isLocked == true {
                lastError = "Locked mid-share — the link is in your dashboard, not the clipboard."
                return nil
            }
            Clipboard.copy(url)
            await refresh()
            return url
        } catch {
            lastError = "\(error)"
            return nil
        }
    }

    /// Shows the HotkeyOverlay panel. Called when ⌥⇧V is pressed.
    /// Panel lifetime is owned entirely by `HotkeyPanelController.live`.
    /// File › New share (⌘N). No-op while locked or logged out — the menu
    /// item is disabled then too; this is the belt to that braces.
    func requestNewShare() {
        guard route == .dashboard, lock?.isLocked != true else { return }
        pendingNewShare = true
    }

    func fireHotkey() {
        if lock?.isLocked == true { return }   // don't mint shares while locked
        HotkeyPanelController.present(model: self)
    }
}
