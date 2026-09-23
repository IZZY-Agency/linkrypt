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

    /// The app is open source; these are the public repository's pages.
    public static let repositoryURL = "https://github.com/IZZY-Agency/linkrypt"
    public static let licenseURL = "\(repositoryURL)/blob/main/LICENSE"
    public static let securityReportURL = "\(repositoryURL)/security/advisories/new"

    /// The GitHub release of exactly this version (tag `macos-v<version>`), or
    /// the list of releases when the bundle has no version.
    public var releaseNotesURL: String {
        guard let version else { return "\(Self.repositoryURL)/releases" }
        return "\(Self.repositoryURL)/releases/tag/macos-v\(version)"
    }
}
