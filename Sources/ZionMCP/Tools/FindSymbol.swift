// FindSymbol.swift — MCP `find_symbol` tool for the ZionMCP server.
// Searches a symbol snapshot written by the Zion host process.
// ZionMCP cannot import Zion directly, so this tool reads a JSON sidecar
// (<repoID>-symbols.json) written to Application Support/Zion/repo-map/
// by the SymbolIndexer.  Until that export is wired (P12.6), the tool is
// still registered so `tools/list` includes `find_symbol` for CLI providers.

import Foundation

// MARK: - find_symbol

struct FindSymbolTool: Tool {
    let repoURL: URL

    var name: String { "find_symbol" }
    var description: String {
        "Find a symbol by exact name across the repo. Returns matching file paths + line numbers + kinds. " +
        "Faster + more precise than grep for identifier search."
    }

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string")
                ]),
                "kind": .object([
                    "type": .string("string"),
                    "description": .string("Optional filter: function, struct, class, protocol, enum, extension, variable, constant, enumCase")
                ])
            ]),
            "required": .array([.string("name")])
        ]
    }

    func call(args: [String: JSONValue]) throws -> JSONValue {
        let symbolName = try args.requireString("name")
        let kindFilter = args.optionalString("kind")

        // Read the symbol sidecar JSON written by the Zion host process.
        // Format: [{ "file": "...", "kind": "...", "name": "...", "line": N }]
        let repoID = RepoMapTool.computeRepoID(for: repoURL)
        let snapshotURL = resolvedSnapshotDir().appendingPathComponent("\(repoID)-symbols.json")

        guard let data = try? Data(contentsOf: snapshotURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return makeContent([
                "available": .bool(false),
                "reason": .string("no_snapshot — run Zion to index the repo"),
                "matches": .array([])
            ])
        }

        let lowerName = symbolName.lowercased()
        var lines: [String] = []
        var matchObjects: [JSONValue] = []

        for entry in json {
            guard let entryName = entry["name"] as? String,
                  entryName.lowercased() == lowerName else { continue }
            let kind = entry["kind"] as? String ?? "unknown"
            if let kf = kindFilter, kind != kf { continue }
            let file = entry["file"] as? String ?? ""
            let line = entry["line"] as? Int ?? 0
            lines.append("\(file):\(line) — \(kind) \(entryName)")
            matchObjects.append(.object([
                "file": .string(file),
                "kind": .string(kind),
                "name": .string(entryName),
                "line": .int(line)
            ]))
        }

        if lines.isEmpty {
            return makeContent([
                "found": .bool(false),
                "message": .string("No symbols found matching '\(symbolName)'.")
            ])
        }

        return makeContent([
            "found": .bool(true),
            "matches": .array(matchObjects),
            "text": .string(lines.joined(separator: "\n"))
        ])
    }

    // MARK: - Helpers

    private func resolvedSnapshotDir() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Zion")
            .appendingPathComponent("repo-map")
    }
}
