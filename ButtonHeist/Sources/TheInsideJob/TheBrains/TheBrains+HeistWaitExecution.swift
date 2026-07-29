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
        let resolved: ResolvedWaitStep
        do {
            resolved = try step.resolve(in: context.environment)
        } catch {
            return resume(afterCompletedLeaf: HeistExecution.ResultProjector.waitResolutionFailure(
                step: step,
                context: context,
                error: error
            ))
        }

        let id = nextID()
        let timeout = HeistExecution.duration(resolved.timeout)
        let predicate = HeistExecution.Predicate(
            authored: step.predicate,
            resolved: resolved.predicate
        )
        activeLeaf = .wait(HeistExecution.WaitLeaf(
            id: id,
            step: step,
            predicate: predicate,
            timeout: timeout,
            context: context,
            phase: .beginningObservation,
            boundary: nil,
            expectation: Expectation()
        ))
        return .pending(.perform([
            .beginObservation(
                id,
                HeistExecution.ObservationRequest(
                    scope: predicate.observationScope,
                    timeout: timeout
                )
            ),
        ]))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
