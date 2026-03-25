import XCTest
@testable import Zion

@MainActor
final class RepositoryViewModelNavigationTests: XCTestCase {

    func testNonGitFolderStillAllowsCodeSection() {
        let vm = RepositoryViewModel()
        vm.repositoryURL = URL(fileURLWithPath: "/tmp/project")
        vm.isGitRepository = false

        XCTAssertTrue(vm.canAccess(.code))
        XCTAssertTrue(vm.canAccess(.graph))
        XCTAssertTrue(vm.canAccess(.operations))
    }

    func testGitRepositoryAllowsAllSections() {
        let vm = RepositoryViewModel()
        vm.repositoryURL = URL(fileURLWithPath: "/tmp/project")
        vm.isGitRepository = true

        XCTAssertTrue(vm.canAccess(.code))
        XCTAssertTrue(vm.canAccess(.graph))
        XCTAssertTrue(vm.canAccess(.operations))
    }

    func testNoWorkspaceOnlyAllowsCodeSection() {
        let vm = RepositoryViewModel()

        XCTAssertTrue(vm.canAccess(.code))
        XCTAssertFalse(vm.canAccess(.graph))
        XCTAssertFalse(vm.canAccess(.operations))
    }
}
