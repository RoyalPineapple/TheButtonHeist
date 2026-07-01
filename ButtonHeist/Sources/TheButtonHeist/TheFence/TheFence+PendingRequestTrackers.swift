import Foundation
import os

import TheScore

extension TheFence {

    // MARK: - Pending Request Tracking

    enum PendingResponseExpectation: Sendable, Equatable {
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

    enum PendingResponse: Sendable {
        case action(ActionResult)
        case pong(PongPayload)
        case interface(Interface)
        case screen(ScreenPayload)
        case heistExecution(HeistExecutionResult)

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
    }

    @ButtonHeistActor
    final class PendingRequestTrackers {
        private struct PendingRequest: Sendable {
            let owner: UUID
            let callback: @Sendable (Result<PendingResponse, Error>) -> Void
        }

        private enum PendingResponseContinuation: Sendable {
            case action(PendingRequest)
            case pong(PendingRequest)
            case interface(PendingRequest)
            case screen(PendingRequest)
            case heistExecution(PendingRequest)

            init(expectation: PendingResponseExpectation, request: PendingRequest) {
                switch expectation {
                case .action:
                    self = .action(request)
                case .pong:
                    self = .pong(request)
                case .interface:
                    self = .interface(request)
                case .screen:
                    self = .screen(request)
                case .heistExecution:
                    self = .heistExecution(request)
                }
            }

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
                request.owner
            }

            func resumeSuccess(_ response: PendingResponse) {
                request.callback(.success(response))
            }

            func resumeFailure(_ error: Error) {
                request.callback(.failure(error))
            }

            private var request: PendingRequest {
                switch self {
                case .action(let request),
                     .pong(let request),
                     .interface(let request),
                     .screen(let request),
                     .heistExecution(let request):
                    return request
                }
            }
        }

        private var pending: [String: PendingResponseContinuation] = [:]

        func waitForAction(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> ActionResult {
            let response = try await waitForResponse(
                requestId: requestId,
                expecting: .action,
                timeout: timeout,
                afterRegister: afterRegister
            )
            guard case .action(let result) = response else {
                throw Self.responseTypeMismatchError(expected: .action, actual: response.expectation)
            }
            return result
        }

        func waitForPong(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> PongPayload {
            let response = try await waitForResponse(
                requestId: requestId,
                expecting: .pong,
                timeout: timeout,
                afterRegister: afterRegister
            )
            guard case .pong(let payload) = response else {
                throw Self.responseTypeMismatchError(expected: .pong, actual: response.expectation)
            }
            return payload
        }

        func waitForInterface(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> Interface {
            let response = try await waitForResponse(
                requestId: requestId,
                expecting: .interface,
                timeout: timeout,
                afterRegister: afterRegister
            )
            guard case .interface(let interface) = response else {
                throw Self.responseTypeMismatchError(expected: .interface, actual: response.expectation)
            }
            return interface
        }

        func waitForScreen(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> ScreenPayload {
            let response = try await waitForResponse(
                requestId: requestId,
                expecting: .screen,
                timeout: timeout,
                afterRegister: afterRegister
            )
            guard case .screen(let payload) = response else {
                throw Self.responseTypeMismatchError(expected: .screen, actual: response.expectation)
            }
            return payload
        }

        func waitForHeistExecution(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> HeistExecutionResult {
            let response = try await waitForResponse(
                requestId: requestId,
                expecting: .heistExecution,
                timeout: timeout,
                afterRegister: afterRegister
            )
            guard case .heistExecution(let result) = response else {
                throw Self.responseTypeMismatchError(expected: .heistExecution, actual: response.expectation)
            }
            return result
        }

        func waitForResponse(
            requestId: String,
            expecting expectation: PendingResponseExpectation,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> PendingResponse {
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

                    let pendingRequest = PendingRequest(owner: owner) { result in
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
                    pending[requestId] = PendingResponseContinuation(
                        expectation: expectation,
                        request: pendingRequest
                    )
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
                resolveResponse(.pong(payload), requestId: requestId)
            case .interface(let payload):
                resolveResponse(.interface(payload), requestId: requestId)
            case .actionResult(let result):
                if case .heistExecution(let heistResult) = result.payload {
                    resolveResponse(.heistExecution(heistResult), requestId: requestId)
                } else {
                    resolveResponse(.action(result), requestId: requestId)
                }
            case .screen(let payload):
                resolveResponse(.screen(payload), requestId: requestId)
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

        static func responseTypeMismatchError(
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

        private func resolveResponse(_ response: PendingResponse, requestId: String) {
            guard let request = pending.removeValue(forKey: requestId) else { return }
            guard request.expectation == response.expectation else {
                request.resumeFailure(Self.responseTypeMismatchError(
                    expected: request.expectation,
                    actual: response.expectation,
                    requestId: requestId
                ))
                return
            }
            request.resumeSuccess(response)
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
