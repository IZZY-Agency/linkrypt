import XCTest
@testable import LinkryptCore

final class PresetCycleTests: XCTestCase {
    // MARK: - next(_:in:)

    func testCyclesForwardThroughExpiries() {
        XCTAssertEqual(PresetCycle.next("1h", in: PresetCycle.expiries), "24h")
        XCTAssertEqual(PresetCycle.next("24h", in: PresetCycle.expiries), "7d")
    }

    func testWrapsAroundToFirst() {
        XCTAssertEqual(PresetCycle.next("7d", in: PresetCycle.expiries), "1h")
        XCTAssertEqual(PresetCycle.next(5, in: PresetCycle.opens), 1)
    }

    func testCyclesOpens() {
        XCTAssertEqual(PresetCycle.next(1, in: PresetCycle.opens), 5)
    }

    /// A value that isn't one of the presets (e.g. a share minted from the
    /// composer with a custom expiry) must land on a known preset, not stick.
    func testUnknownCurrentFallsBackToFirst() {
        XCTAssertEqual(PresetCycle.next("90d", in: PresetCycle.expiries), "1h")
        XCTAssertEqual(PresetCycle.next(3, in: PresetCycle.opens), 1)
    }

    func testEmptyOptionsReturnsCurrentUnchanged() {
        XCTAssertEqual(PresetCycle.next("1h", in: []), "1h")
    }

    func testSingleOptionIsStable() {
        XCTAssertEqual(PresetCycle.next("1h", in: ["1h"]), "1h")
    }

    /// The presets must stay in sync with the overlay's visible buttons.
    func testPresetsMatchOverlayButtons() {
        XCTAssertEqual(PresetCycle.expiries, ["1h", "24h", "7d"])
        XCTAssertEqual(PresetCycle.opens, [1, 5])
    }

    /// Cycling the full length returns to the start.
    func testFullCycleReturnsToStart() {
        var v = "1h"
        for _ in 0..<PresetCycle.expiries.count { v = PresetCycle.next(v, in: PresetCycle.expiries) }
        XCTAssertEqual(v, "1h")
    }

    // MARK: - clamp(_:to:default:)

    func testClampKeepsAKnownPreset() {
        XCTAssertEqual(PresetCycle.clamp("7d", to: PresetCycle.expiries, default: "24h"), "7d")
        XCTAssertEqual(PresetCycle.clamp(5, to: PresetCycle.opens, default: 1), 5)
    }

    func testClampFallsBackToDefaultForAnUnknownValue() {
        XCTAssertEqual(PresetCycle.clamp("90d", to: PresetCycle.expiries, default: "24h"), "24h")
        XCTAssertEqual(PresetCycle.clamp(0, to: PresetCycle.opens, default: 1), 1)
    }
}
