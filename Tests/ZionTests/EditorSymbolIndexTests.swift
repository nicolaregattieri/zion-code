import XCTest
@testable import Zion

final class EditorSymbolIndexTests: XCTestCase {
    func testFindDefinitionsAndReferences() async throws {
        let root = try makeTempRepository(name: "editor-symbol-index-defs")
        let swiftFile = root.appendingPathComponent("Main.swift")
        try """
        struct Greeter {
            func greet() -> String {
                greetHelper()
            }

            func greetHelper() -> String { "hi" }
        }
        """.write(to: swiftFile, atomically: true, encoding: .utf8)

        let index = EditorSymbolIndex()
        await index.rebuild(repositoryURL: root)

        let definitionQuery = EditorSymbolQuery(
            symbol: "greetHelper",
            currentFilePath: swiftFile.path,
            lineText: "greetHelper()"
        )
        let definitions = await index.definitions(for: definitionQuery, repositoryURL: root)
        XCTAssertFalse(definitions.isEmpty)
        XCTAssertTrue(definitions.contains { $0.relativePath == "Main.swift" })

        let references = await index.references(for: definitionQuery, repositoryURL: root)
        XCTAssertGreaterThanOrEqual(references.count, 2)
        XCTAssertTrue(references.contains { $0.preview.contains("greetHelper()") })
    }

    func testResolveRelativeJSImportAsDefinition() async throws {
        let root = try makeTempRepository(name: "editor-symbol-index-import")
        let srcDir = root.appendingPathComponent("src", isDirectory: true)
        let utilsDir = srcDir.appendingPathComponent("utils", isDirectory: true)
        try FileManager.default.createDirectory(at: utilsDir, withIntermediateDirectories: true)

        let mainFile = srcDir.appendingPathComponent("main.ts")
        let helperFile = utilsDir.appendingPathComponent("helper.ts")
        try """
        import { helper } from "./utils/helper"
        console.log(helper())
        """.write(to: mainFile, atomically: true, encoding: .utf8)
        try """
        export function helper() { return 1 }
        """.write(to: helperFile, atomically: true, encoding: .utf8)

        let index = EditorSymbolIndex()
        await index.rebuild(repositoryURL: root)

        let importQuery = EditorSymbolQuery(
            symbol: "helper",
            currentFilePath: mainFile.path,
            lineText: #"import { helper } from "./utils/helper""#
        )
        let definitions = await index.definitions(for: importQuery, repositoryURL: root)
        XCTAssertFalse(definitions.isEmpty)
        XCTAssertTrue(definitions.contains { $0.relativePath.hasSuffix("src/utils/helper.ts") })
    }

    private func makeTempRepository(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name + "-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
