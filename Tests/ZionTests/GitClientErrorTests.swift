import XCTest
@testable import Zion

final class GitClientErrorTests: XCTestCase {

    // AC 7: stderr containing `fatal: not a git repository` is detected.
    func testNotAGitRepositoryDetection() {
        let positive = [
            "fatal: not a git repository (or any of the parent directories): .git",
            "fatal: not a git repository",
            "some preamble\nfatal: not a git repository (or any parent up to mount point /tmp)\n",
            "FATAL: NOT A GIT REPOSITORY", // case-insensitive
        ]
        for stderr in positive {
            XCTAssertTrue(
                isNotAGitRepoStderr(stderr),
                "Expected true for stderr: \(stderr.prefix(60))..."
            )
        }

        let negative = [
            "",
            "nothing to commit, working tree clean",
            "fatal: Paths with -a does not make sense.",
            "error: pathspec 'foo' did not match any file(s) known to git",
        ]
        for stderr in negative {
            XCTAssertFalse(
                isNotAGitRepoStderr(stderr),
                "Expected false for stderr: \(stderr.prefix(60))..."
            )
        }
    }

    func testGitClientErrorLocalizedDescription() {
        let err: GitClientError = .notAGitRepository
        // Key is looked up in the bundle; if the key is missing we at least get
        // the key string back (Zion's L10n fallback behavior).
        XCTAssertNotNil(err.errorDescription)
    }

    func testGitClientErrorEquatable() {
        XCTAssertEqual(GitClientError.notAGitRepository, GitClientError.notAGitRepository)
        XCTAssertEqual(GitClientError.repositoryNotSelected, GitClientError.repositoryNotSelected)
        XCTAssertNotEqual(GitClientError.notAGitRepository, GitClientError.repositoryNotSelected)
    }
}
