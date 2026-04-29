import XCTest
@testable import Zion

@MainActor
final class MultiRemotePRSheetTests: XCTestCase {

    private func remote(_ name: String, _ url: String) -> RemoteInfo {
        RemoteInfo(name: name, url: url)
    }

    private func makeVM(remotes: [RemoteInfo]) -> RepositoryViewModel {
        let vm = RepositoryViewModel()
        vm.remotes = remotes
        return vm
    }

    // MARK: - hostedRemotes filtering

    func testHostedRemotesPreservesOrderAndProvider() {
        let vm = makeVM(remotes: [
            remote("bitbucket", "https://bitbucket.org/team/proj.git"),
            remote("origin", "https://github.com/user/repo.git"),
            remote("internal", "https://example.com/foo.git") // Not a known host
        ])

        let hosted = vm.hostedRemotes()
        XCTAssertEqual(hosted.count, 2, "Unrecognized hosts must be filtered out")
        XCTAssertEqual(hosted.map(\.remote.name), ["bitbucket", "origin"])
        XCTAssertEqual(hosted[0].provider.kind, .bitbucket)
        XCTAssertEqual(hosted[1].provider.kind, .github)
    }

    func testHostedRemotesEmptyWhenNoRecognizedHost() {
        let vm = makeVM(remotes: [remote("custom", "/path/to/local/bare.git")])
        XCTAssertTrue(vm.hostedRemotes().isEmpty)
    }

    // MARK: - detectHostingProvider(for:) overload

    func testDetectHostingProviderForSpecificRemote() {
        let vm = makeVM(remotes: [
            remote("origin", "https://github.com/user/repo.git"),
            remote("bitbucket", "https://bitbucket.org/team/proj.git")
        ])

        let github = vm.detectHostingProvider(for: "origin")
        XCTAssertEqual(github?.provider.kind, .github)
        XCTAssertEqual(github?.remote.repo, "repo")

        let bb = vm.detectHostingProvider(for: "bitbucket")
        XCTAssertEqual(bb?.provider.kind, .bitbucket)
        XCTAssertEqual(bb?.remote.owner, "team")
    }

    func testDetectHostingProviderForUnknownRemoteIsNil() {
        let vm = makeVM(remotes: [remote("origin", "https://github.com/user/repo.git")])
        XCTAssertNil(vm.detectHostingProvider(for: "doesnotexist"))
    }

    // MARK: - detectHostingProvider() honors preferred remote

    func testDetectHostingProviderHonorsPreferred() {
        let vm = makeVM(remotes: [
            remote("origin", "https://github.com/user/repo.git"),
            remote("bitbucket", "https://bitbucket.org/team/proj.git")
        ])
        // Without preference, first match (origin/GitHub) wins
        XCTAssertEqual(vm.detectHostingProvider()?.provider.kind, .github)

        // Set preferred remote → that one is returned even though it isn't first
        vm.repositoryURL = URL(fileURLWithPath: "/tmp/zion-pr-test-\(UUID().uuidString)")
        vm.preferredRemoteName = "bitbucket"
        XCTAssertEqual(vm.detectHostingProvider()?.provider.kind, .bitbucket)

        // Cleanup persisted preference so it doesn't leak across runs
        vm.preferredRemoteName = nil
    }
}
