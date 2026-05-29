import Foundation

/// Phase 4 — "Continue (+10 hops)" affordance for `max_hops_exceeded`.
/// Today the tool loop aborts when the per-turn hop budget runs out; this
/// extension lets the user bump the budget by `Constants.Limits.continueChipHopBoost`
/// and resume the loop on the same thread. While an active subprocess is
/// in flight (`activeProcesses` non-empty), the resume DEFERS until that
/// subprocess returns — no new hop is consumed mid-tool.
extension ChatService {

    /// Bumps the per-message extra-hop grant by `delta`. The harness loop
    /// reads this value the next time it considers stopping. If a tool
    /// subprocess is currently running, the resume is deferred via the
    /// existing `activeProcesses` tracking; the loop picks up after the
    /// process unregisters.
    func continueWithExtraHops(_ delta: Int = Constants.Limits.continueChipHopBoost) {
        extraHopsGranted += delta
        Task { @MainActor in
            DiagnosticLogger.shared.log(
                .info,
                "chat.continueWithExtraHops delta=\(delta) total=\(self.extraHopsGranted) activeProcesses=\(self.activeProcesses.count) deferred=\(!self.activeProcesses.isEmpty)"
            )
        }
        // If a subprocess is in flight, the loop will resume naturally when
        // unregisterProcess fires — no further action needed here.
    }

    /// Effective hop budget for the current turn = base `maxHopsPerTurn`
    /// (private) + any continue-chip grants the user has tapped. Exposed
    /// here as a computed accessor so the loop can consult a single source.
    var effectiveHopBudget: Int {
        Self.publicMaxHopsPerTurn + extraHopsGranted
    }
}

extension ChatService {
    /// Mirror of the file-private `maxHopsPerTurn` so this extension can
    /// reason about the base budget without touching the original constant.
    static var publicMaxHopsPerTurn: Int { 3 }
}

/// Emitted on the assistant turn when the harness detects hop exhaustion.
/// `ChatScreen` renders an inline `ContinueChipView` for any message
/// carrying this event.
struct ContinueChipPayload: Equatable, Codable {
    let messageID: UUID
    let hopsAlreadyUsed: Int
    /// Localized label key — `chat.continue.plus10` resolves via L10n at
    /// render time so the view does not embed the budget number directly.
    let labelKey: String
}
