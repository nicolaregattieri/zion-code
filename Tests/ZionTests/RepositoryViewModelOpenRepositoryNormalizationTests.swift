import XCTest
@testable import Zion

@MainActor
final class RepositoryViewModelOpenRepositoryNormalizationTests: XCTestCase {

    private func makeTemporaryRepoDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let gitDir = directory.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        return directory.standardizedFileURL.resolvingSymlinksInPath()
    }

    // RT-006: terminal hyperlink handler resolves links like
    // `./scripts/foo.sh` against the repo root and ends up creating URLs
    // such as `file:///Users/.../GraphForge/./scripts/foo.sh`. Walking up
    // from there with `deletingLastPathComponent` produces an intermediate
    // URL whose `lastPathComponent == "."` — which made
    // `findGitRepository` return a non-canonical URL and downstream
    // equality / stash-key lookups miss the already-open repo. The fix
    // standardizes both the input and the returned URL.
    func testFindGitRepositoryNormalizesPathsContainingDotSegments() throws {
        let vm = RepositoryViewModel()
        let repoRoot = try makeTemporaryRepoDirectory()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let scripts = repoRoot.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        let scriptFile = scripts.appendingPathComponent("test.sh")
        try "echo hi\n".write(to: scriptFile, atomically: true, encoding: .utf8)

        // Construct the unstandardized URL the terminal hyperlink resolver
        // produces when joining a `./scripts/test.sh` link to the repo URL.
        let unstandardizedPath = repoRoot.path + "/./scripts/test.sh"
        let unstandardized = URL(fileURLWithPath: unstandardizedPath)
        XCTAssertTrue(unstandardized.path.contains("/./"), "Test setup must reproduce the dot-segment URL shape")

        let resolvedRepo = vm.findGitRepository(containing: unstandardized)
        XCTAssertNotNil(resolvedRepo)
        XCTAssertEqual(
            resolvedRepo?.standardizedFileURL.resolvingSymlinksInPath(),
            repoRoot,
            "findGitRepository must return a normalized URL even when the input contains /./ segments"
        )
        XCTAssertNotEqual(resolvedRepo?.lastPathComponent, ".",
                          "Returned repo URL must not have `.` as its lastPathComponent")
    }

    // openRepository must treat a URL containing `/./` against the same
    // repo as the already-open repo (not switch + spawn fresh terminals).
    // Before the fix, this would log `target=.` and create a new empty
    // terminal session because the stash dict is keyed by lastPathComponent.
    func testOpenRepositoryWithDotSegmentMatchesOpenRepo() throws {
        let vm = RepositoryViewModel()
        let repoRoot = try makeTemporaryRepoDirectory()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        vm.openRepository(repoRoot)
        XCTAssertEqual(vm.repositoryURL, repoRoot)

        // Re-open via a URL with a dot segment in the middle, like the
        // terminal hyperlink handler produces.
        let dotSegmentURL = URL(fileURLWithPath: repoRoot.path + "/./")
        XCTAssertTrue(dotSegmentURL.path.hasSuffix("/."), "Test setup must reproduce trailing-dot URL")
        vm.openRepository(dotSegmentURL)

        XCTAssertEqual(vm.repositoryURL, repoRoot,
                       "Reopen with a dot-segment URL must resolve to the same canonical repo URL")
    }
}
