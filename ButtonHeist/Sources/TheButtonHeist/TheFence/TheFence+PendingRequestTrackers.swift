import Foundation

import TheScore

extension TheFence {

    // MARK: - Pending Request Tracking

    struct PendingRequestTrackers {
        private let actionTracker = PendingRequestTracker<ActionResult>()
        private let interfaceTracker = PendingRequestTracker<Interface>()
        private let screenTracker = PendingRequestTracker<ScreenPayload>()

        @ButtonHeistActor
        func waitForAction(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> ActionResult {
            try await actionTracker.wait(
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister
            )
        }

        @ButtonHeistActor
        func waitForInterface(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> Interface {
            try await interfaceTracker.wait(
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister
            )
        }

        @ButtonHeistActor
        func waitForScreen(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> ScreenPayload {
            try await screenTracker.wait(
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister
            )
        }

        @ButtonHeistActor
        func resolveAction(requestId: String, result: Result<ActionResult, Error>) {
            actionTracker.resolve(requestId: requestId, result: result)
        }

        @ButtonHeistActor
        func resolveInterface(requestId: String, result: Result<Interface, Error>) {
            interfaceTracker.resolve(requestId: requestId, result: result)
        }

        @ButtonHeistActor
        func resolveScreen(requestId: String, result: Result<ScreenPayload, Error>) {
            screenTracker.resolve(requestId: requestId, result: result)
        }

        @ButtonHeistActor
        func resolveTransientResponse(_ message: ServerMessage, requestId: String) -> Bool {
            switch message {
            case .interface(let payload):
                resolveInterface(requestId: requestId, result: .success(payload))
            case .actionResult(let result):
                resolveAction(requestId: requestId, result: .success(result))
            case .screen(let payload):
                resolveScreen(requestId: requestId, result: .success(payload))
            case .error(let serverError):
                resolveTransientFailure(FenceError.serverError(serverError), requestId: requestId)
            default:
                return false
            }
            return true
        }

        @ButtonHeistActor
        func resolveTransientFailure(_ error: Error, requestId: String) {
            resolveAction(requestId: requestId, result: .failure(error))
            resolveInterface(requestId: requestId, result: .failure(error))
            resolveScreen(requestId: requestId, result: .failure(error))
        }

        @ButtonHeistActor
        func cancelAll(error: Error) {
            actionTracker.cancelAll(error: error)
            interfaceTracker.cancelAll(error: error)
            screenTracker.cancelAll(error: error)
        }
    }
}
