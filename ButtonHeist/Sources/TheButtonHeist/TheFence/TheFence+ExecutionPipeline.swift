import Foundation

import TheScore

extension TheFence {
    struct DispatchResult {
        let response: FenceResponse
        let durationMs: Int
    }

    private struct PostDispatchOutcome {
        let preActionCaptureRef: AccessibilityTrace.CaptureRef?
        let recordingLookupCaptureRef: AccessibilityTrace.CaptureRef?
        let deliveredCaptureRef: AccessibilityTrace.CaptureRef?
    }

    private struct ValidatedResponse {
        let response: FenceResponse
        let deliveredCaptureRef: AccessibilityTrace.CaptureRef?
    }

    private struct BackgroundExpectationResponse {
        let response: FenceResponse
        let deliveredCaptureRef: AccessibilityTrace.CaptureRef?
    }

    func clientMessageExecutionPlan(for request: ParsedRequest) throws -> ClientMessageExecutionPlan {
        guard let messages = request.executableMessages else {
            throw FenceError.invalidRequest(
                "command \"\(request.command.rawValue)\" is not an executable action command"
            )
        }
        let descriptor = request.command.descriptor
        return ClientMessageExecutionPlan(
            messages: messages,
            timeout: try descriptor.executionTimeout(for: request),
            recordsCompletion: descriptor.recordsActionCompletion
        )
    }

    func execute(parsed: ParsedRequest) async throws -> FenceResponse {
        if let immediate = parsed.immediateResponse { return immediate }

        logCommand(parsed)

        if parsed.command == .waitForChange,
           let backgroundResponse = responseIfBackgroundExpectationMet(
            parsed.expectationPayload.expectation, requestId: parsed.requestId
           ) {
            finishAccessibilityDelivery(backgroundResponse.deliveredCaptureRef)
            return backgroundResponse.response
        }

        let preDispatchBackgroundCount = backgroundAccessibility.pendingTraceCount
        let preDispatchCaptureRef = backgroundAccessibility.latestRef
        let dispatched = try await dispatchCommand(parsed)
        commandExecutionState.noteDispatchedResponse(dispatched.response, latencyMs: dispatched.durationMs)
        logResponse(requestId: parsed.requestId, response: dispatched.response, durationMs: dispatched.durationMs)

        let postDispatch = capturePostDispatchEffects(
            parsed: parsed,
            response: dispatched.response,
            preDispatchCaptureRef: preDispatchCaptureRef
        )
        let validatedResponse = try await validateActionResponse(
            dispatched.response,
            expectation: parsed.expectationPayload.expectation,
            expectationTimeout: parsed.expectationPayload.postActionValidationTimeout,
            preActionCaptureRef: postDispatch.preActionCaptureRef,
            postDispatchBackgroundStartIndex: preDispatchBackgroundCount
        )
        recordHeistEvidence(
            parsed,
            dispatchedResponse: dispatched.response,
            validatedResponse: validatedResponse.response,
            lookupCaptureRef: postDispatch.recordingLookupCaptureRef
        )
        finishAccessibilityDelivery(validatedResponse.deliveredCaptureRef ?? postDispatch.deliveredCaptureRef)
        return validatedResponse.response
    }

    private func dispatchCommand(_ parsed: ParsedRequest) async throws -> DispatchResult {
        try await ensureConnectedIfNeeded(for: parsed.command)
        return try await dispatchWithErrorLogging(
            parsed,
            requestId: parsed.requestId
        )
    }

    private func capturePostDispatchEffects(
        parsed: ParsedRequest,
        response: FenceResponse,
        preDispatchCaptureRef: AccessibilityTrace.CaptureRef?
    ) -> PostDispatchOutcome {
        if let fullInterface = fullInterfaceCapture(from: response, parsed: parsed) {
            let captureRef = backgroundAccessibility.append(interface: fullInterface)
            return PostDispatchOutcome(
                preActionCaptureRef: nil,
                recordingLookupCaptureRef: nil,
                deliveredCaptureRef: captureRef
            )
        }

        guard let actionResult = response.actionResult else {
            return PostDispatchOutcome(
                preActionCaptureRef: nil,
                recordingLookupCaptureRef: nil,
                deliveredCaptureRef: nil
            )
        }

        let cursor = ingestActionTrace(actionResult)
        let beforeRef = cursor?.first ?? preDispatchCaptureRef
        return PostDispatchOutcome(
            preActionCaptureRef: beforeRef,
            recordingLookupCaptureRef: beforeRef,
            deliveredCaptureRef: cursor?.last
        )
    }

