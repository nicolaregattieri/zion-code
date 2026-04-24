import XCTest
@testable import Zion

@MainActor
final class MultiRemoteSelectionTests: XCTestCase {

    private var sandbox: URL!
    private var vm: RepositoryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("zion_multiremote_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)

        vm = RepositoryViewModel()
        vm.repositoryURL = sandbox
        // Clear any stale preference from a prior test run.
        vm.preferredRemoteName = nil
    }

    override func tearDown() async throws {
        vm.preferredRemoteName = nil
        vm = nil
        try? FileManager.default.removeItem(at: sandbox)
        sandbox = nil
        try await super.tearDown()
    }

    // MARK: - preferredRemoteName persistence

    func testPreferredRemoteNameRoundtrip() {
        XCTAssertNil(vm.preferredRemoteName, "defaults to nil")

        vm.preferredRemoteName = "bitbucket"
        XCTAssertEqual(vm.preferredRemoteName, "bitbucket")

        vm.preferredRemoteName = nil
        XCTAssertNil(vm.preferredRemoteName, "nil clears the preference")
    }

    func testPreferredRemoteNameIsScopedPerRepo() {
        let otherRepo = sandbox.deletingLastPathComponent()
            .appendingPathComponent("zion_multiremote_other_\(UUID().uuidString)", isDirectory: true)

        vm.preferredRemoteName = "bitbucket"
        vm.repositoryURL = otherRepo
        XCTAssertNil(vm.preferredRemoteName, "changing repoURL must not leak preference from another repo")

        vm.repositoryURL = sandbox
        XCTAssertEqual(vm.preferredRemoteName, "bitbucket", "returning to the original repo must see its preference")
    }

    // MARK: - resolveTargetRemote

    func testResolveTargetRemoteReturnsNilWhenNoRemotes() {
        vm.remotes = []
        XCTAssertNil(vm.resolveTargetRemote(for: .push))
        XCTAssertNil(vm.resolveTargetRemote(for: .createPR))
    }

    func testResolveTargetRemotePrefersOriginByDefault() {
        vm.remotes = [
            RemoteInfo(name: "upstream", url: "https://github.com/upstream/repo.git"),
            RemoteInfo(name: "origin", url: "https://github.com/user/repo.git"),
            RemoteInfo(name: "bitbucket", url: "https://bitbucket.org/user/repo.git"),
        ]
        XCTAssertEqual(vm.resolveTargetRemote(for: .push)?.name, "origin")
    }

    func testResolveTargetRemoteFallsBackToFirstWhenNoOrigin() {
        vm.remotes = [
            RemoteInfo(name: "upstream", url: "https://github.com/upstream/repo.git"),
            RemoteInfo(name: "bitbucket", url: "https://bitbucket.org/user/repo.git"),
        ]
        XCTAssertEqual(vm.resolveTargetRemote(for: .push)?.name, "upstream")
    }

    func testResolveTargetRemoteHonorsPreferredWhenItExists() {
        vm.remotes = [
            RemoteInfo(name: "origin", url: "https://github.com/user/repo.git"),
            RemoteInfo(name: "bitbucket", url: "https://bitbucket.org/user/repo.git"),
        ]
        vm.preferredRemoteName = "bitbucket"
        XCTAssertEqual(vm.resolveTargetRemote(for: .createPR)?.name, "bitbucket")
    }

    func testResolveTargetRemoteIgnoresStalePreferred() {
        vm.remotes = [
            RemoteInfo(name: "origin", url: "https://github.com/user/repo.git"),
        ]
        vm.preferredRemoteName = "bitbucket" // remote no longer exists
        XCTAssertEqual(vm.resolveTargetRemote(for: .push)?.name, "origin",
                       "stale preferred must not block the origin fallback")
    }

    // MARK: - hostedRemotes

    func testHostedRemotesFiltersUnparseableAndPreservesOrder() {
        vm.remotes = [
            RemoteInfo(name: "origin", url: "https://github.com/user/repo.git"),
            RemoteInfo(name: "mirror", url: "file:///tmp/local-mirror.git"), // not a hosted provider
            RemoteInfo(name: "bitbucket", url: "https://bitbucket.org/user/repo.git"),
        ]

        let hosted = vm.hostedRemotes()
        XCTAssertEqual(hosted.map { $0.remote.name }, ["origin", "bitbucket"])
    }

    func testHostedRemotesEmptyWhenNoRemotes() {
        vm.remotes = []
        XCTAssertTrue(vm.hostedRemotes().isEmpty)
    }

    // MARK: - detectHostingProvider(for:)

    func testDetectHostingProviderForKnownRemote() {
        vm.remotes = [
            RemoteInfo(name: "origin", url: "https://github.com/user/repo.git"),
            RemoteInfo(name: "bitbucket", url: "https://bitbucket.org/user/repo.git"),
        ]

        let githubMatch = vm.detectHostingProvider(for: "origin")
        XCTAssertNotNil(githubMatch)
        XCTAssertEqual(githubMatch?.remote.owner, "user")

        let bitbucketMatch = vm.detectHostingProvider(for: "bitbucket")
        XCTAssertNotNil(bitbucketMatch)
        XCTAssertEqual(bitbucketMatch?.remote.owner, "user")
    }

    func testDetectHostingProviderForUnknownRemoteIsNil() {
        vm.remotes = [RemoteInfo(name: "origin", url: "https://github.com/user/repo.git")]
        XCTAssertNil(vm.detectHostingProvider(for: "does-not-exist"))
    }
}
