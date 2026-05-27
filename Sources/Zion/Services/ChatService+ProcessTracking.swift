import Foundation

/// Phase 4 — cooperative subprocess termination on `ChatService.stop()`.
/// Existing `stop()` cancels the stream task, but tool calls that already
/// spawned a `Process` (bash, sed, edit, search) kept running until the
/// subprocess finished. With this extension every spawned tool process
/// registers under a per-call UUID; `terminateAllActiveProcesses()` sends
/// SIGTERM in parallel, waits `Constants.Timing.harnessCancelDeadlineMs`,
/// then SIGKILLs any stragglers. Gated by
/// `Constants.Feature.harnessProcessKillOnStop` (UserDefaults overrideable,
/// default true) so we can flip the kill-switch without recompiling.
extension ChatService {

    /// Register a freshly-spawned tool subprocess so `stop()` can reach it.
    /// Caller is the harness adapter that owns the `Process` lifecycle.
    func registerProcess(_ process: Process, toolCallID: UUID, tool: String) {
        activeProcesses[toolCallID] = TrackedProcess(process: process, tool: tool)
    }

    /// Unregister once the subprocess returns normally — keeps the map tight.
    func unregisterProcess(toolCallID: UUID) {
        activeProcesses.removeValue(forKey: toolCallID)
    }

    /// SIGTERM every active tool subprocess in parallel, await the cancel
    /// deadline, then SIGKILL stragglers. No-op when the map is empty so
    /// `stop()` on an idle chat does not produce diagnostic noise.
    func terminateAllActiveProcesses() async {
        guard Self.harnessProcessKillOnStopEnabled else { return }
        let snapshot = activeProcesses
        guard !snapshot.isEmpty else { return }
        activeProcesses.removeAll(keepingCapacity: true)

        await DiagnosticLogger.shared.log(
            .info,
            "harness.stop terminating \(snapshot.count) active subprocess(es)"
        )

        for (_, tracked) in snapshot where tracked.process.isRunning {
            tracked.process.terminate() // SIGTERM
            await DiagnosticLogger.shared.log(
                .info,
                "harness.stop SIGTERM tool=\(tracked.tool) pid=\(tracked.process.processIdentifier)"
            )
        }

        let deadlineNs = UInt64(Constants.Timing.harnessCancelDeadlineMs) * 1_000_000
        try? await Task.sleep(nanoseconds: deadlineNs)

        for (_, tracked) in snapshot where tracked.process.isRunning {
            kill(tracked.process.processIdentifier, SIGKILL)
            await DiagnosticLogger.shared.log(
                .warn,
                "harness.stop SIGKILL tool=\(tracked.tool) pid=\(tracked.process.processIdentifier)"
            )
        }
    }

    /// Reads the kill-switch from `UserDefaults` (debug override) and falls
    /// back to the compile-time default. Static because it is consulted
    /// before any ChatService instance state is touched.
    static var harnessProcessKillOnStopEnabled: Bool {
        if let override = UserDefaults.standard.object(forKey: "harness.processKillOnStop") as? Bool {
            return override
        }
        return Constants.Feature.harnessProcessKillOnStop
    }
}

/// Wraps the spawned `Process` together with the tool name so diagnostic
/// logs can name what we just killed.
struct TrackedProcess {
    let process: Process
    let tool: String
}
