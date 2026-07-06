import Foundation

import ThePlans
import TheScore

extension TheFence {

    // MARK: - Send Action

    func sendAndAwaitAction(_ message: ClientMessage, timeout: TimeInterval) async throws -> ActionResult {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForAction(
            requestId: requestId,
            timeout: timeout
        ) {
            self.sendClientMessage(message, requestId: requestId)
        }
    }

    func sendAndAwaitPong(timeout: TimeInterval) async throws -> PongPayload {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForPong(
            requestId: requestId,
            timeout: timeout
        ) {
            self.sendClientMessage(.ping, requestId: requestId)
        }
    }

    func sendAndAwaitInterface(_ message: ClientMessage, timeout: TimeInterval) async throws -> Interface {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForInterface(
            requestId: requestId,
            timeout: timeout
        ) {
            self.sendClientMessage(message, requestId: requestId)
        }
    }

    func sendAndAwaitScreen(
        _ message: ClientMessage,
        timeout: TimeInterval
    ) async throws -> ScreenPayload {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForScreen(
            requestId: requestId,
            timeout: timeout
        ) {
            self.sendClientMessage(message, requestId: requestId)
        }
    }

    func sendAndAwaitAnnouncements(timeout: TimeInterval) async throws -> AnnouncementListPayload {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForAnnouncements(
            requestId: requestId,
            timeout: timeout
        ) {
            self.sendClientMessage(.getAnnouncements, requestId: requestId)
        }
    }

    func sendAndAwaitHeistExecution(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        timeout: TimeInterval
    ) async throws -> HeistExecutionResult {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let message = ClientMessage.heistPlan(HeistPlanRun(plan: plan, argument: argument))
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForHeistExecution(
            requestId: requestId,
            timeout: timeout
        ) {
            self.sendClientMessage(message, requestId: requestId)
        }
    }

    func cancelAllPendingRequests(error: Error = FenceError.actionTimeout) {
        pendingRequests.cancelAll(error: error)
    }

    private func sendClientMessage(
        _ message: ClientMessage,
        requestId: String
    ) {
        let outcome = handoff.send(
            message,
            requestId: requestId
        )
        if case .failed(let failure) = outcome {
            pendingRequests.resolveTransientFailure(FenceError(failure), requestId: requestId)
        }
    }
}
