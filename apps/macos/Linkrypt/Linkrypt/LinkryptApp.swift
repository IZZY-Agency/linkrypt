import SwiftUI
import AppKit
import LinkryptCore

@main
struct LinkryptApp: App {
    // Hold a strong reference so the hotkey handler can capture it safely.
    private let sharedModel: AppModel
    @State private var model: AppModel
    @State private var prefs: Preferences
    @State private var lock: AppLock
    @State private var loginItem: LoginItemController
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let p = Preferences()
        let m = AppModel(prefs: p)
        let lk = AppLock(prefs: p)
        m.lock = lk
        lk.onLock = { HotkeyPanelController.dismiss() }   // don't leave a mint panel behind the lock
        sharedModel = m
        _model = State(wrappedValue: m)
        _prefs = State(wrappedValue: p)
        let li = LoginItemController()
        _lock = State(wrappedValue: lk)
        _loginItem = State(wrappedValue: li)
        Clipboard.configure(prefs: p)
        lk.lockIfEnabled(hasSession: m.route == .dashboard)   // lock on launch

        // Capture `m` directly (it's a class — same instance); hop to
        // @MainActor because AppModel is @MainActor-isolated. Registration is
        // owned by HotkeyRegistration so Settings can toggle it at runtime.
        HotkeyRegistration.configure {
            Task { @MainActor in m.fireHotkey() }
        }
        HotkeyRegistration.setEnabled(p.globalHotkeyEnabled)

        let nc = NotificationCenter.default
        // "Show in Dock" → activation policy. Applied once the app object is
        // fully up (NSApp isn't reliable inside App.init).
        nc.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DockIcon.apply(show: p.showInDock, activate: false) }
        }
        // A login-item approval/removal made in System Settings while we were
        // in the background must show up when the user comes back.
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { li.refresh() }
        }
        // Best-effort clipboard burn on quit (the in-process delayed burn can't
        // run once the app has exited).
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Clipboard.sweepOnTerminate() }
        }
        // Auto-lock lifecycle: hide content on deactivation, evaluate auto-reveal
        // on return (deactivation + grace).
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { lk.onResignActive(hasSession: m.route == .dashboard) }
        }
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { lk.onBecomeActive() }
        }
        // Screen sleep / fast-user-switch are HARD security boundaries: lock and
        // kill any in-flight Touch ID prompt (the auth dialog's own resign must
        // NOT do this — that's why it routes to onSecurityResign, not onResignActive).
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { lk.onSecurityResign(hasSession: m.route == .dashboard) }
        }
        wsnc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { lk.onSecurityResign(hasSession: m.route == .dashboard) }
        }
        wsnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { lk.onBecomeActive() }
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            // Lock is an OVERLAY (LockGate), not a branch: RootView and every
            // sheet / draft under it stay alive across deactivation + Touch ID.
            RootView().lockGated()
                .environment(model).environment(prefs).environment(lock)
            .frame(minWidth: 1000, minHeight: 640)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LK.bg)
            .background(WindowChrome(isMain: true))   // black window + dark titlebar; registers MainWindow
            .preferredColorScheme(.dark)
            .environment(\.locale, prefs.resolvedLocale)
            .task {
                // Wire dock-drop delivery once the model is live; flushes any
                // file dropped during cold launch.
                appDelegate.dropBuffer.onReady { [model] urls in
                    model.receiveDroppedFile(urls.first)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)                 // immersive: content under the titlebar
        .windowResizability(.contentMinSize)
        // "Launch hidden": menu-bar item only at startup. Both modifiers are
        // needed — restoration would otherwise bring the window back on its own.
        .defaultLaunchBehavior(prefs.launchHidden ? .suppressed : .automatic)
        .restorationBehavior(prefs.launchHidden ? .disabled : .automatic)
        .commands {
            // Replace the stock About panel with the branded window.
            CommandGroup(replacing: .appInfo) { AboutMenuItem() }
            // ⌘N means "new share", not "new dashboard window" (the stock
            // WindowGroup item opened a second main window).
            CommandGroup(replacing: .newItem) { NewShareMenuItem(model: sharedModel, lock: lock) }
        }

        Window("About Linkrypt", id: "about") {
            AboutView()
                .environment(prefs)
                .background(LK.bg)
                .background(WindowChrome())
                .preferredColorScheme(.dark)
                .environment(\.locale, prefs.resolvedLocale)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MenuBarView().environment(model).environment(prefs).environment(lock)
                .environment(\.locale, prefs.resolvedLocale)
        } label: {
            Image(nsImage: .linkryptMenuBar)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(prefs)
                .environment(loginItem)
                .environment(lock)
                .preferredColorScheme(.dark)
                .environment(\.locale, prefs.resolvedLocale)
        }
    }
}

/// App-menu "About Linkrypt" → the custom About window. A View so it can read
/// File › New share (⌘N): bring the dashboard forward (creating it if it was
/// closed / launched hidden) and hand it a "new share" request.
struct NewShareMenuItem: View {
    let model: AppModel
    let lock: AppLock
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("New share") {
            MainWindow.open(openWindow)
            model.requestNewShare()
        }
        .keyboardShortcut("n", modifiers: .command)
        .disabled(model.route != .dashboard || lock.isLocked)
    }
}

/// `openWindow` from the environment (commands can't take it directly).
private struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("About Linkrypt") { openWindow(id: "about") }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Group {
            switch model.route {
            case .login: LoginView()
            case .dashboard: DashboardView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LK.bg)
    }
}

/// Paints the underlying NSWindow black and forces a dark titlebar so the
/// whole window reads as one navy surface (no light-gray surround).
/// Styling runs in `viewDidMoveToWindow`, so it re-applies if the window is
/// closed and reopened.
private struct WindowChrome: NSViewRepresentable {
    var isMain = false
    func makeNSView(context: Context) -> NSView { ChromeView(isMain: isMain) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ChromeView: NSView {
        let isMain: Bool
        init(isMain: Bool) { self.isMain = isMain; super.init(frame: .zero) }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            if isMain { MainWindow.register(w) }
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(LK.bg)
            w.isOpaque = true
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
        }
    }
}
