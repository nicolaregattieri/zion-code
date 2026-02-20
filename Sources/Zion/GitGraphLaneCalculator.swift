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

            let incomingLanesSet = Set(incomingLaneColors.map(\.lane))
            let edgeTargets = Set(edges.filter { $0.from != $0.to }.map(\.to))
            
            // Only filter out the outgoing lane if it's being "started" by a diagonal edge here.
            // If it was already active (in incomingLanes), it must continue as a straight line.
            let finalOutgoingLanes = outgoingLaneColors.map(\.lane).filter { l in
                if edgeTargets.contains(l) && !incomingLanesSet.contains(l) {
                    return false
                }
                return true
            }

            rows.append(
                CommitGraphLayout(
                    id: commit.hash,
                    lane: lane,
                    nodeColorKey: nodeColorKey,
                    incomingLanes: incomingLaneColors.map(\.lane).sorted(),
                    outgoingLanes: Array(Set(finalOutgoingLanes)).sorted(),
                    laneColors: laneColors,
                    outgoingEdges: edges
                )
            )
        }

        return rows
    }

    private func laneForCommit(
        _ hash: String,
        isMainChain: Bool,
        hashes: inout [String?],
        colorKeys: inout [Int?]
    ) -> Int {
        if let existing = hashes.firstIndex(where: { $0 == hash }) {
            return existing
        }
        // Main-chain commits prefer lane 0; non-main commits prefer lane 1+ to leave room
        let preferred = isMainChain ? 0 : 1
        return firstAvailableLane(preferred: preferred, hashes: &hashes, colorKeys: &colorKeys)
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
        if let existing = hashes.firstIndex(where: { $0 == hash }) {
            // For main-chain commits, always use pre-assigned color 0 regardless of what a feature branch set
            let isMain = mainChain.contains(hash)
            let colorKey: Int
            if isMain, let mainColor = colorKeyByHash[hash] {
                colorKey = mainColor
            } else {
                colorKey = colorKeys[existing]
                    ?? colorKeyByHash[hash]
                    ?? assignedColorKey(
                        for: hash,
                        preferredColorKey: preferredColorKey,
                        colorKeyByHash: &colorKeyByHash,
                        nextColorKey: &nextColorKey
                    )
            }

            // Relocate misplaced main-chain parent to lane 0 if it's available
            if isMain && existing != 0 {
                ensureCapacity(0, hashes: &hashes, colorKeys: &colorKeys)
                if hashes[0] == nil {
                    hashes[existing] = nil
                    colorKeys[existing] = nil
                    hashes[0] = hash
                    colorKeys[0] = colorKey
                    return (0, colorKey)
                }
            }

            colorKeys[existing] = colorKey
            return (existing, colorKey)
        }

        let lane = firstAvailableLane(preferred: preferred, hashes: &hashes, colorKeys: &colorKeys)
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
