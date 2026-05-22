// PendingChanges.swift — zion_pending_changes tool

import Foundation

struct PendingChanges: Tool {
    let repoURL: URL

    var name: String { "zion_pending_changes" }
    var description: String { "Return staged and unstaged changes in the working tree." }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([:]),
            "required": .array([])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        // porcelain v1 for simplicity: XY PATH or XY PATH -> RENAMED
        let raw = try git(
            args: ["status", "--porcelain"],
            repoURL: repoURL
        )

        var staged: [JSONValue] = []
        var unstaged: [JSONValue] = []

        for line in raw.components(separatedBy: "\n") {
            guard line.count >= 3 else { continue }
            let x = String(line[line.startIndex])       // index status
            let y = String(line[line.index(line.startIndex, offsetBy: 1)]) // work-tree status
            let path = String(line.dropFirst(3))

            if x != " " && x != "?" {
                staged.append(.object(["path": .string(path), "status": .string(x)]))
            }
            if y != " " && y != "?" {
                unstaged.append(.object(["path": .string(path), "status": .string(y)]))
            }
            // untracked
            if x == "?" && y == "?" {
                unstaged.append(.object(["path": .string(path), "status": .string("?")]))
            }
        }

        return makeContent(["staged": .array(staged), "unstaged": .array(unstaged)])
    }
}
