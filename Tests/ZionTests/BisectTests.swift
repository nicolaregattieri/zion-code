import XCTest
@testable import Zion

final class BisectTests: XCTestCase {

    // MARK: - BisectPhase Equatability

    func testBisectPhaseInactiveEquality() {
        XCTAssertEqual(BisectPhase.inactive, BisectPhase.inactive)
    }

    func testBisectPhaseAwaitingGoodCommitEquality() {
        XCTAssertEqual(
            BisectPhase.awaitingGoodCommit(badCommitHash: "abc123"),
            BisectPhase.awaitingGoodCommit(badCommitHash: "abc123")
        )
        XCTAssertNotEqual(
            BisectPhase.awaitingGoodCommit(badCommitHash: "abc123"),
            BisectPhase.awaitingGoodCommit(badCommitHash: "def456")
        )
    }

    func testBisectPhaseActiveEquality() {
        XCTAssertEqual(
            BisectPhase.active(currentHash: "abc123", stepsRemaining: 5),
            BisectPhase.active(currentHash: "abc123", stepsRemaining: 5)
        )
        XCTAssertNotEqual(
            BisectPhase.active(currentHash: "abc123", stepsRemaining: 5),
            BisectPhase.active(currentHash: "abc123", stepsRemaining: 3)
        )
    }

    func testBisectPhaseFoundCulpritEquality() {
        XCTAssertEqual(
            BisectPhase.foundCulprit(commitHash: "abc123"),
            BisectPhase.foundCulprit(commitHash: "abc123")
        )
        XCTAssertNotEqual(
            BisectPhase.foundCulprit(commitHash: "abc123"),
            BisectPhase.foundCulprit(commitHash: "def456")
        )
    }

    func testBisectPhaseCrossTypeInequality() {
        XCTAssertNotEqual(BisectPhase.inactive, BisectPhase.awaitingGoodCommit(badCommitHash: "abc"))
        XCTAssertNotEqual(BisectPhase.inactive, BisectPhase.active(currentHash: "abc", stepsRemaining: 3))
        XCTAssertNotEqual(BisectPhase.inactive, BisectPhase.foundCulprit(commitHash: "abc"))
    }

    // MARK: - parseBisectOutput — Found Culprit

    @MainActor
    func testParseBisectOutputFoundCulprit() {
        let model = RepositoryViewModel()
        let output = """
        abc123def456789012345678901234567890abcd is the first bad commit
        commit abc123def456789012345678901234567890abcd
        Author: Test User <test@example.com>
        Date:   Mon Jan 15 10:30:00 2025 +0000

            Break the auth flow
        """

        let result = model.parseBisectOutput(output)

        if case .foundCulprit(let hash) = result {
            XCTAssertEqual(hash, "abc123def456789012345678901234567890abcd")
        } else {
            XCTFail("Expected .foundCulprit, got \(result)")
        }
    }

    @MainActor
    func testParseBisectOutputFoundCulpritShortHash() {
        let model = RepositoryViewModel()
        let output = "abc1234 is the first bad commit\ncommit abc1234\n"

        let result = model.parseBisectOutput(output)

        if case .foundCulprit(let hash) = result {
            XCTAssertEqual(hash, "abc1234")
        } else {
            XCTFail("Expected .foundCulprit, got \(result)")
        }
    }

    // MARK: - parseBisectOutput — Continuing

    @MainActor
    func testParseBisectOutputContinuingWithSteps() {
        let model = RepositoryViewModel()
        let output = """
        Bisecting: 7 revisions left to test after this (roughly 3 steps)
        [abc123def456789012345678901234567890abcd] Refactor module
        """

        let result = model.parseBisectOutput(output)

        if case .continuing(let nextHash, let steps) = result {
            XCTAssertEqual(nextHash, "abc123def456789012345678901234567890abcd")
            XCTAssertEqual(steps, 3)
        } else {
            XCTFail("Expected .continuing, got \(result)")
        }
    }

