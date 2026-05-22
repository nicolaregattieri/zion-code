// ToolSchemaTranslatorTests.swift

import XCTest
@testable import Zion

final class ToolSchemaTranslatorTests: XCTestCase {

    // MARK: - Fixtures

    private let toolA = MCPToolDescriptor(
        name: "read_file",
        description: "Read a file from disk",
        inputSchema: [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "Absolute file path"]
            ],
            "required": ["path"]
        ]
    )

    private let toolB = MCPToolDescriptor(
        name: "run_command",
        description: "Execute a shell command",
        inputSchema: [
            "type": "object",
            "properties": [
                "command": ["type": "string"],
                "cwd":     ["type": "string"]
            ],
            "required": ["command"]
        ]
    )

    private var fixtures: [MCPToolDescriptor] { [toolA, toolB] }

    // MARK: - Anthropic

    func test_anthropic_topLevelShape() {
        let shapes = ToolSchemaTranslator.translate(fixtures, for: .anthropic)
        XCTAssertEqual(shapes.count, 2)

        let first = shapes[0]
        XCTAssertEqual(first["name"] as? String, "read_file")
        XCTAssertEqual(first["description"] as? String, "Read a file from disk")
        XCTAssertNotNil(first["input_schema"])
        XCTAssertNil(first["parameters"])   // anthropic uses input_schema, not parameters
    }

    func test_anthropic_inputSchemaPreserved() {
        let shapes = ToolSchemaTranslator.translate([toolA], for: .anthropic)
        let schema = shapes[0]["input_schema"] as? [String: Any]
        XCTAssertEqual(schema?["type"] as? String, "object")
        let props = schema?["properties"] as? [String: Any]
        XCTAssertNotNil(props?["path"])
    }

    // MARK: - OpenAI

    func test_openai_topLevelShape() {
        let shapes = ToolSchemaTranslator.translate(fixtures, for: .openai)
        XCTAssertEqual(shapes.count, 2)

        let first = shapes[0]
        XCTAssertEqual(first["type"] as? String, "function")
        let fn = first["function"] as? [String: Any]
        XCTAssertEqual(fn?["name"] as? String, "read_file")
        XCTAssertEqual(fn?["description"] as? String, "Read a file from disk")
        XCTAssertNotNil(fn?["parameters"])
    }

    func test_openai_additionalPropertiesFalse() {
        let shapes = ToolSchemaTranslator.translate([toolA], for: .openai)
        let fn     = shapes[0]["function"] as? [String: Any]
        let params = fn?["parameters"] as? [String: Any]
        XCTAssertEqual(params?["additionalProperties"] as? Bool, false)
    }

    func test_openrouter_followsOpenAIShape() {
        let openaiShapes   = ToolSchemaTranslator.translate(fixtures, for: .openai)
        let openrouterShapes = ToolSchemaTranslator.translate(fixtures, for: .openrouter)

        // Both should have the same type and function name structure
        XCTAssertEqual(openaiShapes.count, openrouterShapes.count)
        for (oa, or_) in zip(openaiShapes, openrouterShapes) {
            XCTAssertEqual(oa["type"] as? String, or_["type"] as? String)
            let oaFn = oa["function"] as? [String: Any]
            let orFn = or_["function"] as? [String: Any]
            XCTAssertEqual(oaFn?["name"] as? String, orFn?["name"] as? String)
        }
    }

    func test_localOpenAICompatible_followsOpenAIShape() {
        let openaiShapes = ToolSchemaTranslator.translate(fixtures, for: .openai)
        let localShapes  = ToolSchemaTranslator.translate(fixtures, for: .localOpenAICompatible)

        for (oa, lo) in zip(openaiShapes, localShapes) {
            XCTAssertEqual(oa["type"] as? String, lo["type"] as? String)
        }
    }

    // MARK: - Gemini

    func test_gemini_topLevelShape() {
        let shapes = ToolSchemaTranslator.translate(fixtures, for: .gemini)
        XCTAssertEqual(shapes.count, 2)

        let first = shapes[0]
        XCTAssertEqual(first["name"] as? String, "read_file")
        XCTAssertEqual(first["description"] as? String, "Read a file from disk")
        XCTAssertNotNil(first["parameters"])
        XCTAssertNil(first["type"])          // gemini has no "type": "function" wrapper
        XCTAssertNil(first["input_schema"])  // gemini uses "parameters"
    }

    func test_gemini_parametersPreserved() {
        let shapes = ToolSchemaTranslator.translate([toolB], for: .gemini)
        let params = shapes[0]["parameters"] as? [String: Any]
        XCTAssertEqual(params?["type"] as? String, "object")
        let props = params?["properties"] as? [String: Any]
        XCTAssertNotNil(props?["command"])
    }

    // MARK: - normalizeForOpenAIStrict

    func test_normalizeAddsAdditionalProperties() {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"]
            ]
        ]
        let normalized = ToolSchemaTranslator.normalizeForOpenAIStrict(schema)
        XCTAssertEqual(normalized["additionalProperties"] as? Bool, false)
    }

    func test_normalizeRecursesIntoProperties() {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "nested": [
                    "type": "object",
                    "properties": ["x": ["type": "number"]]
                ]
            ]
        ]
        let normalized = ToolSchemaTranslator.normalizeForOpenAIStrict(schema)
        let props = normalized["properties"] as? [String: Any]
        let nested = props?["nested"] as? [String: Any]
        XCTAssertEqual(nested?["additionalProperties"] as? Bool, false)
    }

    func test_normalizeNonObjectUnchanged() {
        let schema: [String: Any] = ["type": "string"]
        let normalized = ToolSchemaTranslator.normalizeForOpenAIStrict(schema)
        XCTAssertNil(normalized["additionalProperties"])
    }
}
