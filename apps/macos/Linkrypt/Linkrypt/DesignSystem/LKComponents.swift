import SwiftUI
import AppKit

/// Bordered box with a floating uppercase amber label (the load-bearing primitive).
struct LKPanel<Content: View>: View {
    var label: LocalizedStringKey? = nil
    var focused = false
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LK.bgElev)
            .overlay(Rectangle().stroke(focused ? LK.amber : LK.border, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if let label {
                    Text(label).textCase(.uppercase)
                        .font(LK.mono(9)).tracking(1.5).foregroundStyle(LK.amber)
                        .padding(.horizontal, 8).background(LK.bg)
                        .offset(x: 14, y: -7)
                }
            }
    }
}

/// Bracketed button — Linkrypt signature `[ label ]`.
struct LKButton: View {
    let title: LocalizedStringKey
    let verbatimTitle: String?
    var primary = false
    var arrow = false
    var disabledLook = false
    var action: () -> Void
    init(title: LocalizedStringKey, primary: Bool = false, arrow: Bool = false,
         disabledLook: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.verbatimTitle = nil
        self.primary = primary; self.arrow = arrow; self.disabledLook = disabledLook; self.action = action
    }
    init(verbatim: String, primary: Bool = false, arrow: Bool = false,
         disabledLook: Bool = false, action: @escaping () -> Void) {
        self.title = ""; self.verbatimTitle = verbatim
        self.primary = primary; self.arrow = arrow; self.disabledLook = disabledLook; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("[").foregroundStyle(LK.borderHi)
                Group { if let v = verbatimTitle { Text(verbatim: v) } else { Text(title) } }
                    .foregroundStyle(primary ? LK.amber : LK.fgMuted)
                    .textCase(primary ? .uppercase : nil)
                if arrow { Text("→").foregroundStyle(primary ? LK.amber : LK.fgMuted) }
                Text("]").foregroundStyle(LK.borderHi)
            }
            .font(LK.mono(primary ? 12.5 : 12, weight: primary ? .bold : .regular))
            .tracking(primary ? 1 : 0.4).opacity(disabledLook ? 0.5 : 1).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Squared, status-keyed pill.
struct LKPill: View {
    let kind: String   // active|opened|burned|expired|revoked|pending|new|submitted
    var body: some View {
        let c = color(for: kind)
        Text(LocalizedStringKey(kind)).textCase(.uppercase)
            .font(LK.mono(10)).tracking(1.2).foregroundStyle(c)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(c, lineWidth: 1))
            .background(c.opacity(0.06))
    }
    func color(for k: String) -> Color {
        switch k {
        case "active", "new", "submitted": return LK.ok
        case "opened", "pending": return LK.amber
        case "burned": return LK.burn
        case "revoked": return LK.err
        default: return LK.fgDim   // includes request "expired"
        }
    }
}

/// Read-only mono value with a copy affordance.
struct LKMonoField: View {
    let value: String
    @State private var copied = false
    var body: some View {
        HStack(spacing: 10) {
            Text(value).font(LK.mono(11)).foregroundStyle(LK.fg)
                .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            Spacer()
            Button { copyToPasteboard(value); copied = true } label: {
                Text(copied ? "✓ COPIED" : "⧉ COPY")
                    .font(LK.mono(10)).tracking(0.8)
                    .foregroundStyle(copied ? LK.ok : LK.amber)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(12).background(LK.bg)
        .overlay(Rectangle().stroke(LK.border, lineWidth: 1))
    }
}

/// All copies route through `Clipboard` so the burn-clipboard setting applies
/// to every affordance (mono fields, menu bar, dashboard, hotkey result).
@MainActor func copyToPasteboard(_ s: String) {
    Clipboard.copy(s)
}

/// Box-drawn padlock (no SF Symbol).
struct LKLock: View {
    var size: CGFloat = 22
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: size * 0.27)
                .stroke(lineWidth: max(1.4, size * 0.07))
                .frame(width: size * 0.55, height: size * 0.45)
                .offset(y: size * 0.07)
            Rectangle().frame(width: size * 0.9, height: size * 0.55)
                .cornerRadius(size * 0.06)
        }.frame(width: size, height: size).foregroundStyle(LK.amber)
    }
}

