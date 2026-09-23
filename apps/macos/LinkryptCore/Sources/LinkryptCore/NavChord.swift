import Foundation

/// The dashboard sidebar's `g`-prefixed chords (`g s` shares, `g r` requests,
/// `g n` new share, …): a leader key that stays armed for `timeout`, then one
/// letter. Pure so arming / firing / cancelling / expiry are unit-tested
/// independently of the SwiftUI key-press plumbing.
public enum NavChord {
    public static let leader: Character = "g"
    /// How long the leader stays armed before a lone letter is a plain key again.
    public static let timeout: TimeInterval = 1.5

    /// Raw value = the letter shown in the sidebar hint. Must mirror
    /// `DashboardView`'s `navItem(…, hint: "g x")` entries.
    public enum Action: String, CaseIterable, Sendable, Equatable {
        case shares = "s", requests = "r"
        case newShare = "n", newRequest = "N"
        case openShare = "v", answerRequest = "p", inbox = "i"
        case auditLog = "a", apiTokens = "t"
    }

    public static func action(for key: Character) -> Action? { Action(rawValue: String(key)) }

    public enum Outcome: Equatable, Sendable {
        /// Leader pressed (or re-pressed): waiting for the letter.
        case armed
        case fired(Action)
        /// Armed, but the letter maps to nothing — swallowed, disarmed.
        case cancelled
        /// Not part of a chord; let the caller's normal key handling run.
        case ignored
    }

    public struct State: Sendable, Equatable {
        /// Monotonic seconds (`ProcessInfo.systemUptime`), not wall-clock: a
        /// clock adjustment must not stretch or shrink the arming window.
        private var armedAt: TimeInterval?
        public init() {}
        public var isArmed: Bool { armedAt != nil }

        public mutating func press(_ key: Character,
                                   at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Outcome {
            if let t = armedAt, time - t <= NavChord.timeout {
                if key == NavChord.leader { armedAt = time; return .armed }
                armedAt = nil
                if let a = NavChord.action(for: key) { return .fired(a) }
                return .cancelled
            }
            armedAt = nil   // expired or idle
            if key == NavChord.leader { armedAt = time; return .armed }
            return .ignored
        }

        /// Stand down. Called when a key the focused table consumed (`j/k/y/d/⏎`)
        /// never reached the chord handler — `g`, `j`, `s` must not move the
        /// selection and then switch workspace.
        public mutating func disarm() { armedAt = nil }
    }
}
