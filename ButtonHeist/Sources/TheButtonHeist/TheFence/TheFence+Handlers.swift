import Foundation
import ThePlans

import TheScore

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Interface

    func handlePing(timeout: TimeInterval) async throws -> FenceResponse {
        let payload = try await sendAndAwaitPong(timeout: timeout)
        return .pong(payload)
    }

    func handleGetInterface(_ request: GetInterfaceRequest, timeout: TimeInterval) async throws -> FenceResponse {
        let interface = try await sendAndAwaitInterface(
            .requestInterface(request.query),
            timeout: timeout
        )
        return .interface(interface, detail: request.detail)
    }

    func handleGetPasteboard(timeout: TimeInterval) async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(
            .getPasteboard,
            timeout: timeout
        )
        return .action(command: .getPasteboard, result: result)
    }

    func handleGetAnnouncements(timeout: TimeInterval) async throws -> FenceResponse {
        let payload = try await sendAndAwaitAnnouncements(
            timeout: timeout
        )
        return .announcements(payload.announcements)
    }

    // MARK: - Direct Action Execution

    func executeDirectAction(_ execution: DirectActionExecution, command: Command) async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(
            .runtimeAction(execution.action),
            timeout: execution.timeout
        )
        return .action(command: command, result: result)
    }

}
