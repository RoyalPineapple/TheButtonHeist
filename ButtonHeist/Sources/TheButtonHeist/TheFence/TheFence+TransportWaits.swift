import Foundation

import ThePlans
import TheScore

extension TheFence {

    // MARK: - Send Action

    func sendAndAwaitAction(_ message: ClientMessage, timeout: TimeInterval) async throws -> ActionResult {
        let response = try await sendAndAwaitResponse(message, expecting: .action, timeout: timeout)
        guard case .action(let result) = response else {
            throw PendingRequestTrackers.responseTypeMismatchError(expected: .action, actual: response.expectation)
        }
        return result
    }

    func sendAndAwaitPong(timeout: TimeInterval) async throws -> PongPayload {
        let response = try await sendAndAwaitResponse(.ping, expecting: .pong, timeout: timeout)
        guard case .pong(let payload) = response else {
            throw PendingRequestTrackers.responseTypeMismatchError(expected: .pong, actual: response.expectation)
        }
        return payload
    }

    func sendAndAwaitInterface(_ message: ClientMessage, timeout: TimeInterval) async throws -> Interface {
        let response = try await sendAndAwaitResponse(message, expecting: .interface, timeout: timeout)
        guard case .interface(let interface) = response else {
            throw PendingRequestTrackers.responseTypeMismatchError(expected: .interface, actual: response.expectation)
        }
        return interface
    }

    func sendAndAwaitScreen(_ message: ClientMessage, timeout: TimeInterval) async throws -> ScreenPayload {
        let response = try await sendAndAwaitResponse(message, expecting: .screen, timeout: timeout)
        guard case .screen(let payload) = response else {
            throw PendingRequestTrackers.responseTypeMismatchError(expected: .screen, actual: response.expectation)
        }
        return payload
    }

    func sendAndAwaitHeistExecution(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        timeout: TimeInterval
    ) async throws -> HeistExecutionResult {
        let message = ClientMessage.heistPlan(HeistPlanRun(plan: plan, argument: argument))
        let response = try await sendAndAwaitResponse(message, expecting: .heistExecution, timeout: timeout)
        guard case .heistExecution(let result) = response else {
            throw PendingRequestTrackers.responseTypeMismatchError(
                expected: .heistExecution,
                actual: response.expectation
            )
        }
        return result
    }

    func cancelAllPendingRequests(error: Error = FenceError.actionTimeout) {
        pendingRequests.cancelAll(error: error)
    }

    private func sendAndAwaitResponse(
        _ message: ClientMessage,
        expecting expectation: PendingResponseExpectation,
        timeout: TimeInterval
    ) async throws -> PendingResponse {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForResponse(
            requestId: requestId,
            expecting: expectation,
            timeout: timeout
        ) {
            let outcome = self.handoff.send(message, requestId: requestId)
            if case .failed(let failure) = outcome {
                self.pendingRequests.resolveTransientFailure(FenceError(failure), requestId: requestId)
            }
        }
    }
}
