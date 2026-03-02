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

    // MARK: - Main Chain Lane 0 Enforcement

    func testMainChainStaysAtLaneZeroThroughSequentialMerges() {
        // Topology (newest first):
        //   merge3 ---> merge2 ---> merge1 ---> base
        //     \            \            \
        //   feat-c       feat-b       feat-a
        //     |            |            |
        //   feat-c-base  feat-b-base  base (fork point)
        //
        // feat-c forks from merge1 (not merge2), so when processing feat-c-base's
        // parent reservation, merge1 could get displaced from lane 0.
        let commits = [
            makeCommit(hash: "merge3", parents: ["merge2", "feat-c"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "feat-c", parents: ["feat-c-base"], decorations: ["feature-c"]),
            makeCommit(hash: "feat-c-base", parents: ["merge1"]),
            makeCommit(hash: "merge2", parents: ["merge1", "feat-b"], decorations: []),
            makeCommit(hash: "feat-b", parents: ["feat-b-base"], decorations: ["feature-b"]),
            makeCommit(hash: "feat-b-base", parents: ["base"]),
            makeCommit(hash: "merge1", parents: ["base", "feat-a"], decorations: []),
            makeCommit(hash: "feat-a", parents: ["base"], decorations: ["feature-a"]),
            makeCommit(hash: "base", parents: []),
        ]
        let mainChain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)
        let layout = calculator.layout(for: commits, mainChain: mainChain)
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })

        // Every main-chain commit must be at lane 0
        let mainHashes = ["merge3", "merge2", "merge1", "base"]
        for hash in mainHashes {
            XCTAssertEqual(layoutByID[hash]?.lane, 0, "\(hash) should be at lane 0")
        }

        // Feature commits must NOT be at lane 0
        let featureHashes = ["feat-c", "feat-c-base", "feat-b", "feat-b-base", "feat-a"]
        for hash in featureHashes {
            XCTAssertNotEqual(layoutByID[hash]?.lane, 0, "\(hash) should not be at lane 0")
        }
    }

    func testMainChainLaneZeroWithLongLivedBranch() {
        // Long-lived branch with multiple commits between merge points:
        //   merge ---> m3 ---> m2 ---> m1 ---> base
        //     \
        //   f5 -> f4 -> f3 -> f2 -> f1
        //                              \
        //                             base (fork)
        let commits = [
            makeCommit(hash: "merge", parents: ["m3", "f5"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "f5", parents: ["f4"], decorations: ["long-lived"]),
            makeCommit(hash: "f4", parents: ["f3"]),
            makeCommit(hash: "f3", parents: ["f2"]),
            makeCommit(hash: "m3", parents: ["m2"]),
            makeCommit(hash: "f2", parents: ["f1"]),
            makeCommit(hash: "m2", parents: ["m1"]),
            makeCommit(hash: "f1", parents: ["base"]),
            makeCommit(hash: "m1", parents: ["base"]),
            makeCommit(hash: "base", parents: []),
        ]
        let mainChain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)
        let layout = calculator.layout(for: commits, mainChain: mainChain)
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })

        // All main-chain commits at lane 0
        for hash in ["merge", "m3", "m2", "m1", "base"] {
            XCTAssertEqual(layoutByID[hash]?.lane, 0, "\(hash) should be at lane 0")
        }

        // All main-chain commits share color key 0
        for hash in ["merge", "m3", "m2", "m1", "base"] {
            XCTAssertEqual(layoutByID[hash]?.nodeColorKey, 0, "\(hash) should have colorKey 0")
        }
    }

    // MARK: - Merge Edge Eviction Regression

    func testMergeEdgesPointToDistinctLanesAfterEviction() {
        // Reproduces the bug: merge commit with two mainChain parents.
        // Parent 7831c34 is reserved at lane 0, then 7f16d84 evicts it to lane 1.
        // Before the fix, the edge for 7831c34 still pointed to lane 0 (stale).
        let commits = [
            makeCommit(hash: "2e0f174", parents: ["7831c34", "7f16d84"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "7831c34", parents: ["base"]),
            makeCommit(hash: "7f16d84", parents: ["base"]),
            makeCommit(hash: "base", parents: []),
        ]
        let mainChain: Set<String> = ["2e0f174", "7831c34", "7f16d84", "base"]
        let layout = calculator.layout(for: commits, mainChain: mainChain)
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })

        let mergeEdges = layoutByID["2e0f174"]?.outgoingEdges ?? []
        XCTAssertEqual(mergeEdges.count, 2, "Merge should have 2 outgoing edges")

        let targetLanes = Set(mergeEdges.map(\.to))
        XCTAssertEqual(targetLanes.count, 2, "Edges must point to 2 distinct lanes (was broken by stale eviction)")

        // Each edge target must match the actual lane of its parent
        let p1Lane = layoutByID["7831c34"]?.lane
        let p2Lane = layoutByID["7f16d84"]?.lane
        XCTAssertTrue(targetLanes.contains(p1Lane!), "Edge must reach 7831c34 at lane \(p1Lane!)")
        XCTAssertTrue(targetLanes.contains(p2Lane!), "Edge must reach 7f16d84 at lane \(p2Lane!)")
    }

    func testOctopusMergeEdgesAllDistinct() {
        // 3-parent merge where all parents are mainChain — verifies the fix generalizes.
        let commits = [
            makeCommit(hash: "octopus", parents: ["p1", "p2", "p3"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "p1", parents: ["root"]),
            makeCommit(hash: "p2", parents: ["root"]),
            makeCommit(hash: "p3", parents: ["root"]),
            makeCommit(hash: "root", parents: []),
        ]
        let mainChain: Set<String> = ["octopus", "p1", "p2", "p3", "root"]
        let layout = calculator.layout(for: commits, mainChain: mainChain)
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })

        let edges = layoutByID["octopus"]?.outgoingEdges ?? []
        XCTAssertEqual(edges.count, 3, "Octopus merge should have 3 outgoing edges")

        let targetLanes = Set(edges.map(\.to))
        XCTAssertEqual(targetLanes.count, 3, "All 3 edges must point to distinct lanes")

        // Each edge must reach the actual lane of its parent
        for parentHash in ["p1", "p2", "p3"] {
            guard let parentLane = layoutByID[parentHash]?.lane else {
                XCTFail("\(parentHash) missing from layout")
                continue
            }
            XCTAssertTrue(targetLanes.contains(parentLane), "Edge must reach \(parentHash) at lane \(parentLane)")
        }
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
