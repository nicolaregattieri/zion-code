import XCTest
@testable import Zion

final class ZionToolsTests: XCTestCase {

    // MARK: - Tool count

    func testSixToolsDefined() {
        XCTAssertEqual(ZionTools.tools.count, 6)
    }

    func testToolNamesAreCorrect() {
        let names = ZionTools.tools.map(\.name)
        XCTAssertEqual(names, ["read", "edit", "write", "bash", "grep", "glob"])
    }

    // MARK: - OpenAI envelope

    func testOpenAISchemaHasSixEntries() {
        XCTAssertEqual(ZionTools.toolSchemasJSON().count, 6)
    }

    func testOpenAIEnvelopeShape() {
        let schemas = ZionTools.toolSchemasJSON()
        for schema in schemas {
            // Must have "type": "function"
            XCTAssertEqual(schema["type"] as? String, "function", "Missing type:function for \(schema)")
            // Must have "function" dict
            guard let fn = schema["function"] as? [String: Any] else {
                XCTFail("Missing function key in schema")
                return
            }
            XCTAssertNotNil(fn["name"])
            XCTAssertNotNil(fn["description"])
            // Must have "parameters" with "type":"object"
            guard let params = fn["parameters"] as? [String: Any] else {
                XCTFail("Missing parameters in function schema for \(fn["name"] ?? "")")
                return
            }
            XCTAssertEqual(params["type"] as? String, "object")
            XCTAssertNotNil(params["properties"])
            XCTAssertNotNil(params["required"])
        }
    }

    // MARK: - Anthropic envelope

    func testAnthropicSchemaHasSixEntries() {
        XCTAssertEqual(ZionTools.anthropicToolSchemas().count, 6)
    }

    func testAnthropicEnvelopeShape() {
        let schemas = ZionTools.anthropicToolSchemas()
        for schema in schemas {
            // Must NOT have "type":"function" at top level
            XCTAssertNil(schema["type"], "Anthropic schema should not have top-level type key")
            XCTAssertNotNil(schema["name"])
            XCTAssertNotNil(schema["description"])
            // Must have "input_schema" instead of "parameters"
            guard let inputSchema = schema["input_schema"] as? [String: Any] else {
                XCTFail("Missing input_schema for \(schema["name"] ?? "")")
                return
            }
            XCTAssertEqual(inputSchema["type"] as? String, "object")
            XCTAssertNotNil(inputSchema["properties"])
            XCTAssertNotNil(inputSchema["required"])
            // Must NOT have "parameters" key
            XCTAssertNil(schema["parameters"], "Anthropic schema must use input_schema, not parameters")
        }
    }

    // MARK: - Envelope difference

    func testEnvelopesAreDifferent() {
        let openAI = ZionTools.toolSchemasJSON()
        let anthropic = ZionTools.anthropicToolSchemas()
        // OpenAI uses "type"+"function" wrapper; Anthropic uses "input_schema"
        XCTAssertNotNil(openAI[0]["type"])
        XCTAssertNil(anthropic[0]["type"])
        XCTAssertNotNil(openAI[0]["function"])
        XCTAssertNil(anthropic[0]["function"])
        XCTAssertNil(openAI[0]["input_schema"])
        XCTAssertNotNil(anthropic[0]["input_schema"])
    }

    // MARK: - Edit tool str_replace schema

    func testEditToolHasPathAndEdits() {
        guard let editTool = ZionTools.tools.first(where: { $0.name == "edit" }) else {
            XCTFail("edit tool not found")
            return
        }
        XCTAssertTrue(editTool.required.contains("path"))
        XCTAssertTrue(editTool.required.contains("edits"))
        XCTAssertNotNil(editTool.properties["path"])
        XCTAssertNotNil(editTool.properties["edits"])
    }

