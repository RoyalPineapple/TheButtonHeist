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

    func handleDirectActionRequest(_ request: DirectActionRequest) async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(
            .runtimeAction(request.action),
            timeout: directActionTimeout(for: request.action)
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
