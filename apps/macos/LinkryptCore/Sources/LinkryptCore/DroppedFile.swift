import Foundation

/// Whether a dropped file URL is shareable: a readable regular file, not a
/// directory/package, and not an indirection (Finder alias or symlink — share
/// the real file, not a pointer).
public enum DroppedFile {
    /// Why a dropped URL cannot be shared.
    public enum Rejection: Equatable {
        /// A directory or package.
        case folder
        /// A symlink, alias, unreadable item or non-file URL.
        case unsupported
    }

    /// `nil` when the URL is shareable (see `isAcceptable`).
    public static func rejectionReason(_ url: URL) -> Rejection? {
        guard url.isFileURL else { return .unsupported }
        guard let v = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isDirectoryKey, .isReadableKey, .isSymbolicLinkKey, .isAliasFileKey,
        ]) else { return .unsupported }
        if v.isDirectory == true { return .folder }
        guard v.isRegularFile == true, v.isReadable == true else { return .unsupported }
        if v.isSymbolicLink == true || v.isAliasFile == true { return .unsupported }
        return nil
    }

    public static func isAcceptable(_ url: URL) -> Bool {
        rejectionReason(url) == nil
    }
}
