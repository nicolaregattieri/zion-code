// BranchList.swift — zion_branch_list tool

import Foundation

struct BranchList: Tool {
    let repoURL: URL

    var name: String { "zion_branch_list" }
    var description: String { "List all local branches with tracking info." }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([:]),
            "required": .array([])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        // format: refname:short \x1f upstream:short \x1f ahead-behind:upstream \x1f HEAD
        let sep = "\u{1f}"
        let fmt = "%(refname:short)\(sep)%(upstream:short)\(sep)%(ahead-behind:upstream)\(sep)%(HEAD)"
        let raw = try git(
            args: ["for-each-ref", "--format=\(fmt)", "refs/heads/"],
            repoURL: repoURL
        )

        let branches: [JSONValue] = raw
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line -> JSONValue in
                let parts = line.components(separatedBy: sep)
                let name       = parts.count > 0 ? parts[0] : ""
                let upstream   = parts.count > 1 ? parts[1] : ""
                let aheadBehind = parts.count > 2 ? parts[2] : "0 0"
                let headMark   = parts.count > 3 ? parts[3] : ""

                let ab = aheadBehind.components(separatedBy: " ")
                let ahead  = Int(ab.first ?? "0") ?? 0
                let behind = Int(ab.last ?? "0") ?? 0
                let isCurrent = headMark == "*"

                var obj: [String: JSONValue] = [
                    "name":       .string(name),
                    "ahead":      .int(ahead),
                    "behind":     .int(behind),
                    "dirty_count":.int(0),
                    "is_current": .bool(isCurrent)
                ]
                if !upstream.isEmpty {
                    obj["upstream"] = .string(upstream)
                }
                return .object(obj)
            }

        return makeContent(["branches": .array(branches)])
    }
}
