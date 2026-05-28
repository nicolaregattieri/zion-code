import XCTest
@testable import Zion

@available(macOS 14, *)
final class EmbeddingProviderTests: XCTestCase {

    // MARK: - NLContextualEmbeddingProvider

    func test_nlContextual_emitsFixedDim() async throws {
        let provider = NLContextualEmbeddingProvider()

        let isReady = await provider.ready()
        guard isReady else {
            throw XCTSkip("NLContextualEmbedding assets not available in this environment")
        }

        let texts = ["func hello() { print(\"world\") }", "struct Foo { var bar: Int }"]
        let vectors = try await provider.embed(texts)

        XCTAssertEqual(vectors.count, texts.count, "Should return one vector per input text")
        for (index, vector) in vectors.enumerated() {
            XCTAssertEqual(
                vector.count,
                provider.dim,
                "Vector \(index) should have exactly \(provider.dim) dimensions, got \(vector.count)"
            )
        }
    }

    func test_nlContextual_emptyStringReturnsZeroVector() async throws {
        let provider = NLContextualEmbeddingProvider()

        let isReady = await provider.ready()
        guard isReady else {
            throw XCTSkip("NLContextualEmbedding assets not available in this environment")
        }

        let vectors = try await provider.embed([""])
        XCTAssertEqual(vectors.count, 1)
        XCTAssertEqual(vectors[0].count, provider.dim)
        XCTAssertTrue(
            vectors[0].allSatisfy { $0 == 0.0 },
            "Empty text should yield a zero vector"
        )
    }

    func test_nlContextual_backendID() {
        let provider = NLContextualEmbeddingProvider()
        XCTAssertEqual(provider.backendID, "nl-contextual-latin-512")
    }

    func test_nlContextual_dim() {
        let provider = NLContextualEmbeddingProvider()
        XCTAssertEqual(provider.dim, 512)
    }

    // MARK: - QodoEmbeddingProvider

    func test_qodo_dim() {
        let provider = QodoEmbeddingProvider()
        XCTAssertEqual(provider.dim, 1536)
    }

    func test_qodo_backendID() {
        let provider = QodoEmbeddingProvider()
        XCTAssertEqual(provider.backendID, "qodo-codebert-1536")
    }

    func test_qodo_embedThrowsBackendUnavailable() async {
        let provider = QodoEmbeddingProvider()
        do {
            _ = try await provider.embed(["hello"])
            XCTFail("Expected EmbeddingError.backendUnavailable to be thrown")
        } catch EmbeddingError.backendUnavailable {
            // Expected
        } catch {
            XCTFail("Expected EmbeddingError.backendUnavailable, got \(error)")
        }
    }

    func test_qodo_readyReflectsFeatureFlag() async {
        // Feature flag is off by default; ready() should return false.
        let provider = QodoEmbeddingProvider()
        let isReady = await provider.ready()
        let flagValue = Constants.Feature.ragQodoEnabled
        XCTAssertEqual(isReady, flagValue, "QodoEmbeddingProvider.ready() should mirror Constants.Feature.ragQodoEnabled")
    }
}
