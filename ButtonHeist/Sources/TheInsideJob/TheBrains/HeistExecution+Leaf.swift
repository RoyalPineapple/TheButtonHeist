#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension HeistExecution {
    internal static func duration(_ timeout: WaitTimeout) -> Duration {
        .milliseconds(Int64((timeout.seconds * 1_000).rounded(.up)))
    }
}

extension HeistExecution.Machine {
    internal mutating func advanceActiveLeaf(
        _ input: HeistExecution.Input
    ) -> HeistExecution.State {
        guard let activeLeaf else { return .pending(.wait) }
        switch activeLeaf {
        case .action(let leaf):
            return advance(action: leaf, input: input)
        case .wait(let leaf):
            return advance(wait: leaf, input: input)
        }
    }

    /// Rejoins the authored sequence after either an observed leaf or a
    /// synchronous leaf-admission failure.
    internal mutating func resume(
        afterCompletedLeaf result: HeistExecutionStepResult
    ) -> HeistExecution.State {
        activeLeaf = nil
        guard case .sequence(var sequence) = continuations.popLast() else {
            preconditionFailure("A completed leaf requires an active sequence")
        }
        sequence.children.append(result)
        continuations.append(.sequence(sequence))
        return advanceExecution()
    }
}

private extension HeistExecution.Machine {
    mutating func advance(
        action leaf: HeistExecution.ActionLeaf,
        input: HeistExecution.Input
    ) -> HeistExecution.State {
        var leaf = leaf
        switch input {
        case .observationBegan(let id, let boundary):
            guard id == leaf.id,
                  leaf.phase == .beginningObservation else {
                return .pending(.wait)
            }
            leaf.boundary = boundary
            return update(
                action: leaf,
                performing: [
                    .currentSnapshot(
                        leaf.id,
                        scope: leaf.predicate?.observationScope ?? .visible
                    ),
                ]
            )

        case .event(let event):
            return observe(action: leaf, event: event)

        case .dispatchCompleted(let id, let dispatch):
            guard id == leaf.id,
                  leaf.phase == .dispatching else {
                return .pending(.wait)
            }
            return completeDispatch(action: leaf, dispatch: dispatch)

        case .currentSnapshot(let id, let snapshot):
            guard id == leaf.id,
                  leaf.phase == .beginningObservation,
                  leaf.boundary != nil,
                  leaf.dispatch == nil else {
                return .pending(.wait)
            }
            leaf.expectation = Expectation(
                leaf.predicate.map { [$0.resolved, .noChange] } ?? [.noChange],
                baseline: snapshot
            )
            leaf.phase = .dispatching
            return update(
                action: leaf,
                performing: [.dispatch(leaf.id, leaf.command)]
            )

        case .viewportExited(let id, let outcome):
            guard id == leaf.id,
                  leaf.phase == .exploring else {
                return .pending(.wait)
            }
            switch outcome {
            case .failed:
                return finish(action: leaf, exitPosition: .current)
            case .superseded:
                guard let predicate = leaf.predicate else {
                    preconditionFailure("A superseded action discovery requires a predicate")
                }
                return update(
                    action: leaf,
                    performing: [.explore(leaf.id, predicate)]
                )
            case .restored, .retained:
                leaf.phase = .observing
                activeLeaf = .action(leaf)
                return .pending(.wait)
            }

        case .observationFinished(let id, let evidence, let outcome):
            guard id == leaf.id,
                  leaf.boundary != nil,
                  leaf.phase != .beginningObservation else {
                return .pending(.wait)
            }
            let result = HeistExecution.ResultProjector.project(
                action: leaf,
                evidence: evidence,
                outcome: outcome
            )
            return resume(afterCompletedLeaf: result)

        case .failureScreenshotCaptured:
            return .pending(.wait)
        }
    }

    mutating func advance(
        wait leaf: HeistExecution.WaitLeaf,
        input: HeistExecution.Input
    ) -> HeistExecution.State {
        var leaf = leaf
        switch input {
        case .observationBegan(let id, let boundary):
            guard id == leaf.id,
                  leaf.phase == .beginningObservation else {
                return .pending(.wait)
            }
            leaf.boundary = boundary
            let predicateExpectation = Expectation(
                [leaf.predicate.resolved],
                baseline: boundary.baseline
            )
            leaf.expectation = predicateExpectation.result == .satisfied
                ? Expectation([.noChange])
                : Expectation(
                    [leaf.predicate.resolved, .noChange],
                    baseline: boundary.baseline
                )
            if predicateExpectation.result == .satisfied {
                leaf.phase = .observing
                activeLeaf = .wait(leaf)
                return .pending(.wait)
            }
            if leaf.predicate.isNotification {
                leaf.phase = .observing
                activeLeaf = .wait(leaf)
                return .pending(.wait)
            }
            leaf.phase = .exploring
            return update(
                wait: leaf,
                performing: [.explore(leaf.id, leaf.predicate)]
            )

        case .event(let event):
            return observe(wait: leaf, event: event)

        case .viewportExited(let id, let outcome):
            guard id == leaf.id,
                  leaf.phase == .exploring else {
                return .pending(.wait)
            }
            switch outcome {
            case .failed:
                return finish(wait: leaf, exitPosition: .current)
            case .superseded:
                return update(
                    wait: leaf,
                    performing: [.explore(leaf.id, leaf.predicate)]
                )
            case .restored, .retained:
                leaf.phase = .observing
                activeLeaf = .wait(leaf)
                return .pending(.wait)
            }

        case .observationFinished(let id, let evidence, let outcome):
            guard id == leaf.id,
                  leaf.boundary != nil,
                  leaf.phase != .beginningObservation else {
                return .pending(.wait)
            }
            let result = HeistExecution.ResultProjector.project(
                wait: leaf,
                evidence: evidence,
                outcome: outcome
            )
            guard outcome == .timedOut,
                  let unmatched = result.unmatchedWaitEvidence,
                  let elseBody = leaf.step.elseBody else {
                return resume(afterCompletedLeaf: result)
            }
            activeLeaf = nil
            continuations.append(.waitElse(HeistExecution.WaitElseContinuation(
                step: leaf.step,
                context: leaf.context,
                evidence: unmatched
            )))
            continuations.append(.sequence(HeistExecution.SequenceContinuation(
                steps: elseBody,
                context: HeistExecution.StepContext(
                    path: leaf.context.path.waitElseBody(),
                    environment: leaf.context.environment,
                    scope: leaf.context.scope
                ),
                nextIndex: 0,
                children: .empty
            )))
            return advanceExecution()

        case .currentSnapshot, .dispatchCompleted, .failureScreenshotCaptured:
            return .pending(.wait)
        }
    }

