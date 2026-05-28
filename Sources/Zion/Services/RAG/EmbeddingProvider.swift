import Foundation
import NaturalLanguage

// MARK: - Error types

enum EmbeddingError: Error, Sendable {
    /// The embedding backend is not available (e.g. stub or missing asset).
    case backendUnavailable
    /// The NL asset failed to load.
    case assetLoadFailed(String)
}

// MARK: - Protocol

/// A Sendable embedding backend that converts text strings into dense float vectors.
protocol EmbeddingProvider: Sendable {
    /// Dimensionality of the output vectors.
    var dim: Int { get }

    /// Stable identifier for this backend (e.g. used in index metadata).
    var backendID: String { get }

    /// Embed a batch of texts. Returns one vector per input, each of length `dim`.
    func embed(_ texts: [String]) async throws -> [[Float]]

    /// Returns true when the backend's assets are downloaded and ready to use.
    func ready() async -> Bool
}

// MARK: - NLContextualEmbeddingProvider

/// Wraps `NLContextualEmbedding` (macOS 14+) for Latin-script languages.
/// Mean-pools per-token vectors to produce a fixed `dim`-length output.
@available(macOS 14, *)
struct NLContextualEmbeddingProvider: EmbeddingProvider {

    let dim: Int = 512
    let backendID: String = "nl-contextual-latin-512"

    // MARK: ready()

    func ready() async -> Bool {
        guard let embedding = NLContextualEmbedding(language: .english) else {
            return false
        }
        guard embedding.hasAvailableAssets else {
            // Fire background download without blocking.
            Task.detached(priority: .background) {
                try? await embedding.requestAssets()
            }
            return false
        }
        return true
    }

    // MARK: embed(_:)

    func embed(_ texts: [String]) async throws -> [[Float]] {
        guard let embedding = NLContextualEmbedding(language: .english) else {
            throw EmbeddingError.assetLoadFailed("NLContextualEmbedding unavailable for .english")
        }

        var results: [[Float]] = []
        results.reserveCapacity(texts.count)

        for text in texts {
            let vector = try await embedSingleText(text, using: embedding)
            results.append(vector)
        }

        return results
    }

    // MARK: Private helpers

    private func embedSingleText(
        _ text: String,
        using embedding: NLContextualEmbedding
    ) async throws -> [Float] {
        guard !text.isEmpty else {
            return [Float](repeating: 0, count: dim)
        }

        // NLContextualEmbeddingResult is obtained synchronously from a pre-loaded embedding.
        // The actual compute is lightweight once assets are present.
        let result: NLContextualEmbeddingResult
        do {
            result = try embedding.embeddingResult(for: text, language: .english)
        } catch {
            // Model could not process the text; return zero vector.
            return [Float](repeating: 0, count: dim)
        }

        // Mean-pool all token vectors to produce a single dim-length vector.
        var accumulator = [Double](repeating: 0.0, count: dim)
        var tokenCount = 0

        result.enumerateTokenVectors(in: text.startIndex ..< text.endIndex) { tokenVector, _ in
            // tokenVector is [Double] of length equal to the model's native dim.
            let count = min(tokenVector.count, self.dim)
            for i in 0 ..< count {
                accumulator[i] += tokenVector[i]
            }
            tokenCount += 1
            return true
        }

        guard tokenCount > 0 else {
            return [Float](repeating: 0, count: dim)
        }

        let scale = 1.0 / Double(tokenCount)
        return accumulator.prefix(dim).map { Float($0 * scale) }
    }
}

// MARK: - QodoEmbeddingProvider

/// Stub conformance for the Qodo embedding backend.
/// Returns `EmbeddingError.backendUnavailable` until the Core ML asset path lands.
/// Gated by `Constants.Feature.ragQodoEnabled`.
struct QodoEmbeddingProvider: EmbeddingProvider {

    let dim: Int = 1536
    let backendID: String = "qodo-codebert-1536"

    func ready() async -> Bool {
        return Constants.Feature.ragQodoEnabled
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        throw EmbeddingError.backendUnavailable
    }
}
