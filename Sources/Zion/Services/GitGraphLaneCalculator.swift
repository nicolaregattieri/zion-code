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
    /// Walk first-parent chain from HEAD to build the set of main-line commit hashes.
    static func mainFirstParentChain(from commits: [ParsedCommit]) -> Set<String> {
        // Find the HEAD commit (has "HEAD" in decorations)
        guard let headCommit = commits.first(where: { commit in
            commit.decorations.contains { $0.contains("HEAD") }
        }) else {
            return []
        }

        let parentIndex = Dictionary(uniqueKeysWithValues: commits.map { ($0.hash, $0.parents) })
        var chain = Set<String>()
        var current = headCommit.hash

        while true {
            chain.insert(current)
            guard let parents = parentIndex[current], let firstParent = parents.first else {
                break
            }
            current = firstParent
        }

        return chain
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
            var edges: [LaneEdge] = []

            if let firstParent = commit.parents.first {
                let firstParentReservation = reserveLane(
                    for: firstParent,
                    preferred: lane,
                    preferredColorKey: nodeColorKey,
                    mainChain: mainChain,
                    hashes: &activeLaneHashes,
                    colorKeys: &activeLaneColorKeys,
                    colorKeyByHash: &colorKeyByHash,
                    nextColorKey: &nextColorKey
                )
                edges.append(
                    LaneEdge(
                        from: lane,
                        to: firstParentReservation.lane,
                        colorKey: firstParentReservation.colorKey
                    )
                )

                for parent in commit.parents.dropFirst() {
                    let mergeReservation = reserveLane(
                        for: parent,
                        preferred: lane + 1,
                        preferredColorKey: nil,
                        mainChain: mainChain,
                        hashes: &activeLaneHashes,
                        colorKeys: &activeLaneColorKeys,
                        colorKeyByHash: &colorKeyByHash,
                        nextColorKey: &nextColorKey
                    )
                    edges.append(
                        LaneEdge(
                            from: lane,
                            to: mergeReservation.lane,
                            colorKey: mergeReservation.colorKey
                        )
                    )
                }
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

        if let occupant = hashes[0] {
            // Lane 0 is occupied by another hash — relocate it
            let targetLane: Int
            if let previousLane {
                // Swap: put the occupant where the main-chain hash was
                targetLane = previousLane
            } else {
                // Main-chain hash wasn't reserved yet — find a new lane for the occupant
                targetLane = firstAvailableLane(preferred: 1, hashes: &hashes, colorKeys: &colorKeys)
            }
            hashes[targetLane] = occupant
            colorKeys[targetLane] = colorKeys[0]
        }

        // Clear the previous lane if the main-chain hash was already reserved elsewhere
        if let previousLane {
            hashes[previousLane] = nil
            colorKeys[previousLane] = nil
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
