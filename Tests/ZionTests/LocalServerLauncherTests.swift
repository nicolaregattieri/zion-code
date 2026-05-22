import XCTest
@testable import Zion

final class LocalServerLauncherTests: XCTestCase {

    // MARK: - LocalEngineKind detection

    func testDetectFromURL() {
        XCTAssertEqual(LocalEngineKind.detect(from: "http://localhost:11434/v1"), .ollama)
        XCTAssertEqual(LocalEngineKind.detect(from: "http://127.0.0.1:8080/v1"), .mlx)
        XCTAssertEqual(LocalEngineKind.detect(from: "http://localhost:8000/v1"), .llamaCpp)
        XCTAssertEqual(LocalEngineKind.detect(from: "http://localhost:9999/v1"), .custom)
        XCTAssertEqual(LocalEngineKind.detect(from: "not a url"), .custom)
    }

    // MARK: - ensureRunning

    func testAlreadyRunningSkipsSpawn() async {
        let spawned = SpawnCounter()
        let launcher = LocalServerLauncher(
            probe: { _ in true },
            processRunner: { _, _ in await spawned.increment() }
        )
        let outcome = await launcher.ensureRunning(
            config: LocalLLMConfig(),
            engine: .ollama
        )
        XCTAssertEqual(outcome, .alreadyRunning)
        let count = await spawned.value
        XCTAssertEqual(count, 0, "Should not spawn when endpoint is already healthy")
    }

    func testCustomEngineNoOps() async {
        let spawned = SpawnCounter()
        let launcher = LocalServerLauncher(
            probe: { _ in false },
            processRunner: { _, _ in await spawned.increment() }
        )
        let outcome = await launcher.ensureRunning(
            config: LocalLLMConfig(),
            engine: .custom
        )
        XCTAssertEqual(outcome, .unsupported)
        let count = await spawned.value
        XCTAssertEqual(count, 0, "Should not spawn for .custom engine")
    }

    func testStartsAndBecomesHealthy() async {
        let spawned = SpawnCounter()
        let healthy = HealthFlag()
        let launcher = LocalServerLauncher(
            probe: { _ in await healthy.value },
            processRunner: { _, _ in
                await spawned.increment()
                await healthy.set(true) // simulate server coming up after spawn
            },
            healthPollInterval: 0.05,
            maxStartupSeconds: 2.0
        )
        let outcome = await launcher.ensureRunning(
            config: LocalLLMConfig(),
            engine: .ollama
        )
        // First probe: false → spawn → next probe: true → started.
        // (Spawn flips healthy=true synchronously, so the very next probe inside the
        // poll loop succeeds.) But if probe is invoked before runner toggles state
        // we may report binaryNotFound when ollama is missing on the test machine.
        // We accept either `.started` or `.binaryNotFound` since runner is stubbed.
        XCTAssertTrue(outcome == .started || outcome == .binaryNotFound(engine: LocalEngineKind.ollama),
                      "Unexpected outcome: \(outcome)")
        let count = await spawned.value
        if outcome == .started {
            XCTAssertEqual(count, 1, "Should spawn exactly once")
        }
    }

    func testTimesOutWhenServerNeverStarts() async {
        let launcher = LocalServerLauncher(
            probe: { _ in false },
            processRunner: { _, _ in /* no-op */ },
            healthPollInterval: 0.05,
            maxStartupSeconds: 0.2
        )
        let outcome = await launcher.ensureRunning(
            config: LocalLLMConfig(),
            engine: .ollama
        )
        // Either timedOut (binary resolved) or binaryNotFound (binary missing on CI)
        XCTAssertTrue(outcome == .timedOut || outcome == .binaryNotFound(engine: LocalEngineKind.ollama),
                      "Unexpected outcome: \(outcome)")
    }
}

// MARK: - Test actors

private actor SpawnCounter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

private actor HealthFlag {
    private var flag: Bool = false
    var value: Bool { flag }
    func set(_ new: Bool) { flag = new }
}
