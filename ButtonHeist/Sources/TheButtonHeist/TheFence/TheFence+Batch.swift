import Foundation

import TheScore

extension TheFence {

    // MARK: - Batch Execution and Session State

    enum BatchPolicy: String, CaseIterable {
        case stopOnError = "stop_on_error"
        case continueOnError = "continue_on_error"
    }

    func handleRunBatch(_ request: RunBatchRequest) async throws -> FenceResponse {
        var results: [[String: Any]] = []
        var stepSummaries: [BatchStepSummary] = []
        var failedIndex: Int?
        var expectationsMet = 0
        var expectationsChecked = 0
        let batchStart = CFAbsoluteTimeGetCurrent()

        for (index, step) in request.steps.enumerated() {
            let originalCommandName = step["command"] as? String ?? "?"
            var normalizedCommand: Command?
            do {
                let operation = try Self.normalizedBatchStep(step, index: index)
                let command = operation.command
                normalizedCommand = command
                let response = try await execute(request: operation.requestDictionary)
                results.append(response.jsonDict() ?? ["status": "ok"])

                let outcome = stepOutcome(response: response)

                // Count explicit tier expectations only — delivery failures have
                // expectation.expectation == nil and should not inflate the count
                if outcome.expectationCounted {
                    expectationsChecked += 1
                    if outcome.expectationMet == true { expectationsMet += 1 }
                }

                stepSummaries.append(makeStepSummary(
                    command: command, response: response,
                    expectationMet: outcome.expectationCounted ? outcome.expectationMet : nil
                ))

                if outcome.isFailed, request.policy == .stopOnError {
                    failedIndex = index
                    break
                }
            } catch {
                let errorDict: [String: Any] = [
                    "status": "error",
                    "message": error.localizedDescription,
                ]
                let failureDetails = (error as? FenceError)?.failureDetails
                results.append(errorDict)
                stepSummaries.append(BatchStepSummary(
                    command: normalizedCommand?.rawValue ?? originalCommandName,
                    deltaKind: nil,
                    screenName: nil,
                    screenId: nil,
                    expectationMet: nil, elementCount: nil, error: error.localizedDescription,
                    errorCode: failureDetails?.errorCode,
                    phase: failureDetails?.phase.rawValue,
                    nextCommand: Self.batchNextCommand(from: failureDetails)
                ))
                if request.policy == .stopOnError {
                    failedIndex = index
                    break
                }
            }
        }

        if let failedIndex, request.policy == .stopOnError {
            stepSummaries.append(contentsOf: skippedStepSummaries(
                steps: request.steps,
                afterFailedIndex: failedIndex
            ))
        }

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - batchStart) * 1000)
        return .batch(
            results: results,
            completedSteps: results.count,
            failedIndex: failedIndex,
            totalTimingMs: totalMs,
            expectationsChecked: expectationsChecked,
            expectationsMet: expectationsMet,
            stepSummaries: stepSummaries
        )
    }

    private static func normalizedBatchStep(
        _ step: [String: Any],
        index: Int
    ) throws -> NormalizedOperation {
        switch FenceOperationCatalog.normalizeBatchStep(step) {
        case .success(let operation):
            return operation
        case .failure(let error):
            throw FenceError.invalidRequest("run_batch step \(index): \(error.message)")
        }
    }

    private func skippedStepSummaries(
        steps: [[String: Any]], afterFailedIndex failedIndex: Int
    ) -> [BatchStepSummary] {
        steps.dropFirst(failedIndex + 1).map { step in
            let command = switch FenceOperationCatalog.normalizeBatchStep(step) {
            case .success(let operation):
                operation.command.rawValue
            case .failure:
                step["command"] as? String ?? "?"
            }
            return BatchStepSummary(
                command: command,
                deltaKind: nil,
                screenName: nil,
                screenId: nil,
                expectationMet: nil,
                elementCount: nil,
                error: "skipped: stop_on_error stopped batch after step \(failedIndex)"
            )
        }
    }

    // MARK: - Step Outcome

    private struct StepOutcome {
        let isFailed: Bool
        /// Whether this step carried an explicit expectation that counts
        /// toward the batch's expectations-met/checked totals.
        let expectationCounted: Bool
        /// Whether the explicit expectation was met. Only meaningful when
        /// `expectationCounted` is true.
        let expectationMet: Bool?
    }

    private func stepOutcome(response: FenceResponse) -> StepOutcome {
        switch response {
        case .action(let actionResult, let expectation):
            let result = expectation
            let counted = result?.expectation != nil
            let met = counted ? result?.met : nil
            let failed = !actionResult.success || (result.map { !$0.met } ?? false)
            return StepOutcome(
                isFailed: failed,
                expectationCounted: counted,
                expectationMet: met
            )
        case .error:
            return StepOutcome(
                isFailed: true,
                expectationCounted: false,
                expectationMet: nil
            )
        default:
            return StepOutcome(
                isFailed: false,
                expectationCounted: false,
                expectationMet: nil
            )
        }
    }

    // MARK: - Step Summary

    private func makeStepSummary(
        command: Command, response: FenceResponse, expectationMet: Bool?
    ) -> BatchStepSummary {
        let commandName = command.rawValue
        switch response {
        case .action(let result, _):
            return BatchStepSummary(
                command: commandName,
                deltaKind: result.accessibilityDelta?.kindRawValue,
                screenName: result.screenName,
                screenId: result.screenId,
                expectationMet: expectationMet,
                elementCount: nil,
                error: result.success ? nil : result.message
            )
        case .interface(let iface, _, _, _):
            return BatchStepSummary(
                command: commandName, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: iface.elements.count, error: nil
            )
        case .error(let message, let details):
            return BatchStepSummary(
                command: commandName, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: nil, error: message,
                errorCode: details?.errorCode,
                phase: details?.phase.rawValue,
                nextCommand: Self.batchNextCommand(from: details)
            )
        default:
            return BatchStepSummary(
                command: commandName, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: nil, error: nil
            )
        }
    }

    private static func batchNextCommand(from details: FailureDetails?) -> String? {
        guard details?.errorCode == FenceRequestErrorCode.missingTarget else { return nil }
        return details?.hint
    }

    // MARK: - Session State

    func currentSessionState() -> [String: Any] {
        let connected = handoff.isConnected
        var payload: [String: Any] = [
            "status": "ok",
            "connected": connected,
            "phase": handoff.connectionPhaseName,
        ]
        if let device = handoff.connectedDevice {
            payload["deviceName"] = handoff.displayName(for: device)
            payload["appName"] = device.appName
            payload["connectionType"] = device.connectionType.rawValue
            if let shortId = device.shortId { payload["shortId"] = shortId }
        }
        payload["isRecording"] = isRecording
        payload["actionTimeoutSeconds"] = Timeouts.actionSeconds
        payload["longActionTimeoutSeconds"] = Timeouts.longActionSeconds
        if let failure = handoff.connectionDiagnosticFailure {
            var failurePayload: [String: Any] = [
                "errorCode": failure.failureCode,
                "phase": failure.phase.rawValue,
                "retryable": failure.retryable,
            ]
            if let message = failure.errorDescription {
                failurePayload["message"] = message
            }
            if let hint = failure.hint {
                failurePayload["hint"] = hint
            }
            payload["lastFailure"] = failurePayload
        }

        if let last = lastActionResult {
            payload["lastAction"] = [
                "method": last.method.rawValue,
                "success": last.success,
                "message": last.message as Any,
                "latency_ms": lastLatencyMs,
            ]
        }
        return payload
    }
}
