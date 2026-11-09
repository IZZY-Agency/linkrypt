import Foundation

/// Binary (1024-based) sizes for display, matching the web client and the plan
/// pages: "512 B", "5 MB", "5.2 MB", "1.1 GB". The value is kept to one
/// decimal place; callers drop a trailing ".0" and localize the number and unit.
public enum ByteSize {
    public enum Unit: Equatable, Sendable { case bytes, kilobytes, megabytes, gigabytes }

    public struct Scaled: Equatable, Sendable {
        /// The value in `unit`, times ten (52 megabytes = 5.2 MB).
        public let tenths: Int
        public let unit: Unit
        public init(tenths: Int, unit: Unit) { self.tenths = tenths; self.unit = unit }
    }

    /// `bytes` in the largest unit (up to GB) whose value stays below 1024,
    /// rounded to one decimal. `roundingUp` rounds up instead of to nearest,
    /// so a size just over a limit never displays as the limit itself.
    public static func tenths(_ bytes: Int, roundingUp: Bool = false) -> Scaled {
        let n = max(0, bytes)
        if n < 1024 { return Scaled(tenths: n * 10, unit: .bytes) }
        let units: [Unit] = [.kilobytes, .megabytes, .gigabytes]
        var divisor = 1024
        for (i, unit) in units.enumerated() {
            // Integer arithmetic: whole part times ten, plus the rounded tenth.
            let whole = n / divisor, rest = n % divisor
            let tenth = roundingUp ? (rest * 10 + divisor - 1) / divisor : (rest * 10 + divisor / 2) / divisor
            let value = whole * 10 + tenth
            if value < 10240 || i == units.count - 1 { return Scaled(tenths: value, unit: unit) }
            divisor *= 1024
        }
        preconditionFailure("unreachable: the last unit always returns")
    }
}
