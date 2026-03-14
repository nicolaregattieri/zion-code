import XCTest
@testable import Zion

final class ContextualFeatureTourTests: XCTestCase {
    func testFirstRepositoryTourAutoStartsOnlyBeforeAnyRepositoryWasOpened() {
        XCTAssertTrue(
            FeatureTourLaunchPolicy.shouldAutoStartFirstRepositoryTour(
                hasOpenedRepositoryOnce: false,
                hasCompletedFeatureTour: false
            )
        )

        XCTAssertFalse(
            FeatureTourLaunchPolicy.shouldAutoStartFirstRepositoryTour(
                hasOpenedRepositoryOnce: true,
                hasCompletedFeatureTour: false
            )
        )
    }

    func testFirstRepositoryTourDoesNotAutoStartAfterTourWasAlreadyCompleted() {
        XCTAssertFalse(
            FeatureTourLaunchPolicy.shouldAutoStartFirstRepositoryTour(
                hasOpenedRepositoryOnce: false,
                hasCompletedFeatureTour: true
            )
        )
    }

    func testExistingHistoryInferenceUsesStoredRecentsData() {
        XCTAssertFalse(FeatureTourLaunchPolicy.inferredExistingRepositoryHistory(from: nil))
        XCTAssertFalse(FeatureTourLaunchPolicy.inferredExistingRepositoryHistory(from: Data()))
        XCTAssertTrue(FeatureTourLaunchPolicy.inferredExistingRepositoryHistory(from: Data([0x01])))
    }

    func testFeatureTourStepOrderMatchesCuratedWalkthrough() {
        XCTAssertEqual(
            ContextualFeatureTourStep.allCases,
            [.recentRepositories, .workspace, .worktrees, .zenToolbar, .treeHeader]
        )
    }

    func testStepSectionRequirements() {
        XCTAssertEqual(ContextualFeatureTourStep.recentRepositories.requiredSection, .code)
        XCTAssertEqual(ContextualFeatureTourStep.workspace.requiredSection, .code)
        XCTAssertEqual(ContextualFeatureTourStep.worktrees.requiredSection, .code)
        XCTAssertEqual(ContextualFeatureTourStep.zenToolbar.requiredSection, .code)
        XCTAssertEqual(ContextualFeatureTourStep.treeHeader.requiredSection, .graph)
    }

    func testOnlyWorktreesStepCarriesOptionalAIMessage() {
        XCTAssertNil(ContextualFeatureTourStep.recentRepositories.supplementaryKey)
        XCTAssertNil(ContextualFeatureTourStep.workspace.supplementaryKey)
        XCTAssertNil(ContextualFeatureTourStep.treeHeader.supplementaryKey)
        XCTAssertNil(ContextualFeatureTourStep.zenToolbar.supplementaryKey)
        XCTAssertEqual(ContextualFeatureTourStep.worktrees.supplementaryKey, "featureTour.ai.optional")
    }
}
