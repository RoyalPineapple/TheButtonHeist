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

    // MARK: - Handler: Executable Commands

    func handleDirectActionRequest(_ request: DirectActionRequest, command: Command) async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(
            .runtimeAction(request.action),
            timeout: request.timeout
        )
        return .action(command: command, result: result)
    }

}
