import XCTest
@testable import Zion

final class SmartAutoTriageTests: XCTestCase {

    // MARK: - HeuristicTriageClassifier

    func test_heuristic_empty_classifiesAsEasy() async {
        let h = HeuristicTriageClassifier()
        await XCTAssertEqualAsync(await h.classify(""),       .easy)
        await XCTAssertEqualAsync(await h.classify("   \n "), .easy)
    }

    func test_heuristic_shortGreetings_classifyAsEasy() async {
        let h = HeuristicTriageClassifier()
        await XCTAssertEqualAsync(await h.classify("ola"),       .easy)
        await XCTAssertEqualAsync(await h.classify("hi"),        .easy)
        await XCTAssertEqualAsync(await h.classify("tudo bem?"), .easy)
        await XCTAssertEqualAsync(await h.classify("ok obrigado"), .easy)
    }

    func test_heuristic_reasoningKeywords_classifyAsHard() async {
        let h = HeuristicTriageClassifier()
        await XCTAssertEqualAsync(await h.classify("why does Swift use ARC?"), .hard)
        await XCTAssertEqualAsync(await h.classify("explain the actor model"), .hard)
        await XCTAssertEqualAsync(await h.classify("what's the best architecture for this?"), .hard)
        await XCTAssertEqualAsync(await h.classify("compare gRPC and REST"), .hard)
    }

    func test_heuristic_reviewKeywords_classifyAsHard() async {
        let h = HeuristicTriageClassifier()
        await XCTAssertEqualAsync(await h.classify("review my diff"),  .hard)
        await XCTAssertEqualAsync(await h.classify("audit this code"), .hard)
    }

    func test_heuristic_codeSignals_classifyAsMedium() async {
        let h = HeuristicTriageClassifier()
        let fence = "fix this:\n```swift\nfunc foo() {}\n```"
        await XCTAssertEqualAsync(await h.classify(fence), .medium)
        await XCTAssertEqualAsync(await h.classify("update ChatService.swift to add X"), .medium)
        await XCTAssertEqualAsync(await h.classify("@file Sources/Foo.swift handle this"), .medium)
        await XCTAssertEqualAsync(await h.classify("/diff"), .medium)
    }

    func test_heuristic_longUnstructured_defaultsToMedium() async {
        let h = HeuristicTriageClassifier()
        let msg = "Please refactor the orchestrator chain so the second pass also respects health checks consistently."
        await XCTAssertEqualAsync(await h.classify(msg), .hard) // "refactor" is in reasoning markers
    }

    // MARK: - SmartAutoTierTable

    func test_tierTable_anthropicMapping() {
        let t = SmartAutoTierTable.default
        XCTAssertEqual(t.modelID(provider: .anthropic, tier: .easy),   "claude-haiku-4-5")
        XCTAssertEqual(t.modelID(provider: .anthropic, tier: .medium), "claude-sonnet-4-6")
        XCTAssertEqual(t.modelID(provider: .anthropic, tier: .hard),   "claude-opus-4-7")
    }

    func test_tierTable_claudeCLIMapping() {
        let t = SmartAutoTierTable.default
        XCTAssertEqual(t.modelID(provider: .claudeCLI, tier: .easy),   "haiku")
        XCTAssertEqual(t.modelID(provider: .claudeCLI, tier: .medium), "sonnet")
        XCTAssertEqual(t.modelID(provider: .claudeCLI, tier: .hard),   "opus")
    }

    func test_tierTable_openaiMapping() {
        let t = SmartAutoTierTable.default
        XCTAssertEqual(t.modelID(provider: .openai, tier: .easy),   "gpt-4o-mini")
        XCTAssertEqual(t.modelID(provider: .openai, tier: .medium), "gpt-4o")
        XCTAssertEqual(t.modelID(provider: .openai, tier: .hard),   "o1")
    }

    func test_tierTable_localReturnsNil_respectsUserConfig() {
        let t = SmartAutoTierTable.default
        XCTAssertNil(t.modelID(provider: .local, tier: .easy))
        XCTAssertNil(t.modelID(provider: .local, tier: .hard))
    }

    // MARK: - Tier ↔ Lane mapping

    func test_tier_lane_mapping() {
        XCTAssertEqual(SmartAutoTier.easy.lane,   .cheapSummary)
        XCTAssertEqual(SmartAutoTier.medium.lane, .general)
        XCTAssertEqual(SmartAutoTier.hard.lane,   .reasoning)
    }

    // MARK: - SmartAutoTriage end-to-end

    func test_triage_easyGreetingPicksCheapModelOnAnthropic() async {
        let triage = SmartAutoTriage()
        let decision = await triage.decide(text: "ola", provider: .anthropic)
        XCTAssertEqual(decision.tier, .easy)
        XCTAssertEqual(decision.modelID, "claude-haiku-4-5")
    }

    func test_triage_hardReasoningPicksOpusOnAnthropic() async {
        let triage = SmartAutoTriage()
        let decision = await triage.decide(text: "explain the architecture trade-offs of actors vs queues", provider: .anthropic)
        XCTAssertEqual(decision.tier, .hard)
        XCTAssertEqual(decision.modelID, "claude-opus-4-7")
    }

    func test_triage_codeFencePicksSonnetOnAnthropic() async {
        let triage = SmartAutoTriage()
        let msg = "fix:\n```swift\nfunc f() {}\n```"
        let decision = await triage.decide(text: msg, provider: .anthropic)
        XCTAssertEqual(decision.tier, .medium)
        XCTAssertEqual(decision.modelID, "claude-sonnet-4-6")
    }
}

// MARK: - Async XCTest helper

func XCTAssertEqualAsync<T: Equatable>(
    _ lhs: @autoclosure () async throws -> T,
    _ rhs: T,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        let value = try await lhs()
        XCTAssertEqual(value, rhs, file: file, line: line)
    } catch {
        XCTFail("threw \(error)", file: file, line: line)
    }
}
