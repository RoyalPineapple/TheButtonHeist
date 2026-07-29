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
        case .observationBegan(let id, let baseline):
            guard id == leaf.id,
                  case .beginningObservation = leaf.phase else {
                return .pending(.wait)
            }
            let expectation = Expectation(
                leaf.predicate.map { [$0.resolved, .noChange] } ?? [.noChange],
                baseline: baseline
            )
            leaf.phase = .dispatching(expectation)
            return update(
                action: leaf,
                performing: [.dispatch(leaf.id, leaf.command)]
            )

        case .event(let event):
            return observe(action: leaf, event: event)

        case .dispatchCompleted(let id, let dispatch):
            guard id == leaf.id,
                  case .dispatching(let expectation) = leaf.phase else {
                return .pending(.wait)
            }
            return completeDispatch(
                action: leaf,
                expectation: expectation,
                dispatch: dispatch
            )

        case .viewportExited(let id, let outcome):
            guard id == leaf.id,
                  case .exploring(let expectation, let dispatch) = leaf.phase else {
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
                leaf.phase = .observing(expectation, dispatch: dispatch)
                activeLeaf = .action(leaf)
                return .pending(.wait)
            }

        case .observationFinished(
            let source,
            let observationID,
            let evidence,
            let outcome
        ):
            guard observationID == leaf.id,
                  HeistExecution.ActiveLeaf.action(leaf).admits(source) else {
                return .pending(.wait)
            }
            let result = HeistExecution.ResultProjector.project(
                action: leaf,
                evidence: evidence,
                outcome: outcome
            )
            return resume(afterCompletedLeaf: result)

        case .currentSnapshot, .failureScreenshotCaptured:
            return .pending(.wait)
        }
    }

    mutating func advance(
        wait leaf: HeistExecution.WaitLeaf,
        input: HeistExecution.Input
    ) -> HeistExecution.State {
        var leaf = leaf
        switch input {
        case .observationBegan(let id, let baseline):
            guard id == leaf.id,
                  case .beginningObservation = leaf.phase else {
                return .pending(.wait)
            }
            if leaf.predicate.isNotification {
                leaf.phase = .observing(Expectation([
                    leaf.predicate.resolved,
                    .noChange,
                ]))
                activeLeaf = .wait(leaf)
                return .pending(.wait)
            }
            return begin(wait: leaf, baseline: baseline)

        case .event(let event):
            return observe(wait: leaf, event: event)

        case .viewportExited(let id, let outcome):
            guard id == leaf.id,
                  case .exploring(let expectation) = leaf.phase else {
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
                leaf.phase = .observing(expectation)
                activeLeaf = .wait(leaf)
                return .pending(.wait)
            }

        case .observationFinished(
            let source,
            let observationID,
            let evidence,
            let outcome
        ):
            guard observationID == leaf.id,
                  HeistExecution.ActiveLeaf.wait(leaf).admits(source) else {
                return .pending(.wait)
            }
            if case .beginningObservation = leaf.phase {
                leaf.phase = .observing(Expectation([leaf.predicate.resolved]))
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

    mutating func begin(
        wait leaf: HeistExecution.WaitLeaf,
        baseline: Observation.Snapshot?
    ) -> HeistExecution.State {
        var leaf = leaf
        let predicateExpectation = Expectation(
            [leaf.predicate.resolved],
            baseline: baseline
        )
        let expectation = predicateExpectation.result == .satisfied
            ? Expectation([.noChange])
            : Expectation(
                [leaf.predicate.resolved, .noChange],
                baseline: baseline
            )
        if predicateExpectation.result == .satisfied {
            leaf.phase = .observing(expectation)
            activeLeaf = .wait(leaf)
            return .pending(.wait)
        }
        leaf.phase = .exploring(expectation)
        return update(
            wait: leaf,
            performing: [.explore(leaf.id, leaf.predicate)]
        )
    }

    mutating func finish(
        action leaf: HeistExecution.ActionLeaf,
        exitPosition: Navigation.ViewportExitPosition
    ) -> HeistExecution.State {
        var leaf = leaf
        guard let dispatch = leaf.dispatch else {
            return .pending(.wait)
        }
        let requestID = nextID()
        leaf.phase = .finishingObservation(
            requestID,
            expectation: leaf.expectation,
            dispatch: dispatch
        )
        return update(
            action: leaf,
            performing: [.finishObservation(
                requestID: requestID,
                observationID: leaf.id,
                exitPosition: exitPosition
            )]
        )
    }

    mutating func observe(
        action leaf: HeistExecution.ActionLeaf,
        event: Observation.Event
    ) -> HeistExecution.State {
        var leaf = leaf
        switch leaf.phase {
        case .dispatching(let expectation):
            guard case .noChange = event else {
                leaf.phase = .dispatching(
                    expectation
                    .evaluating(event)
                    .requiringNoChange()
                )
                activeLeaf = .action(leaf)
                return .pending(.wait)
            }
            return .pending(.wait)
        case .observing(let current, let dispatch):
            let evaluated = expectation(
                current,
                evaluating: event
            )
            guard evaluated.result == .satisfied else {
                if leaf.predicate?.resolved.watchTarget != nil,
                   !evaluated.isWaitingOnlyForNoChange,
                   shouldExplore(after: event, for: leaf.predicate) {
                    guard let predicate = leaf.predicate else {
                        preconditionFailure("An observing action without a predicate cannot request discovery")
                    }
                    leaf.phase = .exploring(evaluated, dispatch: dispatch)
                    return update(
                        action: leaf,
                        performing: [.explore(leaf.id, predicate)]
                    )
                }
                leaf.phase = .observing(evaluated, dispatch: dispatch)
                activeLeaf = .action(leaf)
                return .pending(.wait)
            }
            leaf.phase = .observing(evaluated, dispatch: dispatch)
            return finish(action: leaf, exitPosition: .current)
        case .exploring(let current, let dispatch):
            let evaluated = expectation(
                current,
                evaluating: event
            )
            leaf.phase = .exploring(evaluated, dispatch: dispatch)
            guard evaluated.result == .satisfied else {
                activeLeaf = .action(leaf)
                return .pending(.wait)
            }
            return finish(action: leaf, exitPosition: .current)
        case .finishingObservation(_, let current, let dispatch):
            guard case .noChange = event else {
                leaf.phase = .observing(current, dispatch: dispatch)
                return observe(action: leaf, event: event)
            }
            return .pending(.wait)
        case .beginningObservation:
            return .pending(.wait)
        }
    }

    mutating func completeDispatch(
        action leaf: HeistExecution.ActionLeaf,
        expectation: Expectation,
        dispatch: TheSafecracker.ActionDispatchResult
    ) -> HeistExecution.State {
        var leaf = leaf
        leaf.phase = .observing(expectation, dispatch: dispatch)
        guard dispatch.success else {
            return finish(action: leaf, exitPosition: .current)
        }
        guard let predicate = leaf.predicate,
              !predicate.isNotification else {
            activeLeaf = .action(leaf)
            return .pending(.wait)
        }
        guard predicate.resolved.watchTarget != nil else {
            activeLeaf = .action(leaf)
            return .pending(.wait)
        }
        leaf.phase = .exploring(expectation, dispatch: dispatch)
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
        let requestID = nextID()
        leaf.phase = .finishingObservation(
            requestID,
            expectation: leaf.expectation
        )
        return update(
            wait: leaf,
            performing: [.finishObservation(
                requestID: requestID,
                observationID: leaf.id,
                exitPosition: exitPosition
            )]
        )
    }

    mutating func observe(
        wait leaf: HeistExecution.WaitLeaf,
        event: Observation.Event
    ) -> HeistExecution.State {
        var leaf = leaf
        switch leaf.phase {
        case .finishingObservation(_, let current):
            guard case .noChange = event else {
                leaf.phase = .observing(current)
                return observe(wait: leaf, event: event)
            }
            return .pending(.wait)
        case .observing(let current):
            let evaluated = expectation(current, evaluating: event)
            guard evaluated.result == .satisfied else {
                if !evaluated.isWaitingOnlyForNoChange,
                   shouldExplore(after: event, for: leaf.predicate) {
                    leaf.phase = .exploring(evaluated)
                    return update(
                        wait: leaf,
                        performing: [.explore(leaf.id, leaf.predicate)]
                    )
                }
                leaf.phase = .observing(evaluated)
                activeLeaf = .wait(leaf)
                return .pending(.wait)
            }
            leaf.phase = .observing(evaluated)
            return finish(wait: leaf, exitPosition: .current)
        case .exploring(let current):
            let evaluated = expectation(current, evaluating: event)
            leaf.phase = .exploring(evaluated)
            guard evaluated.result == .satisfied else {
                activeLeaf = .wait(leaf)
                return .pending(.wait)
            }
            return finish(wait: leaf, exitPosition: .current)
        case .beginningObservation:
            return .pending(.wait)
        }
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

    func expectation(
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
