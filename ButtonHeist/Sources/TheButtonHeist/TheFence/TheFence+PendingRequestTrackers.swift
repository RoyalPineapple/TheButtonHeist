import Foundation
import os

import TheScore

extension TheFence {

    // MARK: - Pending Request Tracking

    fileprivate enum PendingResponseExpectation: Sendable {
        case action
        case pong
        case interface
        case screen
        case heistExecution

        fileprivate var responseName: String {
            switch self {
            case .action:
                return "action"
            case .pong:
                return "pong"
            case .interface:
                return "interface"
            case .screen:
                return "screen"
            case .heistExecution:
                return "heist execution"
            }
        }
    }

    fileprivate struct PendingRequest<Response: Sendable>: Sendable {
        let owner: UUID
        let callback: @Sendable (Result<Response, Error>) -> Void
    }

    fileprivate enum PendingResponseContinuation: Sendable {
        case action(PendingRequest<ActionResult>)
        case pong(PendingRequest<PongPayload>)
        case interface(PendingRequest<Interface>)
        case screen(PendingRequest<ScreenPayload>)
        case heistExecution(PendingRequest<HeistExecutionResult>)

        var expectation: PendingResponseExpectation {
            switch self {
            case .action:
                return .action
            case .pong:
                return .pong
            case .interface:
                return .interface
            case .screen:
                return .screen
            case .heistExecution:
                return .heistExecution
            }
        }

        var owner: UUID {
            switch self {
            case .action(let request):
                return request.owner
            case .pong(let request):
                return request.owner
            case .interface(let request):
                return request.owner
            case .screen(let request):
                return request.owner
            case .heistExecution(let request):
                return request.owner
            }
        }

        func resumeFailure(_ error: Error) {
            switch self {
            case .action(let request):
                request.callback(.failure(error))
            case .pong(let request):
                request.callback(.failure(error))
            case .interface(let request):
                request.callback(.failure(error))
            case .screen(let request):
                request.callback(.failure(error))
            case .heistExecution(let request):
                request.callback(.failure(error))
            }
        }
    }

    @ButtonHeistActor
    final class PendingRequestTrackers {
        private var pending: [String: PendingResponseContinuation] = [:]