    @MainActor
    func testParseBisectOutputContinuingRoughly1Step() {
        let model = RepositoryViewModel()
        let output = """
        Bisecting: 1 revision left to test after this (roughly 1 step)
        [def4567] Fix typo
        """

        let result = model.parseBisectOutput(output)

        if case .continuing(let nextHash, let steps) = result {
            XCTAssertEqual(nextHash, "def4567")
            XCTAssertEqual(steps, 1)
        } else {
            XCTFail("Expected .continuing, got \(result)")
        }
    }

    @MainActor
    func testParseBisectOutputContinuingNoStepLine() {
        let model = RepositoryViewModel()
        let output = "[abc1234] Some commit message\n"

        let result = model.parseBisectOutput(output)

        if case .continuing(let nextHash, let steps) = result {
            XCTAssertEqual(nextHash, "abc1234")
            XCTAssertEqual(steps, 0)
        } else {
            XCTFail("Expected .continuing, got \(result)")
        }
    }

    @MainActor
    func testParseBisectOutputEmptyFallback() {
        let model = RepositoryViewModel()
        model.bisectCurrentHash = "fallback123"
        let output = ""

        let result = model.parseBisectOutput(output)

        if case .continuing(let nextHash, let steps) = result {
            XCTAssertEqual(nextHash, "fallback123")
            XCTAssertEqual(steps, 0)
        } else {
            XCTFail("Expected .continuing, got \(result)")
        }
    }

    // MARK: - BisectCommitRole

    @MainActor
    func testBisectRoleInactive() {
        let model = RepositoryViewModel()
        model.bisectPhase = .inactive
        XCTAssertEqual(model.bisectRole(for: "abc123"), .none)
    }

    @MainActor
    func testBisectRoleAwaitingGoodCommitBad() {
        let model = RepositoryViewModel()
        model.bisectPhase = .awaitingGoodCommit(badCommitHash: "abc123")
        model.bisectBadCommits = ["abc123"]
        XCTAssertEqual(model.bisectRole(for: "abc123"), .markedBad)
    }

    @MainActor
    func testBisectRoleAwaitingGoodCommitOther() {
        let model = RepositoryViewModel()
        model.bisectPhase = .awaitingGoodCommit(badCommitHash: "abc123")
        XCTAssertEqual(model.bisectRole(for: "def456"), .none)
    }

    @MainActor
    func testBisectRoleActiveCurrentTest() {
        let model = RepositoryViewModel()
        model.bisectPhase = .active(currentHash: "abc123", stepsRemaining: 3)
        model.bisectCurrentHash = "abc123"
        XCTAssertEqual(model.bisectRole(for: "abc123"), .currentTest)
    }

    @MainActor
    func testBisectRoleActiveGood() {
        let model = RepositoryViewModel()
        model.bisectPhase = .active(currentHash: "abc123", stepsRemaining: 3)
        model.bisectGoodCommits = ["def456"]
        XCTAssertEqual(model.bisectRole(for: "def456"), .markedGood)
    }

    @MainActor
    func testBisectRoleActiveBad() {
        let model = RepositoryViewModel()
        model.bisectPhase = .active(currentHash: "abc123", stepsRemaining: 3)
        model.bisectBadCommits = ["ghi789"]
        XCTAssertEqual(model.bisectRole(for: "ghi789"), .markedBad)
    }

    @MainActor
    func testBisectRoleActiveNone() {
        let model = RepositoryViewModel()
        model.bisectPhase = .active(currentHash: "abc123", stepsRemaining: 3)
        XCTAssertEqual(model.bisectRole(for: "zzz000"), .none)
    }

    @MainActor
    func testBisectRoleFoundCulprit() {
        let model = RepositoryViewModel()
        model.bisectPhase = .foundCulprit(commitHash: "abc123")
        XCTAssertEqual(model.bisectRole(for: "abc123"), .culprit)
    }

    @MainActor
    func testBisectRoleFoundCulpritGood() {
        let model = RepositoryViewModel()
        model.bisectPhase = .foundCulprit(commitHash: "abc123")
        model.bisectGoodCommits = ["def456"]
        XCTAssertEqual(model.bisectRole(for: "def456"), .markedGood)
    }

