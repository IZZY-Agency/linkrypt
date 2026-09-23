import XCTest
@testable import LinkryptCore

final class AppLanguageTests: XCTestCase {
    let enFrOnly = ["en", "fr"]   // a server that serves only en + fr

    func testExplicitSupported() {
        XCTAssertEqual(AppLanguage.resolveCode(.fr, preferred: [], supported: enFrOnly), "fr")
    }
    func testExplicitUnsupportedClampsViaPreferred() {
        XCTAssertEqual(AppLanguage.resolveCode(.uk, preferred: ["uk","en"], supported: enFrOnly), "en")
    }
    func testExplicitUnsupportedNoPreferredMatchUsesFirstSupported() {
        XCTAssertEqual(AppLanguage.resolveCode(.uk, preferred: ["uk"], supported: enFrOnly), "en")
    }
    func testSystemBestMatch() {
        XCTAssertEqual(AppLanguage.resolveCode(.system, preferred: ["fr-FR","en"], supported: enFrOnly), "fr")
    }
    func testSystemNoMatchFallsBack() {
        XCTAssertEqual(AppLanguage.resolveCode(.system, preferred: ["de"], supported: enFrOnly), "en")
        XCTAssertEqual(AppLanguage.resolveCode(.system, preferred: [], supported: enFrOnly), "en")
    }
    func testUkHonoredWhenTenantSupportsIt() {
        XCTAssertEqual(AppLanguage.resolveCode(.uk, preferred: [], supported: ["en","fr","uk"]), "uk")
    }
    func testAllCasesPresent() {
        XCTAssertEqual(AppLanguage.allCases, [.system, .en, .fr, .uk])
    }
}
