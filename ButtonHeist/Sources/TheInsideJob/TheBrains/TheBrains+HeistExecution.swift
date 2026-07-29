#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension HeistExecution {
    internal enum Failure: Error, Sendable, LocalizedError, CustomStringConvertible {
        internal struct Detail: Sendable, CustomStringConvertible {
            internal let description: String

            internal init(_ error: any Error) {
                description = String(describing: error)
            }
        }

        case runtimeUnavailable
        case accessibilityTreeUnavailable
        case runtimeBoundary(Detail)
        case invalidResult(Detail)
        case submissionCancelled
        case interactionQueueFull
        case cleanupTimedOut
        case runtimeStopping

        internal var description: String {
            switch self {
            case .runtimeUnavailable:
                "ButtonHeist runtime is not active."
            case .accessibilityTreeUnavailable:
                "Could not observe accessibility tree."
            case .runtimeBoundary(let detail):
                "Heist execution failed at its runtime boundary: \(detail)"
            case .invalidResult(let detail):
                "Could not admit heist execution result: \(detail)"
            case .submissionCancelled:
                "In-app heist execution was cancelled."
            case .interactionQueueFull:
                "Interaction queue is full."
            case .cleanupTimedOut:
                "The previous interaction did not finish cancellation cleanup."
            case .runtimeStopping:
                "ButtonHeist runtime is stopping."
            }
        }

        internal var errorDescription: String? { description }

        internal var serverError: ServerError {
            let message: ServerErrorMessage
            do {
                message = try ServerErrorMessage(validating: description)
            } catch {
                preconditionFailure("HeistExecution.Failure descriptions have a non-empty static prefix")
            }
            let kind: ServerError.Kind = switch self {
            case .invalidResult:
                .validationError
            case .runtimeUnavailable,
                 .accessibilityTreeUnavailable,
                 .runtimeBoundary,
                 .submissionCancelled,
                 .interactionQueueFull,
                 .cleanupTimedOut,
                 .runtimeStopping:
                .general
            }
            return ServerError(kind: kind, message: message)
        }

        internal var actionFailureKind: ActionFailure.Kind {
            switch self {
            case .accessibilityTreeUnavailable:
                return .accessibilityTreeUnavailable
            case .invalidResult:
                return .validationError
            case .runtimeUnavailable,
                 .runtimeBoundary,
                 .submissionCancelled,
                 .interactionQueueFull,
                 .cleanupTimedOut,
                 .runtimeStopping:
                return .actionFailed
            }
        }
    }
}

extension TheBrains {
    internal func executeHeistPlan(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        timeout: HeistTimeout = .default
    ) async -> Result<HeistResult, HeistExecution.Failure> {
        guard semanticObservationIsActive else {
            return .failure(.runtimeUnavailable)
        }
        if tripwire.isPulseRunning {
            switch await interactionCoordinator.refreshedVisibleObservation() {
            case .committed:
                break
            case .unavailable:
                return .failure(.accessibilityTreeUnavailable)
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
            return .failure(.runtimeBoundary(.init(error)))
        }
        return heistResult(
            completion,
            durationMs: elapsedMilliseconds(since: startedAt)
        )
    }

    private func heistResult(
        _ completion: HeistExecution.Completion,
        durationMs: ElapsedMilliseconds
    ) -> Result<HeistResult, HeistExecution.Failure> {
        do {
            return .success(try HeistResult(
                steps: completion.steps,
                durationMs: durationMs
            ))
        } catch {
            return .failure(.invalidResult(.init(error)))
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
