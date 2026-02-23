import Foundation

struct EditorSymbolLocation: Identifiable, Hashable, Sendable {
    let relativePath: String
    let line: Int
    let column: Int
    let preview: String

    var id: String { "\(relativePath):\(line):\(column)" }
}

struct EditorSymbolQuery: Sendable {
    let symbol: String
    let currentFilePath: String?
    let lineText: String?
}

actor EditorSymbolIndex {
    private var cachedRepositoryURL: URL?
    private var indexedFiles: [URL] = []
    private var definitionsBySymbol: [String: [EditorSymbolLocation]] = [:]
    private var isBuilding = false

    private let ignoredDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "DerivedData", "node_modules", "dist", "build",
        "__pycache__", ".next", ".nuxt", ".idea", ".vscode", "Pods", ".gradle", ".cache"
    ]

    private let allowedExtensions: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp",
        "js", "jsx", "ts", "tsx",
        "py", "rb", "go", "java", "kt", "kts", "php", "rs", "cs",
        "json", "yml", "yaml", "toml", "md", "sh", "zsh", "bash"
    ]

    private let declarationPatterns: [NSRegularExpression] = {
        let patterns = [
            #"^\s*(?:public|private|fileprivate|internal|open|final|override|static|class|mutating|nonmutating|actor|convenience|required|indirect|\s)*(?:func|class|struct|enum|protocol|actor|typealias|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            #"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)"#,
            #"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(?:\([^)]*\)\s*=>|function\b)"#,
            #"^\s*(?:def|class)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            #"^\s*func\s+(?:\([^)]+\)\s*)?([A-Za-z_][A-Za-z0-9_]*)"#,
            #"^\s*(?:class|interface|enum|type)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private let jsImportPattern = try! NSRegularExpression(pattern: #"(?:from\s+|require\()\s*["']([^"']+)["']"#)
    private let swiftImportPattern = try! NSRegularExpression(pattern: #"^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)"#)

    func rebuild(repositoryURL: URL) async {
        guard !isBuilding else { return }
        isBuilding = true
        defer { isBuilding = false }

        cachedRepositoryURL = repositoryURL.standardizedFileURL
        indexedFiles = enumerateCandidateFiles(in: repositoryURL)
        definitionsBySymbol = [:]

        for fileURL in indexedFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let definitions = parseDefinitions(content: content, fileURL: fileURL, repositoryURL: repositoryURL)
            for (symbol, location) in definitions {
                definitionsBySymbol[symbol, default: []].append(location)
            }
        }

        for symbol in definitionsBySymbol.keys {
            definitionsBySymbol[symbol]?.sort {
                ($0.relativePath, $0.line, $0.column) < ($1.relativePath, $1.line, $1.column)
            }
            definitionsBySymbol[symbol] = Array(Set(definitionsBySymbol[symbol] ?? []))
                .sorted { ($0.relativePath, $0.line, $0.column) < ($1.relativePath, $1.line, $1.column) }
        }
    }

    func definitions(for query: EditorSymbolQuery, repositoryURL: URL) async -> [EditorSymbolLocation] {
        await ensureIndex(for: repositoryURL)
        let symbol = query.symbol.clean
        guard !symbol.isEmpty else { return [] }

        if let importResolved = resolveImport(query: query, repositoryURL: repositoryURL) {
            return importResolved
        }

        let direct = definitionsBySymbol[symbol] ?? []
        if !direct.isEmpty {
            return direct
        }

        return fallbackDefinitions(for: symbol, repositoryURL: repositoryURL)
    }

    func references(for query: EditorSymbolQuery, repositoryURL: URL, maxResults: Int = 300) async -> [EditorSymbolLocation] {
        await ensureIndex(for: repositoryURL)
        let symbol = query.symbol.clean
        guard !symbol.isEmpty else { return [] }

        var locations: [EditorSymbolLocation] = []
        let enforceBoundary = symbol.allSatisfy { isIdentifierCharacter($0) }

        for fileURL in indexedFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            for (lineIndex, lineText) in lines.enumerated() {
                for column in matchColumns(in: lineText, symbol: symbol, enforceBoundary: enforceBoundary) {
                    if locations.count >= maxResults {
                        return locations
                    }
                    locations.append(
                        EditorSymbolLocation(
                            relativePath: relativePath(for: fileURL, repositoryURL: repositoryURL),
                            line: lineIndex + 1,
                            column: column,
                            preview: lineText.trimmingCharacters(in: .whitespaces)
                        )
                    )
                }
            }
        }

        return locations.sorted { ($0.relativePath, $0.line, $0.column) < ($1.relativePath, $1.line, $1.column) }
    }

    private func ensureIndex(for repositoryURL: URL) async {
        let standardized = repositoryURL.standardizedFileURL
        guard cachedRepositoryURL != standardized || indexedFiles.isEmpty else { return }
        await rebuild(repositoryURL: repositoryURL)
    }

    private func enumerateCandidateFiles(in repositoryURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: repositoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey])
            let name = url.lastPathComponent

            if values?.isDirectory == true {
                if ignoredDirectories.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }
            guard allowedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            if let size = values?.fileSize, size > 1_500_000 { continue }
            files.append(url)
        }

        return files
    }

    private func parseDefinitions(content: String, fileURL: URL, repositoryURL: URL) -> [(String, EditorSymbolLocation)] {
        let lines = content.components(separatedBy: .newlines)
        var result: [(String, EditorSymbolLocation)] = []

        for (lineIndex, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let nsLine = rawLine as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            for regex in declarationPatterns {
                guard let match = regex.firstMatch(in: rawLine, options: [], range: fullRange),
                      match.numberOfRanges > 1 else {
                    continue
                }
                let symbolRange = match.range(at: 1)
                guard symbolRange.location != NSNotFound else { continue }
                let symbol = nsLine.substring(with: symbolRange)
                let location = EditorSymbolLocation(
                    relativePath: relativePath(for: fileURL, repositoryURL: repositoryURL),
                    line: lineIndex + 1,
                    column: symbolRange.location + 1,
                    preview: line
                )
                result.append((symbol, location))
                break
            }
        }

        return result
    }

    private func fallbackDefinitions(for symbol: String, repositoryURL: URL) -> [EditorSymbolLocation] {
        let declarationHints = ["func ", "class ", "struct ", "enum ", "protocol ", "typealias ", "let ", "var ", "def ", "function "]
        let enforceBoundary = symbol.allSatisfy { isIdentifierCharacter($0) }
        var matches: [EditorSymbolLocation] = []

        for fileURL in indexedFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for (lineIndex, lineText) in content.components(separatedBy: .newlines).enumerated() {
                if !declarationHints.contains(where: { lineText.contains($0) }) { continue }
                guard let firstColumn = matchColumns(in: lineText, symbol: symbol, enforceBoundary: enforceBoundary).first else {
                    continue
                }
                matches.append(
                    EditorSymbolLocation(
                        relativePath: relativePath(for: fileURL, repositoryURL: repositoryURL),
                        line: lineIndex + 1,
                        column: firstColumn,
                        preview: lineText.trimmingCharacters(in: .whitespaces)
                    )
                )
            }
        }

        return matches.sorted { ($0.relativePath, $0.line, $0.column) < ($1.relativePath, $1.line, $1.column) }
    }

    private func resolveImport(query: EditorSymbolQuery, repositoryURL: URL) -> [EditorSymbolLocation]? {
        guard let lineText = query.lineText?.clean, !lineText.isEmpty else { return nil }
        let nsLine = lineText as NSString
        let range = NSRange(location: 0, length: nsLine.length)

        if let jsMatch = jsImportPattern.firstMatch(in: lineText, options: [], range: range),
           jsMatch.numberOfRanges > 1 {
            let modulePath = nsLine.substring(with: jsMatch.range(at: 1))
            if let currentFilePath = query.currentFilePath {
                let resolved = resolveJavaScriptImport(modulePath: modulePath, currentFilePath: currentFilePath)
                if !resolved.isEmpty { return resolved }
            }
        }

        if let swiftMatch = swiftImportPattern.firstMatch(in: lineText, options: [], range: range),
           swiftMatch.numberOfRanges > 1 {
            let moduleName = nsLine.substring(with: swiftMatch.range(at: 1))
            if moduleName == query.symbol {
                let swiftCandidates = indexedFiles.filter {
                    $0.lastPathComponent == moduleName + ".swift"
                    || $0.path.contains("/\(moduleName)/")
                }
                if let first = swiftCandidates.first {
                    return [EditorSymbolLocation(relativePath: relativePath(for: first, repositoryURL: repositoryURL), line: 1, column: 1, preview: "import \(moduleName)")]
                }
            }
        }

        return nil
    }

    private func resolveJavaScriptImport(modulePath: String, currentFilePath: String) -> [EditorSymbolLocation] {
        guard modulePath.hasPrefix(".") || modulePath.hasPrefix("/") else { return [] }
        let currentURL = URL(fileURLWithPath: currentFilePath)
        let baseURL = currentURL.deletingLastPathComponent()
        let rawTarget: URL = if modulePath.hasPrefix("/") {
            URL(fileURLWithPath: modulePath)
        } else {
            baseURL.appendingPathComponent(modulePath)
        }

        let extensions = ["", ".ts", ".tsx", ".js", ".jsx", ".swift", ".json"]
        var candidates: [URL] = []
        for ext in extensions {
            let candidate = ext.isEmpty ? rawTarget : URL(fileURLWithPath: rawTarget.path + ext)
            if FileManager.default.fileExists(atPath: candidate.path) {
                candidates.append(candidate.standardizedFileURL)
            }
        }

        if FileManager.default.fileExists(atPath: rawTarget.path), isDirectory(path: rawTarget.path) {
            for indexName in ["index.ts", "index.tsx", "index.js", "index.jsx"] {
                let indexFile = rawTarget.appendingPathComponent(indexName)
                if FileManager.default.fileExists(atPath: indexFile.path) {
                    candidates.append(indexFile.standardizedFileURL)
                }
            }
        }

        return candidates.prefix(5).map {
            EditorSymbolLocation(relativePath: cachedRelativePath(for: $0), line: 1, column: 1, preview: modulePath)
        }
    }

    private func isDirectory(path: String) -> Bool {
        var isDir = ObjCBool(false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func relativePath(for fileURL: URL, repositoryURL: URL) -> String {
        let repoPath = repositoryURL.standardizedFileURL.path + "/"
        let fullPath = fileURL.standardizedFileURL.path
        if fullPath.hasPrefix(repoPath) {
            return String(fullPath.dropFirst(repoPath.count))
        }
        return fileURL.lastPathComponent
    }

    private func cachedRelativePath(for fileURL: URL) -> String {
        guard let repo = cachedRepositoryURL else { return fileURL.lastPathComponent }
        return relativePath(for: fileURL, repositoryURL: repo)
    }

    private func matchColumns(in line: String, symbol: String, enforceBoundary: Bool) -> [Int] {
        guard !line.isEmpty, !symbol.isEmpty else { return [] }
        var columns: [Int] = []
        var searchRange = line.startIndex..<line.endIndex
        while let found = line.range(of: symbol, options: [], range: searchRange) {
            let lower = found.lowerBound
            let upper = found.upperBound
            if !enforceBoundary || isBoundaryMatch(in: line, lower: lower, upper: upper) {
                columns.append(line.distance(from: line.startIndex, to: lower) + 1)
            }
            searchRange = upper..<line.endIndex
        }
        return columns
    }

    private func isBoundaryMatch(in line: String, lower: String.Index, upper: String.Index) -> Bool {
        let leftOK: Bool
        if lower == line.startIndex {
            leftOK = true
        } else {
            let prev = line[line.index(before: lower)]
            leftOK = !isIdentifierCharacter(prev)
        }

        let rightOK: Bool
        if upper == line.endIndex {
            rightOK = true
        } else {
            rightOK = !isIdentifierCharacter(line[upper])
        }
        return leftOK && rightOK
    }

    private func isIdentifierCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_"
    }
}
