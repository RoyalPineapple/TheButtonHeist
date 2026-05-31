import Foundation

import TheScore

extension TheFence {
    struct DispatchResult {
        let response: FenceResponse
        let durationMs: Int
    }

    private struct PostDispatchOutcome {
        let preActionElements: [HeistId: HeistElement]
    }

    private struct ValidatedResponse {
        let response: FenceResponse
    }

    func executableActionMessages(for request: ParsedRequest) throws -> [ClientMessage] {
        guard let messages = request.executableMessages else {
            throw FenceError.invalidRequest(
                "command \"\(request.command.rawValue)\" is not an executable action command"
            )
        }
        return messages
    }

    func execute(parsed: ParsedRequest) async throws -> FenceResponse {
        let dispatched = try await dispatchCommand(parsed)

        let postDispatch = capturePostDispatchEffects(response: dispatched.response)
        let validatedResponse = try await validateActionResponse(
            dispatched.response,
            command: parsed.command,
            expectation: parsed.expectationPayload.expectation,
            expectationTimeout: parsed.expectationPayload.postActionValidationTimeout,
            preActionElements: postDispatch.preActionElements
        )
        recordHeistStep(
            parsed,
            dispatchedResponse: dispatched.response,
            validatedResponse: validatedResponse.response,
            targetCapture: dispatched.response.actionResult?.accessibilityTrace?.captures.first
        )
        return validatedResponse.response
    }

    private func dispatchCommand(_ parsed: ParsedRequest) async throws -> DispatchResult {
        try await ensureConnectedIfNeeded(for: parsed.command)
        return try await dispatchWithErrorLogging(parsed)
    }

    private func capturePostDispatchEffects(response: FenceResponse) -> PostDispatchOutcome {
        let elements = response.actionResult?.accessibilityTrace?.captures.first?.interface.elements ?? []
        return PostDispatchOutcome(preActionElements: Dictionary(
            elements.map { ($0.heistId, $0) },
            uniquingKeysWith: { _, latest in latest }
        ))
    }

    private func ensureConnectedIfNeeded(for command: Command) async throws {
        guard !handoff.isConnected, command.descriptor.requiresConnectionBeforeDispatch else { return }
        try await start()
    }

    private func dispatchWithErrorLogging(_ parsed: ParsedRequest) async throws -> DispatchResult {
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
            throw error
        }
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    private func validateActionResponse(
        _ response: FenceResponse,
        command: Command,
        expectation: ActionExpectation?,
        expectationTimeout: Double?,
        preActionElements: [HeistId: HeistElement]
    ) async throws -> ValidatedResponse {
        if let actionResult = response.actionResult {
            let delivery = ActionExpectation.validateDelivery(actionResult)
            if !delivery.met {
                return ValidatedResponse(
                    response: .action(command: command, result: actionResult, expectation: delivery)
                )
            }
            if let expectation {
                let validation = expectation.validate(
                    against: actionResult, preActionElements: preActionElements
                )
                if validation.met {
                    return ValidatedResponse(
                        response: .action(command: command, result: actionResult, expectation: validation)
                    )
                }
                return try await waitForPostActionExpectation(
                    expectation,
                    command: command,
                    initialResult: actionResult,
                    initialValidation: validation,
                    preActionElements: preActionElements,
                    timeout: expectationTimeout
                )
            }
        }

        return ValidatedResponse(response: response)
    }

    private func waitForPostActionExpectation(
        _ expectation: ActionExpectation,
        command: Command,
        initialResult: ActionResult,
        initialValidation: ExpectationResult,
        preActionElements: [HeistId: HeistElement],
        timeout: Double?
    ) async throws -> ValidatedResponse {
        let target = WaitForChangeTarget(expect: expectation, timeout: timeout)
        do {
            let waitResult = try await sendAndAwaitAction(
                .waitForChange(target),
                timeout: target.resolvedTimeout + config.postActionExpectationTimeoutBuffer
            )
            let waitValidation = expectation.validate(against: waitResult, preActionElements: preActionElements)
            return ValidatedResponse(
                response: .action(
                    command: .waitForChange,
                    result: waitResult,
                    expectation: waitValidation
                )
            )
        } catch FenceError.actionTimeout {
            return ValidatedResponse(
                response: .action(command: command, result: initialResult, expectation: initialValidation)
            )
        }
    }
}
