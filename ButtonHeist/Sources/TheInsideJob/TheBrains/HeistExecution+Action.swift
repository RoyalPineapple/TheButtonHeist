#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension HeistExecution.Machine {
    internal mutating func begin(
        action step: ActionStep,
        path: HeistExecutionPath,
        environment: HeistExecutionEnvironment
    ) -> HeistExecution.Decision {
        let command: ResolvedHeistActionCommand
        do {
            command = try step.command.resolve(in: environment)
        } catch {
            return resume(afterCompletedLeaf: HeistExecution.ResultProjector.actionResolutionFailure(
                step: step,
                path: path,
                error: error
            ))
        }

        let expectation: HeistExecution.ActionObservationExpectation
        let observationTimeout: Duration
        do {
            expectation = try HeistExecution.ActionObservationExpectation(
                step.executionExpectation,
                bindings: environment
            )
            switch step.executionExpectation {
            case .authoredThenNoChange(let authored):
                observationTimeout = HeistExecution.duration(
                    authored.waitStep(using: actionExpectationTimeoutPolicy).timeout
                )
            case .noChange:
                observationTimeout = HeistExecution.duration(actionExpectationTimeoutPolicy.standard)
            }
        } catch {
            return resume(afterCompletedLeaf: HeistExecution.ResultProjector.expectationResolutionFailure(
                step: step,
                command: command,
                path: path,
                error: error
            ))
        }

        let id = nextID()
        running.activeLeaf = .action(HeistExecution.ActionLeaf(
            id: id,
            step: step,
            command: command,
            expectation: expectation,
            path: path,
            phase: .beginningObservation
        ))
        return .perform(.beginObservation(
            id,
            HeistExecution.ObservationRequest(
                scope: expectation.observationScope,
                timeout: observationTimeout
            )
        ))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
