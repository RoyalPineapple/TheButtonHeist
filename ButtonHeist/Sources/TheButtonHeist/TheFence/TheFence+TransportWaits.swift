import Foundation

import ThePlans
import TheScore

extension TheFence {

    // MARK: - Send Action

    func sendAndAwaitAction(_ message: ClientMessage, timeout: TimeInterval) async throws -> ActionResult {
        try await sendAndAwait(message, expecting: .action, timeout: timeout)
    }

    func sendAndAwaitPong(timeout: TimeInterval) async throws -> PongPayload {
        try await sendAndAwait(.ping, expecting: .pong, timeout: timeout)
    }

    func sendAndAwaitInterface(_ message: ClientMessage, timeout: TimeInterval) async throws -> Interface {
        try await sendAndAwait(message, expecting: .interface, timeout: timeout)
    }

    func sendAndAwaitScreen(
        _ message: ClientMessage,
        timeout: TimeInterval
    ) async throws -> ScreenPayload {
        try await sendAndAwait(message, expecting: .screen, timeout: timeout)
    }

    func sendAndAwaitAnnouncements(timeout: TimeInterval) async throws -> AnnouncementListPayload {
        try await sendAndAwait(.getAnnouncements, expecting: .announcements, timeout: timeout)
    }

    func sendAndAwaitHeistExecution(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        timeout: TimeInterval
    ) async throws -> HeistExecutionResult {
        let message = ClientMessage.heistPlan(HeistPlanRun(plan: plan, argument: argument))
        return try await sendAndAwait(message, expecting: .heistExecution, timeout: timeout)
    }

    func cancelAllPendingRequests(error: Error = FenceError.actionTimeout) {
        pendingRequests.cancelAll(error: error)
    }

    private func sendAndAwait<Response: Sendable>(
        _ message: ClientMessage,
        expecting expectation: PendingResponseExpectation<Response>,
        timeout: TimeInterval
    ) async throws -> Response {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = try RequestID(validating: UUID().uuidString)
        return try await pendingRequests.waitForResponse(
            expectation,
            requestId: requestId,
            timeout: timeout
        ) {
            self.sendClientMessage(message, requestId: requestId)
        }
    }

    private func sendClientMessage(
        _ message: ClientMessage,
        requestId: RequestID
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
