import Foundation

/// Tracks the set of git operations currently running in the ViewModel.
///
/// Reference-counted so overlapping calls of the same kind (e.g. two concurrent
/// `status` reads) are tracked correctly. `isIdle` flips back to `true` only
/// when every counter is at zero.
///
/// Mirrors VS Code's `OperationManager` (`extensions/git/src/operation.ts`),
/// minus the progress-reporter wiring which Zion does not need at this layer.
@MainActor
public final class OperationManager {

    private var counts: [OperationKind: Int] = [:]
    private var progressCounts: [OperationKind: Int] = [:]
    private var nonReadOnlyCount: Int = 0

    public init() {}

    // MARK: - Lifecycle

    public func start(_ op: GitOperation) {
        counts[op.kind, default: 0] += 1
        if op.showProgress {
            progressCounts[op.kind, default: 0] += 1
        }
        if !op.readOnly {
            nonReadOnlyCount += 1
        }
    }

    public func end(_ op: GitOperation) {
        if let current = counts[op.kind], current > 1 {
            counts[op.kind] = current - 1
        } else {
            counts.removeValue(forKey: op.kind)
        }

        if op.showProgress {
            if let current = progressCounts[op.kind], current > 1 {
                progressCounts[op.kind] = current - 1
            } else {
                progressCounts.removeValue(forKey: op.kind)
            }
        }

        if !op.readOnly {
            nonReadOnlyCount = max(0, nonReadOnlyCount - 1)
        }
    }

    // MARK: - Queries

    public func isRunning(_ kind: OperationKind) -> Bool {
        (counts[kind] ?? 0) > 0
    }

    public var isIdle: Bool {
        counts.isEmpty
    }

    /// True when any non-read-only operation (commit, fetch, push, etc.) is in flight.
    /// Used by the idle+focus gate to defer file-watcher refreshes that could race
    /// with a running mutation.
    public var hasActiveNonReadOnlyOperation: Bool {
        nonReadOnlyCount > 0
    }

    public func shouldShowProgress() -> Bool {
        !progressCounts.isEmpty
    }
}
