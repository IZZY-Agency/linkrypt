import SwiftUI
import AppKit
import Observation
import LinkryptCore

// MARK: - HotkeyOverlay SwiftUI view

/// Floating heads-up card shown when ⌥⇧V is pressed.
/// Displays a clipboard preview, offers expiry/opens presets, a primary
/// "⏎ seal & copy link" button, and an Esc affordance to dismiss.
struct HotkeyOverlay: View {
    @State var vm: HotkeyOverlayViewModel
    var onConfirm: () async -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Header ────────────────────────────────────────────────────
            HStack {
                LKLock(size: 18)
                Text("SEAL & SHARE").font(LK.mono(11, weight: .bold)).tracking(2).foregroundStyle(LK.amber)
                Spacer()
                Text("⌥⇧V").font(LK.mono(9)).foregroundStyle(LK.fgDim)
            }

            // ── Clipboard preview ─────────────────────────────────────────
            LKPanel(label: "clipboard") {
                Text(vm.clipboardPreview)
                    .font(LK.mono(11))
                    .foregroundStyle(LK.fgBody)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // ── Presets ───────────────────────────────────────────────────
            HStack(spacing: 10) {
                Text("EXPIRES").font(LK.mono(9)).tracking(1.2).foregroundStyle(LK.fgMuted)
                Text(verbatim: "e").font(LK.mono(8)).foregroundStyle(LK.fgDim)
                ForEach(vm.expiries, id: \.self) { e in
                    presetButton(e, selected: vm.expiry == e) { vm.expiry = e }
                }
                Spacer()
                Text("OPENS").font(LK.mono(9)).tracking(1.2).foregroundStyle(LK.fgMuted)
                Text(verbatim: "o").font(LK.mono(8)).foregroundStyle(LK.fgDim)
                ForEach(vm.opens, id: \.self) { n in
                    presetButton("\(n)", selected: vm.maxOpens == n) { vm.maxOpens = n }
                }
            }

            // ── Status / result ───────────────────────────────────────────
            if let url = vm.resultURL {
                LKMonoField(value: url)
            } else if let err = vm.errorMessage {
                (Text(verbatim: "× ") + Text(LocalizedStringKey(err)))
                    .font(LK.mono(10)).foregroundStyle(LK.err).lineLimit(2)
            }

            // ── Actions ───────────────────────────────────────────────────
            HStack(spacing: 12) {
                if vm.state == .done {
                    LKButton(title: "✓ link copied", primary: true, action: onCancel)
                        .disabled(true)
                    if let deadline = vm.closeDeadline {
                        LKDrainBar(deadline: deadline,
                                   total: HotkeyOverlayViewModel.autoCloseSeconds)
                    }
                } else {
                    LKButton(title: "⏎ seal & copy link", primary: true, arrow: true) {
                        guard vm.state == .idle else { return }
                        HotkeyPanelController.beginMint(for: vm) { await onConfirm() }
                    }
                    .disabled(vm.state == .working || vm.rawClipboard.isEmpty)

                    LKButton(title: "esc  cancel", action: onCancel)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(LK.bg)
        .overlay(Rectangle().stroke(LK.border, lineWidth: 1))
    }

    @ViewBuilder
    private func presetButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(label))   // "24h" → fr "24 h", uk "24 год"; opens counts fall through verbatim
                .font(LK.mono(10))
                .foregroundStyle(selected ? LK.amber : LK.fgMuted)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Rectangle().stroke(selected ? LK.amber : LK.border, lineWidth: 1))
                .background(selected ? LK.amber.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Auto-close indicator

/// Draining auto-close bar shown beside "✓ link copied": a 10-cell block run
/// that empties over `total` seconds. Deliberately wordless — no digits, so
/// there is nothing to translate and the width never shifts as it counts.
private struct LKDrainBar: View {
    let deadline: Date
    let total: TimeInterval
    private static let cells = 10

    var body: some View {
        // Repaints 10×/s — enough for a 10-cell bar over 5s, far cheaper than
        // .animation, and it reads the clock rather than accumulating drift.
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let lit = Countdown.litCells(
                fraction: Countdown.remainingFraction(now: ctx.date, deadline: deadline, total: total),
                cells: Self.cells)
            HStack(spacing: 1) {
                ForEach(0..<Self.cells, id: \.self) { i in
                    Text(verbatim: i < lit ? "▓" : "░")
                        .foregroundStyle(i < lit ? LK.amber.opacity(0.55) : LK.border)
                }
            }
            .font(LK.mono(10))
        }
        .accessibilityHidden(true)   // decorative; the badge already says "link copied"
    }
}

// MARK: - ViewModel

enum HotkeyOverlayState { case idle, working, done, failed }

@MainActor
@Observable
final class HotkeyOverlayViewModel {
    var state: HotkeyOverlayState = .idle
    var expiry: String = "24h"
    var maxOpens: Int = 1
    /// Presets actually offered — `PresetCycle.*` filtered by the plan at
    /// present time, so `e`/`o` and the buttons agree and never pick a 402.
    var expiries: [String] = PresetCycle.expiries
    var opens: [Int] = PresetCycle.opens
    var resultURL: String?
    var errorMessage: String?
    /// When the panel should auto-close after a successful copy; nil until then.
    var closeDeadline: Date?

