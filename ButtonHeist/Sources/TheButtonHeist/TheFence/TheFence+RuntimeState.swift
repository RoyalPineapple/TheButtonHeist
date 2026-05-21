import Foundation
import os

import TheScore

private enum PendingRequestStore {
    case action(PendingRequestTracker<ActionResult>)
    case interface(PendingRequestTracker<Interface>)
    case screen(PendingRequestTracker<ScreenPayload>)
}

private struct RecordingPendingWait<Value: Sendable>: Sendable {
    let owner: UUID
    let callback: @Sendable (Result<Value, Error>) -> Void
}

extension TheFence {

    /// Owns TheHandoff-backed connection projection for session-state reads.
    struct SessionConnectionState {
        let handoff: TheHandoff

        @ButtonHeistActor
        var snapshot: SessionConnectionSnapshot {
            SessionConnectionSnapshot(
                connected: handoff.isConnected,
                phase: sessionConnectionPhase,
                device: sessionDevicePayload,
                lastFailure: sessionFailurePayload
            )
        }

        @ButtonHeistActor
        private var sessionConnectionPhase: SessionConnectionPhase {
            switch handoff.connectionPhase {
            case .disconnected:
                return .disconnected
            case .connecting:
                return .connecting
            case .connected:
                return .connected
            case .failed:
                return .failed
            }
        }

        @ButtonHeistActor
        private var sessionDevicePayload: SessionDevicePayload? {
            handoff.connectedDevice.map { device in
                SessionDevicePayload(
                    deviceName: handoff.displayName(for: device),
                    appName: device.appName,
                    connectionType: device.connectionType,
                    shortId: device.shortId
                )
            }
        }

        @ButtonHeistActor
        private var sessionFailurePayload: SessionFailurePayload? {
            handoff.connectionDiagnosticFailure.map { failure in
                SessionFailurePayload(
                    errorCode: failure.failureCode,
                    phase: failure.phase,
                    retryable: failure.retryable,
                    message: failure.errorDescription,
                    hint: failure.hint
                )
            }
        }
    }

    /// Owns retained accessibility captures plus the queued background traces.
    struct BackgroundAccessibilityState {
        private static let defaultPendingTraceLimit = 20

        private var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
        private let pendingTraceLimit: Int

        init(pendingTraceLimit: Int = Self.defaultPendingTraceLimit) {
            self.pendingTraceLimit = pendingTraceLimit
        }

        var pendingTraceCount: Int {
            history.pendingTraceCount
        }

        var latestRef: AccessibilityTrace.CaptureRef? {
            history.latestRef
        }

        mutating func reset() {
            history.reset()
            history.retention = .dropAfterDelivery
        }

        mutating func enqueue(_ trace: AccessibilityTrace) {
            history.enqueuePendingTrace(trace, limit: pendingTraceLimit)
        }

        mutating func drainTrace() -> AccessibilityTrace? {
            history.drainPendingTrace()
        }

        mutating func drainTraces() -> [AccessibilityTrace] {
            history.drainPendingTraces()
        }

        func pendingTraces(startingAt startIndex: Int = 0) -> [AccessibilityTrace.PendingTrace] {
            history.pendingTraces(startingAt: startIndex)
        }

        mutating func removePendingTrace(at index: Int) -> AccessibilityTrace.PendingTrace? {
            history.removePendingTrace(at: index)
        }

        @discardableResult
        mutating func append(interface: Interface) -> AccessibilityTrace.CaptureRef {
            history.append(interface: interface)
        }

        @discardableResult
        mutating func ingest(_ trace: AccessibilityTrace) -> AccessibilityTrace.Cursor? {
            history.ingest(trace)
        }

        func capture(ref: AccessibilityTrace.CaptureRef) -> AccessibilityTrace.Capture? {
            history.capture(ref: ref)
        }

        func elementLookup(captureRef: AccessibilityTrace.CaptureRef?) -> [HeistId: HeistElement] {
            history.elementLookup(captureRef: captureRef)
        }

        mutating func markDelivered(through ref: AccessibilityTrace.CaptureRef?) {
            history.markDelivered(through: ref)
        }

        mutating func beginRecordingRetention() {
            history.retention = .persistForSession
        }

        mutating func endRecordingRetention() {
            history.retention = .dropAfterDelivery
        }
    }

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

    // MARK: - Recording State

    @ButtonHeistActor
    final class RecordingWait<Value: Sendable> {
        private var pending: RecordingPendingWait<Value>?

        func wait(
            timeout: TimeInterval,
            afterRegister: (() -> Void)? = nil
        ) async throws -> Value {
            let owner = UUID()

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    guard pending == nil else {
                        continuation.resume(
                            throwing: FenceError.invalidRequest("Recording wait already registered")
                        )
                        return
                    }

                    let didResume = OSAllocatedUnfairLock(initialState: false)
                    let timeoutTask = Task {
                        guard await Task.cancellableSleep(for: .seconds(timeout)) else { return }
                        if let callback = self.removePending(owner: owner) {
                            callback(.failure(FenceError.actionTimeout))
                        }
                    }

                    pending = RecordingPendingWait(owner: owner) { result in
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
                    afterRegister?()
                }
            } onCancel: {
                Task { @ButtonHeistActor [weak self] in
                    if let callback = self?.removePending(owner: owner) {
                        callback(.failure(CancellationError()))
                    }
                }
            }
        }

        func resolve(_ result: Result<Value, Error>) {
            guard let pending else { return }
            self.pending = nil
            pending.callback(result)
        }

        func cancel(error: Error) {
            resolve(.failure(error))
        }

