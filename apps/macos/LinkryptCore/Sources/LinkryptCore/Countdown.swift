import Foundation

/// Geometry for the draining auto-close bar shown after the quick-share
/// overlay copies a link.
///
/// Pure so the clamping — past-deadline, backwards clock jump, zero total —
/// is unit-testable; the view only renders what these return.
public enum Countdown {
    /// How much of the window is left, as `0...1`.
    ///
    /// Clamped at both ends: the timeline keeps ticking past the deadline
    /// until the close actually lands, and a backwards clock jump (NTP sync,
    /// wake from sleep) must not report more than full.
    public static func remainingFraction(now: Date, deadline: Date, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        let remaining = deadline.timeIntervalSince(now)
        return min(1, max(0, remaining / total))
    }

    /// Lit cells in a `cells`-wide bar for a given remaining `fraction`.
    ///
    /// Rounds up so a sliver of time still shows one lit cell — the bar hits
    /// empty only when the countdown is genuinely done.
    public static func litCells(fraction: Double, cells: Int) -> Int {
        guard cells > 0, fraction > 0 else { return 0 }
        return min(cells, Int(ceil(min(1, fraction) * Double(cells))))
    }
}
