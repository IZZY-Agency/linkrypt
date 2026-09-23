import Foundation

/// Decision core for "burn clipboard after N seconds": only clear if nothing
/// else was copied since. `NSPasteboard.changeCount` increments on every write
/// (including re-copying the same string), so a stale burn no-ops and only the
/// newest copy's burn can clear. The NSPasteboard + scheduling glue lives in the
/// app's `Clipboard`.
public enum ClipboardBurner {
    public static func shouldClear(original: Int, current: Int) -> Bool {
        original == current
    }
}
