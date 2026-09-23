import Foundation

/// Selection movement for the dashboard `j`/`k` keyboard model. Pure so the
/// SwiftUI view can stay declarative. Selection is tracked by share id (not
/// index) so it survives list reordering across `refresh()`.
///
/// Rules: clamp at the ends (no wrap), an empty list has no selection, and a
/// stale/absent selection re-anchors to the nearest sensible end (`next` →
/// first, `previous` → last) so the keys always do something useful.
public enum DashboardNav {

    /// Selection after pressing `j` (move down).
    public static func next(after id: String?, in ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let id, let i = ids.firstIndex(of: id) else { return ids.first }
        return ids[min(i + 1, ids.count - 1)]
    }

    /// Selection after pressing `k` (move up).
    public static func previous(before id: String?, in ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let id, let i = ids.firstIndex(of: id) else { return ids.last }
        return ids[max(i - 1, 0)]
    }

    /// The selection restricted to `ids` (the currently visible rows) — nil if
    /// the id is absent because it was filtered out or removed after a refresh.
    /// Callers gate actions on this so a stale selection can never act on an
    /// off-screen row (e.g. silently revoke a share you can't see).
    public static func resolve(_ id: String?, in ids: [String]) -> String? {
        guard let id, ids.contains(id) else { return nil }
        return id
    }
}