    /// How long the copied link stays on screen before the panel closes itself.
    static let autoCloseSeconds: TimeInterval = 5

    /// Raw clipboard text — used for the disabled-state guard.
    let rawClipboard: String
    /// Display string (shows placeholder when clipboard is empty).
    let clipboardPreview: String

    init() {
        let raw = NSPasteboard.general.string(forType: .string) ?? ""
        rawClipboard = raw
        clipboardPreview = raw.isEmpty ? "(clipboard is empty)" : raw
    }
}

// MARK: - Locale-observing root wrapper

/// Reads `Preferences` from the environment so that a language change while
/// the panel is open re-renders `HotkeyOverlay` with the updated locale.
private struct HotkeyRoot: View {
    @Environment(Preferences.self) private var prefs
    let vm: HotkeyOverlayViewModel
    let onConfirm: () async -> Void
    let onCancel: () -> Void
    var body: some View {
        HotkeyOverlay(vm: vm, onConfirm: onConfirm, onCancel: onCancel)
            .environment(\.locale, prefs.resolvedLocale)
    }
}

// MARK: - Keyable panel

/// Borderless panels don't become key by default, so keyboard events never
/// reach them. Override so Esc/Return work.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Panel controller (thin NSPanel wrapper)

/// Pure AppKit helper — creates and manages a borderless floating panel
/// hosting the HotkeyOverlay SwiftUI view. Retains itself until closed.
@MainActor
final class HotkeyPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let vm: HotkeyOverlayViewModel
    private var keyMonitor: Any?
    private var autoCloseTask: Task<Void, Never>?
    private var mintTask: Task<Void, Never>?

    private init(panel: NSPanel, vm: HotkeyOverlayViewModel) {
        self.panel = panel
        self.vm = vm
        super.init()
        panel.delegate = self
    }

    /// Runs a mint owned by this panel, so closing the panel cancels it.
    /// `AppLock.onLock` dismisses the panel; without this the in-flight mint
    /// would run to completion behind the lock screen and put a key-bearing
    /// URL on the pasteboard.
    static func beginMint(for vm: HotkeyOverlayViewModel, _ body: @escaping () async -> Void) {
        guard let c = live, c.vm === vm else { return }
        c.mintTask?.cancel()
        c.mintTask = Task { @MainActor in await body() }
    }

