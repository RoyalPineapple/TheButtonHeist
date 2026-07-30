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

        let predicate: HeistExecution.Predicate?
        let observationTimeout: Duration
        do {
            if let authored = step.expectationPolicy.expectedExpectation?
                .waitStep(using: actionExpectationTimeoutPolicy) {
                predicate = try HeistExecution.Predicate(
                    authored: authored.predicate,
                    bindings: environment
                )
                observationTimeout = HeistExecution.duration(authored.timeout)
            } else {
                predicate = nil
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
        activeLeaf = .action(HeistExecution.ActionLeaf(
            id: id,
            step: step,
            command: command,
            predicate: predicate,
            path: path,
            phase: .beginningObservation
        ))
        return .perform(.beginObservation(
            id,
            HeistExecution.ObservationRequest(
                scope: predicate?.observationScope ?? .visible,
                timeout: observationTimeout
            )
        ))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
