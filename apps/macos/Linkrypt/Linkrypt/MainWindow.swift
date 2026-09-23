import AppKit
import SwiftUI

/// Tracks the dashboard's NSWindow so "open the dashboard" actions target it
/// specifically. The app now has several ordinary windows (About, Settings),
/// so "first window that can become main" no longer identifies the dashboard.
@MainActor
enum MainWindow {
    private(set) weak static var live: NSWindow?

    /// Called by the main scene's chrome once its window exists.
    static func register(_ w: NSWindow) { live = w }

    /// Bring the dashboard forward, creating it if it was closed or suppressed
    /// at launch ("Launch hidden").
    static func open(_ openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        if let w = live, w.isVisible { w.makeKeyAndOrderFront(nil) } else { openWindow(id: "main") }
    }
}
