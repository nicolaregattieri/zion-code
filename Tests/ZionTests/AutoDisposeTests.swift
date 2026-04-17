import XCTest
@testable import Zion

@MainActor
final class AutoDisposeTests: XCTestCase {

    // AC 8: markRepositoryDisposed flips the visible + internal flags.
    func testMarkRepositoryDisposedSetsFlags() {
        let vm = RepositoryViewModel()
        XCTAssertFalse(vm.isRepositoryDisposed, "Fresh VM must start non-disposed")
        XCTAssertTrue(vm.isGitRepository, "Fresh VM defaults to isGitRepository true")

        vm.markRepositoryDisposed(reason: "unit-test")

        XCTAssertTrue(vm.isRepositoryDisposed)
        XCTAssertFalse(vm.isGitRepository)
    }

    // AC 8: shouldSkipBecauseDisposed mirrors the flag.
    func testShouldSkipBecauseDisposed() {
        let vm = RepositoryViewModel()
        XCTAssertFalse(vm.shouldSkipBecauseDisposed())

        vm.markRepositoryDisposed(reason: "unit-test")
        XCTAssertTrue(vm.shouldSkipBecauseDisposed())
    }

    // AC 9: clearRepositoryDisposedFlag resets to allow retry after
    // an external `git init`.
    func testReopenClearsDisposedFlag() {
        let vm = RepositoryViewModel()
        vm.markRepositoryDisposed(reason: "unit-test")
        XCTAssertTrue(vm.isRepositoryDisposed)

        vm.clearRepositoryDisposedFlag()

        XCTAssertFalse(vm.isRepositoryDisposed, "Clearing the flag must allow retry")
    }
}
