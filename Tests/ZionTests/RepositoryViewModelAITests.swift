import XCTest
@testable import Zion

@MainActor
final class RepositoryViewModelAITests: XCTestCase {
    private struct PendingSummaryError: Error {}

    // MARK: - generateCommitMessage (static heuristic)

    func testSingleNewFileProducesFeat() {
        let status = "?? Sources/login.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("feat"), "Expected 'feat' type for new file, got: \(result)")
        XCTAssertTrue(result.contains("login"), "Expected filename 'login' in message, got: \(result)")
    }

    func testSingleModifiedFileProducesType() {
        let status = " M Sources/Helpers/utils.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        // With 0 added and 1 modified, modified > added => "fix"
        XCTAssertTrue(result.contains("fix") || result.contains("feat"),
                       "Expected 'fix' or 'feat' for modified file, got: \(result)")
        XCTAssertTrue(result.contains("utils"), "Expected filename 'utils' in message, got: \(result)")
    }

    func testMultipleFilesWithMixedTypes() {
        let status = "A  src/a.swift\n M src/b.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("2 files"), "Expected '2 files' in message, got: \(result)")
        XCTAssertTrue(result.contains("(src)"), "Expected scope '(src)', got: \(result)")
    }

    func testOnlyDeletionsProducesChore() {
        let status = " D old.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("chore"), "Expected 'chore' for deletions, got: \(result)")
    }

    func testTestFilesProducesTestType() {
        // Use "M " (modified) so the else branch is reached where allSatisfy test-file check runs
        let status = " M Tests/MyTest.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("test"), "Expected 'test' type for test files, got: \(result)")
    }

