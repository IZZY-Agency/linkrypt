import XCTest
@testable import LinkryptCore

final class RequestStatusTests: XCTestCase {
    private func row(expiresAt: Int? = 2_000, submittedAt: Int? = nil,
                     burnedAt: Int? = nil, revokedAt: Int? = nil) -> RequestRow {
        let json = """
        {"id":"x","label":null,"maxSubmissions":1,"submissionsUsed":0,
         "expiresAt":\(expiresAt.map(String.init) ?? "null"),
         "createdAt":1,"submittedAt":\(submittedAt.map(String.init) ?? "null"),
         "burnedAt":\(burnedAt.map(String.init) ?? "null"),
         "revokedAt":\(revokedAt.map(String.init) ?? "null"),
         "contentType":null,"filename":null,"size":null}
        """
        return try! JSONDecoder().decode(RequestRow.self, from: Data(json.utf8))
    }
    private let now = 1_000

    func testRevokedWins() { XCTAssertEqual(RequestStatus.of(row(submittedAt: 5, burnedAt: 5, revokedAt: 5), now: now), "revoked") }
    func testBurnedBeatsSubmitted() { XCTAssertEqual(RequestStatus.of(row(submittedAt: 5, burnedAt: 5), now: now), "burned") }
    func testSubmittedBeatsExpired() { XCTAssertEqual(RequestStatus.of(row(expiresAt: 500, submittedAt: 5), now: now), "submitted") }
    func testExpired() { XCTAssertEqual(RequestStatus.of(row(expiresAt: 500), now: now), "expired") }
    func testExpiresExactlyNowIsExpired() { XCTAssertEqual(RequestStatus.of(row(expiresAt: now), now: now), "expired") }
    func testPending() { XCTAssertEqual(RequestStatus.of(row(expiresAt: 2_000), now: now), "pending") }
}