    private func responseIfBackgroundExpectationMet(
        _ expectation: ActionExpectation?,
        requestId: String,
        startingAt startIndex: Int = 0
    ) -> BackgroundExpectationResponse? {
        guard let expectation else { return nil }

        guard let match = backgroundAccessibility.consumeFirstTraceMatchingExpectation(
            expectation,
            startingAt: startIndex
        ) else {
            return nil
        }
        let response = FenceResponse.action(result: match.result, expectation: match.validation)
        logResponse(requestId: requestId, response: response, durationMs: 0)
        return BackgroundExpectationResponse(
            response: response,
            deliveredCaptureRef: match.deliveredCaptureRef
        )
    }

    private func ensureConnectedIfNeeded(for command: Command) async throws {
        guard !handoff.isConnected, command.requiresConnectionBeforeDispatch else { return }
        try await start()
    }

    private func dispatchWithErrorLogging(
        _ parsed: ParsedRequest,
        requestId: String
    ) async throws -> DispatchResult {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let response = try await dispatch(parsed)
            return DispatchResult(response: response, durationMs: elapsedMilliseconds(since: start))
        } catch let error as SchemaValidationError {
            return DispatchResult(
                response: .error(error.message),
                durationMs: elapsedMilliseconds(since: start)
            )
        } catch {
            let durationMs = elapsedMilliseconds(since: start)
            logErrorResponse(requestId: requestId, error: error, durationMs: durationMs)
            throw error
        }
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    private func validateActionResponse(
        _ response: FenceResponse,
        expectation: ActionExpectation?,
        expectationTimeout: Double?,
        preActionCaptureRef: AccessibilityTrace.CaptureRef?,
        postDispatchBackgroundStartIndex: Int
    ) async throws -> ValidatedResponse {
        if let actionResult = response.actionResult {
            let delivery = ActionExpectation.validateDelivery(actionResult)
            if !delivery.met {
                return ValidatedResponse(
                    response: .action(result: actionResult, expectation: delivery),
                    deliveredCaptureRef: nil
                )
            }
            if let expectation {
                let preActionElements = backgroundAccessibility.elementLookup(captureRef: preActionCaptureRef)
                let validation = expectation.validate(
                    against: actionResult, preActionElements: preActionElements
                )
                if validation.met {
                    return ValidatedResponse(
                        response: .action(result: actionResult, expectation: validation),
                        deliveredCaptureRef: nil
                    )
                }
                return try await waitForPostActionExpectation(
                    expectation,
                    initialResult: actionResult,
                    initialValidation: validation,
                    preActionElements: preActionElements,
                    timeout: expectationTimeout,
                    backgroundStartIndex: postDispatchBackgroundStartIndex
                )
            }
        }

        return ValidatedResponse(response: response, deliveredCaptureRef: nil)
    }

    private func waitForPostActionExpectation(
        _ expectation: ActionExpectation,
        initialResult: ActionResult,
        initialValidation: ExpectationResult,
        preActionElements: [HeistId: HeistElement],
        timeout: Double?,
        backgroundStartIndex: Int
    ) async throws -> ValidatedResponse {
        if let backgroundResponse = responseIfBackgroundExpectationMet(
            expectation,
            requestId: UUID().uuidString,
            startingAt: backgroundStartIndex
        ) {
            return ValidatedResponse(
                response: backgroundResponse.response,
                deliveredCaptureRef: backgroundResponse.deliveredCaptureRef
            )
        }

        let target = WaitForChangeTarget(expect: expectation, timeout: timeout)
        do {
            let waitResult = try await sendAndAwaitAction(
                .waitForChange(target),
                timeout: target.resolvedTimeout + config.postActionExpectationTimeoutBuffer
            )
            recordCompletedAction(waitResult)
            let waitCursor = ingestActionTrace(waitResult)
            let waitValidation = expectation.validate(against: waitResult, preActionElements: preActionElements)
            return ValidatedResponse(
                response: .action(
                    result: waitResult,
                    expectation: waitValidation
                ),
                deliveredCaptureRef: waitCursor?.last
            )
        } catch FenceError.actionTimeout {
            return ValidatedResponse(
                response: .action(result: initialResult, expectation: initialValidation),
                deliveredCaptureRef: nil
            )
        }
    }

    private func fullInterfaceCapture(from response: FenceResponse, parsed: ParsedRequest) -> Interface? {
        guard case .getInterface = parsed.payload,
              case .interface(let iface, _) = response else {
            return nil
        }
        return iface
    }

    private func ingestActionTrace(_ actionResult: ActionResult) -> AccessibilityTrace.Cursor? {
        guard let trace = actionResult.accessibilityTrace else { return nil }
        return backgroundAccessibility.ingest(trace)
    }

    private func finishAccessibilityDelivery(_ captureRef: AccessibilityTrace.CaptureRef?) {
        backgroundAccessibility.markDelivered(through: captureRef)
    }
}
