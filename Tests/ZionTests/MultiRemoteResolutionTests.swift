import XCTest
@testable import Zion

final class MultiRemoteResolutionTests: XCTestCase {

    private func remote(_ name: String, _ url: String = "https://example.com/x.git") -> RemoteInfo {
        RemoteInfo(name: name, url: url)
    }

    // MARK: - resolveTargetRemote

    func testResolveReturnsNilWhenNoRemotes() {
        let result = RepositoryViewModel.resolveTargetRemote(in: [], preferred: nil, action: RepositoryViewModel.RemoteTargetAction.push)
        XCTAssertNil(result)
    }

    func testResolveReturnsOriginWhenNoPreference() {
        let remotes = [remote("bitbucket"), remote("origin"), remote("upstream")]
        let result = RepositoryViewModel.resolveTargetRemote(in: remotes, preferred: nil, action: RepositoryViewModel.RemoteTargetAction.push)
        XCTAssertEqual(result?.name, "origin")
    }

    func testResolveFallsBackToFirstWhenNoOriginAndNoPreference() {
        let remotes = [remote("bitbucket"), remote("upstream")]
        let result = RepositoryViewModel.resolveTargetRemote(in: remotes, preferred: nil, action: RepositoryViewModel.RemoteTargetAction.createPR)
        XCTAssertEqual(result?.name, "bitbucket")
    }

    func testResolveHonorsPreferredWhenPresent() {
        let remotes = [remote("origin"), remote("bitbucket")]
        let result = RepositoryViewModel.resolveTargetRemote(in: remotes, preferred: "bitbucket", action: RepositoryViewModel.RemoteTargetAction.push)
        XCTAssertEqual(result?.name, "bitbucket")
    }

    func testResolveIgnoresPreferredWhenNotPresent() {
        let remotes = [remote("origin"), remote("bitbucket")]
        let result = RepositoryViewModel.resolveTargetRemote(in: remotes, preferred: "gone", action: RepositoryViewModel.RemoteTargetAction.push)
        XCTAssertEqual(result?.name, "origin")
    }

    func testResolveTreatsEmptyPreferredAsNoPreference() {
        let remotes = [remote("origin"), remote("bitbucket")]
        let result = RepositoryViewModel.resolveTargetRemote(in: remotes, preferred: "", action: RepositoryViewModel.RemoteTargetAction.push)
        XCTAssertEqual(result?.name, "origin")
    }

    // MARK: - UserDefaults key

    func testPreferredRemoteKeyIsStableForFingerprint() {
        let key1 = UserDefaultsKeys.GitHosting.preferredRemoteKey(repoFingerprint: "abc123")
        let key2 = UserDefaultsKeys.GitHosting.preferredRemoteKey(repoFingerprint: "abc123")
        XCTAssertEqual(key1, key2)
        XCTAssertTrue(key1.hasPrefix(UserDefaultsKeys.GitHosting.preferredRemotePrefix))
    }

    func testPreferredRemoteKeyDiffersBetweenRepos() {
        let a = UserDefaultsKeys.GitHosting.preferredRemoteKey(repoFingerprint: "aaa")
        let b = UserDefaultsKeys.GitHosting.preferredRemoteKey(repoFingerprint: "bbb")
        XCTAssertNotEqual(a, b)
    }
}
