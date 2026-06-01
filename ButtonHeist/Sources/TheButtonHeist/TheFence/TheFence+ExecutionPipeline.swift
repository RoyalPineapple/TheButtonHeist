import Foundation

import TheScore

extension TheFence {
    struct DispatchResult {
        let response: FenceResponse
        let durationMs: Int
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

        let validatedResponse: ValidatedResponse
        if let waitPredicate = Self.waitCommandPredicate(in: parsed) {
            // The wait command carries its predicate in the payload (not the
            // `expect` slot). Validate it against the returned trace and attach
            // the result — the wait result is already the outcome, so there is
            // no post-action re-wait.
            validatedResponse = validateWaitResponse(
                dispatched.response,
                predicate: waitPredicate
            )
        } else {
            validatedResponse = try await validateActionResponse(
                dispatched.response,
                command: parsed.command,
                expectation: parsed.expectationPayload.expectation,
                expectationTimeout: parsed.expectationPayload.postActionValidationTimeout
            )
        }
        recordHeistStep(
            parsed,
            dispatchedResponse: dispatched.response,
            validatedResponse: validatedResponse.response
        )
        return validatedResponse.response
    }

    private func dispatchCommand(_ parsed: ParsedRequest) async throws -> DispatchResult {
        try await ensureConnectedIfNeeded(for: parsed.command)
        return try await dispatchWithErrorLogging(parsed)
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
        expectation: AccessibilityPredicate?,
        expectationTimeout: Double?
    ) async throws -> ValidatedResponse {
        if let actionResult = response.actionResult {
            let delivery = deliveryExpectationResult(for: actionResult)
            if !delivery.met {
                return ValidatedResponse(
                    response: .action(command: command, result: actionResult, expectation: delivery)
                )
            }
            if let expectation {
                let validation = expectation.validate(against: actionResult)
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
                    timeout: expectationTimeout
                )
            }
        }

        return ValidatedResponse(response: response)
    }

    /// The predicate carried by a `wait` command's payload, if this is one.
    private static func waitCommandPredicate(in parsed: ParsedRequest) -> AccessibilityPredicate? {
        guard parsed.command == .wait,
              case .wait(let target)? = parsed.executableMessages?.first else {
            return nil
        }
        return target.predicate
    }

    /// Validate a `wait` command's own predicate against its returned trace and
    /// attach the result. On a non-delivered result the delivery failure is
    /// reported as-is; there is no post-action re-wait (the result is final).
    private func validateWaitResponse(
        _ response: FenceResponse,
        predicate: AccessibilityPredicate
    ) -> ValidatedResponse {
        guard let actionResult = response.actionResult else {
            return ValidatedResponse(response: response)
        }
        let delivery = deliveryExpectationResult(for: actionResult)
        guard delivery.met else {
            return ValidatedResponse(
                response: .action(command: .wait, result: actionResult, expectation: delivery)
            )
        }
        let validation = predicate.validate(against: actionResult)
        return ValidatedResponse(
            response: .action(command: .wait, result: actionResult, expectation: validation)
        )
    }

    private func deliveryExpectationResult(for result: ActionResult) -> ExpectationResult {
        ExpectationResult(
            met: result.success,
            predicate: nil,
            actual: result.success ? "delivered" : (result.message ?? "failed")
        )
    }

    private func waitForPostActionExpectation(
        _ expectation: AccessibilityPredicate,
        command: Command,
        initialResult: ActionResult,
        initialValidation: ExpectationResult,
        timeout: Double?
    ) async throws -> ValidatedResponse {
        let target = WaitTarget(predicate: expectation, timeout: timeout)
        do {
            let waitResult = try await sendAndAwaitAction(
                .wait(target),
                timeout: target.resolvedTimeout + config.postActionExpectationTimeoutBuffer
            )
            let waitValidation = expectation.validate(against: waitResult)
            return ValidatedResponse(
                response: .action(
                    command: .wait,
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
