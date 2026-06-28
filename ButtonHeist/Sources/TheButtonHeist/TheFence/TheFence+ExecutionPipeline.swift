import Foundation
import ThePlans

import TheScore

extension TheFence {
    struct DispatchResult {
        let response: FenceResponse
        let durationMs: Int
    }

    func executableRuntimeActions(for request: ParsedRequest) throws -> NonEmptyRuntimeActionMessages {
        guard let messages = request.runtimeActionMessages else {
            throw FenceError.invalidRequest(
                "command \"\(request.command.rawValue)\" is not an executable action command"
            )
        }
        return messages
    }

    /// Execute one user intent.
    ///
    /// Every executable UI action and the `wait` command run as a one-step
    /// `HeistPlan` on the device — the same engine that runs a composed heist.
    /// There is no client-side action dispatch or expectation evaluation: a
    /// single command is a one-step heist, and its expectation is the action
    /// step's expectation, evaluated server-side against the action's own
    /// pre-action baseline. Non-action commands (interface, screen, session,
    /// the `get_pasteboard` read) keep their dedicated handler.
    func execute(parsed: ParsedRequest) async throws -> FenceResponse {
        try await ensureConnectedIfNeeded(for: parsed.command)

        if let plan = try singleStepHeistPlan(for: parsed) {
            return try await executeSingleStepHeist(parsed, plan: plan)
        }

        let dispatched = try await dispatchWithErrorLogging(parsed)
        return dispatched.response
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
                response: .failure(error),
                durationMs: elapsedMilliseconds(since: start)
            )
        } catch {
            throw error
        }
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}
