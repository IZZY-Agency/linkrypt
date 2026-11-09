import XCTest
@testable import LinkryptCore

/// Binary (1024-based) size display, matching the web client's
/// `formatBytes` / `formatBytesCeil` and the plan pages ("5 MB", "100 MB").
final class ByteSizeTests: XCTestCase {
    private let kib = 1024, mib = 1024 * 1024, gib = 1024 * 1024 * 1024

    func testBytesBelowOneKiB() {
        XCTAssertEqual(ByteSize.tenths(0), .init(tenths: 0, unit: .bytes))
        XCTAssertEqual(ByteSize.tenths(512), .init(tenths: 5120, unit: .bytes))
        XCTAssertEqual(ByteSize.tenths(1023), .init(tenths: 10230, unit: .bytes))
        XCTAssertEqual(ByteSize.tenths(-5), .init(tenths: 0, unit: .bytes))
    }

    func testPlanLimitsAreWholeBinaryUnits() {
        XCTAssertEqual(ByteSize.tenths(5 * mib), .init(tenths: 50, unit: .megabytes))      // "5 MB"
        XCTAssertEqual(ByteSize.tenths(100 * mib), .init(tenths: 1000, unit: .megabytes))  // "100 MB"
        XCTAssertEqual(ByteSize.tenths(kib), .init(tenths: 10, unit: .kilobytes))
        XCTAssertEqual(ByteSize.tenths(gib), .init(tenths: 10, unit: .gigabytes))
    }

    func testNearestRoundsToOneDecimal() {
        XCTAssertEqual(ByteSize.tenths(5_452_595), .init(tenths: 52, unit: .megabytes))   // 5.2000004 MiB
        XCTAssertEqual(ByteSize.tenths(5 * mib + 1), .init(tenths: 50, unit: .megabytes))
        XCTAssertEqual(ByteSize.tenths(1536), .init(tenths: 15, unit: .kilobytes))
    }

    func testRoundingUpNeverShowsAnOverLimitSizeAsTheLimit() {
        XCTAssertEqual(ByteSize.tenths(5 * mib + 1, roundingUp: true), .init(tenths: 51, unit: .megabytes))
        XCTAssertEqual(ByteSize.tenths(5 * mib, roundingUp: true), .init(tenths: 50, unit: .megabytes))
        XCTAssertEqual(ByteSize.tenths(gib + 1, roundingUp: true), .init(tenths: 11, unit: .gigabytes))
        XCTAssertEqual(ByteSize.tenths(100 * mib + 1, roundingUp: true), .init(tenths: 1001, unit: .megabytes))
    }

    func testPromotesWhenTheValueReaches1024() {
        XCTAssertEqual(ByteSize.tenths(mib - 1), .init(tenths: 10, unit: .megabytes))
        XCTAssertEqual(ByteSize.tenths(mib - 1, roundingUp: true), .init(tenths: 10, unit: .megabytes))
        XCTAssertEqual(ByteSize.tenths(1023 * mib + 1, roundingUp: true), .init(tenths: 10231, unit: .megabytes))
        XCTAssertEqual(ByteSize.tenths(Padding.maxPlaintext), .init(tenths: 40, unit: .gigabytes))   // "4 GB"
    }

    func testGigabytesIsTheLargestUnitAndNeverTraps() {
        XCTAssertEqual(ByteSize.tenths(2048 * gib), .init(tenths: 20480, unit: .gigabytes))
        XCTAssertEqual(ByteSize.tenths(Int.max).unit, .gigabytes)
        XCTAssertEqual(ByteSize.tenths(Int.max, roundingUp: true).unit, .gigabytes)
    }
}
