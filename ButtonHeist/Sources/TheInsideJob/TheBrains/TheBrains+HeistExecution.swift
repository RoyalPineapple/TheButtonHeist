#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension TheBrains {
    internal func executeHeistPlan(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        timeout: HeistTimeout = .default
    ) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(payload: .heist(nil))
        }
        if tripwire.isPulseRunning {
            switch await interactionCoordinator.refreshedVisibleObservation() {
            case .committed:
                break
            case .unavailable(let failure):
                return treeUnavailableResult(
                    payload: .heist(nil),
                    failure: failure
                )
            }
        }

        let host = HeistExecution.Host(brains: self)
        let startedAt = RuntimeElapsed.now
        let completion: HeistExecution.Completion
        do {
            completion = try await host.execute(
                plan,
                argument: argument,
                timeout: timeout
            )
        } catch {
            return .failure(
                payload: .heist(nil),
                failureKind: .actionFailed,
                message: "Heist execution failed at its runtime boundary: \(error)"
            )
        }
        return heistActionResult(
            completion,
            durationMs: elapsedMilliseconds(since: startedAt)
        )
    }

    private func heistActionResult(
        _ completion: HeistExecution.Completion,
        durationMs: ElapsedMilliseconds
    ) -> ActionResult {
        let result: HeistResult
        do {
            result = try HeistResult(
                steps: completion.steps,
                durationMs: durationMs
            )
        } catch {
            return .failure(
                payload: .heist(nil),
                failureKind: .validationError,
                message: "Could not admit heist execution result: \(error)"
            )
        }
        let message = heistExecutionMessage(
            completedCount: completion.steps.count,
            abortedAtPath: completion.abortedAtPath
        )
        guard completion.abortedAtPath == nil else {
            return .failure(
                payload: .heist(result),
                failureKind: .actionFailed,
                message: message
            )
        }
        return .success(payload: .heist(result), message: message)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
