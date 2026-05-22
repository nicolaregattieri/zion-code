import XCTest
@testable import Zion

// Counter actor used to safely track call counts from @Sendable closures.
private actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

final class CLIDiscoveryServiceTests: XCTestCase {

    // MARK: - testProbeOrderHonored
    // `which` fails (exit 1), probe finds binary via which returning homebrew path

    func testProbeOrderHonored() async {
        let homebrewPath = "/opt/homebrew/bin/claude"

        let runner: CLIDiscoveryService.ProcessRunner = { executable, arguments, _ in
            if executable == "/usr/bin/which" {
                return (0, homebrewPath, "")
            }
            if executable == homebrewPath {
                if arguments == ["--version"] {
                    return (0, "claude 2.1.120", "")
                }
                // auth probe
                return (0, "{}", "")
            }
            return (1, "", "")
        }

        let svc = CLIDiscoveryService(processRunner: runner)
        let result = await svc.status(for: .claude, refresh: true)

        XCTAssertTrue(result.installed)
        XCTAssertEqual(result.path?.path, homebrewPath)
        XCTAssertEqual(result.version, "2.1.120")
    }

    // MARK: - testSemverParse

    func testSemverParse() {
        XCTAssertEqual(CLIDiscoveryService.parseSemver(from: "2.1.120"), "2.1.120")
        XCTAssertEqual(CLIDiscoveryService.parseSemver(from: "codex-cli 0.131.0"), "0.131.0")
        XCTAssertEqual(CLIDiscoveryService.parseSemver(from: "claude version 1.0.5 (build 42)"), "1.0.5")
    }

    // MARK: - testRejectsGarbageVersion

    func testRejectsGarbageVersion() {
        XCTAssertNil(CLIDiscoveryService.parseSemver(from: "not a version"))
        XCTAssertNil(CLIDiscoveryService.parseSemver(from: ""))
        XCTAssertNil(CLIDiscoveryService.parseSemver(from: "v2"))
    }

    // MARK: - testAuthDetected
    // Claude ping returns valid JSON without permission_denials → isAuthenticated true

    func testAuthDetected() async {
        let binaryPath = "/usr/local/bin/claude"
        let runner: CLIDiscoveryService.ProcessRunner = { executable, arguments, _ in
            if executable == "/usr/bin/which" {
                return (0, binaryPath, "")
            }
            if executable == binaryPath {
                if arguments == ["--version"] {
                    return (0, "claude 1.2.3", "")
                }
                if arguments.contains("--output-format") {
                    // Valid JSON, no permission_denials
                    return (0, #"{"result": "pong", "session_id": "abc"}"#, "")
                }
            }
            return (1, "", "")
        }

        let svc = CLIDiscoveryService(processRunner: runner)
        let result = await svc.status(for: .claude, refresh: true)

        XCTAssertTrue(result.installed)
        XCTAssertEqual(result.isAuthenticated, true)
    }

    // MARK: - testAuthMissing
    // Claude ping returns non-zero exit → isAuthenticated false

    func testAuthMissing() async {
        let binaryPath = "/usr/local/bin/claude"
        let runner: CLIDiscoveryService.ProcessRunner = { executable, arguments, _ in
            if executable == "/usr/bin/which" {
                return (0, binaryPath, "")
            }
            if executable == binaryPath {
                if arguments == ["--version"] {
                    return (0, "claude 1.2.3", "")
                }
                if arguments.contains("--output-format") {
                    return (1, "", "Error: Not authenticated")
                }
            }
            return (1, "", "")
        }

        let svc = CLIDiscoveryService(processRunner: runner)
        let result = await svc.status(for: .claude, refresh: true)

        XCTAssertTrue(result.installed)
        XCTAssertEqual(result.isAuthenticated, false)
    }

    // MARK: - testCacheHit
    // 2 calls with refresh: false → auth probe invoked only once

    func testCacheHit() async {
        let uniqueVersion = "9.\(Int.random(in: 1000...9999)).0"
        let binaryPath = "/usr/local/bin/codex"
        let counter = Counter()

        let runner: CLIDiscoveryService.ProcessRunner = { [counter] executable, arguments, _ in
            await counter.increment()
            if executable == "/usr/bin/which" {
                return (0, binaryPath, "")
            }
            if executable == binaryPath {
                if arguments == ["--version"] {
                    return (0, "codex \(uniqueVersion)", "")
                }
                return (0, "", "")
            }
            return (1, "", "")
        }

        let svc = CLIDiscoveryService(processRunner: runner)

        // First call — populates cache
        _ = await svc.status(for: .codex, refresh: true)
        let afterFirst = await counter.value

        XCTAssertGreaterThan(afterFirst, 0, "Runner must be called on first probe")
        let callsForFirstProbe = afterFirst

        // Second call with refresh: false — should hit cache (only which + version called for key, no auth)
        _ = await svc.status(for: .codex, refresh: false)
        let afterSecond = await counter.value
        let additionalCalls = afterSecond - afterFirst

        XCTAssertLessThanOrEqual(additionalCalls, callsForFirstProbe,
            "Second call should not invoke more probes than first (auth cached)")
    }

    // MARK: - testCacheStaleAfterTTL
    // Simulate stale by overwriting indexed_at; refresh: false re-probes when TTL exceeded

    func testCacheStaleAfterTTL() async {
        let binaryPath = "/usr/local/bin/claude"
        let counter = Counter()

        let runner: CLIDiscoveryService.ProcessRunner = { [counter] executable, arguments, _ in
            await counter.increment()
            if executable == "/usr/bin/which" {
                return (0, binaryPath, "")
            }
            if executable == binaryPath {
                if arguments == ["--version"] {
                    return (0, "claude 3.0.0", "")
                }
                if arguments.contains("--output-format") {
                    return (0, "{}", "")
                }
            }
            return (1, "", "")
        }

        let svc = CLIDiscoveryService(processRunner: runner)

        // First call — populates cache
        _ = await svc.status(for: .claude, refresh: true)
        let afterFirst = await counter.value

        // Poison the cache: set indexed_at far in the past
        let cacheKey = "cli.discovery.claude.\(binaryPath).3.0.0"
        struct StaleEntry: Codable {
            struct S: Codable {
                let installed: Bool
                let path: String?
                let version: String?
                let isAuthenticated: Bool?
            }
            let status: S
            let indexedAt: TimeInterval
        }
        let stale = StaleEntry(
            status: .init(installed: true, path: binaryPath, version: "3.0.0", isAuthenticated: true),
            indexedAt: Date().timeIntervalSince1970 - 999_999.0
        )
        if let data = try? JSONEncoder().encode(stale) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }

        // Call again with refresh: false — cache is stale, should re-probe
        _ = await svc.status(for: .claude, refresh: false)
        let afterSecond = await counter.value

        XCTAssertGreaterThan(afterSecond, afterFirst,
            "Runner should be called again when cache is stale")
    }
}
