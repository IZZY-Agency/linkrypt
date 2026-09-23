import AppKit
import LinkryptCore

/// Single entry point for all clipboard copies, with optional "burn after N
/// seconds". Records the pasteboard changeCount at copy time; a delayed task
/// clears it only if `ClipboardBurner.shouldClear` (nothing copied since).
/// Non-durable: if the app quits first, `sweepOnTerminate()` clears it if still
/// ours.
///
/// `prefs` is a launch-configured process global so EVERY copy affordance —
/// including ones outside the SwiftUI scene environment (the hotkey NSPanel) —
/// honors the burn setting without per-view plumbing.
@MainActor
enum Clipboard {
    private static var prefs: Preferences?
    private static var lastArmedChangeCount: Int?

    /// Call once at app launch (LinkryptApp.init).
    static func configure(prefs: Preferences) { self.prefs = prefs }

    static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard pb.setString(string, forType: .string) else { return } // arm only on success
        guard prefs?.burnClipboard == true else { lastArmedChangeCount = nil; return }
        let seconds = prefs?.burnClipboardSeconds ?? 60
        let token = pb.changeCount
        lastArmedChangeCount = token
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if ClipboardBurner.shouldClear(original: token, current: NSPasteboard.general.changeCount) {
                NSPasteboard.general.clearContents()
            }
        }
    }

    /// Best-effort clear if our last armed copy is still on the pasteboard.
    /// Call from applicationWillTerminate.
    static func sweepOnTerminate() {
        guard let token = lastArmedChangeCount else { return }
        if ClipboardBurner.shouldClear(original: token, current: NSPasteboard.general.changeCount) {
            NSPasteboard.general.clearContents()
        }
    }
}
