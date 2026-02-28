import XCTest
@testable import Zion

@MainActor
final class RepositoryViewModelAITests: XCTestCase {

    // MARK: - generateCommitMessage (static heuristic)

    func testSingleNewFileProducesFeat() {
        let status = "?? Sources/login.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("feat"), "Expected 'feat' type for new file, got: \(result)")
        XCTAssertTrue(result.contains("login"), "Expected filename 'login' in message, got: \(result)")
    }

    func testSingleModifiedFileProducesType() {
        let status = " M Sources/Helpers/utils.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        // With 0 added and 1 modified, modified > added => "fix"
        XCTAssertTrue(result.contains("fix") || result.contains("feat"),
                       "Expected 'fix' or 'feat' for modified file, got: \(result)")
        XCTAssertTrue(result.contains("utils"), "Expected filename 'utils' in message, got: \(result)")
    }

    func testMultipleFilesWithMixedTypes() {
        let status = "A  src/a.swift\n M src/b.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("2 files"), "Expected '2 files' in message, got: \(result)")
        XCTAssertTrue(result.contains("(src)"), "Expected scope '(src)', got: \(result)")
    }

    func testOnlyDeletionsProducesChore() {
        let status = " D old.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("chore"), "Expected 'chore' for deletions, got: \(result)")
    }

    func testTestFilesProducesTestType() {
        // Use "M " (modified) so the else branch is reached where allSatisfy test-file check runs
        let status = " M Tests/MyTest.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("test"), "Expected 'test' type for test files, got: \(result)")
    }

    func testDocFilesProducesDocsType() {
        // Use "M " (modified) so the else branch is reached where allSatisfy doc-file check runs
        let status = " M README.md"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("docs"), "Expected 'docs' type for .md files, got: \(result)")
    }

    func testEmptyStatusReturnsEmptyString() {
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: "")

        XCTAssertEqual(result, "", "Expected empty string for empty status")
    }

    func testSingleAddedFileContainsAddVerb() {
        let status = "A  Sources/NewFeature.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("add"), "Expected 'add' verb for new file, got: \(result)")
        XCTAssertTrue(result.contains("NewFeature"), "Expected 'NewFeature' in message, got: \(result)")
    }

    func testSingleModifiedFileContainsUpdateVerb() {
        let status = " M Sources/Existing.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("update"), "Expected 'update' verb for modified file, got: \(result)")
    }

    func testScopeFromCommonDirectory() {
        let status = "A  Views/Login/LoginView.swift\nA  Views/Login/LoginModel.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        // The most common directory component (after dropping filename) should be "Login"
        XCTAssertTrue(result.contains("(Login)") || result.contains("(Views)"),
                       "Expected scope from common directory, got: \(result)")
    }

    // MARK: - dismissPreCommitReview

    func testDismissPreCommitReviewResetsState() {
        let vm = RepositoryViewModel()
        vm.preCommitReviewPending = true
        vm.isReviewVisible = true

        vm.dismissPreCommitReview()

        XCTAssertFalse(vm.preCommitReviewPending, "preCommitReviewPending should be false after dismiss")
        XCTAssertFalse(vm.isReviewVisible, "isReviewVisible should be false after dismiss")
    }

    // MARK: - clearSemanticSearch

    func testClearSemanticSearchResetsState() {
        let vm = RepositoryViewModel()
        vm.aiSemanticSearchResults = ["abc123", "def456"]
        vm.isSemanticSearchActive = true

        vm.clearSemanticSearch()

        XCTAssertTrue(vm.aiSemanticSearchResults.isEmpty, "aiSemanticSearchResults should be empty after clear")
        XCTAssertFalse(vm.isSemanticSearchActive, "isSemanticSearchActive should be false after clear")
    }
}
