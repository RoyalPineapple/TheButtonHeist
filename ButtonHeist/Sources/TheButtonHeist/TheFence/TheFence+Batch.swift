import Foundation

import TheScore

extension TheFence {

    // MARK: - Batch Execution and Session State

    enum BatchPolicy: String {
        case stopOnError = "stop_on_error"
        case continueOnError = "continue_on_error"
    }

    func handleRunBatch(_ args: [String: Any]) async throws -> FenceResponse {
        guard let steps = args["steps"] as? [[String: Any]], !steps.isEmpty else {
            throw FenceError.invalidRequest("run_batch requires a non-empty 'steps' array")
        }
        let policyString = (args["policy"] as? String) ?? BatchPolicy.stopOnError.rawValue
        guard let policy = BatchPolicy(rawValue: policyString) else {
            throw FenceError.invalidRequest(
                "Unknown batch policy: \"\(policyString)\". Valid: stop_on_error, continue_on_error"
            )
        }

        var results: [[String: Any]] = []
        var stepSummaries: [BatchStepSummary] = []
        var stepDeltas: [InterfaceDelta] = []
        var failedIndex: Int?
        var expectationsMet = 0
        var expectationsChecked = 0
        let batchStart = CFAbsoluteTimeGetCurrent()

        for (index, step) in steps.enumerated() {
            let commandName = step["command"] as? String ?? "?"
            do {
                let response = try await execute(request: step)
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
                results.append(errorDict)
                stepSummaries.append(BatchStepSummary(
                    command: commandName, deltaKind: nil, screenName: nil, screenId: nil,
                    expectationMet: nil, elementCount: nil, error: error.localizedDescription
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
        let netDelta = NetDeltaAccumulator.merge(deltas: stepDeltas)
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
        let isFailed: Bool
        let delta: InterfaceDelta?
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
            let failed = result.map { !$0.met } ?? false
            return StepOutcome(
                isFailed: failed,
                delta: actionResult.interfaceDelta,
                expectationCounted: counted,
                expectationMet: met
            )
        case .error:
            return StepOutcome(isFailed: true, delta: nil, expectationCounted: false, expectationMet: nil)
        default:
            return StepOutcome(isFailed: false, delta: nil, expectationCounted: false, expectationMet: nil)
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
                deltaKind: result.interfaceDelta?.kindRawValue,
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
        case .error(let message, _):
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: nil, error: message
            )
        default:
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: nil, error: nil
            )
        }
    }

    // MARK: - Session State

    func currentSessionState() -> [String: Any] {
        let connected = handoff.isConnected
        var payload: [String: Any] = [
            "status": "ok",
            "connected": connected,
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