        private func removePending(owner: UUID) -> (@Sendable (Result<Value, Error>) -> Void)? {
            guard let pending, pending.owner == owner else { return nil }
            self.pending = nil
            return pending.callback
        }
    }

    enum RecordingLifecycle {
        case idle
        case starting(wait: RecordingWait<Void>)
        case recording
        case completing(wait: RecordingWait<RecordingPayload>, serverRecording: Bool)
    }

    struct RecordingCoordinator {
        private var lifecycle: RecordingLifecycle = .idle

        var snapshot: RecordingSnapshot {
            RecordingSnapshot(
                isRecording: isRecording,
                isWaitingForCompletion: isWaitingForCompletion
            )
        }

        var isRecording: Bool {
            switch lifecycle {
            case .recording:
                return true
            case .completing(_, let serverRecording):
                return serverRecording
            case .idle, .starting:
                return false
            }
        }

        private var isWaitingForCompletion: Bool {
            if case .completing = lifecycle {
                return true
            }
            return false
        }

        mutating func reset() {
            lifecycle = .idle
        }

        @ButtonHeistActor
        func cancelAll(error: Error) {
            switch lifecycle {
            case .starting(let wait):
                wait.cancel(error: error)
            case .completing(let wait, _):
                wait.cancel(error: error)
            case .idle, .recording:
                break
            }
        }

        mutating func beginStartWait() throws -> RecordingWait<Void> {
            guard case .idle = lifecycle else {
                throw startRecordingConflictError
            }
            let wait = RecordingWait<Void>()
            lifecycle = .starting(wait: wait)
            return wait
        }

        mutating func finishStartWait(_ wait: RecordingWait<Void>) {
            guard case .starting(let activeWait) = lifecycle, activeWait === wait else { return }
            lifecycle = .idle
        }

        mutating func beginCompletionWait() throws -> RecordingWait<RecordingPayload> {
            let wait = RecordingWait<RecordingPayload>()
            switch lifecycle {
            case .idle:
                lifecycle = .completing(wait: wait, serverRecording: false)
            case .recording:
                lifecycle = .completing(wait: wait, serverRecording: true)
            case .starting, .completing:
                throw FenceError.invalidRequest("stop_recording already waiting for completion")
            }
            return wait
        }

        mutating func finishCompletionWait(_ wait: RecordingWait<RecordingPayload>) {
            guard case .completing(let activeWait, _) = lifecycle, activeWait === wait else { return }
            lifecycle = .idle
        }

        @ButtonHeistActor
        func resolveActiveCompletion(_ result: Result<RecordingPayload, Error>) {
            guard case .completing(let wait, _) = lifecycle else { return }
            wait.resolve(result)
        }

        @ButtonHeistActor
        mutating func handleEvent(_ event: RecordingEvent) {
            switch event {
            case .started:
                if case .starting(let wait) = lifecycle {
                    lifecycle = .recording
                    wait.resolve(.success(()))
                } else if case .completing(let wait, _) = lifecycle {
                    lifecycle = .completing(wait: wait, serverRecording: true)
                } else {
                    lifecycle = .recording
                }
            case .stopped:
                if case .completing(let wait, _) = lifecycle {
                    lifecycle = .completing(wait: wait, serverRecording: false)
                } else {
                    lifecycle = .idle
                }
            case .completed(let payload):
                let wait: RecordingWait<RecordingPayload>?
                if case .completing(let activeWait, _) = lifecycle {
                    wait = activeWait
                } else {
                    wait = nil
                }
                lifecycle = .idle
                wait?.resolve(.success(payload))
            case .failed(let message):
                let error = FenceError.actionFailed("Recording failed: \(message)")
                switch lifecycle {
                case .starting(let wait):
                    lifecycle = .idle
                    wait.resolve(.failure(error))
                case .completing(let wait, _):
                    lifecycle = .idle
                    wait.resolve(.failure(error))
                case .idle, .recording:
                    lifecycle = .idle
                }
            }
        }

        private var startRecordingConflictError: FenceError {
            switch lifecycle {
            case .idle:
                return .invalidRequest("Recording state changed while starting")
            case .starting:
                return .invalidRequest("start_recording already waiting for acknowledgement")
            case .recording:
                return .invalidRequest("Recording already in progress — use stop_recording first")
            case .completing:
                return .invalidRequest("stop_recording already waiting for completion")
            }
        }
    }

    // MARK: - Command Execution State

    /// Last completed action, if any. Session display state derives from the
    /// active case instead of sibling cached projections.
    enum LastAction {
        case none
        case completed(result: ActionResult, latencyMs: Int)

        var sessionPayload: SessionLastActionPayload? {
            guard case .completed(let result, let latencyMs) = self else { return nil }
            return SessionLastActionPayload(
                method: result.method,
                success: result.success,
                message: result.message,
                latencyMs: latencyMs
            )
        }

        var latencyMsForReplacement: Int {
            guard case .completed(_, let latencyMs) = self else { return 0 }
            return latencyMs
        }
    }

    /// Owns command-execution state derived from dispatched action responses.
    struct CommandExecutionState {
        private(set) var lastAction: LastAction = .none

        mutating func noteDispatchedResponse(_ response: FenceResponse, latencyMs: Int) {
            guard let result = response.actionResult else { return }
            lastAction = .completed(result: result, latencyMs: latencyMs)
        }

        mutating func completeAction(_ result: ActionResult) {
            lastAction = .completed(result: result, latencyMs: lastAction.latencyMsForReplacement)
        }

        mutating func reset() {
            lastAction = .none
        }
    }
}
