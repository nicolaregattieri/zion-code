// Worktrees.swift — zion_worktrees tool

import Foundation

struct Worktrees: Tool {
    let repoURL: URL

    var name: String { "zion_worktrees" }
    var description: String { "List all git worktrees for this repository." }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([:]),
            "required": .array([])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        let raw = try git(
            args: ["worktree", "list", "--porcelain"],
            repoURL: repoURL
        )

        var worktrees: [JSONValue] = []
        var block: [String: String] = [:]

        func flush() {
            guard let path = block["worktree"] else { return }
            let branch   = block["branch"] ?? ""
            let head     = block["HEAD"] ?? ""
            let isBare   = block["bare"] != nil
            let isCurrent = block["current"] != nil
            // main worktree is the first one (no "linked" key)
            let isMain   = block["main"] != nil

            var branchShort = branch
            if branchShort.hasPrefix("refs/heads/") {
                branchShort = String(branchShort.dropFirst("refs/heads/".count))
            }

            worktrees.append(.object([
                "path":       .string(path),
                "branch":     .string(isBare ? "(bare)" : branchShort),
                "head":       .string(head),
                "is_current": .bool(isCurrent),
                "is_main":    .bool(isMain)
            ]))
        }

        var isFirst = true
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                flush()
                block = [:]
                isFirst = false
                continue
            }
            if let spaceIdx = trimmed.firstIndex(of: " ") {
                let key = String(trimmed[trimmed.startIndex..<spaceIdx])
                let val = String(trimmed[trimmed.index(after: spaceIdx)...])
                block[key] = val
            } else {
                // bare flag keywords
                block[trimmed] = ""
            }
            // Mark first block as main
            if block["worktree"] != nil && isFirst {
                block["main"] = ""
            }
        }
        // flush last block
        flush()

        return makeContent(["worktrees": .array(worktrees)])
    }
}
