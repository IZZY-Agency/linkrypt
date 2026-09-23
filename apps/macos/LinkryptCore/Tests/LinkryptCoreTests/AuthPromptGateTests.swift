import XCTest
@testable import LinkryptCore

final class AuthPromptGateTests: XCTestCase {

    // shouldAutoPrompt is true ONLY when isLocked && isActive && !isAuthenticating && !suppressed.
    func testAutoPromptTrueOnlyWhenAllTermsSatisfied() {
        let g = AuthPromptGate()
        XCTAssertTrue(g.shouldAutoPrompt(isLocked: true, isActive: true, isAuthenticating: false))
    }

    func testAutoPromptFalseWhenNotLocked() {
        let g = AuthPromptGate()
        XCTAssertFalse(g.shouldAutoPrompt(isLocked: false, isActive: true, isAuthenticating: false))
    }

    func testAutoPromptFalseWhenInactive() {
        let g = AuthPromptGate()
        XCTAssertFalse(g.shouldAutoPrompt(isLocked: true, isActive: false, isAuthenticating: false))
    }

    func testAutoPromptFalseWhenAuthenticating() {
        let g = AuthPromptGate()
        XCTAssertFalse(g.shouldAutoPrompt(isLocked: true, isActive: true, isAuthenticating: true))
    }

    func testAutoPromptFalseWhenSuppressed() {
        var g = AuthPromptGate()
        g.onAuthDismissed()
        XCTAssertFalse(g.shouldAutoPrompt(isLocked: true, isActive: true, isAuthenticating: false))
    }

    // onAuthDismissed → suppressed.
    func testOnAuthDismissedSuppresses() {
        var g = AuthPromptGate()
        XCTAssertFalse(g.suppressed)
        g.onAuthDismissed()
        XCTAssertTrue(g.suppressed)
    }

    // onRearm → re-armed (suppressed cleared, auto-prompt allowed again).
    func testOnRearmClearsSuppression() {
        var g = AuthPromptGate()
        g.onAuthDismissed()
        XCTAssertTrue(g.suppressed)
        g.onRearm()
        XCTAssertFalse(g.suppressed)
        XCTAssertTrue(g.shouldAutoPrompt(isLocked: true, isActive: true, isAuthenticating: false))
    }
}
