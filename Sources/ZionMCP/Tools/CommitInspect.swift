// CommitInspect.swift — zion_commit_inspect tool

import Foundation

struct CommitInspect: Tool {
    let repoURL: URL

    var name: String { "zion_commit_inspect" }
    var description: String { "Return full details for a single commit including file diff stats." }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "sha": .object([
                    "type": .string("string"),
                    "description": .string("Commit SHA (full or abbreviated).")
                ])
            ]),
            "required": .array([.string("sha")])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        let sha = try args.requireString("sha")

        let sep = "\u{1f}"
        // Header: sha\x1fparents\x1fauthor\x1fdate\x1fsubject\x1fbody
        let fmt = "%H\(sep)%P\(sep)%aN\(sep)%aI\(sep)%s\(sep)%b"
        let header = try git(
            args: ["show", "--no-patch", "--no-pager", "--pretty=format:\(fmt)", sha],
            repoURL: repoURL
        )

        let parts = header.components(separatedBy: sep)
        guard parts.count >= 5 else {
            throw ToolError.executionFailed("Could not parse commit header for \(sha)")
        }
        let commitSha = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let parents = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
        let author  = parts[2]
        let date    = parts[3]
        let subject = parts[4]
        let body    = parts.count > 5 ? parts[5].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        // Numstat: additions\tdeletions\tpath
        let numstat = try git(
            args: ["show", "--no-patch", "--no-pager", "--numstat",
                   "--pretty=format:", sha],
            repoURL: repoURL
        )

        // Name-status for code letter
        let nameStatus = try git(
            args: ["show", "--no-patch", "--no-pager", "--name-status",
                   "--pretty=format:", sha],
            repoURL: repoURL
        )

        // Build status map: path -> status letter
        var statusMap: [String: String] = [:]
        for line in nameStatus.components(separatedBy: "\n") {
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 2 else { continue }
            let st = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let p  = cols.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !st.isEmpty && !p.isEmpty { statusMap[p] = st }
        }

        var files: [JSONValue] = []
        for line in numstat.components(separatedBy: "\n") {
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 3 else { continue }
            let add = Int(cols[0]) ?? 0
            let del = Int(cols[1]) ?? 0
            let p   = cols[2].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { continue }
            files.append(.object([
                "path":      .string(p),
                "status":    .string(statusMap[p] ?? "M"),
                "additions": .int(add),
                "deletions": .int(del)
            ]))
        }

        let result: [String: JSONValue] = [
            "sha":     .string(commitSha),
            "parents": .array(parents.map { .string($0) }),
            "author":  .string(author),
            "date":    .string(date),
            "subject": .string(subject),
            "body":    .string(body),
            "files":   .array(files)
        ]
        return makeContent(result)
    }
}
