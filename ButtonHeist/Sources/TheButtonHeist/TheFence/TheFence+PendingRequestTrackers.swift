import Foundation

import ButtonHeistSupport
import TheScore

extension TheFence {

    // MARK: - Pending Request Tracking

    enum PendingRequestError: Error, Equatable, LocalizedError {
        case duplicateRequestId(String)

        var errorDescription: String? {
            switch self {
            case .duplicateRequestId(let requestId):
                return "Request ID '\(requestId)' already has a pending waiter"
            }
        }
    }

    fileprivate enum PendingResponseKind: Sendable {
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

        static func responseTypeMismatchError(
            expected: PendingResponseKind,
            actual: PendingResponseKind,
            requestId: String
        ) -> FenceError {
            let message = "Protocol mismatch for request \(requestId): expected \(expected.responseName) response, " +
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
    }

    fileprivate enum PendingResponsePayload: Sendable {
        case action(ActionResult)
        case pong(PongPayload)
        case interface(Interface)
        case screen(ScreenPayload)
        case heistExecution(HeistExecutionResult)

        var kind: PendingResponseKind {
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

        static func result(from message: ServerMessage) -> Result<PendingResponsePayload, Error>? {
            switch message {
            case .pong(let payload):
                return .success(.pong(payload))
            case .interface(let payload):
                return .success(.interface(payload))
            case .actionResult(let result):
                if case .heistExecution(let heistResult) = result.payload {
                    return .success(.heistExecution(heistResult))
                }
                return .success(.action(result))
            case .screen(let payload):
                return .success(.screen(payload))
            case .error(let serverError):
                return .failure(FenceError.serverError(serverError))
            default:
                return nil
            }
        }
    }

    fileprivate struct PendingResponseExpectation<Response: Sendable>: Sendable {
        let kind: PendingResponseKind
        let extract: @Sendable (PendingResponsePayload) -> Response?

        func decode(_ result: Result<PendingResponsePayload, Error>, requestId: String) -> Result<Response, Error> {
            switch result {
            case .success(let payload):
                guard let response = extract(payload) else {
                    return .failure(PendingResponseKind.responseTypeMismatchError(
                        expected: kind,
                        actual: payload.kind,
                        requestId: requestId
                    ))
                }
                return .success(response)
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    fileprivate struct PendingRequest: Sendable {
        let owner: UUID
        let expectedKind: PendingResponseKind
        let response: OneShotContinuation<Result<PendingResponsePayload, Error>>
        let timeoutTask: Task<Void, Never>

        func resume(_ result: Result<PendingResponsePayload, Error>, requestId: String) {
            timeoutTask.cancel()

            switch result {
            case .success(let payload) where payload.kind != expectedKind:
                response.resume(returning: .failure(PendingResponseKind.responseTypeMismatchError(
                    expected: expectedKind,
                    actual: payload.kind,
                    requestId: requestId
                )))
            default:
                response.resume(returning: result)
            }
        }
    }

    @ButtonHeistActor
    final class PendingRequestRegistry {
        private var pending: [String: PendingRequest] = [:]

        func waitForAction(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> ActionResult {
            try await waitForPayload(
                .action,
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister
            )
        }

        func waitForPong(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> PongPayload {
            try await waitForPayload(
                .pong,
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister
            )
        }

        func waitForInterface(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> Interface {
            try await waitForPayload(
                .interface,
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister
            )
        }

        func waitForScreen(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> ScreenPayload {
            try await waitForPayload(
                .screen,
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister
            )
        }

        func waitForHeistExecution(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> HeistExecutionResult {
            try await waitForPayload(
                .heistExecution,
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister
            )
        }

        private func waitForPayload<Response: Sendable>(
            _ expectation: PendingResponseExpectation<Response>,
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> Response {
            let owner = UUID()

            return try await withTaskCancellationHandler {
                let result: Result<PendingResponsePayload, Error> = await withCheckedContinuation { continuation in
                    if Task.isCancelled {
                        continuation.resume(returning: .failure(CancellationError()))
                        return
                    }

                    guard pending[requestId] == nil else {
                        continuation.resume(returning: .failure(PendingRequestError.duplicateRequestId(requestId)))
                        return
                    }

                    let response = OneShotContinuation<Result<PendingResponsePayload, Error>>()
                    precondition(response.register(continuation), "New pending request response was resumed before registration")

                    let timeoutTask = Task {
                        guard await Task.cancellableSleep(for: .seconds(timeout)) else { return }
                        if let request = self.removePendingRequest(requestId: requestId, owner: owner) {
                            request.resume(.failure(FenceError.actionTimeout), requestId: requestId)
                        }
                    }

                    pending[requestId] = PendingRequest(
                        owner: owner,
                        expectedKind: expectation.kind,
                        response: response,
                        timeoutTask: timeoutTask
                    )
                    afterRegister?()
                }
                return try expectation.decode(result, requestId: requestId).get()
            } onCancel: {
                Task { @ButtonHeistActor [weak self] in
                    if let request = self?.removePendingRequest(requestId: requestId, owner: owner) {
                        request.resume(.failure(CancellationError()), requestId: requestId)
                    }
                }
            }
        }

        @discardableResult
        func resolveTransientResponse(_ message: ServerMessage, requestId: String) -> Bool {
            guard let result = PendingResponsePayload.result(from: message) else { return false }
            resolveTransientResult(result, requestId: requestId)
            return true
        }

        func resolveTransientFailure(_ error: Error, requestId: String) {
            resolveTransientResult(.failure(error), requestId: requestId)
        }

        private func resolveTransientResult(_ result: Result<PendingResponsePayload, Error>, requestId: String) {
            guard let request = pending.removeValue(forKey: requestId) else { return }
            request.resume(result, requestId: requestId)
        }

        func cancelAll(error: Error) {
            let requests = pending
            pending.removeAll()
            for (requestId, request) in requests {
                request.resume(.failure(error), requestId: requestId)
            }
        }

        private func removePendingRequest(
            requestId: String,
            owner: UUID
        ) -> PendingRequest? {
            guard let request = pending[requestId], request.owner == owner else { return nil }
            pending.removeValue(forKey: requestId)
            return request
        }
    }
}

private extension TheFence.PendingResponseExpectation where Response == ActionResult {
    static var action: Self {
        Self(kind: .action) { payload in
            guard case .action(let result) = payload else { return nil }
            return result
        }
    }
}

private extension TheFence.PendingResponseExpectation where Response == PongPayload {
    static var pong: Self {
        Self(kind: .pong) { payload in
            guard case .pong(let result) = payload else { return nil }
            return result
        }
    }
}

private extension TheFence.PendingResponseExpectation where Response == Interface {
    static var interface: Self {
        Self(kind: .interface) { payload in
            guard case .interface(let result) = payload else { return nil }
            return result
        }
    }
}

private extension TheFence.PendingResponseExpectation where Response == ScreenPayload {
    static var screen: Self {
        Self(kind: .screen) { payload in
            guard case .screen(let result) = payload else { return nil }
            return result
        }
    }
}

private extension TheFence.PendingResponseExpectation where Response == HeistExecutionResult {
    static var heistExecution: Self {
        Self(kind: .heistExecution) { payload in
            guard case .heistExecution(let result) = payload else { return nil }
            return result
        }
    }
}
