import Foundation

/// Phase 5 — output of the A/B eval harness. Compares the recall of
/// the two embedding backends against the hand-labeled golden set and
/// decides whether to promote Qodo to default. Phase 5 records the
/// decision in `DiagnosticLogger`; actual default-swap is a follow-up
/// once we have dogfood evidence on Qodo's 600MB asset cost.
enum RAGBackendPromotion: Equatable {
    case keepDefault
    case promoteQodo(deltaRecall: Double)
    case unavailable(reason: String)

    /// `deltaThreshold` defaults to 0.10 (10%) per the RFC. Returns
    /// `.unavailable` if Qodo recall is nil.
    static func decide(
        nlContextualRecall: Double,
        qodoRecall: Double?,
        deltaThreshold: Double = 0.10
    ) -> RAGBackendPromotion {
        guard let qodo = qodoRecall else {
            return .unavailable(reason: "qodo asset missing")
        }
        let delta = qodo - nlContextualRecall
        if delta >= deltaThreshold {
            return .promoteQodo(deltaRecall: delta)
        }
        return .keepDefault
    }
}
