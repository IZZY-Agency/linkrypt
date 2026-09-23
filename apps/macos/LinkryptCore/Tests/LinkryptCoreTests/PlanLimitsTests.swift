import XCTest
@testable import LinkryptCore

/// `PlanLimits` is what `/api/cli/whoami` reports for the token owner's
/// EFFECTIVE plan (admin → internal). The app filters the composer / ⌥⇧V /
/// Settings option lists through it so it never offers a value the server's
/// share-create gates will 402.
final class PlanLimitsTests: XCTestCase {
    private let whoamiFree = #"""
    {"userId":"u","email":"a@b.com","scopes":["shares:read"],"plan":"free",
     "limits":{"expiresIn":["24h","7d"],"maxOpensPerShare":1,"maxFileSizeBytes":5242880,
               "features":{"requestLinks":false,"emailRecipient":false,"notifyOnOpen":false,"passphrase":false}}}
    """#
    private let whoamiInternal = #"""
    {"userId":"u","scopes":[],"plan":"internal",
     "limits":{"expiresIn":["1h","24h","7d","30d","90d"],"maxOpensPerShare":null,"maxFileSizeBytes":null,
               "features":{"requestLinks":true,"emailRecipient":true,"notifyOnOpen":true,"passphrase":true}}}
    """#

    private func decode(_ json: String) throws -> WhoAmI {
        try JSONDecoder().decode(WhoAmI.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    func testDecodesPlanAndLimitsFromWhoAmI() throws {
        let w = try decode(whoamiFree)
        XCTAssertEqual(w.plan, "free")
        XCTAssertEqual(w.limits?.expiresIn, ["24h", "7d"])
        XCTAssertEqual(w.limits?.maxOpensPerShare, 1)
        XCTAssertEqual(w.limits?.maxFileSizeBytes, 5_242_880)
        XCTAssertEqual(w.limits?.features.passphrase, false)
    }

    func testDecodesNullCapsAsUnlimited() throws {
        let w = try decode(whoamiInternal)
        XCTAssertEqual(w.plan, "internal")
        XCTAssertNil(w.limits?.maxOpensPerShare)
        XCTAssertNil(w.limits?.maxFileSizeBytes)
        XCTAssertEqual(w.limits?.features.emailRecipient, true)
    }

    /// Older server without the field → nil (the app then offers everything,
    /// exactly as before, and relies on the server's 402).
    func testMissingLimitsDecodesAsNil() throws {
        let w = try decode(#"{"userId":"u","scopes":[]}"#)
        XCTAssertNil(w.plan)
        XCTAssertNil(w.limits)
    }

    // MARK: - Filtering (keeps the caller's order, drops what the plan rejects)

    func testFilterExpiriesKeepsCandidateOrder() throws {
        let l = try XCTUnwrap(decode(whoamiFree).limits)
        XCTAssertEqual(l.filter(expiries: ["1h", "24h", "7d", "30d"]), ["24h", "7d"])
    }

    func testFilterOpensAppliesCap() throws {
        let free = try XCTUnwrap(decode(whoamiFree).limits)
        XCTAssertEqual(free.filter(opens: [1, 2, 5, 100]), [1])
        let unlimited = try XCTUnwrap(decode(whoamiInternal).limits)
        XCTAssertEqual(unlimited.filter(opens: [1, 2, 5, 100]), [1, 2, 5, 100])
    }

    func testClampExpiryFallsBackToFirstAllowedCandidate() throws {
        let l = try XCTUnwrap(decode(whoamiFree).limits)
        XCTAssertEqual(l.clamp(expiry: "1h", candidates: ["1h", "24h", "7d"]), "24h")
        XCTAssertEqual(l.clamp(expiry: "7d", candidates: ["1h", "24h", "7d"]), "7d")
    }

    func testClampOpensFallsBackToFirstAllowedCandidate() throws {
        let l = try XCTUnwrap(decode(whoamiFree).limits)
        XCTAssertEqual(l.clamp(opens: 5, candidates: [1, 5]), 1)
    }

    /// Nothing allowed among the candidates (misconfigured server) → keep the
    /// preferred value so the user still gets a server-side error, not a crash.
    func testClampWithNoAllowedCandidateKeepsPreferred() throws {
        let l = try XCTUnwrap(decode(whoamiFree).limits)
        XCTAssertEqual(l.clamp(expiry: "1h", candidates: ["1h", "30d"]), "1h")
    }

    // MARK: - Optional convenience (nil limits = unrestricted)

    func testNilLimitsIsUnrestricted() {
        let none: PlanLimits? = nil
        XCTAssertEqual(none.filter(expiries: ["1h", "24h"]), ["1h", "24h"])
        XCTAssertEqual(none.filter(opens: [1, 5]), [1, 5])
        XCTAssertEqual(none.clamp(expiry: "1h", candidates: ["24h"]), "1h")
        XCTAssertEqual(none.clamp(opens: 5, candidates: [1]), 5)
        XCTAssertTrue(none.allows(feature: \.passphrase))
    }

    func testFeatureGate() throws {
        let free: PlanLimits? = try decode(whoamiFree).limits
        XCTAssertFalse(free.allows(feature: \.passphrase))
        XCTAssertFalse(free.allows(feature: \.emailRecipient))
        let internalPlan: PlanLimits? = try decode(whoamiInternal).limits
        XCTAssertTrue(internalPlan.allows(feature: \.notifyOnOpen))
    }
}
