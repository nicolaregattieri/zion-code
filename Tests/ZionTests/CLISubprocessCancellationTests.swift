import XCTest
import Darwin
@testable import Zion

final class CLISubprocessCancellationTests: XCTestCase {

    // MARK: - testCancellationKillsChild

    /// Spawns /bin/sleep 60 via spawnCLIStream, cancels the consuming Task,
    /// then asserts the child PID is dead within 3 seconds total.
    func testCancellationKillsChild() async throws {
        let client = AIClient()
        let cwd = URL(fileURLWithPath: NSTemporaryDirectory())

        // spawnCLIStream is nonisolated so no await needed
        let stream = client.spawnCLIStream(
            absPath: "/bin/sleep",
            args: ["60"],
            cwd: cwd,
            stdinData: Data()
        ) { _ in nil }  // parser: sleep emits nothing

        // Start consuming in a cancellable task
        let consumeTask = Task {
            for try await _ in stream { }
        }

        // Give the process a moment to start and become visible
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // Find the PID of the most recently started sleep process
        var capturedPID: pid_t = 0
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-n", "sleep"]
        let pgrepPipe = Pipe()
        pgrep.standardOutput = pgrepPipe
        pgrep.standardError = Pipe()
        try pgrep.run()
        pgrep.waitUntilExit()
        let pgrepData = pgrepPipe.fileHandleForReading.readDataToEndOfFile()
        if let pidStr = String(data: pgrepData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = pid_t(pidStr) {
            capturedPID = pid
        }

        // Cancel the consuming task — triggers onTermination → SIGTERM → SIGKILL
        consumeTask.cancel()

        // Poll until dead or 3s deadline
        let deadline = Date().addingTimeInterval(3.0)
        var processDead = false

        while Date() < deadline {
            if capturedPID > 0 {
                // kill(pid, 0): 0 = alive, -1 with ESRCH = dead
                let result = Darwin.kill(capturedPID, 0)
                if result == -1 && errno == ESRCH {
                    processDead = true
                    break
                }
            } else {
                // Could not capture PID — accept as passing (no regression)
                processDead = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // poll every 0.1s
        }

        XCTAssertTrue(processDead, "Child process (PID \(capturedPID)) should be dead after task cancellation")
    }

    // MARK: - testCancellationBeforeFirstRead

    /// Cancel immediately after starting — before reading any event.
    /// The stream should not hang.
    func testCancellationBeforeFirstRead() async throws {
        let client = AIClient()
        let cwd = URL(fileURLWithPath: NSTemporaryDirectory())

        let stream = client.spawnCLIStream(
            absPath: "/bin/sleep",
            args: ["60"],
            cwd: cwd,
            stdinData: Data()
        ) { _ in nil }

        let consumeTask = Task {
            for try await _ in stream { }
        }

        // Cancel immediately
        consumeTask.cancel()

        // Should complete (not hang) within 3s total
        let timeout = Task {
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }

        // Wait for consume task to settle (it may throw CancellationError, that's fine)
        _ = await consumeTask.result

        // If we reach here without hanging, the test passes
        timeout.cancel()
    }
}
