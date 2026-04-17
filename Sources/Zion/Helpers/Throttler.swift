import Foundation

/// Reusable throttle primitive.
///
/// Semantics: if no work is currently in flight, schedule runs it immediately.
/// If work is in flight, the incoming closure is stored as the single `next` —
/// additional `schedule` calls while `current` and `next` are both present
/// overwrite `next`. When `current` finishes, `next` (if any) is promoted and
/// fires. Net effect: a burst of N schedule calls collapses to at most 2 runs.
///
/// Mirrors VS Code's `_throttle` decorator
/// (`extensions/git/src/decorators.ts:39-68`).
@MainActor
public final class Throttler {

    private let interval: UInt64
    private var current: Task<Void, Never>?
    private var next: (@MainActor () async -> Void)?

    public init(interval: UInt64 = 0) {
        self.interval = interval
    }

    public func schedule(_ work: @MainActor @escaping () async -> Void) {
        if current == nil {
            current = Task { [weak self] in
                await work()
                await self?.drainNext()
            }
            return
        }
        // Work in flight — keep only the most recent next.
        next = work
    }

    public func cancel() {
        current?.cancel()
        current = nil
        next = nil
    }

    // MARK: - Internals

    private func drainNext() async {
        if interval > 0 {
            try? await Task.sleep(nanoseconds: interval)
        }
        if let follow = next {
            next = nil
            current = Task { [weak self] in
                await follow()
                await self?.drainNext()
            }
        } else {
            current = nil
        }
    }

    deinit {
        current?.cancel()
    }
}
