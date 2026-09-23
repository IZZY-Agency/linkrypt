import XCTest
@testable import LinkryptCore

final class ShareRowDecodeTests: XCTestCase {
    private func rows(_ json: String) throws -> [ShareRow] {
        try JSONDecoder().decode(ShareListResponse.self, from: Data(json.utf8)).shares
    }

    // The normalized wire shape: epoch-second integers.
    func testDecodesEpochIntegerTimestamps() throws {
        let r = try rows(#"""
        {"shares":[{"id":"s1","type":"text","label":"hi","filename":null,"size":42,
          "maxOpens":3,"opensUsed":1,"expiresAt":1749549240,"createdAt":1749545640,
          "burnedAt":null,"revokedAt":null}]}
        """#)[0]
        XCTAssertEqual(r.id, "s1")
        XCTAssertEqual(r.expiresAt, 1749549240)
        XCTAssertEqual(r.createdAt, 1749545640)
        XCTAssertNil(r.burnedAt)
        XCTAssertNil(r.revokedAt)
    }

    // The older wire shape (JSON-serialized Dates): ISO-8601 strings.
    // 2025-06-10T09:54:00Z == 1749549240 ; 08:54:00Z == 1749545640.
    func testDecodesISOStringTimestampsToEpoch() throws {
        let r = try rows(#"""
        {"shares":[{"id":"s2","type":"file","label":null,"filename":"a.bin","size":10,
          "maxOpens":1,"opensUsed":0,
          "expiresAt":"2025-06-10T09:54:00.000Z","createdAt":"2025-06-10T08:54:00.000Z",
          "burnedAt":null,"revokedAt":null}]}
        """#)[0]
        XCTAssertEqual(r.expiresAt, 1749549240)
        XCTAssertEqual(r.createdAt, 1749545640)
    }

    func testEpochAndISOAgree() throws {
        let epoch = try rows(#"{"shares":[{"id":"a","type":"text","maxOpens":1,"opensUsed":0,"expiresAt":1749549240}]}"#)[0]
        let iso = try rows(#"{"shares":[{"id":"a","type":"text","maxOpens":1,"opensUsed":0,"expiresAt":"2025-06-10T09:54:00.000Z"}]}"#)[0]
        XCTAssertEqual(epoch.expiresAt, iso.expiresAt)
    }

    func testMissingOptionalsDecodeToNil() throws {
        let r = try rows(#"{"shares":[{"id":"a","type":"text","maxOpens":1,"opensUsed":0}]}"#)[0]
        XCTAssertNil(r.expiresAt)
        XCTAssertNil(r.createdAt)
        XCTAssertNil(r.label)
        XCTAssertNil(r.size)
    }

    // The API emits explicit null (not just absent) for non-terminal timestamps.
    func testDecodesExplicitNullTimestampsToNil() throws {
        let r = try rows(#"""
        {"shares":[{"id":"a","type":"text","maxOpens":1,"opensUsed":0,
          "expiresAt":null,"createdAt":null,"burnedAt":null,"revokedAt":null}]}
        """#)[0]
        XCTAssertNil(r.expiresAt)
        XCTAssertNil(r.createdAt)
        XCTAssertNil(r.burnedAt)
        XCTAssertNil(r.revokedAt)
    }

    // A malformed timestamp must decode to nil, NOT throw — one bad row must not
    // fail the whole list decode (that is the entire point of the tolerant decoder).
    func testUnparseableTimestampStringDecodesToNil() throws {
        let r = try rows(#"{"shares":[{"id":"a","type":"text","maxOpens":1,"opensUsed":0,"expiresAt":"not-a-date"}]}"#)[0]
        XCTAssertNil(r.expiresAt)
    }
}
