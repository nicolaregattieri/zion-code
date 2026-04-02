import Foundation

/// Centralized coordinator that replaces N independent per-terminal flush timers
/// with a single adaptive timer. Allocates a global byte budget per frame and
/// distributes it across active terminals, giving the focused terminal priority.
///
/// Without coordination, 3+ terminals each running heavy output (e.g. Claude Code)
/// schedule independent 16ms timers that saturate the main thread with synchronous
/// `view.feed()` calls, starving input events and causing perceived freezes.
@MainActor
final class TerminalOutputCoordinator {

    // MARK: - Types

    private struct Entry {
        weak var coordinator: AnyObject?  // TerminalTabView.Coordinator
        let flush: (Int) -> Bool          // flushWithBudget → returns true if pending data remains
    }

    // MARK: - State

    private var entries: [UUID: Entry] = [:]
    private var flushTask: Task<Void, Never>?
    weak var viewModel: RepositoryViewModel?

    // MARK: - Tuning

    /// Base flush interval for a single terminal (60fps)
    private static let baseIntervalNanos: UInt64 = 16_000_000
    /// Additional interval per extra terminal beyond the first
    private static let perTerminalIntervalNanos: UInt64 = 4_000_000
    /// Hard cap on flush interval regardless of terminal count
    private static let maxIntervalNanos: UInt64 = 32_000_000
    /// Total byte budget across all terminals per flush cycle
    private static let maxBytesPerFrame = 196_608  // 192KB
    /// Focused terminal gets this multiplier of the base share
    private static let focusedMultiplier = 2.0

    // MARK: - Computed

    var activeCount: Int { entries.count }

    private var flushInterval: UInt64 {
        let n = max(1, entries.count)
        return min(
            Self.maxIntervalNanos,
            Self.baseIntervalNanos + UInt64(max(0, n - 1)) * Self.perTerminalIntervalNanos
        )
    }

    // MARK: - Registration

    func register(sessionID: UUID, coordinator: AnyObject, flush: @escaping (Int) -> Bool) {
        entries[sessionID] = Entry(coordinator: coordinator, flush: flush)
    }

    func unregister(sessionID: UUID) {
        entries.removeValue(forKey: sessionID)
        if entries.isEmpty {
            flushTask?.cancel()
            flushTask = nil
        }
    }

    // MARK: - Scheduling

    /// Called by individual coordinators when new data arrives.
    /// Fast path: flushes the focused terminal immediately (no sleep) so
    /// keystroke echo appears within the same frame. Background terminals
    /// and remaining data go through the batched sleep path.
    func notifyDataAvailable() {
        guard !entries.isEmpty else { return }

        // Fast path — flush focused terminal immediately for responsive typing.
        // Only fires when no batched flush is already scheduled, so heavy
        // output still coalesces through scheduleBatchFlush().
        if flushTask == nil, let focusedID = viewModel?.focusedSessionID,
           let entry = entries[focusedID] {
            _ = entry.flush(Self.maxBytesPerFrame)

            // Also flush any other terminals that may have data
            for (sessionID, otherEntry) in entries where sessionID != focusedID {
                _ = otherEntry.flush(Self.maxBytesPerFrame / max(1, entries.count))
            }

            // Always schedule a batch flush as cooldown — prevents the fast path
            // from firing on every single data notification (which would saturate
            // the main thread with synchronous flushes, starving input events).
            scheduleBatchFlush()
            return
        }

        scheduleBatchFlush()
    }

    private func scheduleBatchFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.flushInterval ?? Self.baseIntervalNanos)
            guard let self else { return }
            self.flushTask = nil
            self.flushAll()
        }
    }

    // MARK: - Flush cycle

    private func flushAll() {
        // Prune dead entries (weak coordinator was deallocated)
        entries = entries.filter { $0.value.coordinator != nil }
        guard !entries.isEmpty else { return }

        let focusedID = viewModel?.focusedSessionID
        let count = entries.count

        // Compute per-terminal byte budgets
        let focusedBudget: Int
        let normalBudget: Int

        if count == 1 {
            focusedBudget = Self.maxBytesPerFrame
            normalBudget = Self.maxBytesPerFrame
        } else {
            let hasFocused = focusedID.flatMap { entries.keys.contains($0) } ?? false
            let focusedCount = hasFocused ? 1 : 0
            let normalCount = count - focusedCount
            let shares = Double(normalCount) + (focusedCount > 0 ? Self.focusedMultiplier : 0)
            normalBudget = max(1, Int(Double(Self.maxBytesPerFrame) / shares))
            focusedBudget = max(1, Int(Double(Self.maxBytesPerFrame) * Self.focusedMultiplier / shares))
        }

        // Flush focused terminal first for lowest latency
        var hasPending = false
        if let focusedID, let entry = entries[focusedID] {
            if entry.flush(focusedBudget) { hasPending = true }
        }
        for (sessionID, entry) in entries where sessionID != focusedID {
            if entry.flush(normalBudget) { hasPending = true }
        }

        if hasPending {
            notifyDataAvailable()
        }
    }
}
