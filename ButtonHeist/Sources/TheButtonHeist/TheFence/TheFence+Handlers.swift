import Foundation
import ThePlans

import TheScore

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Interface

    func handlePing() async throws -> FenceResponse {
        let payload = try await sendAndAwaitPong(timeout: Timeouts.healthSeconds)
        return .pong(payload)
    }

    func handleGetInterface(_ request: GetInterfaceRequest) async throws -> FenceResponse {
        let interface = try await sendAndAwaitInterface(
            .requestInterface(request.query),
            timeout: Timeouts.exploreSeconds
        )
        return .interface(interface, detail: request.detail)
    }

    func handleGetPasteboard() async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(.getPasteboard, timeout: Timeouts.healthSeconds)
        return .action(command: .getPasteboard, result: result)
    }

    // MARK: - Handler: Executable Commands

    func handleClientActionRequest(_ request: ParsedRequest) async throws -> FenceResponse {
        // Defensive fallback: the execution pipeline wraps every runtime action
        // command as a one-step heist before this handler can run.
        .error("command \"\(request.command.rawValue)\" must execute as a heistPlan")
    }

    func missingElementTargetResponse(command: String) -> FenceResponse {
        let contract = "requires target object with predicate fields"
        let next = "get_interface()"
        let matcherFields = ElementTarget.predicateFieldNames.map { "target.\($0)" }
        let matcherHint: String
        if let last = matcherFields.last {
            matcherHint = matcherFields.dropLast().joined(separator: ", ") + ", or \(last)"
        } else {
            matcherHint = ""
        }
        let targetHint = matcherHint
        let message = "\(command) request contract failed: missing target; \(contract). " +
            "Next: \(next) to inspect the current app accessibility state, then retry \(command) with \(targetHint)."
        return .error(
            message,
            details: FailureDetails(
                errorCode: FenceRequestErrorCode.missingTarget,
                phase: .request,
                retryable: false,
                hint: next
            )
        )
    }

}
