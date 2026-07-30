#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension HeistExecution.Machine {
    internal mutating func begin(
        action step: ActionStep,
        context: HeistExecution.StepContext
    ) -> HeistExecution.State {
        let command: ResolvedHeistActionCommand
        do {
            command = try step.command.resolve(in: context.environment)
        } catch {
            return resume(afterCompletedLeaf: HeistExecution.ResultProjector.actionResolutionFailure(
                step: step,
                context: context,
                error: error
            ))
        }

        let predicate: HeistExecution.Predicate?
        let observationTimeout: Duration
        do {
            if let authored = step.expectationPolicy.expectedExpectation?
                .waitStep(using: actionExpectationTimeoutPolicy) {
                let resolved = try authored.resolve(in: context.environment)
                predicate = HeistExecution.Predicate(
                    authored: authored.predicate,
                    resolved: resolved.predicate
                )
                observationTimeout = HeistExecution.duration(resolved.timeout)
            } else {
                predicate = nil
                observationTimeout = SemanticObservationTiming.defaultTimeout
            }
        } catch {
            return resume(afterCompletedLeaf: HeistExecution.ResultProjector.expectationResolutionFailure(
                step: step,
                command: command,
                context: context,
                error: error
            ))
        }

        let id = nextID()
        activeLeaf = .action(HeistExecution.ActionLeaf(
            id: id,
            step: step,
            command: command,
            predicate: predicate,
            context: context,
            phase: .beginningObservation
        ))
        return .pending(.perform([
            .beginObservation(
                id,
                HeistExecution.ObservationRequest(
                    scope: predicate?.observationScope ?? .visible,
                    timeout: observationTimeout
                )
            ),
        ]))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
