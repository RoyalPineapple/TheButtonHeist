import Foundation

import TheScore

extension TheFence {

    // MARK: - Command Execution State

    /// Last completed action, if any. Session display state derives from the
    /// active case instead of sibling cached projections.
    enum LastAction {
        case none
        case completed(result: ActionResult, latencyMs: Int)

        var sessionPayload: SessionLastActionPayload? {
            guard case .completed(let result, let latencyMs) = self else { return nil }
            return SessionLastActionPayload(
                method: result.method,
                success: result.success,
                message: result.message,
                latencyMs: latencyMs
            )
        }

        var latencyMsForReplacement: Int {
            guard case .completed(_, let latencyMs) = self else { return 0 }
            return latencyMs
        }
    }

    /// Owns command-execution state derived from dispatched action responses.
    final class CommandExecutionState {
        private(set) var lastAction: LastAction = .none

        func noteDispatchedResponse(_ response: FenceResponse, latencyMs: Int) {
            guard let result = response.actionResult else { return }
            lastAction = .completed(result: result, latencyMs: latencyMs)
        }

        func completeAction(_ result: ActionResult) {
            lastAction = .completed(result: result, latencyMs: lastAction.latencyMsForReplacement)
        }

        func reset() {
            lastAction = .none
        }
    }
}