    func testDocFilesProducesDocsType() {
        // Use "M " (modified) so the else branch is reached where allSatisfy doc-file check runs
        let status = " M README.md"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("docs"), "Expected 'docs' type for .md files, got: \(result)")
    }

    func testEmptyStatusReturnsEmptyString() {
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: "")

        XCTAssertEqual(result, "", "Expected empty string for empty status")
    }

    func testSingleAddedFileContainsAddVerb() {
        let status = "A  Sources/NewFeature.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("add"), "Expected 'add' verb for new file, got: \(result)")
        XCTAssertTrue(result.contains("NewFeature"), "Expected 'NewFeature' in message, got: \(result)")
    }

    func testSingleModifiedFileContainsUpdateVerb() {
        let status = " M Sources/Existing.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        XCTAssertTrue(result.contains("update"), "Expected 'update' verb for modified file, got: \(result)")
    }

    func testScopeFromCommonDirectory() {
        let status = "A  Views/Login/LoginView.swift\nA  Views/Login/LoginModel.swift"
        let result = RepositoryViewModel.generateCommitMessage(diffStat: "", status: status)

        // The most common directory component (after dropping filename) should be "Login"
        XCTAssertTrue(result.contains("(Login)") || result.contains("(Views)"),
                       "Expected scope from common directory, got: \(result)")
    }

    // MARK: - dismissPreCommitReview

    func testDismissPreCommitReviewResetsState() {
        let vm = RepositoryViewModel()
        vm.preCommitReviewPending = true
        vm.isReviewVisible = true

        vm.dismissPreCommitReview()

        XCTAssertFalse(vm.preCommitReviewPending, "preCommitReviewPending should be false after dismiss")
        XCTAssertFalse(vm.isReviewVisible, "isReviewVisible should be false after dismiss")
    }

    // MARK: - clearSemanticSearch

    func testClearSemanticSearchResetsState() {
        let vm = RepositoryViewModel()
        vm.aiHistorySearchResult = AIHistorySearchResult(
            answer: "Found related commits.",
            matches: [AIHistorySearchMatch(hash: "abc123", reason: "Touched README.md")]
        )
        vm.isSemanticSearchActive = true

        vm.clearSemanticSearch()

        XCTAssertNil(vm.aiHistorySearchResult, "aiHistorySearchResult should be nil after clear")
        XCTAssertFalse(vm.isSemanticSearchActive, "isSemanticSearchActive should be false after clear")
    }

    func testParseHistorySearchResponseExtractsAnswerAndMatches() {
        let raw = """
        ANSWER: README changes happened in the docs refresh commit.
        MATCH: a1b2c3d | Updates README.md and docs navigation
        MATCH: d4e5f6a | Touches docs/README.md during onboarding cleanup
        """

        let result = AIClient.parseHistorySearchResponse(raw)

        XCTAssertEqual(result.answer, "README changes happened in the docs refresh commit.")
        XCTAssertEqual(result.matches.count, 2)
        XCTAssertEqual(result.matches.first?.hash, "a1b2c3d")
        XCTAssertEqual(result.matches.first?.reason, "Updates README.md and docs navigation")
    }

    func testParseHistorySearchResponseHandlesNone() {
        let raw = """
        ANSWER: I could not find a strong match.
        MATCH: NONE
        """

        let result = AIClient.parseHistorySearchResponse(raw)

        XCTAssertEqual(result.answer, "I could not find a strong match.")
        XCTAssertTrue(result.matches.isEmpty)
    }

    func testRankHistorySearchCandidatesPrioritizesTouchedFiles() {
        let candidates = [
            AIHistorySearchCandidate(
                fullHash: "1111111111111111111111111111111111111111",
                shortHash: "1111111",
                subject: "Tidy onboarding copy",
                author: "Nico",
                dateText: "2026-03-10",
                files: ["Sources/Zion/Views/Onboarding/WelcomeView.swift"]
            ),
            AIHistorySearchCandidate(
                fullHash: "2222222222222222222222222222222222222222",
                shortHash: "2222222",
                subject: "Refresh docs landing page",
                author: "Nico",
                dateText: "2026-03-09",
                files: ["README.md", "docs/getting-started.md"]
            ),
        ]

        let ranked = RepositoryViewModel.rankHistorySearchCandidates(candidates, query: "when was the readme updated", limit: 2)

        XCTAssertEqual(ranked.first?.shortHash, "2222222")
    }

    func testParseReviewFindingsSupportsEvidenceAndTestImpact() {
        let raw = """
        warning|Sources/Zion/AI.swift|Potential nil handling gap|guard path stays optional|Add a regression test for empty input
        """

        let findings = AIClient.parseReviewFindings(raw)

        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.file, "Sources/Zion/AI.swift")
        XCTAssertEqual(findings.first?.evidence, "guard path stays optional")
        XCTAssertEqual(findings.first?.testImpact, "Add a regression test for empty input")
    }

    func testParseReviewFindingsKeepsBackwardCompatibility() {
        let raw = "suggestion|general|Code looks good — no issues found."

        let findings = AIClient.parseReviewFindings(raw)

        XCTAssertEqual(findings.count, 1)
        XCTAssertNil(findings.first?.evidence)
        XCTAssertNil(findings.first?.testImpact)
    }

    func testModelCatalogKeepsEfficientOpenAIOnAffordableDefault() {
        let selection = AIModelCatalogService.selection(for: .openai, mode: .efficient, lane: .review)

        XCTAssertEqual(selection.primaryModelID, "gpt-4o-mini")
        XCTAssertTrue(selection.fallbackModelIDs.contains("gpt-5-mini"))
    }

    func testModelCatalogUpgradesReviewLaneForSmartAnthropic() {
        let selection = AIModelCatalogService.selection(for: .anthropic, mode: .smart, lane: .review)

        XCTAssertEqual(selection.primaryModelID, "claude-sonnet-4-0")
        XCTAssertTrue(selection.fallbackModelIDs.contains("claude-3-5-haiku-20241022"))
    }

    func testParseFileHintsFromDiffStatExtractsPaths() {
        let diffStat = """
         Sources/Zion/ViewModel/RepositoryViewModel+AI.swift | 12 +++++++-----
         Tests/ZionTests/RepositoryViewModelAITests.swift    | 10 ++++++++--
        """

        let files = RepositoryViewModel.parseFileHints(fromDiffStat: diffStat)

        XCTAssertEqual(files, [
            "Sources/Zion/ViewModel/RepositoryViewModel+AI.swift",
            "Tests/ZionTests/RepositoryViewModelAITests.swift",
        ])
    }

    func testDeriveModulesPrefersNestedFolders() {
        let modules = RepositoryViewModel.deriveModules(
            from: [
                "Sources/Zion/ViewModel/RepositoryViewModel+AI.swift",
                "Tests/ZionTests/RepositoryViewModelAITests.swift",
            ],
            limit: 4
        )

        XCTAssertEqual(modules, ["Zion", "Sources", "ZionTests", "Tests"])
    }

    // MARK: - recalculateCodeReviewStats

    func testRecalculateCodeReviewStatsTotals() {
        let vm = RepositoryViewModel()
        vm.codeReviewFiles = [
            CodeReviewFile(path: "a.swift", status: .modified, additions: 10, deletions: 3, diff: "", hunks: []),
            CodeReviewFile(path: "b.swift", status: .added, additions: 20, deletions: 0, diff: "", hunks: []),
        ]

        vm.recalculateCodeReviewStats(commitCount: 5)

        XCTAssertEqual(vm.codeReviewStats.totalFiles, 2)
        XCTAssertEqual(vm.codeReviewStats.totalAdditions, 30)
        XCTAssertEqual(vm.codeReviewStats.totalDeletions, 3)
        XCTAssertEqual(vm.codeReviewStats.commitCount, 5)
    }

    func testRecalculateCodeReviewStatsFindingSeverityCounts() {
        let vm = RepositoryViewModel()
        var file = CodeReviewFile(path: "c.swift", status: .modified, additions: 5, deletions: 2, diff: "", hunks: [])
        file.findings = [
            ReviewFinding(severity: .critical, file: "c.swift", message: "Critical issue"),
            ReviewFinding(severity: .warning, file: "c.swift", message: "Warning"),
            ReviewFinding(severity: .suggestion, file: "c.swift", message: "Suggestion"),
            ReviewFinding(severity: .warning, file: "c.swift", message: "Another warning"),
        ]
        vm.codeReviewFiles = [file]

        vm.recalculateCodeReviewStats(commitCount: 1)

        XCTAssertEqual(vm.codeReviewStats.criticalCount, 1)
        XCTAssertEqual(vm.codeReviewStats.warningCount, 2)
        XCTAssertEqual(vm.codeReviewStats.suggestionCount, 1)
    }

    func testRecalculateCodeReviewStatsEmptyFiles() {
        let vm = RepositoryViewModel()
        vm.codeReviewFiles = []

        vm.recalculateCodeReviewStats(commitCount: 0)

        XCTAssertEqual(vm.codeReviewStats.totalFiles, 0)
        XCTAssertEqual(vm.codeReviewStats.totalAdditions, 0)
        XCTAssertEqual(vm.codeReviewStats.totalDeletions, 0)
        XCTAssertEqual(vm.codeReviewStats.criticalCount, 0)
    }

    // MARK: - preCommitHasCritical

    func testPreCommitHasCriticalTrueWithCritical() {
        let vm = RepositoryViewModel()
        vm.aiReviewFindings = [
            ReviewFinding(severity: .critical, file: "a.swift", message: "Danger"),
            ReviewFinding(severity: .suggestion, file: "b.swift", message: "Tip"),
        ]
        XCTAssertTrue(vm.preCommitHasCritical)
    }

    func testPreCommitHasCriticalFalseWithOnlyWarnings() {
        let vm = RepositoryViewModel()
        vm.aiReviewFindings = [
            ReviewFinding(severity: .warning, file: "a.swift", message: "Watch out"),
            ReviewFinding(severity: .suggestion, file: "b.swift", message: "Tip"),
        ]
        XCTAssertFalse(vm.preCommitHasCritical)
    }

    func testPreCommitHasCriticalFalseWhenEmpty() {
        let vm = RepositoryViewModel()
        vm.aiReviewFindings = []
        XCTAssertFalse(vm.preCommitHasCritical)
    }

    // MARK: - cachedReviewFindings

    func testCachedReviewFindingsReturnsNilForUnknown() {
        let vm = RepositoryViewModel()
        XCTAssertNil(vm.cachedReviewFindings(for: "unknown-commit"))
    }

    func testCachedReviewFindingsReturnsCachedValue() {
        let vm = RepositoryViewModel()
        let findings = [ReviewFinding(severity: .warning, file: "a.swift", message: "Issue")]
        vm.commitReviewCache["abc123"] = findings

        let result = vm.cachedReviewFindings(for: "abc123")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.message, "Issue")
    }

    // MARK: - pending changes summary

    func testBeginPendingChangesSummaryRequestKeepsExistingSummaryVisible() {
        let vm = RepositoryViewModel()
        vm.aiPendingChangesSummary = "Existing summary"

        vm.beginPendingChangesSummaryRequest()

        XCTAssertTrue(vm.isLoadingPendingChangesSummary)
        XCTAssertEqual(vm.aiPendingChangesSummary, "Existing summary")
    }

    func testHandlePendingChangesSummaryFailureKeepsExistingSummary() {
        let vm = RepositoryViewModel()
        vm.aiPendingChangesSummary = "Existing summary"
        vm.isLoadingPendingChangesSummary = true

        vm.handlePendingChangesSummaryFailure(PendingSummaryError())

        XCTAssertFalse(vm.isLoadingPendingChangesSummary)
        XCTAssertEqual(vm.aiPendingChangesSummary, "Existing summary")
        XCTAssertFalse((vm.lastError ?? "").isEmpty)
    }

    func testDismissPendingChangesSummaryClearsState() {
        let vm = RepositoryViewModel()
        vm.aiPendingChangesSummary = "Existing summary"
        vm.isLoadingPendingChangesSummary = true

        vm.dismissPendingChangesSummary()

        XCTAssertFalse(vm.isLoadingPendingChangesSummary)
        XCTAssertEqual(vm.aiPendingChangesSummary, "")
    }

    func testSyncPendingChangesSummaryAfterRefreshKeepsSummaryWhenChangesRemain() {
        let vm = RepositoryViewModel()
        vm.aiPendingChangesSummary = "Existing summary"
        vm.isLoadingPendingChangesSummary = true

        vm.syncPendingChangesSummaryAfterRefresh(hasPendingChanges: true)

        XCTAssertTrue(vm.isLoadingPendingChangesSummary)
        XCTAssertEqual(vm.aiPendingChangesSummary, "Existing summary")
    }

    func testSyncPendingChangesSummaryAfterRefreshClearsSummaryWhenNoChangesRemain() {
        let vm = RepositoryViewModel()
        vm.aiPendingChangesSummary = "Existing summary"
        vm.isLoadingPendingChangesSummary = true

        vm.syncPendingChangesSummaryAfterRefresh(hasPendingChanges: false)

        XCTAssertFalse(vm.isLoadingPendingChangesSummary)
        XCTAssertEqual(vm.aiPendingChangesSummary, "")
    }

    // MARK: - PR notification helpers

    func testEnrichedReviewRequestPRPrefersCatalogMetadata() {
        let queued = HostedPRInfo(
            id: 42,
            number: 17,
            title: "Improve inbox",
            state: .open,
            headBranch: "",
            baseBranch: "",
            url: "",
            isDraft: false,
            author: "",
            headSHA: ""
        )
        let catalog = [
            HostedPRInfo(
                id: 42,
                number: 17,
                title: "Improve inbox",
                state: .open,
                headBranch: "feature/inbox",
                baseBranch: "main",
                url: "https://example.com/pr/17",
                isDraft: true,
                author: "nico",
                headSHA: "abc123"
            )
        ]

        let enriched = RepositoryViewModel.enrichedReviewRequestPR(queued, catalog: catalog)

        XCTAssertEqual(enriched.headBranch, "feature/inbox")
        XCTAssertEqual(enriched.baseBranch, "main")
        XCTAssertEqual(enriched.url, "https://example.com/pr/17")
        XCTAssertEqual(enriched.author, "nico")
        XCTAssertEqual(enriched.headSHA, "abc123")
        XCTAssertTrue(enriched.isDraft)
    }

    func testBuildReviewRequestNotificationBodyIncludesRepoHighlights() {
        let pr = HostedPRInfo(
            id: 1,
            number: 23,
            title: "Refresh repo memory prompts",
            state: .open,
            headBranch: "feature/repo-memory",
            baseBranch: "main",
            url: "https://example.com/pr/23",
            isDraft: false,
            author: "fulano",
            headSHA: "abc123"
        )
        let repoContext = """
        changed files: RepositoryViewModel+AI.swift, NotificationSettingsTab.swift
        modules: AI, ViewModel, Settings
        conventions: preserve notifier payload shape, avoid duplicate review events
        """

        let body = RepositoryViewModel.buildReviewRequestNotificationBody(pr: pr, repoContext: repoContext)

        XCTAssertTrue(body.contains("fulano"))
        XCTAssertTrue(body.contains("Refresh repo memory prompts"))
        XCTAssertTrue(body.contains("feature/repo-memory"))
        XCTAssertTrue(body.contains("main"))
        XCTAssertTrue(body.contains("RepositoryViewModel+AI.swift"))
        XCTAssertTrue(body.contains("AI, ViewModel, Settings"))
        XCTAssertTrue(body.contains("preserve notifier payload shape"))
    }

    func testReviewRequestNotificationTransitionDropsInactiveIDs() {
        let active = [
            HostedPRInfo(
                id: 9,
                number: 9,
                title: "Keep inbox state aligned",
                state: .open,
                headBranch: "feature/inbox",
                baseBranch: "main",
                url: "https://example.com/pr/9",
                isDraft: false,
                author: "nico",
                headSHA: "abc123"
            )
        ]

        let transition = RepositoryViewModel.reviewRequestNotificationTransition(
            existingIDs: [7, 9],
            activePRs: active
        )

        XCTAssertTrue(transition.newlyRequested.isEmpty)
        XCTAssertEqual(transition.nextIDs, [9])
    }

    func testOpenPRNotificationTransitionUsesInitialFetchAsBaseline() {
        let active = [
            HostedPRInfo(
                id: 11,
                number: 11,
                title: "Keep all-open inbox fresh",
                state: .open,
                headBranch: "feature/pr-inbox-refresh",
                baseBranch: "main",
                url: "https://example.com/pr/11",
                isDraft: false,
                author: "nico",
                headSHA: "abc123"
            )
        ]

        let transition = RepositoryViewModel.openPRNotificationTransition(
            existingIDs: nil,
            activePRs: active
        )

        XCTAssertTrue(transition.newlyCreated.isEmpty)
        XCTAssertEqual(transition.nextIDs, [11])
    }

    func testOpenPRNotificationTransitionDetectsNewlyAppearedPRsAfterBaseline() {
        let active = [
            HostedPRInfo(
                id: 12,
                number: 12,
                title: "Refresh open PR cache on timer",
                state: .open,
                headBranch: "feature/open-pr-refresh",
                baseBranch: "main",
                url: "https://example.com/pr/12",
                isDraft: false,
                author: "nico",
                headSHA: "def456"
            )
        ]

        let transition = RepositoryViewModel.openPRNotificationTransition(
            existingIDs: [],
            activePRs: active
        )

        XCTAssertEqual(transition.newlyCreated.map(\.id), [12])
        XCTAssertEqual(transition.nextIDs, [12])
    }

    func testReviewRequestTouchedFilesSummaryUsesFileBasenames() {
        let summary = RepositoryViewModel.reviewRequestTouchedFilesSummary(from: [
            (filename: "Sources/Zion/Views/Main/PRInboxCard.swift", status: "modified", additions: 12, deletions: 2, patch: ""),
            (filename: "Sources/Zion/Services/NtfyClient.swift", status: "modified", additions: 8, deletions: 1, patch: ""),
            (filename: "Tests/ZionTests/NtfyEventTests.swift", status: "modified", additions: 6, deletions: 0, patch: ""),
        ])

        XCTAssertEqual(summary, "PRInboxCard.swift, NtfyClient.swift, NtfyEventTests.swift")
    }

    func testBuildReviewNotificationBodySummarizesFixesAndPassSignal() {
        let pr = HostedPRInfo(
            id: 2,
            number: 31,
            title: "Tighten PR review queue",
            state: .open,
            headBranch: "feature/pr-queue",
            baseBranch: "main",
            url: "https://example.com/pr/31",
            isDraft: false,
            author: "fulano",
            headSHA: "def456"
        )
        let findings = [
            ReviewFinding(severity: .warning, file: "Sources/Zion/ViewModel/RepositoryViewModel+AI.swift", message: "Queue item loses branch metadata"),
            ReviewFinding(severity: .critical, file: "Sources/Zion/Views/Main/PRInboxCard.swift", message: "Auth state can mislead users"),
        ]
        let repoContext = """
        modules: AI, Sidebar, Notifications
        sensitive areas: notification spam, review queue state
        """

        let body = RepositoryViewModel.buildReviewNotificationBody(pr: pr, findings: findings, repoContext: repoContext)

        XCTAssertTrue(body.contains("Tighten PR review queue"))
        XCTAssertTrue(body.contains("55%"))
        XCTAssertTrue(body.contains("AI, Sidebar, Notifications"))
        XCTAssertTrue(body.contains("notification spam"))
        XCTAssertTrue(body.contains("Queue item loses branch metadata"))
        XCTAssertTrue(body.contains("Auth state can mislead users"))
    }

    func testBuildReviewNotificationBodyFallsBackToCleanSummary() {
        let pr = HostedPRInfo(
            id: 3,
            number: 41,
            title: "Refine notifier copy",
            state: .open,
            headBranch: "feature/notifier-copy",
            baseBranch: "main",
            url: "https://example.com/pr/41",
            isDraft: false,
            author: "fulano",
            headSHA: "ghi789"
        )

        let body = RepositoryViewModel.buildReviewNotificationBody(pr: pr, findings: [], repoContext: "")

        XCTAssertTrue(body.contains("Refine notifier copy"))
        XCTAssertTrue(body.contains("100%"))
        XCTAssertTrue(body.contains(L10n("pr.notification.review.clean")))
    }
}
