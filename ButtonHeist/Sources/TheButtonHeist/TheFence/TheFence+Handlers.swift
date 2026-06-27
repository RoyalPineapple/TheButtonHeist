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
        .failure(MissingElementTarget(command: command))
    }

}
