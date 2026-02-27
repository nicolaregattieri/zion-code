import XCTest
@testable import Zion

@MainActor
final class SubmoduleParsingTests: XCTestCase {
    private let repoURL = URL(fileURLWithPath: "/tmp/test-repo")

    func testParseUpToDateSubmodule() {
        let raw = " abc123def456789012345678901234567890abcd libs/network (v1.0.0)"
        let subs = RepositoryViewModel.parseSubmoduleStatus(raw, repoURL: repoURL)

        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs[0].status, .upToDate)
        XCTAssertEqual(subs[0].path, "libs/network")
    }

    func testParseModifiedSubmodule() {
        let raw = "+abc123def456789012345678901234567890abcd libs/network (v1.0.0)"
        let subs = RepositoryViewModel.parseSubmoduleStatus(raw, repoURL: repoURL)

        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs[0].status, .modified)
    }

    func testParseUninitializedSubmodule() {
        let raw = "-abc123def456789012345678901234567890abcd libs/network"
        let subs = RepositoryViewModel.parseSubmoduleStatus(raw, repoURL: repoURL)

        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs[0].status, .uninitialized)
    }

    func testParseMultipleSubmodules() {
        let raw = """
         abc123def456789012345678901234567890abcd libs/network (v1.0.0)
        +def456abc123def456789012345678901234567890 libs/ui (heads/main)
        -ghi789abc123def456789012345678901234567890 libs/core
        """
        let subs = RepositoryViewModel.parseSubmoduleStatus(raw, repoURL: repoURL)

        XCTAssertEqual(subs.count, 3)
        XCTAssertEqual(subs[0].status, .upToDate)
        XCTAssertEqual(subs[1].status, .modified)
        XCTAssertEqual(subs[2].status, .uninitialized)
    }

    func testParseEmptyOutput() {
        let subs = RepositoryViewModel.parseSubmoduleStatus("", repoURL: repoURL)
        XCTAssertTrue(subs.isEmpty)
    }

    func testSubmoduleNameFromPath() {
        let raw = " abc123def456789012345678901234567890abcd vendor/external/lib (v2.0)"
        let subs = RepositoryViewModel.parseSubmoduleStatus(raw, repoURL: repoURL)

        // Name should be the last path component
        XCTAssertEqual(subs[0].name, "lib")
    }
}
