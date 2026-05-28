import XCTest
@testable import Zion

/// Coverage test: verify the chunker processes ≥90% of lines across a
/// representative set of source files (the fixture corpus).
///
/// Coverage is defined as: `coveredLines / totalLines >= 0.90`, where
/// `coveredLines` is the union of all line ranges emitted by the chunker.
final class ASTChunkerCoverageTests: XCTestCase {

    private let chunker = ASTChunker()

    // MARK: - Fixtures path

    private var fixturesURL: URL {
        // Tests/ZionTests/Fixtures/rag/
        URL(fileURLWithPath: #filePath)          // ASTChunkerCoverageTests.swift
            .deletingLastPathComponent()         // Tests/ZionTests/
            .appendingPathComponent("Fixtures/rag")
    }

    // MARK: - Coverage baseline

    func test_repoChunkCoverage_meetsBaseline() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fixturesURL.path) else {
            throw XCTSkip("Fixtures directory not found at \(fixturesURL.path)")
        }

        // Collect all source files in the fixtures directory.
        let enumerator = fm.enumerator(
            at: fixturesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var sourceFiles: [URL] = []
        while let item = enumerator?.nextObject() as? URL {
            guard (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let ext = item.pathExtension.lowercased()
            // Only index files whose language we recognise.
            guard SourceLanguage.forExtension(ext) != nil else { continue }
            sourceFiles.append(item)
        }

        XCTAssertFalse(sourceFiles.isEmpty, "No source files found under \(fixturesURL.path)")

        var totalLines = 0
        var coveredLineUnions = 0

        for fileURL in sourceFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let fileLineCount = content.components(separatedBy: "\n").count
            guard fileLineCount > 0 else { continue }

            let ext = fileURL.pathExtension.lowercased()
            let lang = SourceLanguage.forExtension(ext) ?? .plain
            guard let chunks = try? chunker.chunk(file: fileURL, language: lang) else { continue }

            // Compute covered line union using a simple bitset approach.
            var coveredSet = Set<Int>()
            for chunk in chunks {
                for line in chunk.startLine...chunk.endLine {
                    coveredSet.insert(line)
                }
            }

            totalLines += fileLineCount
            // Clamp covered lines to actual file length (chunks may reference
            // trailing empty lines).
            coveredLineUnions += min(coveredSet.count, fileLineCount)
        }

        XCTAssertGreaterThan(totalLines, 0, "No lines counted — check fixtures")

        let coverage = Double(coveredLineUnions) / Double(totalLines)
        XCTAssertGreaterThanOrEqual(
            coverage, 0.90,
            String(format: "Line coverage %.1f%% below 90%% baseline (covered=%d / total=%d)",
                   coverage * 100, coveredLineUnions, totalLines)
        )
    }

    // MARK: - Per-fixture smoke tests

    func test_tsFixture_chunksWithFallback() throws {
        let tsFile = fixturesURL.appendingPathComponent("ts-sample/sample.ts")
        guard FileManager.default.fileExists(atPath: tsFile.path) else {
            throw XCTSkip("TypeScript fixture not found")
        }

        let chunks = try chunker.chunk(file: tsFile, language: .typescript)
        XCTAssertFalse(chunks.isEmpty, "Expected at least one chunk for TypeScript fixture")
        XCTAssertTrue(chunks.allSatisfy { $0.fallback },
                      "All chunks should be fallback=true until grammar is wired")
    }

    func test_pyFixture_chunksWithFallback() throws {
        let pyFile = fixturesURL.appendingPathComponent("py-sample/sample.py")
        guard FileManager.default.fileExists(atPath: pyFile.path) else {
            throw XCTSkip("Python fixture not found")
        }

        let chunks = try chunker.chunk(file: pyFile, language: .python)
        XCTAssertFalse(chunks.isEmpty, "Expected at least one chunk for Python fixture")
        XCTAssertTrue(chunks.allSatisfy { $0.fallback },
                      "All chunks should be fallback=true until grammar is wired")
    }
}
