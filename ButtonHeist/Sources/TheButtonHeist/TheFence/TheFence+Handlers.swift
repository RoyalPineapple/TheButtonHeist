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
        let executable = try executableRequest(for: request)
        guard case .actions(let actions) = executable else {
            return .failure(FenceError.invalidRequest(
                "command \"\(request.command.rawValue)\" direct dispatch requires an action command"
            ))
        }
        guard actions.count == 1 else {
            return .failure(FenceError.invalidRequest(
                "command \"\(request.command.rawValue)\" direct dispatch requires exactly one action command"
            ))
        }
        guard request.expectationPayload.expectation == nil else {
            return .failure(FenceError.invalidRequest(
                "command \"\(request.command.rawValue)\" direct dispatch does not support expect"
            ))
        }
        let command = actions.first
        let result = try await sendAndAwaitAction(
            .runtimeAction(command),
            timeout: directActionTimeout(for: command)
        )
        return .action(command: request.command, result: result)
    }

    func missingElementTargetResponse(command: String) -> FenceResponse {
        .failure(MissingElementTarget(command: command))
    }

    private func directActionTimeout(for command: HeistActionCommand) -> TimeInterval {
        switch command {
        case .typeText:
            return Timeouts.longActionSeconds
        default:
            return Timeouts.actionSeconds
        }
    }

}
