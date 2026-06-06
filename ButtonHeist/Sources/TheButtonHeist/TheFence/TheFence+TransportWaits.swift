import Foundation

import ThePlans
import TheScore

extension TheFence {

    // MARK: - Send Action

    func sendAndAwaitAction(_ message: ClientMessage, timeout: TimeInterval) async throws -> ActionResult {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForAction(requestId: requestId, timeout: timeout) {
            let outcome = self.handoff.send(message, requestId: requestId)
            if case .failed(let failure) = outcome {
                self.pendingRequests.resolveAction(
                    requestId: requestId,
                    result: Result<ActionResult, Error>.failure(FenceError(failure))
                )
            }
        }
    }

    func sendAndAwaitPong(timeout: TimeInterval) async throws -> PongPayload {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForPong(requestId: requestId, timeout: timeout) {
            let outcome = self.handoff.send(.ping, requestId: requestId)
            if case .failed(let failure) = outcome {
                self.pendingRequests.resolvePong(
                    requestId: requestId,
                    result: Result<PongPayload, Error>.failure(FenceError(failure))
                )
            }
        }
    }

    func sendAndAwaitInterface(_ message: ClientMessage, timeout: TimeInterval) async throws -> Interface {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForInterface(requestId: requestId, timeout: timeout) {
            let outcome = self.handoff.send(message, requestId: requestId)
            if case .failed(let failure) = outcome {
                self.pendingRequests.resolveInterface(
                    requestId: requestId,
                    result: Result<Interface, Error>.failure(FenceError(failure))
                )
            }
        }
    }

    func sendAndAwaitScreen(_ message: ClientMessage, timeout: TimeInterval) async throws -> ScreenPayload {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForScreen(requestId: requestId, timeout: timeout) {
            let outcome = self.handoff.send(message, requestId: requestId)
            if case .failed(let failure) = outcome {
                self.pendingRequests.resolveScreen(
                    requestId: requestId,
                    result: Result<ScreenPayload, Error>.failure(FenceError(failure))
                )
            }
        }
    }

    func sendAndAwaitHeistExecution(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        timeout: TimeInterval
    ) async throws -> HeistExecutionResult {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForHeistExecution(requestId: requestId, timeout: timeout) {
            let outcome = self.handoff.send(.heistPlan(HeistPlanRun(plan: plan, argument: argument)), requestId: requestId)
            if case .failed(let failure) = outcome {
                self.pendingRequests.resolveHeistExecution(
                    requestId: requestId,
                    result: Result<HeistExecutionResult, Error>.failure(FenceError(failure))
                )
            }
        }
    }

    func cancelAllPendingRequests(error: Error = FenceError.actionTimeout) {
        pendingRequests.cancelAll(error: error)
    }
}
