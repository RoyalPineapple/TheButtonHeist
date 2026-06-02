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
        let timeout = actionTimeout(for: messages)
        var finalResult: ActionResult?
        for message in messages {
            let result = try await sendAndAwaitAction(message, timeout: timeout)
            finalResult = result
            if !result.success {
                return .action(command: request.command, result: result)
            }
        }
        guard let finalResult else {
            return .error("command \"\(request.command.rawValue)\" did not produce an executable action")
        }
        return .action(command: request.command, result: finalResult)
    }

    private func actionTimeout(for messages: [ClientMessage]) -> TimeInterval {
        guard let message = messages.first else { return Timeouts.actionSeconds }
        switch message {
        case .getPasteboard:
            return Timeouts.healthSeconds
        case .typeText:
            return Timeouts.longActionSeconds
        case .wait(let target):
            return target.resolvedTimeout + 5
        default:
            return Timeouts.actionSeconds
        }
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
