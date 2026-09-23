import XCTest
@testable import LinkryptCore

/// The dashboard sidebar advertises `g s`, `g r`, `g n`, … — a leader key plus
/// one letter. Pure state machine so arming, firing, cancelling and the
/// timeout are gated independently of the SwiftUI key-press plumbing.
final class NavChordTests: XCTestCase {
    private let t0: TimeInterval = 1_000   // monotonic uptime seconds (see NavChord.State.press(_:at:))

    func testLeaderArms() {
        var s = NavChord.State()
        XCTAssertEqual(s.press("g", at: t0), .armed)
        XCTAssertTrue(s.isArmed)
    }

    func testNonLeaderWhileIdleIsIgnoredAndDoesNotArm() {
        var s = NavChord.State()
        XCTAssertEqual(s.press("s", at: t0), .ignored)
        XCTAssertFalse(s.isArmed)
    }

    func testArmedThenMappedKeyFiresAndDisarms() {
        var s = NavChord.State()
        _ = s.press("g", at: t0)
        XCTAssertEqual(s.press("s", at: t0 + (0.3)), .fired(.shares))
        XCTAssertFalse(s.isArmed)
        // a lone `s` afterwards is a plain key again
        XCTAssertEqual(s.press("s", at: t0 + (0.4)), .ignored)
    }

    func testShiftedLetterIsItsOwnChord() {
        var s = NavChord.State()
        _ = s.press("g", at: t0)
        XCTAssertEqual(s.press("N", at: t0), .fired(.newRequest))
        _ = s.press("g", at: t0)
        XCTAssertEqual(s.press("n", at: t0), .fired(.newShare))
    }

    func testArmedThenUnknownKeyCancels() {
        var s = NavChord.State()
        _ = s.press("g", at: t0)
        XCTAssertEqual(s.press("x", at: t0), .cancelled)
        XCTAssertFalse(s.isArmed)
    }

    func testLeaderWhileArmedReArms() {
        var s = NavChord.State()
        _ = s.press("g", at: t0)
        XCTAssertEqual(s.press("g", at: t0 + (1)), .armed)
        XCTAssertEqual(s.press("r", at: t0 + (1.2)), .fired(.requests))
    }

    func testChordExpiresAfterTimeout() {
        var s = NavChord.State()
        _ = s.press("g", at: t0)
        let late = t0 + NavChord.timeout + 0.01
        XCTAssertEqual(s.press("s", at: late), .ignored)
        XCTAssertFalse(s.isArmed)
    }

    func testChordJustInsideTimeoutStillFires() {
        var s = NavChord.State()
        _ = s.press("g", at: t0)
        XCTAssertEqual(s.press("s", at: t0 + (NavChord.timeout)), .fired(.shares))
    }

    /// A key the focused table consumed (`j/k/y/d/⏎`) never reaches the chord
    /// handler, so the table tells the chord to stand down — otherwise
    /// `g`, `j`, `s` would move the selection and THEN switch workspace.
    func testDisarmMakesNextLetterAPlainKey() {
        var s = NavChord.State()
        _ = s.press("g", at: t0)
        s.disarm()
        XCTAssertFalse(s.isArmed)
        XCTAssertEqual(s.press("s", at: t0 + 0.1), .ignored)
    }

    /// Must mirror the sidebar hints in `DashboardView` exactly.
    func testKeyMapMatchesSidebarHints() {
        let expected: [Character: NavChord.Action] = [
            "s": .shares, "r": .requests, "n": .newShare, "N": .newRequest,
            "v": .openShare, "p": .answerRequest, "i": .inbox, "a": .auditLog, "t": .apiTokens,
        ]
        for (k, a) in expected { XCTAssertEqual(NavChord.action(for: k), a, "\(k)") }
        XCTAssertEqual(Set(NavChord.Action.allCases), Set(expected.values))
        XCTAssertEqual(NavChord.leader, "g")
    }
}