    func testEditToolEditsArrayHasOldTextAndNewText() {
        guard let editTool = ZionTools.tools.first(where: { $0.name == "edit" }),
              let editsSchema = editTool.properties["edits"] as? [String: Any],
              let items = editsSchema["items"] as? [String: Any],
              let itemProps = items["properties"] as? [String: Any] else {
            XCTFail("edit tool edits schema malformed")
            return
        }
        XCTAssertNotNil(itemProps["oldText"], "edits items must have oldText key")
        XCTAssertNotNil(itemProps["newText"], "edits items must have newText key")

        // Verify required fields on items
        guard let itemRequired = items["required"] as? [String] else {
            XCTFail("edits items must have required array")
            return
        }
        XCTAssertTrue(itemRequired.contains("oldText"))
        XCTAssertTrue(itemRequired.contains("newText"))
    }

    func testEditToolInOpenAIEnvelope() {
        let openAI = ZionTools.toolSchemasJSON()
        guard let editEntry = openAI.first(where: { ($0["function"] as? [String: Any])?["name"] as? String == "edit" }),
              let fn = editEntry["function"] as? [String: Any],
              let params = fn["parameters"] as? [String: Any],
              let props = params["properties"] as? [String: Any],
              let editsSchema = props["edits"] as? [String: Any],
              let items = editsSchema["items"] as? [String: Any],
              let itemProps = items["properties"] as? [String: Any] else {
            XCTFail("edit tool missing from OpenAI schemas or schema malformed")
            return
        }
        XCTAssertNotNil(itemProps["oldText"])
        XCTAssertNotNil(itemProps["newText"])
    }

    func testEditToolInAnthropicEnvelope() {
        let anthropic = ZionTools.anthropicToolSchemas()
        guard let editEntry = anthropic.first(where: { $0["name"] as? String == "edit" }),
              let inputSchema = editEntry["input_schema"] as? [String: Any],
              let props = inputSchema["properties"] as? [String: Any],
              let editsSchema = props["edits"] as? [String: Any],
              let items = editsSchema["items"] as? [String: Any],
              let itemProps = items["properties"] as? [String: Any] else {
            XCTFail("edit tool missing from Anthropic schemas or schema malformed")
            return
        }
        XCTAssertNotNil(itemProps["oldText"])
        XCTAssertNotNil(itemProps["newText"])
    }

    // MARK: - Required fields per tool

    func testReadRequiresPath() {
        let tool = ZionTools.tools.first(where: { $0.name == "read" })!
        XCTAssertEqual(tool.required, ["path"])
    }

    func testWriteRequiresPathAndContent() {
        let tool = ZionTools.tools.first(where: { $0.name == "write" })!
        XCTAssertTrue(tool.required.contains("path"))
        XCTAssertTrue(tool.required.contains("content"))
    }

    func testBashRequiresCommand() {
        let tool = ZionTools.tools.first(where: { $0.name == "bash" })!
        XCTAssertEqual(tool.required, ["command"])
    }

    func testGrepRequiresPattern() {
        let tool = ZionTools.tools.first(where: { $0.name == "grep" })!
        XCTAssertEqual(tool.required, ["pattern"])
    }

    func testGlobRequiresPattern() {
        let tool = ZionTools.tools.first(where: { $0.name == "glob" })!
        XCTAssertEqual(tool.required, ["pattern"])
    }

    // MARK: - JSONSerialization compatibility

    func testOpenAISchemasAreJSONSerializable() throws {
        let schemas = ZionTools.toolSchemasJSON()
        XCTAssertTrue(JSONSerialization.isValidJSONObject(schemas))
        let data = try JSONSerialization.data(withJSONObject: schemas)
        XCTAssertGreaterThan(data.count, 0)
    }

    func testAnthropicSchemasAreJSONSerializable() throws {
        let schemas = ZionTools.anthropicToolSchemas()
        XCTAssertTrue(JSONSerialization.isValidJSONObject(schemas))
        let data = try JSONSerialization.data(withJSONObject: schemas)
        XCTAssertGreaterThan(data.count, 0)
    }

    // MARK: - Descriptions are concise (≤100 chars)

    func testAllDescriptionsAreConcise() {
        for tool in ZionTools.tools {
            XCTAssertLessThanOrEqual(
                tool.description.count, 100,
                "\(tool.name) description exceeds 100 chars: \(tool.description.count)"
            )
        }
    }
}
