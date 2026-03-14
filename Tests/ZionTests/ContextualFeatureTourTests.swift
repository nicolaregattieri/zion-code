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
            [.recentRepositories, .workspace, .treeHeader, .zenToolbar, .worktrees]
        )
    }

    func testOnlyTreeStepRequiresGraphSection() {
        XCTAssertNil(ContextualFeatureTourStep.recentRepositories.requiredSection)
        XCTAssertNil(ContextualFeatureTourStep.workspace.requiredSection)
        XCTAssertEqual(ContextualFeatureTourStep.treeHeader.requiredSection, .graph)
        XCTAssertNil(ContextualFeatureTourStep.zenToolbar.requiredSection)
        XCTAssertNil(ContextualFeatureTourStep.worktrees.requiredSection)
    }

    func testOnlyFinalStepCarriesOptionalAIMessage() {
        XCTAssertNil(ContextualFeatureTourStep.recentRepositories.supplementaryKey)
        XCTAssertNil(ContextualFeatureTourStep.workspace.supplementaryKey)
        XCTAssertNil(ContextualFeatureTourStep.treeHeader.supplementaryKey)
        XCTAssertNil(ContextualFeatureTourStep.zenToolbar.supplementaryKey)
        XCTAssertEqual(ContextualFeatureTourStep.worktrees.supplementaryKey, "featureTour.ai.optional")
    }
}
