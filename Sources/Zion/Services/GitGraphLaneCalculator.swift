import Foundation

struct CommitGraphLayout {
    let id: String
    let lane: Int
    let nodeColorKey: Int
    let incomingLanes: [Int]
    let outgoingLanes: [Int]
    let laneColors: [LaneColor]
    let outgoingEdges: [LaneEdge]
}

struct GitGraphLaneCalculator {
    /// Walk first-parent chain from the repo's main line to build the set of lane-0 commit hashes.
    static func mainFirstParentChain(from commits: [ParsedCommit]) -> Set<String> {
        guard let anchorCommit = preferredMainlineCommit(in: commits) else {
            return []
        }

        let parentIndex = Dictionary(uniqueKeysWithValues: commits.map { ($0.hash, $0.parents) })
        var chain = Set<String>()
        var current = anchorCommit.hash

        while true {
            chain.insert(current)
            guard let parents = parentIndex[current], let firstParent = parents.first else {
                break
            }
            current = firstParent
        }

        return chain
    }

    private static func preferredMainlineCommit(in commits: [ParsedCommit]) -> ParsedCommit? {
        let preferredNames = ["main", "master", "trunk"]

        for name in preferredNames {
            if let commit = commits.first(where: { commit in
                commit.decorations.contains { decorationMatchesMainline($0, preferredName: name) }
            }) {
                return commit
            }
        }

        return commits.first(where: { commit in
            commit.decorations.contains { $0.contains("HEAD") }
        })
    }

    private static func decorationMatchesMainline(_ decoration: String, preferredName: String) -> Bool {
        let trimmed = decoration.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == preferredName { return true }
        if trimmed.hasPrefix("HEAD -> ") {
            let headTarget = String(trimmed.dropFirst("HEAD -> ".count))
            return headTarget == preferredName
        }
        return trimmed.hasSuffix("/\(preferredName)")
    }

    func layout(for commits: [ParsedCommit], mainChain: Set<String> = []) -> [CommitGraphLayout] {
        var activeLaneHashes: [String?] = []
        var activeLaneColorKeys: [Int?] = []
        var colorKeyByHash: [String: Int] = [:]
        var nextColorKey = 0
        var rows: [CommitGraphLayout] = []
        rows.reserveCapacity(commits.count)

        // Pre-assign color key 0 for ALL main-chain commits so the main line color is consistent
        if !mainChain.isEmpty {
            for hash in mainChain {
                colorKeyByHash[hash] = 0
            }
            nextColorKey = 1
        }

        for commit in commits {
            let incomingLaneColors = activeLaneColors(
                hashes: activeLaneHashes,
                colorKeys: activeLaneColorKeys,
                colorKeyByHash: &colorKeyByHash,
                nextColorKey: &nextColorKey
            )
            let isMainChain = mainChain.contains(commit.hash)
            let lane = laneForCommit(
                commit.hash,
                isMainChain: isMainChain,
                hashes: &activeLaneHashes,
                colorKeys: &activeLaneColorKeys
            )
            let nodeColorKey = colorKey(
                forCommit: commit.hash,
                lane: lane,
                hashes: &activeLaneHashes,
                colorKeys: &activeLaneColorKeys,
                colorKeyByHash: &colorKeyByHash,
                nextColorKey: &nextColorKey
            )
            consumeCommitIfReserved(
                commit.hash,
                lane: lane,
                hashes: &activeLaneHashes,
                colorKeys: &activeLaneColorKeys
            )
            // Phase 1: Reserve lanes for all parents, collecting intended lanes.
            // Edges are NOT built yet — later reservations may evict earlier ones.
            var parentInfo: [(hash: String, colorKey: Int, intendedLane: Int)] = []

            if let firstParent = commit.parents.first {
                let firstRes = reserveLane(
                    for: firstParent,
                    preferred: lane,
                    preferredColorKey: nodeColorKey,
                    mainChain: mainChain,
                    hashes: &activeLaneHashes,
                    colorKeys: &activeLaneColorKeys,
                    colorKeyByHash: &colorKeyByHash,
                    nextColorKey: &nextColorKey
                )
                parentInfo.append((firstParent, firstRes.colorKey, firstRes.lane))

                for parent in commit.parents.dropFirst() {
                    let mergeRes = reserveLane(
                        for: parent,
                        preferred: lane + 1,
                        preferredColorKey: nil,
                        mainChain: mainChain,
                        hashes: &activeLaneHashes,
                        colorKeys: &activeLaneColorKeys,
                        colorKeyByHash: &colorKeyByHash,
                        nextColorKey: &nextColorKey
                    )
                    parentInfo.append((parent, mergeRes.colorKey, mergeRes.lane))
                }
            }

            // Phase 2: Build edges using each parent's *final* lane position.
            // If a parent was virtually reserved (not physically placed), fall
            // back to the intended lane from Phase 1.
            let edges: [LaneEdge] = parentInfo.map { entry in
                let finalLane = activeLaneHashes.firstIndex(where: { $0 == entry.hash })
                    ?? entry.intendedLane
                return LaneEdge(from: lane, to: finalLane, colorKey: entry.colorKey)
            }

            trimTrailingEmptyLanes(hashes: &activeLaneHashes, colorKeys: &activeLaneColorKeys)
            let outgoingLaneColors = activeLaneColors(
                hashes: activeLaneHashes,
                colorKeys: activeLaneColorKeys,
                colorKeyByHash: &colorKeyByHash,
                nextColorKey: &nextColorKey
            )
            var laneColorByLane: [Int: Int] = [:]
            for item in incomingLaneColors {
                laneColorByLane[item.lane] = item.colorKey
            }
            for item in outgoingLaneColors {
                laneColorByLane[item.lane] = item.colorKey
            }
            laneColorByLane[lane] = nodeColorKey
            for edge in edges {
                laneColorByLane[edge.from] = nodeColorKey
                laneColorByLane[edge.to] = edge.colorKey
            }
            let laneColors = laneColorByLane.keys.sorted().compactMap { laneIndex -> LaneColor? in
                guard let colorKey = laneColorByLane[laneIndex] else { return nil }
                return LaneColor(lane: laneIndex, colorKey: colorKey)
            }

            rows.append(
                CommitGraphLayout(
                    id: commit.hash,
                    lane: lane,
                    nodeColorKey: nodeColorKey,
                    incomingLanes: incomingLaneColors.map(\.lane).sorted(),
                    outgoingLanes: Array(Set(outgoingLaneColors.map(\.lane))).sorted(),
                    laneColors: laneColors,
                    outgoingEdges: edges
                )
            )
        }

        return rows
    }

