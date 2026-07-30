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
    ) -> HeistExecution.Decision {
        guard let activeLeaf else { return .wait }
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
    ) -> HeistExecution.Decision {
        activeLeaf = nil
        if case .sequence(var sequence)? = continuations.last {
            continuations.removeLast()
            sequence.children.append(result)
            continuations.append(.sequence(sequence))
            return advanceExecution()
        }
        guard continuations.isEmpty, case .action = root else {
            preconditionFailure("A completed plan leaf requires an active sequence")
        }
        rootChildren.append(result)
        return finish(children: rootChildren)
    }
}

private extension HeistExecution.Machine {
    mutating func advance(
        action leaf: HeistExecution.ActionLeaf,
        input: HeistExecution.Input
    ) -> HeistExecution.Decision {
        var leaf = leaf
        switch input {
        case .observationBegan(let id, let baseline):
            guard id == leaf.id,
                  case .beginningObservation = leaf.phase else {
                return .wait
            }
            let expectation = Expectation(
                leaf.predicate.map { [$0.resolved, .noChange] } ?? [.noChange],
                baseline: baseline
            )
            leaf.phase = .dispatching(expectation)
            return update(
                action: leaf,
                performing: .dispatch(leaf.id, leaf.command)
            )

        case .event(let event):
            return observe(action: leaf, event: event)

        case .dispatchCompleted(let id, let dispatch):
            guard id == leaf.id,
                  case .dispatching(let expectation) = leaf.phase else {
                return .wait
            }
            return completeDispatch(
                action: leaf,
                expectation: expectation,
                dispatch: dispatch
            )

        case .viewportExited(let id, let outcome):
            guard id == leaf.id,
                  case .exploring(let expectation, let dispatch) = leaf.phase else {
                return .wait
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
                    performing: .explore(leaf.id, predicate)
                )
            case .restored, .retained:
                leaf.phase = .observing(expectation, dispatch: dispatch)
                activeLeaf = .action(leaf)
                return .wait
            }

        case .observationFinished(
            let source,
            let observationID,
            let evidence,
            let outcome,
            let timing
        ):
            guard observationID == leaf.id,
                  HeistExecution.ActiveLeaf.action(leaf).admits(source) else {
                return .wait
            }
            let result = HeistExecution.ResultProjector.project(
                action: leaf,
                evidence: evidence,
                outcome: outcome,
                timing: timing
            )
            return resume(afterCompletedLeaf: result)

        case .currentSnapshot, .failureScreenshotCaptured:
            return .wait
        }
    }

    mutating func advance(
        wait leaf: HeistExecution.WaitLeaf,
        input: HeistExecution.Input
    ) -> HeistExecution.Decision {
        var leaf = leaf
        switch input {
        case .observationBegan(let id, let baseline):
            guard id == leaf.id,
                  case .beginningObservation = leaf.phase else {
                return .wait
            }
            if leaf.predicate.isNotification {
                leaf.phase = .observing(Expectation([
                    leaf.predicate.resolved,
                    .noChange,
                ]))
                activeLeaf = .wait(leaf)
                return .wait
            }
            return begin(wait: leaf, baseline: baseline)

        case .event(let event):
            return observe(wait: leaf, event: event)

        case .viewportExited(let id, let outcome):
            guard id == leaf.id,
                  case .exploring(let expectation) = leaf.phase else {
                return .wait
            }
            switch outcome {
            case .failed:
                return finish(wait: leaf, exitPosition: .current)
            case .superseded:
                return update(
                    wait: leaf,
                    performing: .explore(leaf.id, leaf.predicate)
                )
            case .restored, .retained:
                leaf.phase = .observing(expectation)
                activeLeaf = .wait(leaf)
                return .wait
            }

        case .observationFinished(
            let source,
            let observationID,
            let evidence,
            let outcome,
            let timing
        ):
            guard observationID == leaf.id,
                  HeistExecution.ActiveLeaf.wait(leaf).admits(source) else {
                return .wait
            }
            if case .beginningObservation = leaf.phase {
                leaf.phase = .observing(Expectation([leaf.predicate.resolved]))
            }
            let result = HeistExecution.ResultProjector.project(
                wait: leaf,
                evidence: evidence,
                outcome: outcome,
                timing: timing
            )
            guard outcome == .timedOut,
                  let evidence = result.waitEvidence,
                  let fallbackEvidence = HeistPassedWaitEvidence(evidence),
                  fallbackEvidence.usesFallback,
                  let elseBody = leaf.step.elseBody else {
                return resume(afterCompletedLeaf: result)
            }
            activeLeaf = nil
            continuations.append(.waitElse(HeistExecution.WaitElseContinuation(
                step: leaf.step,
                context: leaf.context,
                evidence: fallbackEvidence
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
            return .wait
        }
    }

    mutating func begin(
        wait leaf: HeistExecution.WaitLeaf,
        baseline: Observation.Snapshot?
    ) -> HeistExecution.Decision {
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
            return .wait
        }
        guard leaf.predicate.resolved.canPrepareTargetThroughExploration,
              !predicateExpectation.hasMatchedTemporalBaseline else {
            leaf.phase = .observing(expectation)
            activeLeaf = .wait(leaf)
            return .wait
        }
        leaf.phase = .exploring(expectation)
        return update(
            wait: leaf,
            performing: .explore(leaf.id, leaf.predicate)
        )
    }

    mutating func finish(
        action leaf: HeistExecution.ActionLeaf,
        exitPosition: Navigation.ViewportExitPosition
    ) -> HeistExecution.Decision {
        var leaf = leaf
        guard let dispatch = leaf.dispatch else {
            return .wait
        }
        let requestID = nextID()
        leaf.phase = .finishingObservation(
            requestID,
            expectation: leaf.expectation,
            dispatch: dispatch
        )
        return update(
            action: leaf,
            performing: .finishObservation(
                requestID: requestID,
                observationID: leaf.id,
                exitPosition: exitPosition
            )
        )
    }

    mutating func observe(
        action leaf: HeistExecution.ActionLeaf,
        event: Observation.Event
    ) -> HeistExecution.Decision {
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
                return .wait
            }
            return .wait
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
                        performing: .explore(leaf.id, predicate)
                    )
                }
                leaf.phase = .observing(evaluated, dispatch: dispatch)
                activeLeaf = .action(leaf)
                return .wait
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
                return .wait
            }
            return finish(action: leaf, exitPosition: .current)
        case .finishingObservation(_, let current, let dispatch):
            guard case .noChange = event else {
                leaf.phase = .observing(current, dispatch: dispatch)
                return observe(action: leaf, event: event)
            }
            return .wait
        case .beginningObservation:
            return .wait
        }
    }

    mutating func completeDispatch(
        action leaf: HeistExecution.ActionLeaf,
        expectation: Expectation,
        dispatch: TheSafecracker.ActionDispatchResult
    ) -> HeistExecution.Decision {
        var leaf = leaf
        leaf.phase = .observing(expectation, dispatch: dispatch)
        guard dispatch.success else {
            return finish(action: leaf, exitPosition: .current)
        }
        guard let predicate = leaf.predicate,
              !predicate.isNotification else {
            activeLeaf = .action(leaf)
            return .wait
        }
        guard predicate.resolved.watchTarget != nil else {
            activeLeaf = .action(leaf)
            return .wait
        }
        leaf.phase = .exploring(expectation, dispatch: dispatch)
        return update(
            action: leaf,
            performing: .explore(leaf.id, predicate)
        )
    }

    mutating func finish(
        wait leaf: HeistExecution.WaitLeaf,
        exitPosition: Navigation.ViewportExitPosition
    ) -> HeistExecution.Decision {
        var leaf = leaf
        let requestID = nextID()
        leaf.phase = .finishingObservation(
            requestID,
            expectation: leaf.expectation
        )
        return update(
            wait: leaf,
            performing: .finishObservation(
                requestID: requestID,
                observationID: leaf.id,
                exitPosition: exitPosition
            )
        )
    }

    mutating func observe(
        wait leaf: HeistExecution.WaitLeaf,
        event: Observation.Event
    ) -> HeistExecution.Decision {
        var leaf = leaf
        switch leaf.phase {
        case .finishingObservation(_, let current):
            guard case .noChange = event else {
                leaf.phase = .observing(current)
                return observe(wait: leaf, event: event)
            }
            return .wait
        case .observing(let current):
            let evaluated = expectation(current, evaluating: event)
            guard evaluated.result == .satisfied else {
                if !evaluated.isWaitingOnlyForNoChange,
                   shouldExplore(after: event, for: leaf.predicate) {
                    leaf.phase = .exploring(evaluated)
                    return update(
                        wait: leaf,
                        performing: .explore(leaf.id, leaf.predicate)
                    )
                }
                leaf.phase = .observing(evaluated)
                activeLeaf = .wait(leaf)
                return .wait
            }
            leaf.phase = .observing(evaluated)
            return finish(wait: leaf, exitPosition: .current)
        case .exploring(let current):
            let evaluated = expectation(current, evaluating: event)
            leaf.phase = .exploring(evaluated)
            guard evaluated.result == .satisfied else {
                activeLeaf = .wait(leaf)
                return .wait
            }
            return finish(wait: leaf, exitPosition: .current)
        case .beginningObservation:
            return .wait
        }
    }

    mutating func update(
        action leaf: HeistExecution.ActionLeaf,
        performing request: HeistExecution.MainActorRequest
    ) -> HeistExecution.Decision {
        activeLeaf = .action(leaf)
        return .perform(request)
    }

    mutating func update(
        wait leaf: HeistExecution.WaitLeaf,
        performing request: HeistExecution.MainActorRequest
    ) -> HeistExecution.Decision {
        activeLeaf = .wait(leaf)
        return .perform(request)
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

private extension ObservationPredicate {
    var canPrepareTargetThroughExploration: Bool {
        guard case .elementsChanged(let assertions) = self,
              assertions.count == 1 else {
            return false
        }
        switch assertions[0] {
        case .exists, .disappeared, .updated:
            return true
        case .missing, .appeared:
            return false
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
