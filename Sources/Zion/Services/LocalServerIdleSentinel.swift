import Foundation

/// Background watchdog that stops the local LLM server (mlx_lm.server /
/// ollama / llama-server / lms) after a period of inactivity.
///
/// Without this, a user who sends one chat to the local model and then
/// leaves Zion Talks idle keeps a multi-GB process alive indefinitely
/// (e.g. Qwen2.5-Coder-14B holds ~7 GB weights + 8 GB prompt cache).
///
/// Flow:
/// 1. `ChatService.runLocalStream` calls `noteActivity()` on every turn
///    aimed at the local model.
/// 2. A polling task ticks every `checkInterval` seconds. When the
///    server is up AND the time since `lastActivity` exceeds the
///    user's idle timeout, it asks `LocalServerLauncher.stop(...)` to
///    SIGTERM the listener.
/// 3. The sentinel itself never spawns the server — only Smart Auto +
///    the user-confirmed banner do that. Idle stop is reversible: the
///    next turn re-spawns via `ensureLocalServerRunning`.
///
/// The idle timeout is persisted in `UserDefaults` under the key
/// `chat.local.idleTimeoutMinutes`. `0` disables the sentinel.
@MainActor
final class LocalServerIdleSentinel {

    static let shared = LocalServerIdleSentinel()

    private static let defaultsKey = "chat.local.idleTimeoutMinutes"
    private static let defaultTimeoutMinutes: Int = 10
    private static let checkInterval: TimeInterval = 60

    private var lastActivity: Date = .distantPast
    private var pollTask: Task<Void, Never>?

    private init() {}

    /// Idle timeout in minutes. `0` disables auto-stop. Default: 10.
    var timeoutMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.defaultsKey)
        if UserDefaults.standard.object(forKey: Self.defaultsKey) == nil {
            return Self.defaultTimeoutMinutes
        }
        return max(0, stored)
    }

    /// Mark the local server as in-use right now. Restarts the watchdog
    /// timer if it has not been started yet.
    func noteActivity() {
        lastActivity = Date()
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.checkInterval * 1_000_000_000))
                guard let self else { return }
                await self.tick()
            }
        }
    }

    private func tick() async {
        let timeoutMin = self.timeoutMinutes
        guard timeoutMin > 0 else { return }
        let idleFor = Date().timeIntervalSince(lastActivity)
        guard idleFor >= TimeInterval(timeoutMin * 60) else { return }

        guard let config = AIClient.loadLocalConfig() else { return }

        let launcher = LocalServerLauncher()
        let outcome = await launcher.stop(config: config)
        switch outcome {
        case .stopped(let pid):
            DiagnosticLogger.shared.log(
                .info,
                "LocalServerIdleSentinel stopped pid=\(pid) after \(Int(idleFor))s idle",
                source: "LocalServerIdleSentinel"
            )
            // Park the activity clock far in the past so we do not fire
            // a stop on the very next tick if the user re-spawns and
            // walks away again — let `noteActivity` reset it.
            lastActivity = .distantPast
        case .notRunning, .noOwnerProcess:
            // Nothing to stop. Idle clock kept; next probe will catch it.
            break
        case .failed(let message):
            DiagnosticLogger.shared.log(
                .warn,
                "LocalServerIdleSentinel stop failed: \(message)",
                source: "LocalServerIdleSentinel"
            )
        }
    }
}
