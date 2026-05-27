import XCTest
@testable import Zion

/// Phase 4 spec criterion #5 — `ChatService.stop()` terminates every
/// active tool subprocess gated behind
/// `Constants.Feature.harnessProcessKillOnStop`. Empty `activeProcesses`
/// is a no-op (no log spam). Kill-switch override via UserDefaults skips
/// termination entirely.
@MainActor
final class ChatServiceCancellationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "harness.processKillOnStop")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "harness.processKillOnStop")
        super.tearDown()
    }

    private func spawnSleepingProcess(seconds: Int = 10) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["\(seconds)"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        return p
    }

    func test_stop_terminatesActiveBashSubprocess() async {
        let svc = makeChatServiceForTest()
        let proc = spawnSleepingProcess(seconds: 10)
        XCTAssertTrue(proc.isRunning)

        svc.registerProcess(proc, toolCallID: UUID(), tool: "bash")
        XCTAssertEqual(svc.activeProcesses.count, 1)

        await svc.terminateAllActiveProcesses()

        // Allow up to the cancel deadline + a small slack for SIGTERM to land.
        let slackMs = UInt64(Constants.Timing.harnessCancelDeadlineMs + 200)
        try? await Task.sleep(nanoseconds: slackMs * 1_000_000)
        XCTAssertFalse(proc.isRunning, "Subprocess must be reaped within the cancel deadline")
    }

    func test_stop_emptyActiveProcesses_isNoop() async {
        let svc = makeChatServiceForTest()
        XCTAssertEqual(svc.activeProcesses.count, 0)
        await svc.terminateAllActiveProcesses() // must not throw, must not crash
        XCTAssertEqual(svc.activeProcesses.count, 0)
    }

    func test_killSwitchDisabled_doesNotTerminate() async {
        UserDefaults.standard.set(false, forKey: "harness.processKillOnStop")
        defer { UserDefaults.standard.removeObject(forKey: "harness.processKillOnStop") }

        XCTAssertFalse(ChatService.harnessProcessKillOnStopEnabled)

        let svc = makeChatServiceForTest()
        let proc = spawnSleepingProcess(seconds: 2)
        svc.registerProcess(proc, toolCallID: UUID(), tool: "bash")

        await svc.terminateAllActiveProcesses()
        // With kill-switch off, the entry is NOT removed and the process
        // keeps running.
        XCTAssertEqual(svc.activeProcesses.count, 1, "kill-switch off must skip termination")
        XCTAssertTrue(proc.isRunning, "process must survive when kill-switch is disabled")

        // Cleanup so we do not leak a runaway sleep into the host.
        proc.terminate()
    }

    private func makeChatServiceForTest() -> ChatService {
        let worker = RepositoryWorker()
        let ai = AIClient()
        let builder = ChatContextBuilder(worker: worker)
        let harness = ZionHarness(worker: worker, repoURL: URL(fileURLWithPath: NSTemporaryDirectory()))
        return ChatService(
            ai: ai,
            worker: worker,
            contextBuilder: builder,
            harness: harness,
            streamProvider: { _, _, _, _ in
                AsyncThrowingStream<String, Error> { _ in }
            }
        )
    }
}
