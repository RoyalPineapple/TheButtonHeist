import Foundation
import ThePlans

import TheScore

extension TheFence {
    struct DispatchResult {
        let response: FenceResponse
        let durationMs: Int
    }

    /// Execute one user intent.
    ///
    /// Durable executable UI actions and the `wait` command run as a one-step
    /// `HeistPlan` on the device — the same engine that runs a composed heist.
    /// Transient runtime actions that are not durable heist primitives fall
    /// through to direct client dispatch. Non-action commands (interface,
    /// screen, session, the `get_pasteboard` read) keep their dedicated handler.
    func execute(parsed: ParsedRequest) async throws -> FenceResponse {
        try await ensureConnectedIfNeeded(for: parsed.command)
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
