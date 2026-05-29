import Foundation

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

    // MARK: - Handler: Executable Commands

    func handleClientActionRequest(_ request: ParsedRequest) async throws -> FenceResponse {
        let plan = try clientMessageExecutionPlan(for: request)
        var finalResult: ActionResult?
        for message in plan.messages {
            let result = try await sendAndAwaitAction(message, timeout: plan.timeout)
            if plan.recordsCompletion {
                recordCompletedAction(result)
            }
            finalResult = result
            if !result.success {
                return .action(result: result)
            }
        }
        guard let finalResult else {
            return .error("command \"\(request.command.rawValue)\" did not produce an executable action")
        }
        return .action(result: finalResult)
    }

    func missingElementTargetResponse(command: String) -> FenceResponse {
        let contract = "requires target object with heistId or matcher fields"
        let next = "get_interface()"
        let message = "\(command) request contract failed: missing target; \(contract). " +
            "Next: \(next) to inspect the current app accessibility state, then retry \(command) with target.heistId or target.label, target.identifier, target.value, target.traits, or target.excludeTraits."
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
