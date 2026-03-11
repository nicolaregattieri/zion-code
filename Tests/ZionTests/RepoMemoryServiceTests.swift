import Foundation
import XCTest
@testable import Zion

final class RepoMemoryServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testBuildSnapshotDerivesCommitStyleModulesAndMappings() {
        let snapshot = RepoMemoryService.buildSnapshot(
            repositoryURL: URL(fileURLWithPath: "/tmp/Zion"),
            activeBranch: "feature/repo-memory",
            headShortHash: "abc1234",
            commitSubjects: [
                "feat(ai): add repo memory cache",
                "fix(ai): tighten prompt context",
                "feat(settings): expose repo memory status",
            ],
            branchNames: [
                "feature/repo-memory",
                "feature/review-evidence",
                "bugfix/test-surface",
            ],
            repositoryFiles: [
                "Sources/Zion/ViewModel/RepositoryViewModel+AI.swift",
                "Sources/Zion/Services/RepoMemoryService.swift",
                "Tests/ZionTests/RepoMemoryServiceTests.swift",
                "Sources/Zion/Resources/en.lproj/Localizable.strings",
            ],
            sampledSource: [
                "@Observable final class RepositoryViewModel {}",
                "Text(L10n(\"settings.ai.repoMemory\"))",
                "DesignSystem.Colors.actionPrimary",
            ],
            remote: "git@github.com:nicolaregattieri/zion-code.git"
        )

        XCTAssertTrue(snapshot.commitStyle.usesConventionalCommits)
        XCTAssertEqual(snapshot.commitStyle.commonTypes.prefix(2), ["feat", "fix"])
        XCTAssertTrue(snapshot.commitStyle.commonScopes.contains("ai"))
        XCTAssertTrue(snapshot.moduleHints.contains("Zion"))
        XCTAssertTrue(snapshot.branchPatterns.contains("feature"))
        XCTAssertTrue(snapshot.conventions.contains("user-facing strings use L10n"))
        XCTAssertEqual(snapshot.testMappings["Zion"]?.first, "Tests/ZionTests/RepoMemoryServiceTests.swift")
    }

    func testBuildSnapshotSanitizesSensitiveStrings() {
        let snapshot = RepoMemoryService.buildSnapshot(
            repositoryURL: URL(fileURLWithPath: "/tmp/Zion"),
            activeBranch: "feature/\(NSHomeDirectory())/foo@example.com/sk-1234567890123456789012345",
            headShortHash: "abc1234",
            commitSubjects: [
                "feat(ai): email foo@example.com from \(NSHomeDirectory()) sk-1234567890123456789012345"
            ],
            branchNames: [
                "feature/foo@example.com",
            ],
            repositoryFiles: [
                "Sources/Zion/Services/AuthTokenStore.swift",
            ],
            sampledSource: [],
            remote: "https://example.com/private.git"
        )

        XCTAssertFalse(snapshot.activeBranch.contains("foo@example.com"))
        XCTAssertFalse(snapshot.activeBranch.contains(NSHomeDirectory()))
        XCTAssertFalse(snapshot.activeBranch.contains("sk-1234567890123456789012345"))
        XCTAssertTrue(snapshot.activeBranch.contains("[redacted-email]"))
        XCTAssertTrue(snapshot.activeBranch.contains("[redacted-secret]"))
        XCTAssertTrue(snapshot.sensitiveAreas.contains("Zion"))
    }

    func testRenderPromptContextUsesSnapshotDetails() {
        let snapshot = RepoMemorySnapshot(
            schemaVersion: 1,
            repositoryID: "repo-123",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            activeBranch: "feature/repo-memory",
            headShortHash: "abc1234",
            commitStyle: CommitStyleProfile(
                usesConventionalCommits: true,
                commonTypes: ["feat", "fix"],
                commonScopes: ["ai", "settings"],
                preferredVerbStyle: "imperative",
                averageTitleLength: 42
            ),
            moduleHints: ["Zion", "Sources", "ZionTests"],
            branchPatterns: ["feature", "bugfix"],
            conventions: ["user-facing strings use L10n", "unit tests live under Tests/ZionTests"],
            testMappings: ["Zion": ["Tests/ZionTests/RepoMemoryServiceTests.swift"]],
            sensitiveAreas: ["Zion"]
        )

        let context = RepoMemoryService.renderPromptContext(
            snapshot: snapshot,
            focusFiles: ["Sources/Zion/Services/RepoMemoryService.swift"],
            mode: .efficient
        )

        XCTAssertTrue(context.contains("branch: feature/repo-memory"))
        XCTAssertTrue(context.contains("commit style: conventional commits"))
        XCTAssertTrue(context.contains("modules: Zion, Sources, ZionTests"))
        XCTAssertTrue(context.contains("likely tests: Tests/ZionTests/RepoMemoryServiceTests.swift"))
    }

    func testSaveAndLoadSnapshotRoundTrip() async throws {
        let baseDirectory = tempDirectory.appendingPathComponent("Cache", isDirectory: true)
        let repositoryURL = tempDirectory.appendingPathComponent("Repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)

        let service = RepoMemoryService(baseDirectory: baseDirectory)
        let snapshot = RepoMemorySnapshot(
            schemaVersion: 1,
            repositoryID: "repo-123",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            activeBranch: "feature/repo-memory",
            headShortHash: "abc1234",
            commitStyle: CommitStyleProfile(
                usesConventionalCommits: true,
                commonTypes: ["feat"],
                commonScopes: ["ai"],
                preferredVerbStyle: "imperative",
                averageTitleLength: 32
            ),
            moduleHints: ["Zion"],
            branchPatterns: ["feature"],
            conventions: ["user-facing strings use L10n"],
            testMappings: ["Zion": ["Tests/ZionTests/RepoMemoryServiceTests.swift"]],
            sensitiveAreas: ["Zion"]
        )

        try await service.saveSnapshot(snapshot, for: repositoryURL)
        let loaded = await service.loadSnapshot(for: repositoryURL)

        XCTAssertEqual(loaded, snapshot)
    }
}