    /// Ensures a main-chain hash occupies lane 0 by relocating whatever is currently there.
    private func evictToLane0(
        _ hash: String,
        hashes: inout [String?],
        colorKeys: inout [Int?]
    ) -> Int {
        ensureCapacity(0, hashes: &hashes, colorKeys: &colorKeys)

        // Already at lane 0 — nothing to do
        if hashes[0] == hash {
            return 0
        }

        // Find the lane this hash currently occupies (if any) so we can relocate the occupant there
        let previousLane = hashes.firstIndex(where: { $0 == hash })
        let occupant = hashes[0]
        let occupantColorKey = colorKeys[0]

        // Clear the hash's previous position FIRST to avoid overwriting the occupant
        // when targetLane == previousLane (swap case).
        if let previousLane {
            hashes[previousLane] = nil
            colorKeys[previousLane] = nil
        }

        // Relocate the lane 0 occupant (if any) to make room
        if let occupant {
            let targetLane: Int
            if let previousLane {
                // Swap: put the occupant where the main-chain hash was
                targetLane = previousLane
            } else {
                // Main-chain hash wasn't reserved yet — find a new lane for the occupant
                targetLane = firstAvailableLane(preferred: 1, hashes: &hashes, colorKeys: &colorKeys)
            }
            hashes[targetLane] = occupant
            colorKeys[targetLane] = occupantColorKey
        }

        // Place the main-chain hash at lane 0
        hashes[0] = hash
        return 0
    }

    private func laneForCommit(
        _ hash: String,
        isMainChain: Bool,
        hashes: inout [String?],
        colorKeys: inout [Int?]
    ) -> Int {
        if isMainChain {
            return evictToLane0(hash, hashes: &hashes, colorKeys: &colorKeys)
        }
        if let existing = hashes.firstIndex(where: { $0 == hash }) {
            return existing
        }
        // Non-main commits prefer lane 1+ to leave room
        return firstAvailableLane(preferred: 1, hashes: &hashes, colorKeys: &colorKeys)
    }

    private func consumeCommitIfReserved(
        _ hash: String,
        lane: Int,
        hashes: inout [String?],
        colorKeys: inout [Int?]
    ) {
        guard lane < hashes.count else { return }
        if hashes[lane] == hash {
            hashes[lane] = nil
            colorKeys[lane] = nil
        }
    }

