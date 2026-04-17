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

    public init() {}

    // MARK: - Lifecycle

    public func start(_ op: Operation) {
        counts[op.kind, default: 0] += 1
        if op.showProgress {
            progressCounts[op.kind, default: 0] += 1
        }
    }

    public func end(_ op: Operation) {
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
    }

    // MARK: - Queries

    public func isRunning(_ kind: OperationKind) -> Bool {
        (counts[kind] ?? 0) > 0
    }

    public var isIdle: Bool {
        counts.isEmpty
    }

    public func shouldShowProgress() -> Bool {
        !progressCounts.isEmpty
    }
}
