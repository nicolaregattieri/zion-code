// GitLog.swift — zion_git_log tool

import Foundation

struct GitLog: Tool {
    let repoURL: URL
    static let maximumLimit = 200

    var name: String { "zion_git_log" }
    var description: String { "Return recent commits from the repository." }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "branch": .object([
                    "type": .string("string"),
                    "description": .string("Branch name. Defaults to HEAD.")
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum number of commits to return. Default 50.")
                ])
            ]),
            "required": .array([])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        let branch = try Self.validatedBranch(args.optionalString("branch") ?? "HEAD")
        let requestedLimit: Int?
        if let v = args["limit"], case .int(let n) = v {
            requestedLimit = n
        } else {
            requestedLimit = nil
        }
        let limit = Self.boundedLimit(requestedLimit)

        // Format: sha\x1fauthor\x1fdate\x1fsubject
        let sep = "\u{1f}"
        let format = "%H\(sep)%aN\(sep)%aI\(sep)%s"
        let logOutput = try git(
            args: ["log", "--no-pager", "--pretty=format:\(format)",
                   "--name-only", "-\(limit)", branch],
            repoURL: repoURL
        )

        let commits = parseLog(logOutput, sep: sep)
        let commitsJSON: [JSONValue] = commits.map { c in
            .object([
                "sha":     .string(c.sha),
                "author":  .string(c.author),
                "date":    .string(c.date),
                "subject": .string(c.subject),
                "files":   .array(c.files.map { .string($0) })
            ])
        }
        let result: [String: JSONValue] = ["commits": .array(commitsJSON)]
        return makeContent(result)
    }

    static func boundedLimit(_ requested: Int?) -> Int {
        max(1, min(requested ?? 50, maximumLimit))
    }

    static func validatedBranch(_ branch: String) throws -> String {
        if branch == "HEAD" { return branch }
        let range = NSRange(branch.startIndex..., in: branch)
        let valid = try? NSRegularExpression(pattern: #"^[A-Za-z0-9][A-Za-z0-9._/-]*$"#)
            .firstMatch(in: branch, range: range)
        guard valid != nil,
              !branch.contains(".."),
              !branch.contains("//"),
              !branch.hasSuffix("/") else {
            throw ToolError.invalidArgument("branch", "expected a branch name or HEAD")
        }
        return branch
    }

    private struct Commit {
        var sha: String
        var author: String
        var date: String
        var subject: String
        var files: [String]
    }

    private func parseLog(_ raw: String, sep: String) -> [Commit] {
        // Each commit block starts with the format line, then file names, separated by blank lines
        var commits: [Commit] = []
        var current: Commit? = nil
        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(sep) {
                // new commit header
                if let c = current { commits.append(c) }
                let parts = trimmed.components(separatedBy: sep)
                guard parts.count >= 4 else { continue }
                current = Commit(sha: parts[0], author: parts[1], date: parts[2],
                                 subject: parts[3...].joined(separator: sep), files: [])
            } else if !trimmed.isEmpty, var c = current {
                c.files.append(trimmed)
                current = c
            }
        }
        if let c = current { commits.append(c) }
        return commits
    }
}
