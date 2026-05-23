// PlanModeGate.swift — Plan-first gating for the agentic loop.
//
// When PlanModeState.current() == .planFirst, the gate forces .readOnly for step 1
// (plan generation), then pauses the loop awaiting user approval.
// User approves → loop resumes with full tier.
// User rejects  → loop cancels, partial LoopResult returned.
//
// Concurrency: actor — all state mutations serialised.

import Foundation

// MARK: - PlanModeStatus

enum PlanModeStatus: Sendable, Equatable {
    case inactive           // PlanModeState != .planFirst
    case beforeFirstStep    // planFirst, step 1 not yet executed
    case awaitingApproval   // step 1 done, waiting for user
    case resumedWithTier(AgentApprovalTier)  // user approved
    case rejected           // user rejected
}

// MARK: - PlanModeGate

actor PlanModeGate {

    private(set) var status: PlanModeStatus
    private var approvalContinuation: CheckedContinuation<AgentApprovalTier?, Never>?

    init(initialState: PlanModeState) {
        self.status = initialState == .planFirst ? .beforeFirstStep : .inactive
    }

    // MARK: - Effective tier

    /// Returns the tier the runner should use for the current step.
    /// Forces .readOnly while in beforeFirstStep / awaitingApproval.
    func effectiveTier(userTier: AgentApprovalTier) -> AgentApprovalTier {
        switch status {
        case .beforeFirstStep, .awaitingApproval:
            return .readOnly
        case .inactive:
            return userTier
        case .resumedWithTier(let tier):
            return tier
        case .rejected:
            return .readOnly   // loop will exit anyway
        }
    }

    // MARK: - Approval flow

    /// Called after step 1 completes (currentStep == 1, status == .beforeFirstStep).
    /// Transitions to .awaitingApproval, suspends, and returns the approved tier (or nil on reject).
    func waitForApprovalIfNeeded(currentStep: Int) async -> AgentApprovalTier? {
        guard currentStep == 1, status == .beforeFirstStep else { return nil }
        status = .awaitingApproval
        return await withCheckedContinuation { cont in
            self.approvalContinuation = cont
        }
    }

    func approve(withTier tier: AgentApprovalTier) {
        guard status == .awaitingApproval else { return }
        status = .resumedWithTier(tier)
        approvalContinuation?.resume(returning: tier)
        approvalContinuation = nil
    }

    func reject() {
        guard status == .awaitingApproval else { return }
        status = .rejected
        approvalContinuation?.resume(returning: nil)
        approvalContinuation = nil
    }
}
