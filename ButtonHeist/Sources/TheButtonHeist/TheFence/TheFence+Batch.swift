import Foundation

import TheScore

extension TheFence {

    // MARK: - Batch Execution and Session State

    enum BatchPolicy: String, CaseIterable {
        case stopOnError = "stop_on_error"
        case continueOnError = "continue_on_error"
    }

    func handleRunBatch(_ args: [String: Any]) async throws -> FenceResponse {
        let steps = try args.requiredSchemaDictionaryArray("steps")
        guard !steps.isEmpty else {
            throw SchemaValidationError(field: "steps", observed: "array count 0", expected: "array count >= 1")
        }
        let policy = try args.schemaEnum("policy", as: BatchPolicy.self) ?? .stopOnError

        var results: [[String: Any]] = []
        var stepSummaries: [BatchStepSummary] = []
        var stepDeltas: [AccessibilityTrace.Delta] = []
        var stepAccessibilityTraces: [AccessibilityTrace] = []
        var actionOutcomeCount = 0
        var failedIndex: Int?
        var expectationsMet = 0
        var expectationsChecked = 0
        let batchStart = CFAbsoluteTimeGetCurrent()

        for (index, step) in steps.enumerated() {
            let originalCommandName = step["command"] as? String ?? "?"
            do {
                let normalizedStep = try Self.normalizedBatchStep(step, index: index)
                let commandName = normalizedStep["command"] as? String ?? "?"
                let response = try await execute(request: normalizedStep)
                results.append(response.jsonDict() ?? ["status": "ok"])

                let outcome = stepOutcome(response: response)

                // Count explicit tier expectations only — delivery failures have
                // expectation.expectation == nil and should not inflate the count
                if outcome.expectationCounted {
                    expectationsChecked += 1
                    if outcome.expectationMet == true { expectationsMet += 1 }
                }

                if let delta = outcome.delta {
                    stepDeltas.append(delta)
                }
                if outcome.hasActionResult {
                    actionOutcomeCount += 1
                    if let accessibilityTrace = outcome.accessibilityTrace {
                        stepAccessibilityTraces.append(accessibilityTrace)
                    }
                }

                stepSummaries.append(makeStepSummary(
                    command: commandName, response: response,
                    expectationMet: outcome.expectationCounted ? outcome.expectationMet : nil
                ))

                if outcome.isFailed, policy == .stopOnError {
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
                    command: originalCommandName, deltaKind: nil, screenName: nil, screenId: nil,
                    expectationMet: nil, elementCount: nil, error: error.localizedDescription,
                    errorCode: failureDetails?.errorCode,
                    phase: failureDetails?.phase.rawValue,
                    nextCommand: Self.batchNextCommand(from: failureDetails)
                ))
                if policy == .stopOnError {
                    failedIndex = index
                    break
                }
            }
        }

        if let failedIndex, policy == .stopOnError {
            stepSummaries.append(contentsOf: skippedStepSummaries(
                steps: steps,
                afterFailedIndex: failedIndex
            ))
        }

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - batchStart) * 1000)
        let netDelta = if actionOutcomeCount > 0,
                          stepAccessibilityTraces.count == actionOutcomeCount,
                          Self.canDeriveNetDeltaFromCaptureReceipts(stepAccessibilityTraces) {
            AccessibilityTrace.captureReceiptDelta(from: stepAccessibilityTraces)
        } else {
            NetDeltaAccumulator.merge(deltas: stepDeltas)
        }
        return .batch(
            results: results,
            completedSteps: results.count,
            failedIndex: failedIndex,
            totalTimingMs: totalMs,
            expectationsChecked: expectationsChecked,
            expectationsMet: expectationsMet,
            stepSummaries: stepSummaries,
            netDelta: netDelta
        )
    }

    private static func normalizedBatchStep(
        _ step: [String: Any],
        index: Int
    ) throws -> [String: Any] {
        switch FenceOperationCatalog.normalizeBatchStep(step) {
        case .success(let normalizedStep):
            return normalizedStep
        case .failure(let error):
            throw FenceError.invalidRequest("run_batch step \(index): \(error.message)")
        }
    }

    private static func canDeriveNetDeltaFromCaptureReceipts(_ traces: [AccessibilityTrace]) -> Bool {
        traces.lazy.flatMap(\.captures).prefix(2).count >= 2
    }

    private func skippedStepSummaries(
        steps: [[String: Any]], afterFailedIndex failedIndex: Int
    ) -> [BatchStepSummary] {
        steps.dropFirst(failedIndex + 1).map { step in
            BatchStepSummary(
                command: step["command"] as? String ?? "?",
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
        let hasActionResult: Bool
        let isFailed: Bool
        let delta: AccessibilityTrace.Delta?
        let accessibilityTrace: AccessibilityTrace?
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
                hasActionResult: true,
                isFailed: failed,
                delta: actionResult.accessibilityDelta,
                accessibilityTrace: actionResult.accessibilityTrace,
                expectationCounted: counted,
                expectationMet: met
            )
        case .error:
            return StepOutcome(
                hasActionResult: false,
                isFailed: true,
                delta: nil,
                accessibilityTrace: nil,
                expectationCounted: false,
                expectationMet: nil
            )
        default:
            return StepOutcome(
                hasActionResult: false,
                isFailed: false,
                delta: nil,
                accessibilityTrace: nil,
                expectationCounted: false,
                expectationMet: nil
            )
        }
    }

    // MARK: - Step Summary

    private func makeStepSummary(
        command: String, response: FenceResponse, expectationMet: Bool?
    ) -> BatchStepSummary {
        switch response {
        case .action(let result, _):
            return BatchStepSummary(
                command: command,
                deltaKind: result.accessibilityDelta?.kindRawValue,
                screenName: result.screenName,
                screenId: result.screenId,
                expectationMet: expectationMet,
                elementCount: nil,
                error: result.success ? nil : result.message
            )
        case .interface(let iface, _, _, _):
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: iface.elements.count, error: nil
            )
        case .error(let message, let details):
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: nil, error: message,
                errorCode: details?.errorCode,
                phase: details?.phase.rawValue,
                nextCommand: Self.batchNextCommand(from: details)
            )
        default:
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
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
        payload["isRecording"] = handoff.isRecording
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
