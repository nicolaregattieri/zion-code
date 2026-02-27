import XCTest
@testable import Zion

final class RemoteParsingTests: XCTestCase {
    private let worker = RepositoryWorker()

    func testParseHTTPSRemote() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        // Add a remote to the real repo
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "remote", "add", "origin", "https://github.com/user/repo.git"]
        process.currentDirectoryURL = repoURL
        try process.run()
        process.waitUntilExit()

        let remotes = try await worker.remoteList(in: repoURL)

        XCTAssertEqual(remotes.count, 1)
        XCTAssertEqual(remotes[0].name, "origin")
        XCTAssertEqual(remotes[0].url, "https://github.com/user/repo.git")
    }

    func testParseMultipleRemotes() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        let addRemote: (String, String) throws -> Void = { name, url in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "remote", "add", name, url]
            process.currentDirectoryURL = repoURL
            try process.run()
            process.waitUntilExit()
        }

        try addRemote("origin", "https://github.com/user/repo.git")
        try addRemote("upstream", "https://github.com/upstream/repo.git")

        let remotes = try await worker.remoteList(in: repoURL)

        XCTAssertEqual(remotes.count, 2)
        // Should be sorted alphabetically
        XCTAssertEqual(remotes[0].name, "origin")
        XCTAssertEqual(remotes[1].name, "upstream")
    }

    func testParseSSHRemote() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "remote", "add", "origin", "git@github.com:user/repo.git"]
        process.currentDirectoryURL = repoURL
        try process.run()
        process.waitUntilExit()

        let remotes = try await worker.remoteList(in: repoURL)

        XCTAssertEqual(remotes[0].url, "git@github.com:user/repo.git")
    }

    func testNoRemotes() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        let remotes = try await worker.remoteList(in: repoURL)
        XCTAssertTrue(remotes.isEmpty)
    }

    func testRemoteDeduplicated() async throws {
        // git remote -v shows each remote twice (fetch + push)
        // The parser should deduplicate by name
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "remote", "add", "origin", "https://github.com/user/repo.git"]
        process.currentDirectoryURL = repoURL
        try process.run()
        process.waitUntilExit()

        let remotes = try await worker.remoteList(in: repoURL)

        // Should be 1, not 2 (fetch + push lines are deduped)
        XCTAssertEqual(remotes.count, 1)
    }

    func testRemotesSortedAlphabetically() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        let addRemote: (String, String) throws -> Void = { name, url in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "remote", "add", name, url]
            process.currentDirectoryURL = repoURL
            try process.run()
            process.waitUntilExit()
        }

        try addRemote("zebra", "https://example.com/zebra.git")
        try addRemote("alpha", "https://example.com/alpha.git")
        try addRemote("middle", "https://example.com/middle.git")

        let remotes = try await worker.remoteList(in: repoURL)

        XCTAssertEqual(remotes.map(\.name), ["alpha", "middle", "zebra"])
    }
}
