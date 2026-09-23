import Foundation

/// Whether a dropped file URL is shareable: a readable regular file, not a
/// directory/package, and not an indirection (Finder alias or symlink — share
/// the real file, not a pointer).
public enum DroppedFile {
    public static func isAcceptable(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard let v = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isReadableKey, .isSymbolicLinkKey, .isAliasFileKey,
        ]) else { return false }
        guard v.isRegularFile == true, v.isReadable == true else { return false }
        if v.isSymbolicLink == true || v.isAliasFile == true { return false }
        return true
    }
}
