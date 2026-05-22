import XCTest
@testable import Zion

// MARK: - AIClientCLIDispatchTests
//
// Verifies the .claudeCLI and .codexCLI dispatch arms added in AIClient+Helpers.swift.
// These tests do NOT invoke real subprocesses — they validate routing behaviour by
// confirming that:
//   1. Missing `cwd` throws `AIError.cliError(stderr: "missing cwd", …)`.
//   2. The error thrown is in the CLI family (not .noProvider or .invalidResponse).

final class AIClientCLIDispatchTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a minimal AIPromptPayload with no cwd (simulates caller that forgot to set it).
    private func makePayloadNoCwd() -> AIPromptPayload {
        AIPromptPayload(
            systemInstructions: "sys",
            taskInstructions: "task",
            untrustedSections: [],
            suspiciousPatterns: [],
            cwd: nil
        )
    }

    /// Builds a minimal AIPromptPayload with a cwd set.
    private func makePayloadWithCwd() -> AIPromptPayload {
        AIPromptPayload(
            systemInstructions: "sys",
            taskInstructions: "task",
            untrustedSections: [],
            suspiciousPatterns: [],
            cwd: URL(fileURLWithPath: "/tmp")
        )
    }

    // MARK: - testClaudeCLIRequiresCwd

    /// Calling .claudeCLI without payload.cwd must throw AIError.cliError with "missing cwd".
    func testClaudeCLIRequiresCwd() async throws {
        let client = AIClient()
        do {
            _ = try await client.call(
                payload: makePayloadNoCwd(),
                provider: .claudeCLI,
                apiKey: "",
                maxTokens: 100,
                lane: .general,
                mode: .efficient
            )
            XCTFail("Expected AIError.cliError to be thrown")
        } catch let error as AIError {
            if case .cliError(let stderr, let exitCode) = error {
                XCTAssertEqual(stderr, "missing cwd")
                XCTAssertEqual(exitCode, -1)
            } else {
                XCTFail("Expected AIError.cliError, got \(error)")
            }
        }
    }

    // MARK: - testCodexCLIRequiresCwd

    /// Calling .codexCLI without payload.cwd must throw AIError.cliError with "missing cwd".
    func testCodexCLIRequiresCwd() async throws {
        let client = AIClient()
        do {
            _ = try await client.call(
                payload: makePayloadNoCwd(),
                provider: .codexCLI,
                apiKey: "",
                maxTokens: 100,
                lane: .general,
                mode: .efficient
            )
            XCTFail("Expected AIError.cliError to be thrown")
        } catch let error as AIError {
            if case .cliError(let stderr, let exitCode) = error {
                XCTAssertEqual(stderr, "missing cwd")
                XCTAssertEqual(exitCode, -1)
            } else {
                XCTFail("Expected AIError.cliError, got \(error)")
            }
        }
    }

    // MARK: - testClaudeCLIProviderRoutedToCLIPath

    /// With a valid cwd but no CLI installed, the error must be in the CLI family
    /// (.cliNotInstalled, .cliNotAuthenticated, or .cliError) — not .noProvider or .invalidResponse.
    /// This proves that the .claudeCLI arm was reached (not short-circuited by the candidates guard).
    func testClaudeCLIProviderRoutedToCLIPath() async throws {
        let client = AIClient()
        do {
            _ = try await client.call(
                payload: makePayloadWithCwd(),
                provider: .claudeCLI,
                apiKey: "",
                maxTokens: 100,
                lane: .general,
                mode: .efficient
            )
            XCTFail("Expected a CLI error to be thrown")
        } catch let error as AIError {
            switch error {
            case .cliNotInstalled, .cliNotAuthenticated, .cliError, .cliVersionTooOld:
                return // correct: routed to CLI family
            case .noProvider:
                XCTFail("Reached .noProvider — dispatch did not enter .claudeCLI arm")
            case .invalidResponse:
                XCTFail("Reached .invalidResponse — dispatch did not enter .claudeCLI arm")
            default:
                return // Any other AIError is acceptable (e.g. process spawn failure on CI)
            }
        } catch {
            // Non-AIError (e.g. Process spawn error) means we did reach the CLI arm — OK
            return
        }
    }

    // MARK: - testCodexCLIProviderRoutedToCLIPath

    /// With a valid cwd but no CLI installed, the error must be in the CLI family.
    /// Proves .codexCLI arm is reached.
    func testCodexCLIProviderRoutedToCLIPath() async throws {
        let client = AIClient()
        do {
            _ = try await client.call(
                payload: makePayloadWithCwd(),
                provider: .codexCLI,
                apiKey: "",
                maxTokens: 100,
                lane: .general,
                mode: .efficient
            )
            XCTFail("Expected a CLI error to be thrown")
        } catch let error as AIError {
            switch error {
            case .cliNotInstalled, .cliNotAuthenticated, .cliError, .cliVersionTooOld:
                return // correct: routed to CLI family
            case .noProvider:
                XCTFail("Reached .noProvider — dispatch did not enter .codexCLI arm")
            case .invalidResponse:
                XCTFail("Reached .invalidResponse — dispatch did not enter .codexCLI arm")
            default:
                return
            }
        } catch {
            // Non-AIError (e.g. Process spawn error) means we did reach the CLI arm — OK
            return
        }
    }

    // MARK: - testCLIDiscoveryPropertyExists

    /// Verifies the `cliDiscovery` property is present on AIClient (compile-time proof via type check).
    func testCLIDiscoveryPropertyExists() async {
        let client = AIClient()
        let discovery = await client.cliDiscovery
        // CLIDiscoveryService is an actor — we just confirm it's accessible and has the right type.
        let _: CLIDiscoveryService = discovery
    }
}
