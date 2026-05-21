import Foundation

import TheScore

private enum PendingRequestStore {
    case action(PendingRequestTracker<ActionResult>)
    case interface(PendingRequestTracker<Interface>)
    case screen(PendingRequestTracker<ScreenPayload>)
}

extension TheFence {

    // MARK: - Pending Request Tracking

    struct PendingRequestTrackers {
        private let storage: [PendingRequestStore] = [
            .action(PendingRequestTracker<ActionResult>()),
            .interface(PendingRequestTracker<Interface>()),
            .screen(PendingRequestTracker<ScreenPayload>()),
        ]

        @ButtonHeistActor
        func waitForAction(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> ActionResult {
            guard let tracker = actionTracker else { throw unavailableWaiterError }
            return try await tracker.wait(
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
            guard let tracker = interfaceTracker else { throw unavailableWaiterError }
            return try await tracker.wait(
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
            guard let tracker = screenTracker else { throw unavailableWaiterError }
            return try await tracker.wait(
                requestId: requestId,
                timeout: timeout,
                afterRegister: afterRegister
            )
        }

        @ButtonHeistActor
        func resolveAction(requestId: String, result: Result<ActionResult, Error>) {
            actionTracker?.resolve(requestId: requestId, result: result)
        }

        @ButtonHeistActor
        func resolveInterface(requestId: String, result: Result<Interface, Error>) {
            interfaceTracker?.resolve(requestId: requestId, result: result)
        }

        @ButtonHeistActor
        func resolveScreen(requestId: String, result: Result<ScreenPayload, Error>) {
            screenTracker?.resolve(requestId: requestId, result: result)
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
            actionTracker?.cancelAll(error: error)
            interfaceTracker?.cancelAll(error: error)
            screenTracker?.cancelAll(error: error)
        }

        private var actionTracker: PendingRequestTracker<ActionResult>? {
            storage.compactMap {
                if case .action(let tracker) = $0 { return tracker }
                return nil
            }.first
        }

        private var interfaceTracker: PendingRequestTracker<Interface>? {
            storage.compactMap {
                if case .interface(let tracker) = $0 { return tracker }
                return nil
            }.first
        }

        private var screenTracker: PendingRequestTracker<ScreenPayload>? {
            storage.compactMap {
                if case .screen(let tracker) = $0 { return tracker }
                return nil
            }.first
        }

        private var unavailableWaiterError: FenceError {
            .actionFailed("Internal pending request waiter unavailable")
        }
    }
}
