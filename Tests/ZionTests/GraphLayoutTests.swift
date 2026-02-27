import XCTest
@testable import Zion

final class GraphLayoutTests: XCTestCase {
    private let calculator = GitGraphLaneCalculator()

    private func makeCommit(
        hash: String,
        parents: [String] = [],
        decorations: [String] = []
    ) -> ParsedCommit {
        ParsedCommit(
            hash: hash,
            parents: parents,
            author: "Test",
            email: "test@test.com",
            date: Date(),
            subject: "Test commit",
            decorations: decorations
        )
    }

    // MARK: - mainFirstParentChain

    func testMainFirstParentChainLinear() {
        let commits = [
            makeCommit(hash: "c3", parents: ["c2"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "c2", parents: ["c1"]),
            makeCommit(hash: "c1", parents: []),
        ]
        let chain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)

        XCTAssertTrue(chain.contains("c3"))
        XCTAssertTrue(chain.contains("c2"))
        XCTAssertTrue(chain.contains("c1"))
        XCTAssertEqual(chain.count, 3)
    }

    func testMainFirstParentChainFollowsFirstParent() {
        let commits = [
            makeCommit(hash: "c3", parents: ["c2", "branch1"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "c2", parents: ["c1"]),
            makeCommit(hash: "branch1", parents: ["c1"]),
            makeCommit(hash: "c1", parents: []),
        ]
        let chain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)

        XCTAssertTrue(chain.contains("c3"))
        XCTAssertTrue(chain.contains("c2"))
        XCTAssertTrue(chain.contains("c1"))
        XCTAssertFalse(chain.contains("branch1"))
    }

    func testMainFirstParentChainNoHEAD() {
        let commits = [
            makeCommit(hash: "c2", parents: ["c1"]),
            makeCommit(hash: "c1", parents: []),
        ]
        let chain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)

        XCTAssertTrue(chain.isEmpty)
    }

    // MARK: - layout: Linear History

    func testLayoutLinearHistory() {
        let commits = [
            makeCommit(hash: "c3", parents: ["c2"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "c2", parents: ["c1"]),
            makeCommit(hash: "c1", parents: []),
        ]
        let mainChain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)
        let layout = calculator.layout(for: commits, mainChain: mainChain)

        XCTAssertEqual(layout.count, 3)
        // All should be on lane 0 (main chain)
        XCTAssertTrue(layout.allSatisfy { $0.lane == 0 })
    }

    func testLayoutAllMainChainSameColor() {
        let commits = [
            makeCommit(hash: "c3", parents: ["c2"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "c2", parents: ["c1"]),
            makeCommit(hash: "c1", parents: []),
        ]
        let mainChain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)
        let layout = calculator.layout(for: commits, mainChain: mainChain)

        // All main chain commits get colorKey 0
        XCTAssertTrue(layout.allSatisfy { $0.nodeColorKey == 0 })
    }

    // MARK: - layout: Branch Fork

    func testLayoutBranchFork() {
        let commits = [
            makeCommit(hash: "c3", parents: ["c2"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "b1", parents: ["c2"], decorations: ["feature"]),
            makeCommit(hash: "c2", parents: ["c1"]),
            makeCommit(hash: "c1", parents: []),
        ]
        let mainChain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)
        let layout = calculator.layout(for: commits, mainChain: mainChain)
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })

        // Main chain commit should be lane 0
        XCTAssertEqual(layoutByID["c3"]?.lane, 0)
        // Branch commit should be on a different lane
        XCTAssertNotEqual(layoutByID["b1"]?.lane, 0)
    }

    // MARK: - layout: Merge

    func testLayoutMerge() {
        let commits = [
            makeCommit(hash: "merge", parents: ["c2", "b1"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "b1", parents: ["c1"], decorations: ["feature"]),
            makeCommit(hash: "c2", parents: ["c1"]),
            makeCommit(hash: "c1", parents: []),
        ]
        let mainChain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)
        let layout = calculator.layout(for: commits, mainChain: mainChain)
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })

        // Merge commit should have 2 outgoing edges
        XCTAssertEqual(layoutByID["merge"]?.outgoingEdges.count, 2)
    }

    func testLayoutMergeEdgesConnectCorrectly() {
        let commits = [
            makeCommit(hash: "merge", parents: ["c2", "b1"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "b1", parents: ["c1"]),
            makeCommit(hash: "c2", parents: ["c1"]),
            makeCommit(hash: "c1", parents: []),
        ]
        let mainChain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)
        let layout = calculator.layout(for: commits, mainChain: mainChain)
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })

        let mergeEdges = layoutByID["merge"]?.outgoingEdges ?? []
        // All edges start from the merge lane
        let mergeLane = layoutByID["merge"]?.lane ?? -1
        XCTAssertTrue(mergeEdges.allSatisfy { $0.from == mergeLane })
    }

    // MARK: - layout: No Main Chain

    func testLayoutWithoutMainChain() {
        let commits = [
            makeCommit(hash: "c2", parents: ["c1"]),
            makeCommit(hash: "c1", parents: []),
        ]
        let layout = calculator.layout(for: commits, mainChain: [])

        XCTAssertEqual(layout.count, 2)
        // Without main chain, commits should still get reasonable lane assignments
        XCTAssertGreaterThanOrEqual(layout[0].lane, 0)
    }

    // MARK: - layout: Single Commit

    func testLayoutSingleCommit() {
        let commits = [
            makeCommit(hash: "c1", parents: [], decorations: ["HEAD -> main"]),
        ]
        let mainChain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)
        let layout = calculator.layout(for: commits, mainChain: mainChain)

        XCTAssertEqual(layout.count, 1)
        XCTAssertEqual(layout[0].lane, 0)
        XCTAssertTrue(layout[0].outgoingEdges.isEmpty)
    }

    // MARK: - layout: Empty

    func testLayoutEmptyCommits() {
        let layout = calculator.layout(for: [], mainChain: [])
        XCTAssertTrue(layout.isEmpty)
    }

    // MARK: - Lane Colors

    func testLayoutProducesLaneColors() {
        let commits = [
            makeCommit(hash: "c2", parents: ["c1"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "c1", parents: []),
        ]
        let mainChain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)
        let layout = calculator.layout(for: commits, mainChain: mainChain)

        // Each row should have at least one lane color entry
        XCTAssertTrue(layout.allSatisfy { !$0.laneColors.isEmpty })
    }
}
