import XCTest
@testable import LinkryptCore

/// The About window reads version/build/copyright from the bundle's Info.plist
/// (single source of truth — the same keys Finder "Get Info" and the stock
/// About panel use). Nothing is fabricated when a key is missing.
final class AboutInfoTests: XCTestCase {
    private let full: [String: Any] = [
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "1",
        "NSHumanReadableCopyright": "© 2026 Example Co.",
    ]

    func testReadsVersionBuildAndCopyrightFromBundleInfo() {
        let info = AboutInfo(bundleInfo: full)
        XCTAssertEqual(info.version, "0.1.0")
        XCTAssertEqual(info.build, "1")
        XCTAssertEqual(info.copyright, "© 2026 Example Co.")
    }

    func testVersionLineIncludesBuild() {
        XCTAssertEqual(AboutInfo(bundleInfo: full).versionLine, "0.1.0 (1)")
    }

    func testVersionLineOmitsBuildWhenMissingOrSameAsVersion() {
        XCTAssertEqual(AboutInfo(bundleInfo: ["CFBundleShortVersionString": "0.1.0"]).versionLine, "0.1.0")
        XCTAssertEqual(AboutInfo(bundleInfo: ["CFBundleShortVersionString": "0.1.0",
                                              "CFBundleVersion": "0.1.0"]).versionLine, "0.1.0")
    }

    func testMissingKeysAreNilNotFabricated() {
        let info = AboutInfo(bundleInfo: [:])
        XCTAssertNil(info.version)
        XCTAssertNil(info.build)
        XCTAssertNil(info.copyright)
        XCTAssertNil(info.versionLine)
    }

    func testBlankValuesReadAsMissing() {
        let info = AboutInfo(bundleInfo: ["CFBundleShortVersionString": "  ", "NSHumanReadableCopyright": ""])
        XCTAssertNil(info.version)
        XCTAssertNil(info.copyright)
    }

    // The open-source links point at the public repository; release notes are
    // the GitHub release of exactly this version (tag macos-v<version>).
    func testOpenSourceLinks() {
        XCTAssertEqual(AboutInfo.repositoryURL, "https://github.com/IZZY-Agency/linkrypt")
        XCTAssertEqual(AboutInfo.licenseURL, "https://github.com/IZZY-Agency/linkrypt/blob/main/LICENSE")
        XCTAssertEqual(AboutInfo.securityReportURL, "https://github.com/IZZY-Agency/linkrypt/security/advisories/new")
        XCTAssertEqual(AboutInfo(bundleInfo: full).releaseNotesURL,
                       "https://github.com/IZZY-Agency/linkrypt/releases/tag/macos-v0.1.0")
    }

    func testReleaseNotesFallBackToAllReleasesWithoutAVersion() {
        XCTAssertEqual(AboutInfo(bundleInfo: [:]).releaseNotesURL,
                       "https://github.com/IZZY-Agency/linkrypt/releases")
    }
}