    mutating func finish(
        action leaf: HeistExecution.ActionLeaf,
        exitPosition: Navigation.ViewportExitPosition
    ) -> HeistExecution.State {
        var leaf = leaf
        leaf.phase = .finishingObservation
        return update(
            action: leaf,
            performing: [.finishObservation(leaf.id, exitPosition: exitPosition)]
        )
    }

    mutating func observe(
        action leaf: HeistExecution.ActionLeaf,
        event: Observation.Event
    ) -> HeistExecution.State {
        var leaf = leaf
        switch leaf.phase {
        case .dispatching:
            guard case .noChange = event else {
                leaf.expectation = leaf.expectation
                    .evaluating(event)
                    .requiringNoChange()
                activeLeaf = .action(leaf)
                return .pending(.wait)
            }
            return .pending(.wait)
        case .observing:
            leaf.expectation = actionExpectation(
                leaf.expectation,
                evaluating: event
            )
            guard leaf.expectation.result == .satisfied else {
                if shouldExplore(after: event, for: leaf.predicate) {
                    guard let predicate = leaf.predicate else {
                        preconditionFailure("An observing action without a predicate cannot request discovery")
                    }
                    leaf.phase = .exploring
                    return update(
                        action: leaf,
                        performing: [.explore(leaf.id, predicate)]
                    )
                }
                activeLeaf = .action(leaf)
                return .pending(.wait)
            }
            return finish(action: leaf, exitPosition: .current)
        case .exploring:
            leaf.expectation = actionExpectation(
                leaf.expectation,
                evaluating: event
            )
            guard leaf.expectation.result == .satisfied else {
                activeLeaf = .action(leaf)
                return .pending(.wait)
            }
            return finish(action: leaf, exitPosition: .current)
        case .beginningObservation, .finishingObservation:
            return .pending(.wait)
        }
    }

    mutating func completeDispatch(
        action leaf: HeistExecution.ActionLeaf,
        dispatch: TheSafecracker.ActionDispatchResult
    ) -> HeistExecution.State {
        var leaf = leaf
        leaf.dispatch = dispatch
        guard dispatch.success else {
            return finish(action: leaf, exitPosition: .current)
        }
        guard let predicate = leaf.predicate,
              !predicate.isNotification else {
            leaf.phase = .observing
            activeLeaf = .action(leaf)
            return .pending(.wait)
        }
        leaf.phase = .exploring
        return update(
            action: leaf,
            performing: [.explore(leaf.id, predicate)]
        )
    }

    mutating func finish(
        wait leaf: HeistExecution.WaitLeaf,
        exitPosition: Navigation.ViewportExitPosition
    ) -> HeistExecution.State {
        var leaf = leaf
        leaf.phase = .finishingObservation
        return update(
            wait: leaf,
            performing: [.finishObservation(leaf.id, exitPosition: exitPosition)]
        )
    }

    mutating func observe(
        wait leaf: HeistExecution.WaitLeaf,
        event: Observation.Event
    ) -> HeistExecution.State {
        var leaf = leaf
        guard leaf.phase == .observing || leaf.phase == .exploring else {
            return .pending(.wait)
        }
        leaf.expectation = leaf.expectation.evaluating(event)
        guard leaf.expectation.result == .satisfied else {
            if leaf.phase == .observing,
               shouldExplore(after: event, for: leaf.predicate) {
                leaf.phase = .exploring
                return update(
                    wait: leaf,
                    performing: [.explore(leaf.id, leaf.predicate)]
                )
            }
            activeLeaf = .wait(leaf)
            return .pending(.wait)
        }
        return finish(wait: leaf, exitPosition: .current)
    }

    mutating func update(
        action leaf: HeistExecution.ActionLeaf,
        performing requests: [HeistExecution.MainActorRequest]
    ) -> HeistExecution.State {
        activeLeaf = .action(leaf)
        return .pending(.perform(requests))
    }

    mutating func update(
        wait leaf: HeistExecution.WaitLeaf,
        performing requests: [HeistExecution.MainActorRequest]
    ) -> HeistExecution.State {
        activeLeaf = .wait(leaf)
        return .pending(.perform(requests))
    }

    func shouldExplore(
        after event: Observation.Event,
        for predicate: HeistExecution.Predicate?
    ) -> Bool {
        guard let predicate,
              case .elementsChanged = predicate.resolved else {
            return false
        }
        if case .noChange = event { return false }
        return true
    }

    func actionExpectation(
        _ expectation: Expectation,
        evaluating event: Observation.Event
    ) -> Expectation {
        let evaluated = expectation.evaluating(event)
        guard case .noChange = event else {
            return evaluated.requiringNoChange()
        }
        return evaluated
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
