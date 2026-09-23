import AppKit
import LinkryptCore

/// Funnels file-open events (dock drop, Finder "Open With", drag-to-app) through
/// a DropBuffer so a cold-launch drop isn't lost before the scene is wired.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dropBuffer = DropBuffer()
    func application(_ application: NSApplication, open urls: [URL]) {
        dropBuffer.receive(urls)
    }
}
