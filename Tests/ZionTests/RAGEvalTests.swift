import XCTest
@testable import Zion

/// Phase 5 spec criteria #13 + #14 — eval harness + A/B promotion
/// gate. The full Recall@10 ≥ 0.55 e2e run requires
/// `ZION_RAG_E2E=1` to be set so CI does not pay the cold-asset cost.
/// `test_qodoAB_promotionGate` runs unconditionally and pins the
/// promotion math.
final class RAGEvalTests: XCTestCase {

    struct GoldenEntry: Codable {
        let query: String
        let expectedFiles: [String]
    }

    func test_qodoAB_promotionGate_unavailableWhenQodoMissing() {
        let decision = RAGBackendPromotion.decide(
            nlContextualRecall: 0.62,
            qodoRecall: nil
        )
        XCTAssertEqual(decision, .unavailable(reason: "qodo asset missing"))
    }

    func test_qodoAB_promotionGate_keepDefaultBelowThreshold() {
        let decision = RAGBackendPromotion.decide(
            nlContextualRecall: 0.62,
            qodoRecall: 0.66  // delta = 4% < 10%
        )
        XCTAssertEqual(decision, .keepDefault)
    }

    func test_qodoAB_promotionGate_promoteAboveThreshold() {
        let decision = RAGBackendPromotion.decide(
            nlContextualRecall: 0.55,
            qodoRecall: 0.70  // delta = 15% >= 10%
        )
        guard case .promoteQodo(let delta) = decision else {
            XCTFail("expected .promoteQodo, got \(decision)")
            return
        }
        XCTAssertEqual(delta, 0.15, accuracy: 1e-9)
    }

    func test_goldenSet_isParseable() throws {
        let url = try Self.goldenURL()
        let data = try Data(contentsOf: url)
        let entries = try JSONDecoder().decode([GoldenEntry].self, from: data)
        XCTAssertGreaterThanOrEqual(entries.count, 10)
        for entry in entries {
            XCTAssertFalse(entry.query.isEmpty)
            XCTAssertFalse(entry.expectedFiles.isEmpty)
        }
    }

    func test_scorer_matchesAbsoluteRelativeAndDirectory() {
        XCTAssertTrue(RAGEvalScorer.matches(
            path: "Sources/Zion/Services/RAG/RAGStore.swift",
            expected: "Sources/Zion/Services/RAG/RAGStore.swift"
        ))
        XCTAssertTrue(RAGEvalScorer.matches(
            path: "/abs/path/Sources/Zion/Services/RAG/RAGStore.swift",
            expected: "Sources/Zion/Services/RAG/RAGStore.swift"
        ))
        XCTAssertTrue(RAGEvalScorer.matches(
            path: "Sources/Zion/Services/SwiftTerm/Foo.swift",
            expected: "Sources/Zion/Services/SwiftTerm"
        ))
        XCTAssertFalse(RAGEvalScorer.matches(
            path: "Sources/Zion/Services/RAG/RAGSchema.swift",
            expected: "Sources/Zion/Services/RAG/RAGStore.swift"
        ))
    }

    func test_scorer_recallAtK_overGoldenStub() async throws {
        // Synthetic golden set + a fake runQuery that mirrors the
        // expected files for the first half of entries.
        let golden: [RAGEvalScorer.GoldenEntry] = [
            .init(query: "q1", expectedFiles: ["a.swift"]),
            .init(query: "q2", expectedFiles: ["b.swift"]),
            .init(query: "q3", expectedFiles: ["c.swift"]),
            .init(query: "q4", expectedFiles: ["d.swift"]),
        ]
        let answers: [String: [String]] = [
            "q1": ["a.swift", "z.swift"],
            "q2": ["b.swift"],
            "q3": ["x.swift"], // miss
            "q4": ["d.swift", "y.swift"],
        ]
        let result = try await RAGEvalScorer.score(entries: golden) { query in
            answers[query] ?? []
        }
        XCTAssertEqual(result.hits, 3)
        XCTAssertEqual(result.totalQueries, 4)
        XCTAssertEqual(result.recallAtK, 0.75, accuracy: 1e-9)
    }

    /// E2E gated behind `ZION_RAG_E2E=1`. Loads the fixture, indexes
    /// `Sources/Zion/`, runs `hybridSearch` per query, asserts
    /// Recall@10 ≥ `Constants.RAG.recallAtTenGate`.
    func test_goldenSet_recallAtTen_meetsGate() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ZION_RAG_E2E"] == "1",
            "Set ZION_RAG_E2E=1 to run the e2e eval"
        )

        // Locate repo root from this test file.
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()  // ZionTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root

        // Spin a temp RAGStore so the eval does not touch user data.
        let tempRepo = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rag-eval-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRepo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRepo) }

        let store = try RAGStore(repoURL: tempRepo)
        defer { Task { await store.close() } }
        let embedder = NLContextualEmbeddingProvider()
        let ready = await embedder.ready()
        try XCTSkipUnless(ready, "NLContextualEmbedding asset not available — run on a host where the OS has downloaded it")

        let indexer = RAGIndexer(store: store, embedder: embedder)
        // Index a *subset* of Sources/Zion/Services/RAG/ + chat + mention surfaces
        // so the eval stays under ~60s. The golden fixture targets these areas.
        let scopedRepo = repoRoot
        _ = try await indexer.index(repoURL: scopedRepo)

        let queryService = RAGQueryService(store: store, embedder: embedder)
        let goldenURL = try Self.goldenURL()
        let goldenData = try Data(contentsOf: goldenURL)
        let entries = try JSONDecoder().decode([RAGEvalScorer.GoldenEntry].self, from: goldenData)

        let result = try await RAGEvalScorer.score(entries: entries) { query in
            let hits = (try? await queryService.hybridSearch(query: query, limit: 10)) ?? []
            return hits.map { $0.chunk.path }
        }

        print("RAG eval Recall@10 = \(result.recallAtK) (\(result.hits)/\(result.totalQueries))")
        XCTAssertGreaterThanOrEqual(
            result.recallAtK,
            Constants.RAG.recallAtTenGate,
            "Recall@10 below the configured gate of \(Constants.RAG.recallAtTenGate)"
        )
    }

    private static func goldenURL() throws -> URL {
        // Use #filePath to resolve the fixture relative to this test file.
        let testFile = URL(fileURLWithPath: #filePath)
        let testsDir = testFile.deletingLastPathComponent()
        return testsDir
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("rag", isDirectory: true)
            .appendingPathComponent("golden.json")
    }
}
