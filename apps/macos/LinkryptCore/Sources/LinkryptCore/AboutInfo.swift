import Foundation

/// Version / build / copyright for the About window, read from the bundle's
/// Info.plist — the same keys Finder "Get Info" and the stock About panel use,
/// so there is one source of truth (`project.yml` + `Info.partial.plist`).
/// A missing or blank key yields `nil`; nothing is fabricated.
public struct AboutInfo: Sendable, Equatable {
    public let version: String?     // CFBundleShortVersionString
    public let build: String?       // CFBundleVersion
    public let copyright: String?   // NSHumanReadableCopyright

    public init(bundleInfo: [String: Any]) {
        func str(_ key: String) -> String? {
            guard let v = bundleInfo[key] as? String else { return nil }
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        version = str("CFBundleShortVersionString")
        build = str("CFBundleVersion")
        copyright = str("NSHumanReadableCopyright")
    }

    /// "0.1.0 (1)"; just "0.1.0" when the build is absent or repeats the
    /// version; `nil` when there is no version at all.
    public var versionLine: String? {
        guard let version else { return nil }
        guard let build, build != version else { return version }
        return "\(version) (\(build))"
    }
}
