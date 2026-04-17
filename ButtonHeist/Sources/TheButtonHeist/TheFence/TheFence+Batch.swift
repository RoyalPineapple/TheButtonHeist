import Foundation

import TheScore

// MARK: - Batch Execution and Session State

extension TheFence {

    enum BatchPolicy: String, CaseIterable {
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
                "Unknown batch policy: \"\(policyString)\". " +
                "Valid: \(BatchPolicy.allCases.map(\.rawValue).joined(separator: ", "))"
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

                // Count explicit tier expectations only — delivery failures have
                // expectation.expectation == nil and should not inflate the count
                var stepExpectationMet: Bool?
                if case .action(_, let expectation) = response,
                   let result = expectation,
                   result.expectation != nil {
                    expectationsChecked += 1
                    if result.met { expectationsMet += 1 }
                    stepExpectationMet = result.met
                }

                // Collect delta for net diff computation
                if case .action(let actionResult, _) = response,
                   let delta = actionResult.interfaceDelta {
                    stepDeltas.append(delta)
                }

                // Build step summary from the typed response
                stepSummaries.append(makeStepSummary(
                    command: commandName, response: response, expectationMet: stepExpectationMet
                ))

                // Check for failure using the typed response, not serialized strings
                let isFailed: Bool
                if case .action(_, let expectation) = response, let result = expectation {
                    isFailed = !result.met
                } else if case .error = response {
                    isFailed = true
                } else {
                    isFailed = false
                }
                if isFailed && policy == .stopOnError {
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

    // MARK: - Step Summary

    private func makeStepSummary(
        command: String, response: FenceResponse, expectationMet: Bool?
    ) -> BatchStepSummary {
        switch response {
        case .action(let result, _):
            return BatchStepSummary(
                command: command,
                deltaKind: result.interfaceDelta?.kind.rawValue,
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
        case .error(let message):
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