    @MainActor
    func testBisectRoleFoundCulpritOther() {
        let model = RepositoryViewModel()
        model.bisectPhase = .foundCulprit(commitHash: "abc123")
        XCTAssertEqual(model.bisectRole(for: "zzz000"), .none)
    }

    // MARK: - clearBisectState

    @MainActor
    func testClearBisectState() {
        let model = RepositoryViewModel()
        model.bisectPhase = .active(currentHash: "abc123", stepsRemaining: 3)
        model.bisectGoodCommits = ["aaa", "bbb"]
        model.bisectBadCommits = ["ccc"]
        model.bisectCurrentHash = "abc123"
        model.bisectAIExplanation = "Some explanation"
        model.isBisectAILoading = true

        model.clearBisectState()

        XCTAssertEqual(model.bisectPhase, .inactive)
        XCTAssertTrue(model.bisectGoodCommits.isEmpty)
        XCTAssertTrue(model.bisectBadCommits.isEmpty)
        XCTAssertTrue(model.bisectCurrentHash.isEmpty)
        XCTAssertTrue(model.bisectAIExplanation.isEmpty)
        XCTAssertFalse(model.isBisectAILoading)
    }

    // MARK: - isBisectActive

    @MainActor
    func testIsBisectActiveWhenInactive() {
        let model = RepositoryViewModel()
        model.bisectPhase = .inactive
        XCTAssertFalse(model.isBisectActive)
    }

    @MainActor
    func testIsBisectActiveWhenActive() {
        let model = RepositoryViewModel()
        model.bisectPhase = .active(currentHash: "abc", stepsRemaining: 2)
        XCTAssertTrue(model.isBisectActive)
    }

    @MainActor
    func testIsBisectActiveWhenFoundCulprit() {
        let model = RepositoryViewModel()
        model.bisectPhase = .foundCulprit(commitHash: "abc")
        XCTAssertTrue(model.isBisectActive)
    }

    @MainActor
    func testIsBisectActiveWhenAwaiting() {
        let model = RepositoryViewModel()
        model.bisectPhase = .awaitingGoodCommit(badCommitHash: "abc")
        XCTAssertTrue(model.isBisectActive)
    }

    // MARK: - Hash Validation (SEC-1,2)

    @MainActor
    func testParseBisectOutputRejectsInvalidHash() {
        let model = RepositoryViewModel()
        // A non-hex "hash" should not be returned as a culprit
        let output = "--exec=malicious is the first bad commit\n"
        let result = model.parseBisectOutput(output)
        if case .foundCulprit = result {
            XCTFail("Should not return .foundCulprit for non-hex hash")
        }
    }

    @MainActor
    func testParseBisectOutputRejectsInvalidBracketHash() {
        let model = RepositoryViewModel()
        let output = "[--output=/etc/passwd] Some subject\n"
        let result = model.parseBisectOutput(output)
        if case .continuing(let hash, _) = result {
            XCTAssertNotEqual(hash, "--output=/etc/passwd", "Should not extract non-hex hash from brackets")
        }
    }

    @MainActor
    func testParseBisectOutputTruncatesLargeInput() {
        let model = RepositoryViewModel()
        // Create a very large output — parsing should not crash
        let largeOutput = String(repeating: "x", count: 50_000)
        let result = model.parseBisectOutput(largeOutput)
        // Should fall through to the fallback
        if case .continuing = result {
            // Good — did not crash
        } else {
            XCTFail("Expected .continuing for garbage output")
        }
    }

    @MainActor
    func testStartBisectRejectsInvalidHash() {
        let model = RepositoryViewModel()
        model.startBisect(badCommitHash: "--exec=bad")
        // Should set lastError and NOT start bisect
        XCTAssertNotNil(model.lastError)
        XCTAssertEqual(model.bisectPhase, .inactive)
    }

    @MainActor
    func testMarkCommitGoodRejectsInvalidHash() {
        let model = RepositoryViewModel()
        model.bisectPhase = .awaitingGoodCommit(badCommitHash: "abc1234")
        model.markCommitGood("not-a-hash!")
        XCTAssertNotNil(model.lastError)
    }
}

// MARK: - BisectCommitRole Equatable conformance for tests

extension BisectCommitRole: Equatable {}
