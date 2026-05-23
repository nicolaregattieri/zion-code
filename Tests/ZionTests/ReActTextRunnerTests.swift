// ReActTextRunnerTests.swift — Unit tests for ReActTextRunner parser + loop behaviour.

import XCTest
@testable import Zion

// MARK: - Mock MCP Client

private final class ReActMockMCPClient: @unchecked Sendable, MCPClientProtocol {
    var callCount = 0
    var fixedResult: [String: Any] = ["content": "mock result"]
    var fixedResultString: String = "file1.swift\nfile2.swift"

    func callTool(_ name: String, args: [String: Any]) async throws -> [String: Any] {
        callCount += 1
        return fixedResult
    }
    func listTools() async throws -> [MCPToolDescriptor] { [] }
}

// MARK: - Stream helper

private func scriptedTextStream(_ chunks: [String]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        for chunk in chunks { continuation.yield(chunk) }
        continuation.finish()
    }
}

// MARK: - Actor call counter (Swift 6 safe)

private actor ReActCallCounter {
    private(set) var value: Int = 0
    func increment() -> Int {
        let current = value
        value += 1
        return current
    }
}

// MARK: - Tests

final class ReActTextRunnerTests: XCTestCase {

    // MARK: 1. Parser happy path

    func test_parseAction_happyPath() {
        let input = "THOUGHT: I need to read the file.\nACTION: read_file({\"path\":\"X\"})\n"
        guard let result = ReActTextRunner.parseAction(input) else {
            XCTFail("parseAction returned nil for valid input")
            return
        }
        XCTAssertEqual(result.tool, "read_file")
        XCTAssertEqual(result.argsJSON["path"] as? String, "X")
    }

    // MARK: 2. Parser bad JSON

    func test_parseAction_badJSON_returnsNil() {
        let input = "ACTION: read_file({invalid})"
        XCTAssertNil(ReActTextRunner.parseAction(input))
    }

    // MARK: 3. Parser no action

    func test_parseAction_noAction_returnsNil() {
        let input = "just text"
        XCTAssertNil(ReActTextRunner.parseAction(input))
    }

    // MARK: 4. Answer parser

    func test_parseAnswer_happyPath() {
        let input = "THOUGHT: done\nANSWER: 42 files"
        let answer = ReActTextRunner.parseAnswer(input)
        XCTAssertEqual(answer, "42 files")
    }

    func test_parseAnswer_noAnswer_returnsNil() {
        XCTAssertNil(ReActTextRunner.parseAnswer("THOUGHT: thinking"))
    }

    // MARK: 5. Three consecutive parse failures abort

    @MainActor
    func test_threeConsecutiveParseFailures_throwsReactParseFailed() async {
        let mockMCP = ReActMockMCPClient()
        // Always returns text that is neither ACTION nor ANSWER
        let factory: TextStreamFactory = { _ in
            return scriptedTextStream(["hello world"])
        }
        let runner = ReActTextRunner(textStreamFactory: factory, mcpClient: mockMCP)
        let cancel = CancellationToken()

        do {
            _ = try await runner.run(
                provider: .local,
                model: nil,
                conversation: [["role": "user", "content": "test"]],
                tools: [],
                maxSteps: 10,
                budgetCap: 0,
                cancel: cancel,
                onStep: { _ in }
            )
            XCTFail("Expected AIError.reactParseFailed to be thrown")
        } catch let error as AIError {
            XCTAssertEqual(error, AIError.reactParseFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: 6. Successful loop: ACTION round then ANSWER round

    @MainActor
    func test_successfulLoop_endTurnWithCorrectResult() async throws {
        let mockMCP = ReActMockMCPClient()
        // Round 1: emit ACTION, round 2: emit ANSWER
        let counter = ReActCallCounter()

        let factory: TextStreamFactory = { _ in
            let index = await counter.increment()
            if index == 0 {
                return scriptedTextStream(["THOUGHT: let me list files\nACTION: list_dir({\"path\":\".\"})\n"])
            } else {
                return scriptedTextStream(["THOUGHT: done\nANSWER: 2 files"])
            }
        }

        let runner = ReActTextRunner(textStreamFactory: factory, mcpClient: mockMCP)
        let cancel = CancellationToken()
        var stepEvents: [AgentStepEvent] = []

        let result = try await runner.run(
            provider: .local,
            model: nil,
            conversation: [["role": "user", "content": "how many files?"]],
            tools: [],
            maxSteps: 10,
            budgetCap: 0,
            cancel: cancel,
            onStep: { event in stepEvents.append(event) }
        )

        XCTAssertEqual(result.stopReason, .endTurn)
        XCTAssertEqual(result.finalText, "2 files")
        XCTAssertEqual(result.stepsUsed, 1)
        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(mockMCP.callCount, 1)
        XCTAssertEqual(stepEvents.count, 1)
        XCTAssertEqual(stepEvents[0].toolEvent.name, "list_dir")
    }
}
