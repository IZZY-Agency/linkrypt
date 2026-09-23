import XCTest
@testable import LinkryptCore

/// How the Settings "Start at login" toggle reads the system's login-item
/// state. The app maps `SMAppService.Status` onto `LoginItemStatus`; the
/// toggle/hint logic lives here so it's testable without ServiceManagement.
final class LoginItemStatusTests: XCTestCase {
    func testEnabledReadsAsOn() {
        XCTAssertTrue(LoginItemStatus.enabled.isOn)
        XCTAssertFalse(LoginItemStatus.enabled.needsApproval)
    }

    /// The user asked for it but macOS is holding it in Login Items until they
    /// approve — the toggle stays ON and a hint explains the pending state.
    func testRequiresApprovalReadsAsOnAndPending() {
        XCTAssertTrue(LoginItemStatus.requiresApproval.isOn)
        XCTAssertTrue(LoginItemStatus.requiresApproval.needsApproval)
    }

    func testNotRegisteredReadsAsOff() {
        XCTAssertFalse(LoginItemStatus.notRegistered.isOn)
        XCTAssertFalse(LoginItemStatus.notRegistered.needsApproval)
    }

    /// `.notFound` is what a never-registered app reports on macOS 27 (probe-
    /// verified 2026-09-04: never-registered → notFound, register() → enabled,
    /// unregister() → notRegistered) — the toggle must be OFF and operable, not
    /// disabled with a "can't find the bundle" error.
    func testNotFoundReadsAsPlainOff() {
        XCTAssertFalse(LoginItemStatus.notFound.isOn)
        XCTAssertFalse(LoginItemStatus.notFound.needsApproval)
    }
}
