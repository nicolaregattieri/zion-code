import Foundation

struct DetectedIndentation {
    let useTabs: Bool
    let tabSize: Int
}

enum IndentationDetector {

    static func detect(in content: String) -> DetectedIndentation? {
        let lines = content.components(separatedBy: "\n")
        let sampleLines = lines.prefix(100)

        var tabCount = 0
        var spaceCount = 0
        var diffs: [Int: Int] = [:]
        var prevIndent = 0

        for line in sampleLines {
            guard let firstChar = line.first else { continue }
            if firstChar == "\t" {
                tabCount += 1
                prevIndent = 0
            } else if firstChar == " " {
                spaceCount += 1
                let leading = line.prefix(while: { $0 == " " }).count
                let diff = abs(leading - prevIndent)
                if diff > 0 && diff <= 8 {
                    diffs[diff, default: 0] += 1
                }
                prevIndent = leading
            } else {
                prevIndent = 0
            }
        }

        guard tabCount > 0 || spaceCount > 0 else { return nil }

        if tabCount > spaceCount {
            return DetectedIndentation(useTabs: true, tabSize: 4)
        }

        // Find the smallest candidate where most diffs are exact multiples,
        // weighted by how closely diffs match the candidate itself.
        // A 4-space file has diffs of {4}, a 2-space file has diffs of {2, 4, 6}.
        // We pick the candidate whose exact match (diffs[candidate]) is highest.
        let candidateSizes = [2, 4, 8]
        var bestSize = 4
        var bestScore = 0
        for size in candidateSizes {
            let score = diffs[size, default: 0]
            if score > bestScore {
                bestScore = score
                bestSize = size
            }
        }

        return DetectedIndentation(useTabs: false, tabSize: bestSize)
    }
}
