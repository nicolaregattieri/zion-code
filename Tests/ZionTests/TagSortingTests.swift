import XCTest
@testable import Zion

final class TagSortingTests: XCTestCase {
    private let worker = RepositoryWorker()

    // MARK: - versionComponents

    func testVersionComponentsStandardSemver() async {
        let result = await worker.versionComponents(from: "v1.2.3")
        XCTAssertEqual(result, [1, 2, 3])
    }

    func testVersionComponentsWithoutVPrefix() async {
        let result = await worker.versionComponents(from: "1.2.3")
        XCTAssertEqual(result, [1, 2, 3])
    }

    func testVersionComponentsUppercaseV() async {
        let result = await worker.versionComponents(from: "V2.0")
        XCTAssertEqual(result, [2, 0])
    }

    func testVersionComponentsWithPrefix() async {
        let result = await worker.versionComponents(from: "release-1.0.0")
        XCTAssertEqual(result, [1, 0, 0])
    }

    func testVersionComponentsNoNumbers() async {
        let result = await worker.versionComponents(from: "abc")
        XCTAssertTrue(result.isEmpty)
    }

    func testVersionComponentsSingleNumber() async {
        let result = await worker.versionComponents(from: "v1")
        XCTAssertEqual(result, [1])
    }

    func testVersionComponentsComplexTag() async {
        let result = await worker.versionComponents(from: "v1.0.0-beta.2")
        XCTAssertEqual(result, [1, 0, 0, 2])
    }

    // MARK: - sortTagsDescending

    func testSortVersionedTags() async {
        let tags = ["v1.0", "v2.0", "v1.5"]
        let sorted = await worker.sortTagsDescending(tags)
        XCTAssertEqual(sorted, ["v2.0", "v1.5", "v1.0"])
    }

    func testSortMixedVersionAndNonVersion() async {
        let tags = ["v1.0", "nightly", "v2.0"]
        let sorted = await worker.sortTagsDescending(tags)

        // Versioned tags come first (v2.0 > v1.0), then non-versioned
        XCTAssertEqual(sorted[0], "v2.0")
        XCTAssertEqual(sorted[1], "v1.0")
        XCTAssertEqual(sorted[2], "nightly")
    }

    func testSortDifferentComponentCount() async {
        // v1 vs v1.0.0 — should be treated as equal (v1 = v1.0.0)
        let tags = ["v1.0.0", "v2.0", "v1"]
        let sorted = await worker.sortTagsDescending(tags)

        XCTAssertEqual(sorted[0], "v2.0")
        // v1.0.0 and v1 are version-equivalent; order between them depends on localizedStandardCompare
        XCTAssertTrue(sorted.contains("v1.0.0"))
        XCTAssertTrue(sorted.contains("v1"))
    }

    func testSortNonVersionedTagsAlphabetically() async {
        let tags = ["beta", "alpha", "nightly"]
        let sorted = await worker.sortTagsDescending(tags)

        // localizedStandardCompare descending
        XCTAssertEqual(sorted, ["nightly", "beta", "alpha"])
    }

    func testSortEmptyArray() async {
        let sorted = await worker.sortTagsDescending([])
        XCTAssertTrue(sorted.isEmpty)
    }

    func testSortPrereleaseTags() async {
        let tags = ["v1.0.0-alpha.1", "v1.0.0-alpha.2", "v1.0.0"]
        let sorted = await worker.sortTagsDescending(tags)

        // v1.0.0 = [1,0,0], v1.0.0-alpha.1 = [1,0,0,1], v1.0.0-alpha.2 = [1,0,0,2]
        // [1,0,0,2] > [1,0,0,1] > [1,0,0]
        XCTAssertEqual(sorted[0], "v1.0.0-alpha.2")
        XCTAssertEqual(sorted[1], "v1.0.0-alpha.1")
        XCTAssertEqual(sorted[2], "v1.0.0")
    }
}
