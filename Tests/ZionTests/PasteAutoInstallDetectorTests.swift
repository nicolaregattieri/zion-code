import XCTest
@testable import Zion

/// Phase 6.3 — paste-to-install heuristic. The composer fires
/// `PasteAutoInstallDetector.detect` on every paste so the user can
/// drop MCP JSON or SKILL.md directly without going through the chat
/// loop. Mirrors Cursor / Claude Desktop UX.
final class PasteAutoInstallDetectorTests: XCTestCase {

    // MARK: MCP

    func test_mcp_fullMap_shape_detected() {
        let raw = #"""
        {"mcpServers":{"fs":{"command":"npx","args":["-y","@org/server","/tmp"]}}}
        """#
        guard case .mcpJSON(let body) = PasteAutoInstallDetector.detect(in: raw) else {
            XCTFail("expected mcpJSON"); return
        }
        XCTAssertTrue(body.contains("mcpServers"))
    }

    func test_mcp_singleNamed_shape_detected() {
        let raw = #"""
        {"my-fs":{"command":"npx","args":["-y"]}}
        """#
        guard case .mcpJSON = PasteAutoInstallDetector.detect(in: raw) else {
            XCTFail("expected mcpJSON"); return
        }
    }

    func test_mcp_singleExplicit_shape_detected() {
        let raw = #"""
        {"id":"foo","command":"node","args":["server.js"]}
        """#
        guard case .mcpJSON = PasteAutoInstallDetector.detect(in: raw) else {
            XCTFail("expected mcpJSON"); return
        }
    }

    func test_mcp_arbitraryJSON_notDetected() {
        let raw = #"""
        {"foo":"bar","baz":1}
        """#
        XCTAssertNil(PasteAutoInstallDetector.detect(in: raw))
    }

    func test_plainText_notDetected() {
        XCTAssertNil(PasteAutoInstallDetector.detect(in: "Just a plain message."))
    }

    // MARK: SKILL.md

    func test_skill_minimal_frontmatter_detected() {
        let raw = """
        ---
        name: Demo
        description: A demo skill.
        ---
        Body of the skill.
        """
        guard case .skillMarkdown(let name, let desc, let body, let triggers) = PasteAutoInstallDetector.detect(in: raw) else {
            XCTFail("expected skillMarkdown"); return
        }
        XCTAssertEqual(name, "Demo")
        XCTAssertEqual(desc, "A demo skill.")
        XCTAssertEqual(body, "Body of the skill.")
        XCTAssertTrue(triggers.isEmpty)
    }

    func test_skill_withTriggers_detected() {
        let raw = """
        ---
        name: Changelog
        description: Generate a release changelog.
        triggers:
          - generate changelog
          - what changed
        ---
        Read git log and summarize.
        """
        guard case .skillMarkdown(_, _, _, let triggers) = PasteAutoInstallDetector.detect(in: raw) else {
            XCTFail("expected skillMarkdown"); return
        }
        XCTAssertEqual(triggers.count, 2)
        XCTAssertTrue(triggers.contains("generate changelog"))
        XCTAssertTrue(triggers.contains("what changed"))
    }

    func test_skill_missingFields_notDetected() {
        let raw = """
        ---
        name: NoDescription
        ---
        Body.
        """
        XCTAssertNil(PasteAutoInstallDetector.detect(in: raw))
    }

    func test_skill_emptyBody_notDetected() {
        let raw = """
        ---
        name: A
        description: B
        ---
        """
        XCTAssertNil(PasteAutoInstallDetector.detect(in: raw))
    }
}
