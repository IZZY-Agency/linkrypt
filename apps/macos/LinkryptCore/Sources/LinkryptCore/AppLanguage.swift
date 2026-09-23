import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system, en, fr, uk

    /// BCP-47 code for link/email `lang`, clamped to `supported` (the server's
    /// served languages). Explicit choice honored only if supported; an
    /// unsupported explicit choice and `system` fall back to the best preferred
    /// match within `supported`, else the first supported, else `en`.
    public static func resolveCode(_ lang: AppLanguage,
                                   preferred: [String],
                                   supported: [String]) -> String {
        if lang != .system, supported.contains(lang.rawValue) { return lang.rawValue }
        for p in preferred {
            let base = String(p.prefix(2)).lowercased()
            if supported.contains(base) { return base }
        }
        return supported.first ?? "en"
    }
}
