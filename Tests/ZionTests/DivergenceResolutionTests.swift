import XCTest
@testable import Zion

@MainActor
final class DivergenceResolutionTests: XCTestCase {

    // MARK: - DivergenceContext

    func testDivergenceContextIdentifiable() {
        let ctx = DivergenceContext(branch: "main", localAhead: 3, remoteAhead: 2)
        XCTAssertEqual(ctx.branch, "main")
        XCTAssertEqual(ctx.localAhead, 3)
        XCTAssertEqual(ctx.remoteAhead, 2)
        XCTAssertNotNil(ctx.id)
    }

    func testDivergenceContextUniqueIDs() {
        let a = DivergenceContext(branch: "main", localAhead: 1, remoteAhead: 1)
        let b = DivergenceContext(branch: "main", localAhead: 1, remoteAhead: 1)
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - isDivergentBranchError

    func testIsDivergentBranchErrorDetectsDivergentBranches() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(
            command: "pull",
            message: "hint: You have divergent branches and need to specify how to reconcile them."
        )
        XCTAssertTrue(vm.isDivergentBranchError(error))
    }

    func testIsDivergentBranchErrorDetectsReconcileMessage() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(
            command: "pull",
            message: "fatal: Need to specify how to reconcile divergent branches."
        )
        XCTAssertTrue(vm.isDivergentBranchError(error))
    }

    func testIsDivergentBranchErrorReturnsFalseForUnrelated() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(
            command: "pull",
            message: "Already up to date."
        )
        XCTAssertFalse(vm.isDivergentBranchError(error))
    }

    func testIsDivergentBranchErrorReturnsFalseForNonGitError() {
        let vm = RepositoryViewModel()
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "network error"])
        XCTAssertFalse(vm.isDivergentBranchError(error))
    }

    // MARK: - resolveDivergence sets state

    func testResolveDivergenceRebaseClearsDivergenceAndSetsBusy() {
        let vm = RepositoryViewModel()
        let ctx = DivergenceContext(branch: "main", localAhead: 1, remoteAhead: 2)
        vm.divergenceResolution = ctx

        // Without a repo, runGitAction will set lastError but divergenceResolution should be cleared
        vm.resolveDivergence(.rebase, context: ctx)

        XCTAssertNil(vm.divergenceResolution, "divergenceResolution should be cleared after resolution")
    }

    func testResolveDivergenceMergeClearsDivergence() {
        let vm = RepositoryViewModel()
        let ctx = DivergenceContext(branch: "main", localAhead: 1, remoteAhead: 2)
        vm.divergenceResolution = ctx

        vm.resolveDivergence(.merge, context: ctx)

        XCTAssertNil(vm.divergenceResolution)
    }

    func testResolveDivergenceForceAlignClearsDivergence() {
        let vm = RepositoryViewModel()
        let ctx = DivergenceContext(branch: "main", localAhead: 1, remoteAhead: 2)
        vm.divergenceResolution = ctx

        vm.resolveDivergence(.forceAlign, context: ctx)

        XCTAssertNil(vm.divergenceResolution)
    }

    // MARK: - Busy Watchdog

    func testArmBusyWatchdogSetsTask() {
        let vm = RepositoryViewModel()
        XCTAssertNil(vm.busyWatchdogTask)

        vm.armBusyWatchdog()

        XCTAssertNotNil(vm.busyWatchdogTask)
    }

    func testDisarmBusyWatchdogClearsTask() {
        let vm = RepositoryViewModel()
        vm.armBusyWatchdog()
        XCTAssertNotNil(vm.busyWatchdogTask)

        vm.disarmBusyWatchdog()

        XCTAssertNil(vm.busyWatchdogTask)
    }

    func testDisarmBusyWatchdogIdempotent() {
        let vm = RepositoryViewModel()
        vm.disarmBusyWatchdog()
        XCTAssertNil(vm.busyWatchdogTask)
    }

    func testArmBusyWatchdogCancelsPreviousWatchdog() {
        let vm = RepositoryViewModel()
        vm.armBusyWatchdog()
        let first = vm.busyWatchdogTask

        vm.armBusyWatchdog()
        let second = vm.busyWatchdogTask

        XCTAssertNotNil(second)
        XCTAssertTrue(first?.isCancelled ?? false, "Previous watchdog should be cancelled")
    }

    // MARK: - Busy watchdog timeout constant

    func testBusyWatchdogTimeoutIs60Seconds() {
        XCTAssertEqual(Constants.Timing.busyWatchdogTimeout, 60_000_000_000)
    }

    // MARK: - L10n keys exist

    func testDivergenceL10nKeysResolve() {
        // Verify keys don't return the raw key (which means they're missing)
        let title = L10n("divergence.title")
        XCTAssertNotEqual(title, "divergence.title", "L10n key 'divergence.title' should be defined")

        let subtitle = L10n("divergence.subtitle", "main")
        XCTAssertFalse(subtitle.isEmpty)

        let rebase = L10n("divergence.option.rebase")
        XCTAssertNotEqual(rebase, "divergence.option.rebase")

        let merge = L10n("divergence.option.merge")
        XCTAssertNotEqual(merge, "divergence.option.merge")

        let forceAlign = L10n("divergence.option.forceAlign")
        XCTAssertNotEqual(forceAlign, "divergence.option.forceAlign")
    }

    func testDivergenceAheadBehindL10nFormats() {
        let localAhead = L10n("divergence.localAhead", 3)
        XCTAssertTrue(localAhead.contains("3"), "Should interpolate count into localAhead string")

        let remoteAhead = L10n("divergence.remoteAhead", 5)
        XCTAssertTrue(remoteAhead.contains("5"), "Should interpolate count into remoteAhead string")
    }
}
