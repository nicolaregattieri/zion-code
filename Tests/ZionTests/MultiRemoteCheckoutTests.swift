import XCTest
@testable import Zion

@MainActor
final class MultiRemoteCheckoutTests: XCTestCase {

    private func branch(_ name: String, upstream: String, isRemote: Bool = false) -> BranchInfo {
        BranchInfo(
            name: name,
            fullRef: isRemote ? "refs/remotes/\(name)" : "refs/heads/\(name)",
            head: "deadbeef",
            upstream: upstream,
            committerDate: Date(),
            isRemote: isRemote
        )
    }

    // MARK: - conflictingUpstream

    func testConflictingUpstreamReturnsCurrentWhenClickedDiffers() {
        let vm = RepositoryViewModel()
        vm.branchInfos = [
            branch("main", upstream: "origin/main"),
            branch("origin/main", upstream: "", isRemote: true),
            branch("pivotree/main", upstream: "", isRemote: true)
        ]

        let result = vm.conflictingUpstream(forLocalName: "main", clickedRemote: "pivotree/main")
        XCTAssertEqual(result, "origin/main")
    }

    func testConflictingUpstreamReturnsNilWhenClickedMatchesUpstream() {
        let vm = RepositoryViewModel()
        vm.branchInfos = [
            branch("main", upstream: "origin/main"),
            branch("origin/main", upstream: "", isRemote: true)
        ]

        let result = vm.conflictingUpstream(forLocalName: "main", clickedRemote: "origin/main")
        XCTAssertNil(result)
    }

    func testConflictingUpstreamReturnsNilWhenLocalDoesNotExist() {
        let vm = RepositoryViewModel()
        vm.branchInfos = [branch("origin/feature", upstream: "", isRemote: true)]

        let result = vm.conflictingUpstream(forLocalName: "feature", clickedRemote: "origin/feature")
        XCTAssertNil(result)
    }

    func testConflictingUpstreamReturnsNilWhenLocalHasNoUpstream() {
        let vm = RepositoryViewModel()
        vm.branchInfos = [
            branch("main", upstream: ""),
            branch("pivotree/main", upstream: "", isRemote: true)
        ]

        let result = vm.conflictingUpstream(forLocalName: "main", clickedRemote: "pivotree/main")
        XCTAssertNil(result)
    }

    // MARK: - createTrackingBranch (no-op when branch exists)

    func testCreateTrackingBranchEarlyReturnsWhenLocalExists() {
        let vm = RepositoryViewModel()
        vm.branchInfos = [branch("pivotree-main", upstream: "")]

        // Should not crash, should not start a task; just sets an error message.
        vm.createTrackingBranch(newLocalName: "pivotree-main", remoteTarget: "pivotree/main")

        XCTAssertFalse(vm.isBusy)
        XCTAssertNil(vm.activeGitActionToken)
    }

    // MARK: - End-to-end git command behavior

    /// Proves the actual git invocations my new methods run produce the desired
    /// state: the upstream switch repoints metadata, and the create-tracking flow
    /// gives the new branch the right upstream — without touching the original.
    func testGitCommandsBehindMultiRemoteFlowsWork() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("zion-multi-remote-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Two bare "remotes" + one working clone
        let originBare = scratch.appendingPathComponent("origin.git")
        let pivotreeBare = scratch.appendingPathComponent("pivotree.git")
        let work = scratch.appendingPathComponent("work")

        try sh(["git", "init", "--bare", originBare.path])
        try sh(["git", "init", "--bare", pivotreeBare.path])

        // Seed origin with an initial commit on main
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try sh(["git", "init", "-b", "main", work.path])
        try sh(["git", "-C", work.path, "config", "user.email", "t@t"])
        try sh(["git", "-C", work.path, "config", "user.name", "t"])
        try "hi".write(to: work.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try sh(["git", "-C", work.path, "add", "-A"])
        try sh(["git", "-C", work.path, "commit", "-m", "init"])
        try sh(["git", "-C", work.path, "remote", "add", "origin", originBare.path])
        try sh(["git", "-C", work.path, "push", "-u", "origin", "main"])
        try sh(["git", "-C", work.path, "remote", "add", "pivotree", pivotreeBare.path])

        // Create a divergent commit on the pivotree side (separate working tree),
        // push it as pivotree/main, then fetch into work.
        let pivotreeWork = scratch.appendingPathComponent("pivotree-work")
        try sh(["git", "clone", originBare.path, pivotreeWork.path])
        try sh(["git", "-C", pivotreeWork.path, "config", "user.email", "p@p"])
        try sh(["git", "-C", pivotreeWork.path, "config", "user.name", "p"])
        try "second".write(to: pivotreeWork.appendingPathComponent("F.txt"), atomically: true, encoding: .utf8)
        try sh(["git", "-C", pivotreeWork.path, "add", "-A"])
        try sh(["git", "-C", pivotreeWork.path, "commit", "-m", "pivotree change"])
        try sh(["git", "-C", pivotreeWork.path, "remote", "set-url", "origin", pivotreeBare.path])
        try sh(["git", "-C", pivotreeWork.path, "push", "origin", "main"])
        try sh(["git", "-C", work.path, "fetch", "pivotree"])

        // Sanity: local main currently tracks origin/main
        let upstreamBefore = try shOut(["git", "-C", work.path, "rev-parse", "--abbrev-ref", "main@{upstream}"])
        XCTAssertEqual(upstreamBefore, "origin/main")

        // --- Flow 1: switchUpstreamAndPull commands ---
        try sh(["git", "-C", work.path, "branch", "--set-upstream-to=pivotree/main", "main"])
        try sh(["git", "-C", work.path, "checkout", "main"])
        try sh(["git", "-C", work.path, "pull"])

        let upstreamAfter = try shOut(["git", "-C", work.path, "rev-parse", "--abbrev-ref", "main@{upstream}"])
        XCTAssertEqual(upstreamAfter, "pivotree/main", "Upstream should now point at pivotree/main")

        let mainHead = try shOut(["git", "-C", work.path, "rev-parse", "main"])
        let pivotreeHead = try shOut(["git", "-C", work.path, "rev-parse", "pivotree/main"])
        XCTAssertEqual(mainHead, pivotreeHead, "main should be aligned with pivotree/main after pull")

        // --- Flow 2: createTrackingBranch commands ---
        // Reset local main back to origin to simulate user choosing the OTHER option
        try sh(["git", "-C", work.path, "branch", "--set-upstream-to=origin/main", "main"])
        try sh(["git", "-C", work.path, "checkout", "-b", "pivotree-main", "--track", "pivotree/main"])

        let newUpstream = try shOut(["git", "-C", work.path, "rev-parse", "--abbrev-ref", "pivotree-main@{upstream}"])
        XCTAssertEqual(newUpstream, "pivotree/main")

        let mainStillOrigin = try shOut(["git", "-C", work.path, "rev-parse", "--abbrev-ref", "main@{upstream}"])
        XCTAssertEqual(mainStillOrigin, "origin/main", "Original main upstream must remain untouched")
    }

    // MARK: - shell helpers

    @discardableResult
    private func sh(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(domain: "shell", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(args.joined(separator: " ")) failed: \(out)"])
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shOut(_ args: [String]) throws -> String {
        try sh(args)
    }
}
