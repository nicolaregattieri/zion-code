import Foundation

// MARK: - Refresh Gate Orchestrator
//
// Single decision point evaluated on every `refreshRepository` call. Each
// rule inspects the current view-model state and the refresh `origin` and
// returns one of:
//
//   - `.proceed`      — run the full `refreshRepository` body (default)
//   - `.skip`         — silently early-return; pending state typically drained
//                       elsewhere on a state change (e.g. Zen exit, section
//                       switch)
//   - `.redirect(...)`— run an alternate, lightweight handler instead of the
//                       full refresh path
//
// Adding a new rule (e.g. a future workspace mode) means appending a single
// `if` block here. Replay logic for each rule lives near the state mutation
// that flips its predicate (e.g. `exitZenMode`, `loadDeferredDataForSection`).

enum RefreshGateAction {
    case proceed
    case skip
    case redirect(() -> Void)
}

extension RepositoryViewModel {

    func evaluateRefreshGate(origin: RefreshOrigin) -> RefreshGateAction {
        // Zen mode: pause all background refreshes (terminal sessions stay
        // silent). Replay armed by `exitZenMode` via `zenResumeTask`.
        if isZenModePaused && (origin == .autoTimer || origin == .fileWatcher) {
            return .skip
        }

        // Zion Code section (RT-007): file-watcher events run only the slim
        // Code-relevant slice (branch/head/status/conflicts). Tree/Ops data
        // stays last-known and refreshes on tab entry via `treeOpsDataStale`,
        // drained by `loadDeferredDataForSection`.
        if origin == .fileWatcher && activeSection == .code {
            return .redirect { [weak self] in self?.refreshCodeMinimal() }
        }

        return .proceed
    }
}
