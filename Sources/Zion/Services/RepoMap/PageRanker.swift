import Foundation

// MARK: - PageRanker

/// Pure Swift power-method PageRank for a directed graph of file nodes.
/// Damping = 0.85, maxIters = 30, converges when Δ < 1e-4.
/// Personalization vector supported for biased restart.
struct PageRanker: Sendable {

    static let defaultDamping: Double = 0.85
    static let defaultMaxIters: Int = 30
    static let convergenceEpsilon: Double = 1e-4

    /// Computes PageRank over a directed graph of file nodes.
    /// - Parameters:
    ///   - nodes: ordered list of file paths
    ///   - edges: adjacency from source file → set of destination files
    ///            (source file references symbols defined in dest file)
    ///   - personalization: per-node restart weight; if nil, uniform 1/N
    ///   - damping: damping factor (default 0.85)
    ///   - maxIters: hard iteration cap (default 30)
    ///   - epsilon: convergence threshold for sum |Δ| (default 1e-4)
    /// - Returns: scores keyed by file path, summing to ~1.0
    static func rank(
        nodes: [String],
        edges: [String: Set<String>],
        personalization: [String: Double]? = nil,
        damping: Double = defaultDamping,
        maxIters: Int = defaultMaxIters,
        epsilon: Double = convergenceEpsilon
    ) -> [String: Double] {
        let n = nodes.count
        guard n > 0 else { return [:] }

        // Map node → index for O(1) lookups
        var nodeIndex: [String: Int] = [:]
        nodeIndex.reserveCapacity(n)
        for (i, node) in nodes.enumerated() {
            nodeIndex[node] = i
        }

        // Build personalization vector (normalized to sum=1).
        // Nodes absent from the explicit dict receive weight 1 (default).
        var p = [Double](repeating: 1.0 / Double(n), count: n)
        if let personalization {
            var raw = [Double](repeating: 1.0, count: n) // default weight 1
            for (node, weight) in personalization {
                if let idx = nodeIndex[node] {
                    raw[idx] = max(0.0, weight)
                }
            }
            let total = raw.reduce(0, +)
            if total > 0 {
                p = raw.map { $0 / total }
            }
        }

        // Build in-links: inLinks[dest] = [src indices] and out-degree per node index.
        var inLinks = [[Int]](repeating: [], count: n)
        var outDegree = [Int](repeating: 0, count: n)

        for (src, dests) in edges {
            guard let srcIdx = nodeIndex[src] else { continue }
            for dest in dests {
                guard let destIdx = nodeIndex[dest], destIdx != srcIdx else { continue }
                inLinks[destIdx].append(srcIdx)
                outDegree[srcIdx] += 1
            }
        }

        // Initial rank: uniform.
        var rank = [Double](repeating: 1.0 / Double(n), count: n)
        var newRank = [Double](repeating: 0.0, count: n)

        for _ in 0 ..< maxIters {
            // Dangling mass: sum of rank for nodes with out-degree == 0.
            // Distributed uniformly across all nodes.
            var danglingMass = 0.0
            for i in 0 ..< n where outDegree[i] == 0 {
                danglingMass += rank[i]
            }
            let danglingPerNode = damping * danglingMass / Double(n)

            // Classic PageRank update:
            // newRank[v] = (1-d)*p[v] + d * (Σ rank[u]/outDeg[u] for u→v) + danglingPerNode
            for v in 0 ..< n {
                var inboundSum = 0.0
                for u in inLinks[v] {
                    inboundSum += rank[u] / Double(outDegree[u])
                }
                newRank[v] = (1.0 - damping) * p[v]
                    + damping * inboundSum
                    + danglingPerNode
            }

            // Check convergence: sum of absolute differences.
            var delta = 0.0
            for i in 0 ..< n {
                delta += abs(newRank[i] - rank[i])
            }

            // Swap buffers (avoids allocation each iteration).
            swap(&rank, &newRank)

            if delta < epsilon {
                break
            }
        }

        // Build result dictionary.
        var result: [String: Double] = [:]
        result.reserveCapacity(n)
        for (i, node) in nodes.enumerated() {
            result[node] = rank[i]
        }
        return result
    }
}
