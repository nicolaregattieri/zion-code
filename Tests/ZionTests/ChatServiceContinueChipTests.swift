import XCTest
@testable import Zion

/// Phase 4 spec criterion #6 — Continue (+10 hops) chip behavior on the
/// ChatService side. 6b: a continue grant while a subprocess is active
/// must not be consumed until the subprocess returns.
@MainActor
final class ChatServiceContinueChipTests: XCTestCase {

    private func makeService() -> ChatService {
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

    func test_continueWithExtraHops_bumpsBudget() {
        let svc = makeService()
        XCTAssertEqual(svc.extraHopsGranted, 0)
        XCTAssertEqual(svc.effectiveHopBudget, ChatService.publicMaxHopsPerTurn)

        svc.continueWithExtraHops(10)
        XCTAssertEqual(svc.extraHopsGranted, 10)
        XCTAssertEqual(svc.effectiveHopBudget, ChatService.publicMaxHopsPerTurn + 10)
    }

    func test_continueWithExtraHops_accumulates() {
        let svc = makeService()
        svc.continueWithExtraHops(10)
        svc.continueWithExtraHops(10)
        XCTAssertEqual(svc.extraHopsGranted, 20)
    }

    /// Spec criterion 6b — calling continueWithExtraHops while an active
    /// subprocess is registered MUST still bump the grant (so the loop has
    /// budget when the subprocess returns), but the resume is deferred —
    /// the subprocess is not interrupted and no new hop is consumed
    /// mid-tool. The deferral is observable via `activeProcesses` being
    /// non-empty AND `effectiveHopBudget` already increased.
    func test_continueWithExtraHops_deferIfSubprocessActive() {
        let svc = makeService()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sleep")
        proc.arguments = ["1"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try? proc.run()
        defer { proc.terminate() }

        svc.registerProcess(proc, toolCallID: UUID(), tool: "bash")
        XCTAssertFalse(svc.activeProcesses.isEmpty)

        svc.continueWithExtraHops(10)
        XCTAssertEqual(svc.extraHopsGranted, 10, "Grant must land even while a tool is in flight")
        XCTAssertFalse(svc.activeProcesses.isEmpty, "Subprocess must NOT be cancelled by continueWithExtraHops")
    }
}