// MARK: - Form controls (custom, replacing native pickers/toggles)

/// Terminal-style tab/segmented row. Active = amber fill, bg text.
/// The number badge is a live key equivalent for the window: `1`…`9` by
/// default; pass `shortcutModifiers: .command` in windows that have text
/// inputs (typing a digit must not switch tabs) — the badge then reads `⌘1`.
struct LKSegmented<T: Hashable>: View {
    @Binding var selection: T
    let items: [(value: T, label: LocalizedStringKey)]
    var shortcutModifiers: EventModifiers = []
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                let active = item.value == selection
                let digit = Character("\(idx + 1)")
                Button { selection = item.value } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: (shortcutModifiers.contains(.command) ? "⌘" : "") + String(digit))
                            .font(LK.mono(9))
                            .foregroundStyle(active ? LK.bg.opacity(0.7) : LK.amber)
                        Text(item.label).font(LK.mono(11))
                    }
                    .foregroundStyle(active ? LK.bg : LK.fgMuted)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(active ? LK.amber : Color.clear)
                    .overlay(Rectangle().stroke(active ? LK.amber : LK.border, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(idx < 9 ? KeyboardShortcut(KeyEquivalent(digit), modifiers: shortcutModifiers) : nil)
            }
        }
    }
}

/// Amber switch matching the design's toggle. Whole row is the hit target.
struct LKToggle: View {
    @Binding var isOn: Bool
    let title: LocalizedStringKey
    var hint: LocalizedStringKey? = nil
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 12) {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isOn ? LK.amber.opacity(0.12) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(isOn ? LK.amber : LK.borderHi, lineWidth: 1))
                        .frame(width: 30, height: 18)
                    Rectangle()
                        .fill(isOn ? LK.amber : LK.fgDim)
                        .frame(width: 12, height: 14)
                        .padding(.horizontal, 2)
                }
                .frame(width: 30, height: 18)
                .animation(.easeOut(duration: 0.12), value: isOn)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(LK.sans(13)).foregroundStyle(LK.fg)
                    if let hint { Text(hint).font(LK.mono(10)).foregroundStyle(LK.fgMuted) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(LK.bgElev)
            .overlay(Rectangle().stroke(LK.borderSoft, lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Mono dropdown styled as `value ▾`. Wraps a native Menu (popup is system-drawn).
struct LKDropdown<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: LocalizedStringKey)]
    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                Button { selection = opt.value } label: { Text(opt.label) }
            }
        } label: {
            Text(options.first { $0.value == selection }?.label ?? "")
                .font(LK.mono(13)).foregroundStyle(LK.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)        // the SYSTEM disclosure chevron → reads as a dropdown
        .tint(LK.amber)                 // chevron in the app's accent
        // Box on the Menu CONTAINER, not the label — `.borderlessButton` strips
        // background/border off label content (the field rendered as plain text).
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(LK.surface2)
        .overlay(Rectangle().stroke(LK.borderHi, lineWidth: 1))
    }
}

// MARK: - Menu-bar icon (Morse-L brand mark · − · ·)

extension NSImage {
    /// The Linkrypt menu-bar mark: Morse code for "L" (· − · ·), drawn as
    /// rounded bars. Template image so macOS tints it for light/dark menu bars.
    static let linkryptMenuBar: NSImage = {
        let height: CGFloat = 15
        let barH: CGFloat = 3
        let widths: [CGFloat] = [3, 9, 3, 3]   // dot, dash, dot, dot
        let gap: CGFloat = 3
        let width = widths.reduce(0, +) + gap * CGFloat(widths.count - 1)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            NSColor.black.setFill()
            let y = (height - barH) / 2
            var x: CGFloat = 0
            for w in widths {
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: barH),
                             xRadius: barH / 2, yRadius: barH / 2).fill()
                x += w + gap
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