        func waitForAction(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> ActionResult {
            try await waitForPayload(
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister,
                makeContinuation: PendingResponseContinuation.action
            )
        }

        func waitForPong(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> PongPayload {
            try await waitForPayload(
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister,
                makeContinuation: PendingResponseContinuation.pong
            )
        }

        func waitForInterface(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> Interface {
            try await waitForPayload(
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister,
                makeContinuation: PendingResponseContinuation.interface
            )
        }

        func waitForScreen(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> ScreenPayload {
            try await waitForPayload(
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister,
                makeContinuation: PendingResponseContinuation.screen
            )
        }

        func waitForHeistExecution(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> HeistExecutionResult {
            try await waitForPayload(
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister,
                makeContinuation: PendingResponseContinuation.heistExecution
            )
        }

        private func waitForPayload<Response: Sendable>(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil,
            makeContinuation: @escaping @Sendable (PendingRequest<Response>) -> PendingResponseContinuation
        ) async throws -> Response {
            let owner = UUID()

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    guard pending[requestId] == nil else {
                        continuation.resume(throwing: PendingRequestTrackerError.duplicateRequestId(requestId))
                        return
                    }

                    let didResume = OSAllocatedUnfairLock(initialState: false)

                    let timeoutTask = Task {
                        guard await Task.cancellableSleep(for: .seconds(timeout)) else { return }
                        if let request = self.removePendingRequest(requestId: requestId, owner: owner) {
                            request.resumeFailure(FenceError.actionTimeout)
                        }
                    }

                    let pendingRequest = PendingRequest<Response>(owner: owner) { result in
                        let shouldResume = didResume.withLock { flag -> Bool in
                            guard !flag else { return false }
                            flag = true
                            return true
                        }
                        if shouldResume {
                            timeoutTask.cancel()
                            continuation.resume(with: result)
                        }
                    }
                    pending[requestId] = makeContinuation(pendingRequest)
                    afterRegister?()
                }
            } onCancel: {
                Task { @ButtonHeistActor [weak self] in
                    if let request = self?.removePendingRequest(requestId: requestId, owner: owner) {
                        request.resumeFailure(CancellationError())
                    }
                }
            }
        }

        @discardableResult
        func resolveTransientResponse(_ message: ServerMessage, requestId: String) -> Bool {
            switch message {
            case .pong(let payload):
                resolvePong(payload, requestId: requestId)
            case .interface(let payload):
                resolveInterface(payload, requestId: requestId)
            case .actionResult(let result):
                if case .heistExecution(let heistResult) = result.payload {
                    resolveHeistExecution(heistResult, requestId: requestId)
                } else {
                    resolveAction(result, requestId: requestId)
                }
            case .screen(let payload):
                resolveScreen(payload, requestId: requestId)
            case .error(let serverError):
                resolveTransientFailure(FenceError.serverError(serverError), requestId: requestId)
            default:
                return false
            }
            return true
        }

        func resolveTransientFailure(_ error: Error, requestId: String) {
            guard let request = pending.removeValue(forKey: requestId) else { return }
            request.resumeFailure(error)
        }

        func cancelAll(error: Error) {
            let requests = pending
            pending.removeAll()
            for (_, request) in requests {
                request.resumeFailure(error)
            }
        }

        private static func responseTypeMismatchError(
            expected: PendingResponseExpectation,
            actual: PendingResponseExpectation,
            requestId: String? = nil
        ) -> FenceError {
            let requestDescription = requestId.map { " for request \($0)" } ?? ""
            let message = "Protocol mismatch\(requestDescription): expected \(expected.responseName) response, " +
                "received \(actual.responseName) response."
            let details = FailureDetails(code: .protocolMismatch)
            return .connectionFailure(ConnectionFailure(
                message: message,
                failureCode: details.code,
                phase: details.phase,
                retryable: details.retryable,
                hint: details.hint
            ))
        }

        private func resolveAction(_ result: ActionResult, requestId: String) {
            guard let request = pending.removeValue(forKey: requestId) else { return }
            guard case .action(let pendingRequest) = request else {
                request.resumeFailure(Self.responseTypeMismatchError(
                    expected: request.expectation,
                    actual: .action,
                    requestId: requestId
                ))
                return
            }
            pendingRequest.callback(.success(result))
        }

        private func resolvePong(_ payload: PongPayload, requestId: String) {
            guard let request = pending.removeValue(forKey: requestId) else { return }
            guard case .pong(let pendingRequest) = request else {
                request.resumeFailure(Self.responseTypeMismatchError(
                    expected: request.expectation,
                    actual: .pong,
                    requestId: requestId
                ))
                return
            }
            pendingRequest.callback(.success(payload))
        }

        private func resolveInterface(_ interface: Interface, requestId: String) {
            guard let request = pending.removeValue(forKey: requestId) else { return }
            guard case .interface(let pendingRequest) = request else {
                request.resumeFailure(Self.responseTypeMismatchError(
                    expected: request.expectation,
                    actual: .interface,
                    requestId: requestId
                ))
                return
            }
            pendingRequest.callback(.success(interface))
        }

        private func resolveScreen(_ payload: ScreenPayload, requestId: String) {
            guard let request = pending.removeValue(forKey: requestId) else { return }
            guard case .screen(let pendingRequest) = request else {
                request.resumeFailure(Self.responseTypeMismatchError(
                    expected: request.expectation,
                    actual: .screen,
                    requestId: requestId
                ))
                return
            }
            pendingRequest.callback(.success(payload))
        }

        private func resolveHeistExecution(_ result: HeistExecutionResult, requestId: String) {
            guard let request = pending.removeValue(forKey: requestId) else { return }
            guard case .heistExecution(let pendingRequest) = request else {
                request.resumeFailure(Self.responseTypeMismatchError(
                    expected: request.expectation,
                    actual: .heistExecution,
                    requestId: requestId
                ))
                return
            }
            pendingRequest.callback(.success(result))
        }

        private func removePendingRequest(
            requestId: String,
            owner: UUID
        ) -> PendingResponseContinuation? {
            guard let request = pending[requestId], request.owner == owner else { return nil }
            pending.removeValue(forKey: requestId)
            return request
        }
    }
}
