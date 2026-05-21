import Foundation

import TheScore

private enum PendingRequestStore {
    case action(PendingRequestTracker<ActionResult>)
    case interface(PendingRequestTracker<Interface>)
    case screen(PendingRequestTracker<ScreenPayload>)
}

private enum RecordingWaiter {
    case start(PendingRequestTracker<Bool>)
    case completion(PendingRequestTracker<RecordingPayload>)
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

    enum RecordingLifecycle {
        case idle
        case starting(waitId: String)
        case recording
        case completing(waitId: String, serverRecording: Bool)
    }

    struct RecordingCoordinator {
        private var lifecycle: RecordingLifecycle = .idle
        private let waiters: [RecordingWaiter] = [
            .start(PendingRequestTracker<Bool>()),
            .completion(PendingRequestTracker<RecordingPayload>()),
        ]

        var snapshot: RecordingSnapshot {
            RecordingSnapshot(
                isRecording: isRecording,
                isWaitingForCompletion: completionWaitId != nil
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

        private var startWaitId: String? {
            if case .starting(let waitId) = lifecycle {
                return waitId
            }
            return nil
        }

        private var completionWaitId: String? {
            if case .completing(let waitId, _) = lifecycle {
                return waitId
            }
            return nil
        }

        mutating func reset() {
            lifecycle = .idle
        }

        @ButtonHeistActor
        func cancelAll(error: Error) {
            startWaiter?.cancelAll(error: error)
            completionWaiter?.cancelAll(error: error)
        }

        mutating func beginStartWait(syntheticId: String) throws {
            guard case .idle = lifecycle else {
                throw startRecordingConflictError
            }
            lifecycle = .starting(waitId: syntheticId)
        }

        mutating func finishStartWait(syntheticId: String) {
            guard case .starting(let waitId) = lifecycle, waitId == syntheticId else { return }
            lifecycle = .idle
        }

        @ButtonHeistActor
        func waitForStart(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)?
        ) async throws {
            guard let waiter = startWaiter else { throw unavailableWaiterError }
            _ = try await waiter.wait(requestId: requestId, timeout: timeout, afterRegister: afterRegister)
        }

        @ButtonHeistActor
        func resolveStartWait(_ result: Result<Bool, Error>) {
            guard let syntheticId = startWaitId else { return }
            startWaiter?.resolve(requestId: syntheticId, result: result)
        }

        @ButtonHeistActor
        func resolveStartWait(requestId: String, result: Result<Bool, Error>) {
            startWaiter?.resolve(requestId: requestId, result: result)
        }

        mutating func beginCompletionWait(syntheticId: String) throws {
            switch lifecycle {
            case .idle:
                lifecycle = .completing(waitId: syntheticId, serverRecording: false)
            case .recording:
                lifecycle = .completing(waitId: syntheticId, serverRecording: true)
            case .starting, .completing:
                throw FenceError.invalidRequest("stop_recording already waiting for completion")
            }
        }

        mutating func finishCompletionWait(syntheticId: String) {
            guard case .completing(let waitId, _) = lifecycle, waitId == syntheticId else { return }
            lifecycle = .idle
        }

        @ButtonHeistActor
        func waitForCompletion(
            requestId: String,
            timeout: TimeInterval,
            afterRegister: (() -> Void)?
        ) async throws -> RecordingPayload {
            guard let waiter = completionWaiter else { throw unavailableWaiterError }
            return try await waiter.wait(requestId: requestId, timeout: timeout, afterRegister: afterRegister)
        }

        @ButtonHeistActor
        func resolveCompletionWait(_ result: Result<RecordingPayload, Error>) {
            guard let syntheticId = completionWaitId else { return }
            completionWaiter?.resolve(requestId: syntheticId, result: result)
        }

        @ButtonHeistActor
        mutating func handleEvent(_ event: RecordingEvent) {
            switch event {
            case .started:
                if let syntheticId = startWaitId {
                    lifecycle = .recording
                    startWaiter?.resolve(requestId: syntheticId, result: .success(true))
                } else if case .completing(let waitId, _) = lifecycle {
                    lifecycle = .completing(waitId: waitId, serverRecording: true)
                } else {
                    lifecycle = .recording
                }
            case .stopped:
                if case .completing(let waitId, _) = lifecycle {
                    lifecycle = .completing(waitId: waitId, serverRecording: false)
                } else {
                    lifecycle = .idle
                }
            case .completed(let payload):
                let waitId = completionWaitId
                lifecycle = .idle
                if let waitId {
                    completionWaiter?.resolve(requestId: waitId, result: .success(payload))
                }
            case .failed(let message):
                let error = FenceError.actionFailed("Recording failed: \(message)")
                switch lifecycle {
                case .starting(let waitId):
                    lifecycle = .idle
                    startWaiter?.resolve(requestId: waitId, result: .failure(error))
                case .completing(let waitId, _):
                    lifecycle = .idle
                    completionWaiter?.resolve(requestId: waitId, result: .failure(error))
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

        private var startWaiter: PendingRequestTracker<Bool>? {
            waiters.compactMap {
                if case .start(let tracker) = $0 { return tracker }
                return nil
            }.first
        }

        private var completionWaiter: PendingRequestTracker<RecordingPayload>? {
            waiters.compactMap {
                if case .completion(let tracker) = $0 { return tracker }
                return nil
            }.first
        }

        private var unavailableWaiterError: FenceError {
            .actionFailed("Internal recording waiter unavailable")
        }
    }

    // MARK: - Command Execution State

    /// Two-phase action history: `.unrun` before any action has completed,
    /// `.completed` once one has. Display state derives from the active case.
    enum LastActionHistory {
        case unrun
        case completed(ActionResult, latencyMs: Int)

        var result: ActionResult? {
            if case .completed(let result, _) = self { return result }
            return nil
        }

        var latencyMs: Int {
            if case .completed(_, let latencyMs) = self { return latencyMs }
            return 0
        }
    }

    /// Owns command-execution state derived from dispatched action responses.
    struct CommandExecutionState {
        private(set) var lastActionHistory: LastActionHistory = .unrun

        var snapshot: CommandExecutionSnapshot {
            CommandExecutionSnapshot(lastAction: lastActionPayload)
        }

        var lastActionResult: ActionResult? {
            lastActionHistory.result
        }

        var lastActionPayload: SessionLastActionPayload? {
            lastActionResult.map { last in
                SessionLastActionPayload(
                    method: last.method,
                    success: last.success,
                    message: last.message,
                    latencyMs: lastLatencyMs
                )
            }
        }

        var lastLatencyMs: Int {
            lastActionHistory.latencyMs
        }

        mutating func noteDispatchedResponse(_ response: FenceResponse, latencyMs: Int) {
            guard let result = response.actionResult else { return }
            lastActionHistory = .completed(result, latencyMs: latencyMs)
        }

        mutating func completeAction(_ result: ActionResult) {
            let latencyMs = lastActionHistory.latencyMs
            lastActionHistory = .completed(result, latencyMs: latencyMs)
        }

        mutating func reset() {
            lastActionHistory = .unrun
        }
    }
}
