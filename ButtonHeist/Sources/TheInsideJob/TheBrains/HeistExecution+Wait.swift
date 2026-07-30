#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension HeistExecution.Machine {
    internal mutating func begin(
        wait step: WaitStep,
        context: HeistExecution.StepContext
    ) -> HeistExecution.State {
        let predicate: HeistExecution.Predicate
        do {
            predicate = try HeistExecution.Predicate(
                authored: step.predicate,
                bindings: context.environment
            )
        } catch {
            return resume(afterCompletedLeaf: HeistExecution.ResultProjector.waitResolutionFailure(
                step: step,
                context: context,
                error: error
            ))
        }

        let id = nextID()
        let timeout = HeistExecution.duration(step.timeout)
        activeLeaf = .wait(HeistExecution.WaitLeaf(
            id: id,
            step: step,
            predicate: predicate,
            context: context,
            phase: .beginningObservation
        ))
        return .pending(.perform(
            .beginObservation(
                id,
                HeistExecution.ObservationRequest(
                    scope: predicate.observationScope,
                    timeout: timeout
                )
            )
        ))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
