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
        let expectationTimeout: Duration
        do {
            if let authored = step.expectationPolicy.expectedStep {
                let resolved = try authored.resolve(in: context.environment)
                predicate = HeistExecution.Predicate(
                    authored: authored.predicate,
                    resolved: resolved.predicate
                )
                expectationTimeout = HeistExecution.duration(resolved.timeout)
            } else {
                predicate = nil
                expectationTimeout = .zero
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
        let timeout = SemanticObservationTiming.defaultTimeout + expectationTimeout
        activeLeaf = .action(HeistExecution.ActionLeaf(
            id: id,
            step: step,
            command: command,
            predicate: predicate,
            timeout: timeout,
            context: context,
            phase: .beginningObservation,
            boundary: nil,
            expectation: Expectation(),
            dispatch: nil
        ))
        return .pending(.perform([
            .beginObservation(
                id,
                HeistExecution.ObservationRequest(
                    scope: predicate?.observationScope ?? .visible,
                    timeout: timeout
                )
            ),
        ]))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