    private func reserveLane(
        for hash: String,
        preferred: Int,
        preferredColorKey: Int?,
        mainChain: Set<String>,
        hashes: inout [String?],
        colorKeys: inout [Int?],
        colorKeyByHash: inout [String: Int],
        nextColorKey: inout Int
    ) -> (lane: Int, colorKey: Int) {
        let isMain = mainChain.contains(hash)

        if let existing = hashes.firstIndex(where: { $0 == hash }) {
            // Main-chain commit already reserved at wrong lane — evict to lane 0
            let lane: Int
            if isMain && existing != 0 {
                lane = evictToLane0(hash, hashes: &hashes, colorKeys: &colorKeys)
            } else {
                lane = existing
            }

            let colorKey: Int
            if isMain, let mainColor = colorKeyByHash[hash] {
                colorKey = mainColor
            } else {
                colorKey = colorKeys[lane]
                    ?? colorKeyByHash[hash]
                    ?? assignedColorKey(
                        for: hash,
                        preferredColorKey: preferredColorKey,
                        colorKeyByHash: &colorKeyByHash,
                        nextColorKey: &nextColorKey
                    )
            }

            colorKeys[lane] = colorKey
            return (lane, colorKey)
        }

        let lane: Int
        if isMain {
            // Virtual reservation: if lane 0 already holds a different mainChain
            // commit, don't evict it — that commit will be processed sooner and
            // needs lane 0. Return lane 0 as the edge target without placing this
            // hash, so no eviction or orphan lines are created.
            if hashes.count > 0,
               let lane0Hash = hashes[0],
               lane0Hash != hash,
               mainChain.contains(lane0Hash) {
                let colorKey = assignedColorKey(
                    for: hash,
                    preferredColorKey: preferredColorKey,
                    colorKeyByHash: &colorKeyByHash,
                    nextColorKey: &nextColorKey
                )
                return (0, colorKey)
            }
            lane = evictToLane0(hash, hashes: &hashes, colorKeys: &colorKeys)
        } else {
            lane = firstAvailableLane(preferred: preferred, hashes: &hashes, colorKeys: &colorKeys)
        }
        let colorKey = assignedColorKey(
            for: hash,
            preferredColorKey: preferredColorKey,
            colorKeyByHash: &colorKeyByHash,
            nextColorKey: &nextColorKey
        )
        hashes[lane] = hash
        colorKeys[lane] = colorKey
        return (lane, colorKey)
    }

    private func firstAvailableLane(
        preferred: Int,
        hashes: inout [String?],
        colorKeys: inout [Int?]
    ) -> Int {
        let normalizedPreferred = max(0, preferred)
        ensureCapacity(normalizedPreferred, hashes: &hashes, colorKeys: &colorKeys)

        if hashes[normalizedPreferred] == nil {
            return normalizedPreferred
        }

        var offset = 1
        while offset < 256 {
            let right = normalizedPreferred + offset
            ensureCapacity(right, hashes: &hashes, colorKeys: &colorKeys)
            if hashes[right] == nil {
                return right
            }

            let left = normalizedPreferred - offset
            if left >= 0 && hashes[left] == nil {
                return left
            }
            offset += 1
        }

        let fallback = hashes.count
        hashes.append(nil)
        colorKeys.append(nil)
        return fallback
    }

    private func ensureCapacity(
        _ index: Int,
        hashes: inout [String?],
        colorKeys: inout [Int?]
    ) {
        if index >= hashes.count {
            let amount = index - hashes.count + 1
            hashes.append(contentsOf: repeatElement(nil, count: amount))
            colorKeys.append(contentsOf: repeatElement(nil, count: amount))
        }
    }

    private func trimTrailingEmptyLanes(hashes: inout [String?], colorKeys: inout [Int?]) {
        while let last = hashes.last, last == nil {
            hashes.removeLast()
            if !colorKeys.isEmpty {
                colorKeys.removeLast()
            }
        }
    }

    private func colorKey(
        forCommit hash: String,
        lane: Int,
        hashes: inout [String?],
        colorKeys: inout [Int?],
        colorKeyByHash: inout [String: Int],
        nextColorKey: inout Int
    ) -> Int {
        if let existing = colorKeyByHash[hash] {
            return existing
        }
        if lane < hashes.count, hashes[lane] == hash, let laneColorKey = colorKeys[lane] {
            colorKeyByHash[hash] = laneColorKey
            return laneColorKey
        }
        let assigned = nextColorKey
        nextColorKey += 1
        colorKeyByHash[hash] = assigned
        return assigned
    }

    private func activeLaneColors(
        hashes: [String?],
        colorKeys: [Int?],
        colorKeyByHash: inout [String: Int],
        nextColorKey: inout Int
    ) -> [LaneColor] {
        hashes.enumerated().compactMap { index, value in
            guard let hash = value else { return nil }
            if let colorKey = colorKeys[index] {
                return LaneColor(lane: index, colorKey: colorKey)
            }
            if let knownColorKey = colorKeyByHash[hash] {
                return LaneColor(lane: index, colorKey: knownColorKey)
            }
            let assigned = nextColorKey
            nextColorKey += 1
            colorKeyByHash[hash] = assigned
            return LaneColor(lane: index, colorKey: assigned)
        }
    }

    private func assignedColorKey(
        for hash: String,
        preferredColorKey: Int?,
        colorKeyByHash: inout [String: Int],
        nextColorKey: inout Int
    ) -> Int {
        if let existing = colorKeyByHash[hash] {
            return existing
        }
        if let preferredColorKey {
            colorKeyByHash[hash] = preferredColorKey
            return preferredColorKey
        }
        let assigned = nextColorKey
        nextColorKey += 1
        colorKeyByHash[hash] = assigned
        return assigned
    }

    private func mergedLanes(_ lanes: [Int], include lane: Int) -> [Int] {
        Array(Set(lanes).union([lane])).sorted()
    }
}