    /// Starts the auto-close countdown for `vm`, but only while the live panel
    /// is still the one that owns it. Pressing ⌥⇧V again mid-mint replaces the
    /// panel; the older confirm finishing must not close the newer panel.
    static func scheduleAutoClose(for vm: HotkeyOverlayViewModel) {
        guard let c = live, c.vm === vm else { return }
        c.autoCloseTask?.cancel()
        c.autoCloseTask = Task { @MainActor [weak c] in
            // Poll the wall clock rather than sleeping one fixed duration: the
            // bar subtracts `Date`s, so a mid-countdown clock jump would
            // otherwise leave the bar and the actual close disagreeing.
            while !Task.isCancelled {
                guard let c, HotkeyPanelController.live === c,
                      let deadline = c.vm.closeDeadline else { return }
                if Date() >= deadline { c.close(); return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // Sole owner of the live panel; @MainActor guarantees safe access.
    static var live: HotkeyPanelController?

    /// Closes any existing panel, creates a new one, and presents it.
    static func present(model: AppModel) {
        live?.close()
        live = nil

        let vm = HotkeyOverlayViewModel()
        // Offer only what the plan accepts, and start on the Settings › Sharing
        // defaults clamped into that set; `e`/`o` still cycle from there.
        vm.expiries = model.limits.filter(expiries: PresetCycle.expiries)
        vm.opens = model.limits.filter(opens: PresetCycle.opens)
        vm.expiry = model.limits.clamp(expiry: model.prefs.quickShareExpiry, candidates: PresetCycle.expiries)
        vm.maxOpens = model.limits.clamp(opens: model.prefs.quickShareMaxOpens, candidates: PresetCycle.opens)

        let onConfirm: () async -> Void = { [weak model] in
            guard let model else { return }
            // Limits may have loaded AFTER the panel opened (first ⌥⇧V right
            // after launch) — re-clamp now and show what is actually sent.
            vm.expiries = model.limits.filter(expiries: PresetCycle.expiries)
            vm.opens = model.limits.filter(opens: PresetCycle.opens)
            vm.expiry = model.limits.clamp(expiry: vm.expiry, candidates: PresetCycle.expiries)
            vm.maxOpens = model.limits.clamp(opens: vm.maxOpens, candidates: PresetCycle.opens)
            vm.state = .working
            let url = await model.quickShareClipboardWith(expiry: vm.expiry, maxOpens: vm.maxOpens,
                                                          text: vm.rawClipboard)
            if let url {
                vm.resultURL = url
                vm.state = .done
                vm.closeDeadline = Date().addingTimeInterval(HotkeyOverlayViewModel.autoCloseSeconds)
                HotkeyPanelController.scheduleAutoClose(for: vm)
            } else {
                vm.errorMessage = model.lastError ?? "Unknown error"
                vm.state = .failed
            }
        }

        let dismiss: () -> Void = { _ = HotkeyPanelController.live?.close() }

        let root = HotkeyRoot(vm: vm, onConfirm: onConfirm, onCancel: dismiss)
            .environment(model.prefs)
        let hostingView = NSHostingView(rootView: root)

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)

        let controller = HotkeyPanelController(panel: panel, vm: vm)
        live = controller

        // Esc → cancel, Return/Enter → confirm (only while this panel is key).
        controller.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard panel.isKeyWindow else { return event }
            switch event.keyCode {
            case 53: // esc
                dismiss(); return nil
            case 36, 76: // return / keypad enter
                if vm.state == .idle && !vm.rawClipboard.isEmpty {
                    HotkeyPanelController.beginMint(for: vm) { await onConfirm() }
                }
                return nil
            default:
                // `e` / `o` cycle the presets, but only while the panel is
                // still editable — after a mint the values are already baked in.
                guard vm.state == .idle else { return event }
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard mods.isDisjoint(with: [.command, .control, .option]) else { return event }
                // Match the character first (AZERTY etc.), then fall back to the
                // physical key so non-Latin layouts (uk) still cycle.
                let ch = event.charactersIgnoringModifiers?.lowercased()
                // Only fall back to the physical key on layouts that produce no
                // Latin letter (uk, ru, el). On a remapped Latin layout (Dvorak)
                // the character is authoritative, so an unrelated key is never
                // hijacked — and never swallowed.
                let latin = ch?.count == 1 && ch?.first?.isASCII == true && ch?.first?.isLetter == true
                if ch == "e" || (!latin && event.keyCode == 14) {
                    vm.expiry = PresetCycle.next(vm.expiry, in: vm.expiries)
                    return nil
                }
                if ch == "o" || (!latin && event.keyCode == 31) {
                    vm.maxOpens = PresetCycle.next(vm.maxOpens, in: vm.opens)
                    return nil
                }
                return event
            }
        }

        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Tear down any live panel (e.g. when the app locks — don't leave a
    /// share-minting panel open behind the lock screen).
    static func dismiss() { live?.close() }

    private func close() {
        autoCloseTask?.cancel(); autoCloseTask = nil
        mintTask?.cancel(); mintTask = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        panel.close()
        if HotkeyPanelController.live === self { HotkeyPanelController.live = nil }
    }

    func windowWillClose(_ notification: Notification) {
        autoCloseTask?.cancel(); autoCloseTask = nil
        mintTask?.cancel(); mintTask = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if HotkeyPanelController.live === self { HotkeyPanelController.live = nil }
    }
}
