import XCTest
@testable import Zion

final class GitStatusEnvTests: XCTestCase {

    // AC 4: status invocation sets GIT_OPTIONAL_LOCKS=0.
    func testStatusSetsOptionalLocksZero() {
        let args = ["-C", "/tmp", "status", "--porcelain=v2"]
        let env = applyStatusEnvOverride(args: args, environment: ["PATH": "/usr/bin"])

        XCTAssertEqual(env["GIT_OPTIONAL_LOCKS"], "0")
        XCTAssertEqual(env["PATH"], "/usr/bin", "Existing env vars must be preserved")
    }

    // AC 5: non-status invocations MUST NOT set GIT_OPTIONAL_LOCKS.
    func testNonStatusInvocationsDoNotSetOptionalLocks() {
        let cases: [[String]] = [
            ["add", "."],
            ["commit", "-m", "msg"],
            ["fetch", "--all"],
            ["push", "origin", "main"],
            ["log", "--oneline"],
            ["-C", "/tmp", "fetch"],
        ]

        for args in cases {
            let env = applyStatusEnvOverride(args: args, environment: ["PATH": "/usr/bin"])
            XCTAssertNil(
                env["GIT_OPTIONAL_LOCKS"],
                "GIT_OPTIONAL_LOCKS must not be set for args: \(args)"
            )
        }
    }

    // Detection must skip multi-token `-C <path>` and `-c key=value` flag pairs
    // before landing on the positional subcommand.
    func testOverrideSkipsDashCAndDashc() {
        let args = ["-C", "/tmp/x", "-c", "core.foo=bar", "status"]
        let env = applyStatusEnvOverride(args: args, environment: [:])
        XCTAssertEqual(env["GIT_OPTIONAL_LOCKS"], "0")
    }

    // `--no-pager` and similar single-token flags should also be skipped.
    func testOverrideSkipsSingleDashFlags() {
        let args = ["--no-pager", "status", "--porcelain"]
        let env = applyStatusEnvOverride(args: args, environment: [:])
        XCTAssertEqual(env["GIT_OPTIONAL_LOCKS"], "0")
    }

    // Pre-existing GIT_OPTIONAL_LOCKS in the inherited env is overridden for status.
    func testOverrideReplacesExistingValue() {
        let args = ["status"]
        let env = applyStatusEnvOverride(
            args: args,
            environment: ["GIT_OPTIONAL_LOCKS": "1", "OTHER": "keep"]
        )
        XCTAssertEqual(env["GIT_OPTIONAL_LOCKS"], "0")
        XCTAssertEqual(env["OTHER"], "keep")
    }
}
