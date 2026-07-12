import Foundation
import ThePlans

import TheScore

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Interface

    func handlePing() async throws -> FenceResponse {
        let payload = try await sendAndAwaitPong(timeout: Command.ping.descriptor.timeout.requiredFixedSeconds)
        return .pong(payload)
    }

    func handleGetInterface(_ request: GetInterfaceRequest) async throws -> FenceResponse {
        let interface = try await sendAndAwaitInterface(
            .requestInterface(request.query),
            timeout: Command.getInterface.descriptor.timeout.requiredFixedSeconds
        )
        return .interface(interface, detail: request.detail)
    }

    func handleGetPasteboard() async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(
            .getPasteboard,
            timeout: Command.getPasteboard.descriptor.timeout.requiredFixedSeconds
        )
        return .action(command: .getPasteboard, result: result)
    }

    func handleGetAnnouncements() async throws -> FenceResponse {
        let payload = try await sendAndAwaitAnnouncements(
            timeout: Command.getAnnouncements.descriptor.timeout.requiredFixedSeconds
        )
        return .announcements(payload.announcements)
    }

    // MARK: - Handler: Executable Commands

    func handleDirectActionRequest(_ request: DirectActionRequest) async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(
            .runtimeAction(request.action),
            timeout: request.command.descriptor.timeout.requiredDirectDispatchSeconds
        )
        return .action(command: request.command, result: result)
    }

}
