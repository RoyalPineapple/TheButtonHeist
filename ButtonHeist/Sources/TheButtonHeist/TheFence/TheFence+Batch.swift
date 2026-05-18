import Foundation

import TheScore

extension TheFence {

    // MARK: - Batch Execution and Session State

    enum BatchPolicy: String, CaseIterable {
        case stopOnError = "stop_on_error"
        case continueOnError = "continue_on_error"
    }

    func handleRunBatch(_ request: RunBatchRequest) async throws -> FenceResponse {
        var outcomes: [BatchStepOutcome] = []
        let batchStart = CFAbsoluteTimeGetCurrent()

        stepLoop: for step in request.steps {
            switch step {
            case .decoded(let parsedRequest):
                let command = parsedRequest.command
                do {
                    let response = try await execute(parsed: parsedRequest)
                    let stopsBatch = response.isFailure && request.policy == .stopOnError
                    outcomes.append(BatchStepOutcome(
                        command: command.rawValue,
                        response: response,
                        stopsBatch: stopsBatch
                    ))

                    if stopsBatch {
                        break stepLoop
                    }
                } catch {
                    let failureDetails = (error as? FenceError)?.failureDetails
                    outcomes.append(BatchStepOutcome(
                        command: command.rawValue,
                        response: .error(error.localizedDescription),
                        diagnosticDetails: failureDetails,
                        stopsBatch: request.policy == .stopOnError
                    ))
                    if request.policy == .stopOnError {
                        break stepLoop
                    }
                }

            case .invalid(let commandName, let failure):
                outcomes.append(BatchStepOutcome(
                    command: commandName,
                    response: failure.resultResponse,
                    diagnosticDetails: failure.details,
                    stopsBatch: request.policy == .stopOnError
                ))
                if request.policy == .stopOnError {
                    break stepLoop
                }
            }
        }

        if let failedIndex = outcomes.stoppedFailedIndex, request.policy == .stopOnError {
            outcomes.append(contentsOf: skippedStepOutcomes(
                steps: request.steps,
                afterFailedIndex: failedIndex
            ))
        }

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - batchStart) * 1000)
        let accessibilityTrace = Self.batchAccessibilityTrace(outcomes: outcomes)
        return .batch(
            outcomes: outcomes,
            totalTimingMs: totalMs,
            accessibilityTrace: accessibilityTrace
        )
    }

    private static func batchAccessibilityTrace(
        outcomes: [BatchStepOutcome]
    ) -> AccessibilityTrace? {
        let actionOutcomeCount = outcomes.count(where: \.hasActionResult)
        let stepAccessibilityTraces = outcomes.compactMap(\.accessibilityTrace)
        guard actionOutcomeCount > 0,
              stepAccessibilityTraces.count == actionOutcomeCount
        else { return nil }
        return AccessibilityTrace.captureEndpointTrace(from: stepAccessibilityTraces)
    }

    private func skippedStepOutcomes(
        steps: [RunBatchStepRequest], afterFailedIndex failedIndex: Int
    ) -> [BatchStepOutcome] {
        steps.dropFirst(failedIndex + 1).map { step in
            BatchStepOutcome.skipped(command: step.commandName, afterFailedIndex: failedIndex)
        }
    }

    static func batchNextCommand(from details: FailureDetails?) -> String? {
        guard details?.errorCode == FenceRequestErrorCode.missingTarget else { return nil }
        return details?.hint
    }

    // MARK: - Session State

    func currentSessionState() -> SessionStatePayload {
        let connected = handoff.isConnected
        let devicePayload = handoff.connectedDevice.map { device in
            SessionDevicePayload(
                deviceName: handoff.displayName(for: device),
                appName: device.appName,
                connectionType: device.connectionType,
                shortId: device.shortId
            )
        }
        let failurePayload = handoff.connectionDiagnosticFailure.map { failure in
            SessionFailurePayload(
                errorCode: failure.failureCode,
                phase: failure.phase,
                retryable: failure.retryable,
                message: failure.errorDescription,
                hint: failure.hint
            )
        }
        let lastActionPayload = lastActionResult.map { last in
            SessionLastActionPayload(
                method: last.method,
                success: last.success,
                message: last.message,
                latencyMs: lastLatencyMs
            )
        }
        return SessionStatePayload(
            connected: connected,
            phase: currentSessionConnectionPhase(),
            device: devicePayload,
            isRecording: isRecording,
            actionTimeoutSeconds: Timeouts.actionSeconds,
            longActionTimeoutSeconds: Timeouts.longActionSeconds,
            lastFailure: failurePayload,
            lastAction: lastActionPayload
        )
    }

    private func currentSessionConnectionPhase() -> SessionConnectionPhase {
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
}
