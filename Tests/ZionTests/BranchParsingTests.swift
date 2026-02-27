import XCTest
@testable import Zion

final class BranchParsingTests: XCTestCase {
    private let worker = RepositoryWorker()

    // MARK: - guessBestParent

    func testGuessParentForFeatureBranch() async {
        let roots = ["main", "develop"]
        let parent = await worker.guessBestParent(for: "feature/login", preferredRoots: roots)

        XCTAssertEqual(parent, "develop")
    }

    func testGuessParentForFeatureFallbackToMain() async {
        let roots = ["main"]  // no develop
        let parent = await worker.guessBestParent(for: "feature/login", preferredRoots: roots)

        XCTAssertEqual(parent, "main")
    }

    func testGuessParentForHotfix() async {
        let roots = ["main", "develop"]
        let parent = await worker.guessBestParent(for: "hotfix/critical-fix", preferredRoots: roots)

        XCTAssertEqual(parent, "main")
    }

    func testGuessParentForReleaseBranch() async {
        let roots = ["main", "develop"]
        let parent = await worker.guessBestParent(for: "release/v2.0", preferredRoots: roots)

        XCTAssertEqual(parent, "main")
    }

    func testGuessParentForBugfix() async {
        let roots = ["main", "develop"]
        let parent = await worker.guessBestParent(for: "bugfix/issue-123", preferredRoots: roots)

        XCTAssertEqual(parent, "develop")
    }

    func testGuessParentForChore() async {
        let roots = ["main", "develop"]
        let parent = await worker.guessBestParent(for: "chore/update-deps", preferredRoots: roots)

        XCTAssertEqual(parent, "develop")
    }

    func testGuessParentForUnprefixedBranch() async {
        let roots = ["main", "develop"]
        let parent = await worker.guessBestParent(for: "my-branch", preferredRoots: roots)

        XCTAssertEqual(parent, "main")
    }

    func testGuessParentForMasterAsRoot() async {
        let roots = ["master"]
        let parent = await worker.guessBestParent(for: "feature/x", preferredRoots: roots)

        XCTAssertEqual(parent, "master")
    }

    func testGuessParentEmptyRoots() async {
        let parent = await worker.guessBestParent(for: "feature/x", preferredRoots: [])
        XCTAssertNil(parent)
    }

    func testGuessParentEmptyBranch() async {
        let parent = await worker.guessBestParent(for: "", preferredRoots: ["main"])
        XCTAssertNil(parent)
    }

    func testGuessParentWithDevRoot() async {
        let roots = ["main", "dev"]
        let parent = await worker.guessBestParent(for: "feature/x", preferredRoots: roots)

        XCTAssertEqual(parent, "dev")
    }

    // MARK: - parseISODate

    func testParseISODateWithFractions() async {
        let date = await worker.parseISODate("2025-06-15T14:30:00.500+00:00")
        XCTAssertNotEqual(date, Date(timeIntervalSince1970: 0))
    }

    func testParseISODateWithoutFractions() async {
        let date = await worker.parseISODate("2025-06-15T14:30:00+00:00")
        XCTAssertNotEqual(date, Date(timeIntervalSince1970: 0))
    }

    func testParseISODateInvalidFallsToEpoch() async {
        let date = await worker.parseISODate("not-a-date")
        XCTAssertEqual(date, Date(timeIntervalSince1970: 0))
    }
}
