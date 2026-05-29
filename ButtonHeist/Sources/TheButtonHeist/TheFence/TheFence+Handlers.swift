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
        let messages = try executableActionMessages(for: request)
        let timeout = try request.command.descriptor.executionTimeout(for: request)
        var finalResult: ActionResult?
        for message in messages {
            let result = try await sendAndAwaitAction(message, timeout: timeout)
            if result.method != .getPasteboard {
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
        let matcherFields = ElementTarget.matcherFieldNames.map { "target.\($0)" }
        let matcherHint: String
        if let last = matcherFields.last {
            matcherHint = matcherFields.dropLast().joined(separator: ", ") + ", or \(last)"
        } else {
            matcherHint = ""
        }
        let targetHint = "target.\(ElementTarget.heistIdFieldName) or \(matcherHint)"
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
