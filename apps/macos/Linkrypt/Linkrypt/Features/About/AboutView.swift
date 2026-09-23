import SwiftUI
import AppKit
import LinkryptCore

/// Branded About window (replaces the stock panel via the app menu, and is
/// reachable from the menu-bar popover and the dashboard sidebar).
/// Version / build / copyright are read from the bundle (`AboutInfo`); the
/// links and acknowledgements are facts about this build (README, Package.swift).
struct AboutView: View {
    @Environment(Preferences.self) private var prefs
    private let info = AboutInfo(bundleInfo: Bundle.main.infoDictionary ?? [:])
    private let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Color.clear.frame(height: 4)   // clear the (hidden) titlebar drag strip
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(verbatim: "▸").foregroundStyle(LK.amber)
                        Text(verbatim: "linkrypt").foregroundStyle(LK.fg)
                    }.font(LK.mono(20, weight: .bold))
                    Text("End-to-end encrypted sharing. By the link.")
                        .font(LK.sans(12)).foregroundStyle(LK.fgMuted)
                }
            }

            LKPanel(label: "build", padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    if let v = info.versionLine {
                        row("version", Text(verbatim: v))
                    } else {
                        row("version", Text("unavailable"), color: LK.err)
                    }
                    row("macOS", Text(verbatim: osVersion))
                    if let c = info.copyright { row("copyright", Text(verbatim: c)) }
                    HStack {
                        Spacer()
                        Button { copyToPasteboard(buildSummary); copied = true } label: {
                            Text(copied ? "✓ COPIED" : "⧉ COPY BUILD INFO")
                                .font(LK.mono(10)).tracking(0.8)
                                .foregroundStyle(copied ? LK.ok : LK.amber)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }

            LKPanel(label: "links", padding: 14) {
                HStack(spacing: 18) {
                    link("linkrypt.sh", AppModel.defaultBaseURL)
                    link("Privacy", "\(AppModel.defaultBaseURL)/\(prefs.languageCode)/privacy")
                    link("Terms", "\(AppModel.defaultBaseURL)/\(prefs.languageCode)/terms")
                }
            }

            LKPanel(label: "acknowledgements", padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ack("JetBrains Mono", "SIL Open Font License 1.1", "https://github.com/JetBrains/JetBrainsMono")
                    ack("Argon2Swift", "Argon2 reference implementation (PHC)", "https://github.com/tmthecoder/Argon2Swift")
                }
            }
        }
        .padding(20).frame(width: 440).background(LK.bg)
    }

    private var buildSummary: String {
        var parts = ["linkrypt"]
        if let v = info.versionLine { parts.append(v) }
        parts.append("macOS \(osVersion)")
        return parts.joined(separator: " · ")
    }

    private func row(_ key: LocalizedStringKey, _ value: Text, color: Color = LK.fg) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key).textCase(.uppercase)
                .font(LK.mono(9)).tracking(1.2).foregroundStyle(LK.fgMuted)
                .frame(width: 80, alignment: .leading)
            value.font(LK.mono(11)).foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func link(_ label: LocalizedStringKey, _ url: String) -> some View {
        Button { open(url) } label: {
            Text(label).font(LK.mono(11)).foregroundStyle(LK.amber).underline()
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(Text(verbatim: url))
    }

    private func ack(_ name: String, _ license: LocalizedStringKey, _ url: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button { open(url) } label: {
                Text(verbatim: name).font(LK.mono(11)).foregroundStyle(LK.amber).underline()
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).help(Text(verbatim: url))
            Text(license).font(LK.mono(10)).foregroundStyle(LK.fgMuted)
        }
    }

    private func open(_ s: String) {
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
}
