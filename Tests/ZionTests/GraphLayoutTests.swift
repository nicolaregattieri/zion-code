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

    func testMainFirstParentChainPrefersMainOverHeadFeatureBranch() {
        let commits = [
            makeCommit(hash: "feature-tip", parents: ["feature-base"], decorations: ["HEAD -> feature/test"]),
            makeCommit(hash: "main-tip", parents: ["main-base"], decorations: ["main"]),
            makeCommit(hash: "feature-base", parents: ["fork"]),
            makeCommit(hash: "main-base", parents: ["fork"]),
            makeCommit(hash: "fork", parents: []),
        ]

        let chain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)

        XCTAssertTrue(chain.contains("main-tip"))
        XCTAssertTrue(chain.contains("main-base"))
        XCTAssertTrue(chain.contains("fork"))
        XCTAssertFalse(chain.contains("feature-tip"))
        XCTAssertFalse(chain.contains("feature-base"))
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

    // MARK: - Merge Edge & Virtual Reservation

    func testMergeWithTwoMainChainParentsEdgesAllReachLaneZero() {
        // Two mainChain parents: the second uses a virtual reservation instead
        // of evicting the first. Both edges should target lane 0 (the main line).
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

        // Both mainChain parents should be reached at lane 0
        XCTAssertTrue(mergeEdges.allSatisfy { $0.to == 0 },
                       "Both edges should target lane 0 (main line)")

        // Both parents should be at lane 0 when processed
        XCTAssertEqual(layoutByID["7831c34"]?.lane, 0)
        XCTAssertEqual(layoutByID["7f16d84"]?.lane, 0)
    }

    func testOctopusMergeMainChainParentsAllTargetLaneZero() {
        // 3-parent merge where all parents are mainChain.
        // Virtual reservation ensures no eviction — all edges target lane 0.
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

        // All mainChain parents target lane 0
        XCTAssertTrue(edges.allSatisfy { $0.to == 0 },
                       "All edges should target lane 0 (main line)")

        // All parents should be at lane 0 when processed
        for hash in ["p1", "p2", "p3"] {
            XCTAssertEqual(layoutByID[hash]?.lane, 0, "\(hash) should be at lane 0")
        }
    }

    // MARK: - Branch Tip Spike Prevention

    func testBranchTipNoDownwardSpike() {
        // Branch tip's mainChain parent uses virtual reservation instead
        // of evicting the existing mainChain commit from lane 0.
        // No spike (evicted commit at tip's lane) or orphan line.
        let commits = [
            makeCommit(hash: "merge", parents: ["fp", "tip"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "tip", parents: ["far"]),
            makeCommit(hash: "fp", parents: ["far"]),
            makeCommit(hash: "far", parents: ["root"]),
            makeCommit(hash: "root", parents: []),
        ]
        let mainChain: Set<String> = ["merge", "fp", "far", "root"]
        let layout = calculator.layout(for: commits, mainChain: mainChain)
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })

        let tipLayout = layoutByID["tip"]!

        // Branch tip should NOT have its own lane in outgoingLanes
        // (parent is mainChain at lane 0, connected via cross-lane edge)
        XCTAssertFalse(
            tipLayout.outgoingLanes.contains(tipLayout.lane),
            "Branch tip should not have downward spike at lane \(tipLayout.lane)"
        )

        // The edge from the tip should go to lane 0 (main line)
        XCTAssertEqual(tipLayout.outgoingEdges.count, 1)
        XCTAssertEqual(tipLayout.outgoingEdges.first?.to, 0,
                       "Branch tip edge should target lane 0")
    }

    func testBranchTipSpikeWithRealTopology() {
        // Full topology from the actual repo that showed the spike:
        //   merge35 [merge34, test_mobile]
        //   test_mobile [feat_mobile]
        //   merge34 [merge33, docs_sync]      ← docs_sync spike here
        //   docs_sync [merge32]
        //   merge33 [merge32, feat_mobile]
        //   feat_mobile [merge32]
        //   merge32 [base]
        let commits = [
            makeCommit(hash: "merge35", parents: ["merge34", "test_mobile"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "test_mobile", parents: ["feat_mobile"]),
            makeCommit(hash: "merge34", parents: ["merge33", "docs_sync"]),
            makeCommit(hash: "docs_sync", parents: ["merge32"]),
            makeCommit(hash: "merge33", parents: ["merge32", "feat_mobile"]),
            makeCommit(hash: "feat_mobile", parents: ["merge32"]),
            makeCommit(hash: "merge32", parents: ["base"]),
            makeCommit(hash: "base", parents: []),
        ]
        let mainChain: Set<String> = ["merge35", "merge34", "merge33", "merge32", "base"]
        let layout = calculator.layout(for: commits, mainChain: mainChain)
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })

        // docs_sync is a branch tip — no spike at its own lane
        let docsLayout = layoutByID["docs_sync"]!
        let docsHasContinuation = docsLayout.outgoingEdges.contains {
            $0.from == docsLayout.lane && $0.to == docsLayout.lane
        }
        if !docsHasContinuation {
            XCTAssertFalse(
                docsLayout.outgoingLanes.contains(docsLayout.lane),
                "docs_sync should not have downward spike at lane \(docsLayout.lane)"
            )
        }

        // All mainChain commits must still be at lane 0
        for hash in ["merge35", "merge34", "merge33", "merge32", "base"] {
            XCTAssertEqual(layoutByID[hash]?.lane, 0, "\(hash) should be at lane 0")
        }
    }

    func testNestedSideBranchDoesNotLeaveDuplicateParallelLane() throws {
        // Reference shape:
        //   main-tip
        //   fresh-store   (forks from first-run tip)
        //   first-run-tip
        //   first-run-2
        //   first-run-1
        //   main-3
        //   main-2
        //   main-1
        //   fork
        //
        // Expected behavior:
        // once the nested branch tip is consumed, the graph should keep only
        // a single non-main side lane alive for the long-lived first-run branch.
        let commits = [
            makeCommit(hash: "main-tip", parents: ["main-3"], decorations: ["HEAD -> main"]),
            makeCommit(hash: "fresh-store", parents: ["first-run-tip"], decorations: ["simulate/fresh-store"]),
            makeCommit(hash: "first-run-tip", parents: ["first-run-2"], decorations: ["simulate/first-run"]),
            makeCommit(hash: "first-run-2", parents: ["first-run-1"]),
            makeCommit(hash: "first-run-1", parents: ["fork"]),
            makeCommit(hash: "main-3", parents: ["main-2"]),
            makeCommit(hash: "main-2", parents: ["main-1"]),
            makeCommit(hash: "main-1", parents: ["fork"]),
            makeCommit(hash: "fork", parents: []),
        ]

        let mainChain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)
        let layout = calculator.layout(for: commits, mainChain: mainChain)
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })

        for hash in ["main-tip", "main-3", "main-2", "main-1", "fork"] {
            XCTAssertEqual(layoutByID[hash]?.lane, 0, "\(hash) should stay on lane 0")
        }

        for hash in ["first-run-tip", "first-run-2", "first-run-1"] {
            let row = try XCTUnwrap(layoutByID[hash], "\(hash) should exist in layout")
            let activeSideLanes = Set(row.outgoingLanes.filter { $0 != 0 })
            XCTAssertLessThanOrEqual(
                activeSideLanes.count,
                1,
                "\(hash) should keep only one active non-main lane, got \(activeSideLanes)"
            )
        }
    }

    func testAiShopifyPlanTopologyCollapsesTipBranchesBackToSingleSideLane() throws {
        let commits = [
            makeCommit(hash: "ff800d6", parents: ["65d5aa7"], decorations: ["main"]),
            makeCommit(hash: "65d5aa7", parents: ["23fb3d8"]),
            makeCommit(hash: "23fb3d8", parents: ["cd23506"]),
            makeCommit(hash: "cd23506", parents: ["c64b917"]),
            makeCommit(hash: "c64b917", parents: ["1236fd8"]),
            makeCommit(hash: "1236fd8", parents: ["353793a"], decorations: ["tag: boilerplate"]),
            makeCommit(hash: "6146eef", parents: ["6d5ba48"], decorations: ["simulate/fresh-store"]),
            makeCommit(hash: "0d04fb5", parents: ["6d5ba48"], decorations: ["HEAD -> simulate/first-run"]),
            makeCommit(hash: "6d5ba48", parents: ["b0c0968"]),
            makeCommit(hash: "b0c0968", parents: ["d211a9a"]),
            makeCommit(hash: "d211a9a", parents: ["9f089f8"]),
            makeCommit(hash: "e8084d1", parents: ["9f089f8", "c9ca8b7"], decorations: ["refs/stash"]),
            makeCommit(hash: "c9ca8b7", parents: ["9f089f8"]),
            makeCommit(hash: "9f089f8", parents: ["d729fb6"]),
            makeCommit(hash: "d729fb6", parents: ["64e0c97"]),
            makeCommit(hash: "64e0c97", parents: ["f01cc56"]),
            makeCommit(hash: "f01cc56", parents: ["27faca3"]),
            makeCommit(hash: "27faca3", parents: ["002ad89"]),
            makeCommit(hash: "002ad89", parents: ["40b12c4"]),
            makeCommit(hash: "40b12c4", parents: ["353793a"]),
            makeCommit(hash: "353793a", parents: []),
        ]

        let mainChain = GitGraphLaneCalculator.mainFirstParentChain(from: commits)
        let layout = calculator.layout(for: commits, mainChain: mainChain)
        let layoutByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })

        for hash in ["ff800d6", "65d5aa7", "23fb3d8", "cd23506", "c64b917", "1236fd8", "353793a"] {
            XCTAssertEqual(layoutByID[hash]?.lane, 0, "\(hash) should stay on lane 0 as the main branch")
        }

        let firstRunTip = try XCTUnwrap(layoutByID["0d04fb5"])
        XCTAssertEqual(firstRunTip.lane, 2, "The current side-branch tip should occupy its own lane before collapsing")
        XCTAssertEqual(firstRunTip.outgoingEdges.map(\.to), [1], "The current side-branch tip should collapse into the shared side lane")
        XCTAssertEqual(Set(firstRunTip.outgoingLanes.filter { $0 != 0 }).count, 1)

        let sharedSideRow = try XCTUnwrap(layoutByID["6d5ba48"])
        XCTAssertEqual(Set(sharedSideRow.incomingLanes.filter { $0 != 0 }).count, 1, "The two tip refs should already have collapsed into the shared side lane by 6d5ba48")
        XCTAssertEqual(Set(sharedSideRow.outgoingLanes.filter { $0 != 0 }).count, 1, "After 6d5ba48 the history should continue as a single shared side lane")

        let stashWIP = try XCTUnwrap(layoutByID["e8084d1"])
        XCTAssertEqual(Set(stashWIP.outgoingLanes.filter { $0 != 0 }).count, 2, "The stash WIP commit should branch to the shared side lane and the index lane")

        let indexRow = try XCTUnwrap(layoutByID["c9ca8b7"])
        XCTAssertEqual(Set(indexRow.incomingLanes.filter { $0 != 0 }).count, 2, "The index row should receive both stash-related side lanes")
        XCTAssertEqual(Set(indexRow.outgoingLanes.filter { $0 != 0 }).count, 1, "After the index row the stash topology should collapse back to one side lane")

        let stashBaseRow = try XCTUnwrap(layoutByID["9f089f8"])
        XCTAssertEqual(Set(stashBaseRow.incomingLanes.filter { $0 != 0 }).count, 1)
        XCTAssertEqual(Set(stashBaseRow.outgoingLanes.filter { $0 != 0 }).count, 1)
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
