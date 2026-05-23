import XCTest
import CryptoKit
@testable import Zion

final class RepoMapServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> RepoMapService {
        RepoMapService()
    }

    /// Replicates the repoID algorithm from RepoMapService / ChatStorage.
    private func repoID(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let data = Data(path.utf8)
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - testEnumeratesSwiftSymbols

    func testEnumeratesSwiftSymbols() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        try GitTestHelper.createFile(name: "Alpha.swift", content: "func alphaFunc() -> Void {}\n", in: repoURL)
        try GitTestHelper.createFile(name: "Beta.swift",  content: "func betaFunc() -> Void {}\n",  in: repoURL)
        try GitTestHelper.createFile(name: "Gamma.swift", content: "func gammaFunc() -> Void {}\n", in: repoURL)
        try GitTestHelper.commitAll(message: "Add swift files", in: repoURL)

        let service = makeService()
        try await service.ensureMap(repoURL: repoURL)

        let alphaResults = await service.query("alphaFunc")
        let betaResults  = await service.query("betaFunc")
        let gammaResults = await service.query("gammaFunc")

        XCTAssertFalse(alphaResults.isEmpty, "alphaFunc should be discovered")
        XCTAssertFalse(betaResults.isEmpty,  "betaFunc should be discovered")
        XCTAssertFalse(gammaResults.isEmpty, "gammaFunc should be discovered")
    }

    // MARK: - testRankingPrioritizesReferencedSymbols

    func testRankingPrioritizesReferencedSymbols() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        // A defines Foo
        try GitTestHelper.createFile(name: "A.swift", content: "public struct Foo {}\n", in: repoURL)
        // B references Foo but defines unrelated things
        try GitTestHelper.createFile(name: "B.swift", content: "let x: Foo = Foo()\nfunc barFunc() {}\n", in: repoURL)
        // C defines something unrelated to Foo
        try GitTestHelper.createFile(name: "C.swift", content: "func unrelatedFunc() {}\n", in: repoURL)
        try GitTestHelper.commitAll(message: "Ranking fixture", in: repoURL)

        let service = makeService()
        try await service.ensureMap(repoURL: repoURL)

        let fooResults       = await service.query("Foo")
        let unrelatedResults = await service.query("unrelatedFunc")

        XCTAssertFalse(fooResults.isEmpty, "Foo should appear in results")

        if let fooEntry = fooResults.first(where: { $0.name == "Foo" }),
           let unrelatedEntry = unrelatedResults.first {
            XCTAssertGreaterThan(fooEntry.score, unrelatedEntry.score,
                "Foo (referenced by B) should rank higher than unrelatedFunc")
        }
    }

    // MARK: - testSnapshotPersistedToDisk

    func testSnapshotPersistedToDisk() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        try GitTestHelper.createFile(name: "Main.swift", content: "func mainEntry() {}\n", in: repoURL)
        try GitTestHelper.commitAll(message: "Add main", in: repoURL)

        let service = makeService()
        try await service.ensureMap(repoURL: repoURL)

        let rID = repoID(for: repoURL)
        let expectedFile = RepoMapService.sharedDirectory()
            .appendingPathComponent("\(rID).json")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedFile.path),
            "Snapshot JSON should exist at \(expectedFile.path)"
        )
    }

    // MARK: - testQueryRespectsLimit

    func testQueryRespectsLimit() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        for i in 1...5 {
            try GitTestHelper.createFile(
                name: "File\(i).swift",
                content: "func limitTest\(i)() {}\n",
                in: repoURL
            )
        }
        try GitTestHelper.commitAll(message: "Add limit fixtures", in: repoURL)

        let service = makeService()
        try await service.ensureMap(repoURL: repoURL)

        let results = await service.query("limitTest", limit: 2)
        XCTAssertLessThanOrEqual(results.count, 2, "query should respect the limit parameter")
    }

    // MARK: - testRefreshUpdatesSnapshot

    func testRefreshUpdatesSnapshot() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        try GitTestHelper.createFile(name: "Existing.swift", content: "func existingSymbol() {}\n", in: repoURL)
        try GitTestHelper.commitAll(message: "Initial file", in: repoURL)

        let service = makeService()
        try await service.ensureMap(repoURL: repoURL)

        let beforeRefresh = await service.query("newlyAddedSymbol")
        XCTAssertTrue(beforeRefresh.isEmpty, "newlyAddedSymbol should not exist before refresh")

        // Add new file and commit
        try GitTestHelper.createFile(name: "New.swift", content: "func newlyAddedSymbol() {}\n", in: repoURL)
        try GitTestHelper.commitAll(message: "Add new symbol", in: repoURL)

        try await service.refresh(repoURL: repoURL)

        let afterRefresh = await service.query("newlyAddedSymbol")
        XCTAssertFalse(afterRefresh.isEmpty, "newlyAddedSymbol should appear after refresh")
    }
}
