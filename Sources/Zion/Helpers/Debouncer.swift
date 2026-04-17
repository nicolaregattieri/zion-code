import Foundation

/// Reusable debounce primitive.
///
/// Each `schedule(_:)` cancels any prior pending work and arms a new Task that
/// fires after `interval` nanoseconds. Cancelling or re-scheduling inside the
/// interval drops the pending work — only the latest scheduled closure fires.
///
/// Mirrors VS Code's `debounce(delay:)` decorator (`extensions/git/src/decorators.ts:83`).
@MainActor
public final class Debouncer {

    private let interval: UInt64
    private var pending: Task<Void, Never>?

    public init(interval: UInt64) {
        self.interval = interval
    }

    public func schedule(_ work: @MainActor @escaping () -> Void) {
        pending?.cancel()
        let ns = interval
        pending = Task { [weak self] in
            if ns > 0 {
                try? await Task.sleep(nanoseconds: ns)
            }
            guard !Task.isCancelled else { return }
            guard self != nil else { return }
            work()
        }
    }

    public func cancel() {
        pending?.cancel()
        pending = nil
    }

    deinit {
        pending?.cancel()
    }
}
