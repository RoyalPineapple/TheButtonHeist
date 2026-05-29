import Foundation

import TheScore

extension TheFence {

    // MARK: - Send Action

    func sendAction(_ message: ClientMessage) async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(message, timeout: Timeouts.actionSeconds)
        commandExecutionState.completeAction(result)
        return .action(result: result)
    }

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

    func sendAndAwaitBatchExecution(
        _ plan: TheScore.BatchPlan,
        timeout: TimeInterval
    ) async throws -> BatchExecutionResult {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let requestId = UUID().uuidString
        return try await pendingRequests.waitForBatchExecution(requestId: requestId, timeout: timeout) {
            let outcome = self.handoff.send(.batchExecutionPlan(plan), requestId: requestId)
            if case .failed(let failure) = outcome {
                self.pendingRequests.resolveBatchExecution(
                    requestId: requestId,
                    result: Result<BatchExecutionResult, Error>.failure(FenceError(failure))
                )
            }
        }
    }

    func cancelAllPendingRequests(error: Error = FenceError.actionTimeout) {
        pendingRequests.cancelAll(error: error)
        recording.cancelAll(error: error)
    }
}
