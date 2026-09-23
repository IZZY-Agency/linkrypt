import Foundation

/// Pure gate that decides whether the app should **auto-present** the Touch ID
/// prompt. After a cancel/fail it becomes `suppressed` so we don't re-prompt in
/// a loop; a genuine return (`onAppResign` re-arm) or a manual unlock attempt
/// re-arms it.
public struct AuthPromptGate: Equatable {
    public private(set) var suppressed = false
    public init() {}

    /// Cancel/fail → stop auto-prompting (user must manually retry).
    public mutating func onAuthDismissed() { suppressed = true }

    /// Genuine return OR manual attempt → allow auto-prompting again.
    public mutating func onRearm() { suppressed = false }

    /// Auto-present only when locked, frontmost, not already authenticating, and
    /// not suppressed by a prior cancel/fail.
    public func shouldAutoPrompt(isLocked: Bool, isActive: Bool, isAuthenticating: Bool) -> Bool {
        isLocked && isActive && !isAuthenticating && !suppressed
    }
}
