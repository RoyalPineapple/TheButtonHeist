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
        guard let activeLeaf = running.activeLeaf else { return .wait }
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
        running.activeLeaf = nil
        if case .sequence(var sequence)? = running.continuations.last {
            running.continuations.removeLast()
            sequence.children.append(result)
            running.continuations.append(.sequence(sequence))
            return advanceExecution()
        }
        guard running.continuations.isEmpty, case .action = running.root else {
            preconditionFailure("A completed plan leaf requires an active sequence")
        }
        return finish(children: HeistPassingChildren.empty.appending(result))
    }
}

extension HeistExecution.Machine {
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
                leaf.expectation.predicates,
                baseline: baseline
            )
            leaf.phase = .dispatching(expectation)
            return update(
                .action(leaf),
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
                guard let predicate = leaf.expectation.authoredPredicate else {
                    preconditionFailure("A superseded action discovery requires a predicate")
                }
                return update(
                    .action(leaf),
                    performing: .explore(leaf.id, predicate)
                )
            case .restored, .retained:
                leaf.phase = .observing(expectation, dispatch: dispatch)
                running.activeLeaf = .action(leaf)
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
                running.activeLeaf = .wait(leaf)
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
                return update(.wait(leaf), performing: .explore(leaf.id, leaf.predicate))
            case .restored, .retained:
                leaf.phase = .observing(expectation)
                running.activeLeaf = .wait(leaf)
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
            let expectation = HeistExecution.ResultProjector.expectationEvidence(
                leaf.predicate,
                observation: evidence,
                outcome: outcome,
                timing: timing
            )
            switch leaf.purpose {
            case .repeatCheck(let loop, let bodyChildren):
                return resumeRepeatCheck(
                    loop,
                    bodyChildren: bodyChildren,
                    expectation: expectation
                )
            case .authored(let step, let context):
                return resumeAuthoredWait(
                    step: step,
                    context: context,
                    expectation: expectation,
                    outcome: outcome
                )
            }

        case .currentSnapshot, .dispatchCompleted, .failureScreenshotCaptured:
            return .wait
        }
    }

    mutating func resumeAuthoredWait(
        step: WaitStep,
        context: HeistExecution.StepContext,
        expectation: HeistExpectationEvidence,
        outcome: HeistExecution.LeafOutcome
    ) -> HeistExecution.Decision {
        let result = HeistExecution.ResultProjector.project(
            wait: step,
            path: context.path,
            expectation: expectation,
            outcome: outcome
        )
        guard outcome == .timedOut,
              let evidence = result.waitEvidence,
              let fallbackEvidence = HeistPassedWaitEvidence(evidence),
              fallbackEvidence.usesFallback,
              let elseBody = step.elseBody else {
            return resume(afterCompletedLeaf: result)
        }
        running.activeLeaf = nil
        running.continuations.append(.waitElse(HeistExecution.WaitElseContinuation(
            step: step,
            context: context,
            evidence: fallbackEvidence
        )))
        running.continuations.append(.sequence(HeistExecution.SequenceContinuation(
            steps: elseBody,
            context: HeistExecution.StepContext(
                path: context.path.waitElseBody(),
                environment: context.environment,
                scope: context.scope
            ),
            nextIndex: 0,
            children: .empty
        )))
        return advanceExecution()
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
        var canPrepareTarget = false
        if case .elementsChanged(let assertions) = leaf.predicate.resolved, assertions.count == 1 {
            switch assertions[0] {
            case .exists, .disappeared, .updated:
                canPrepareTarget = true
            case .missing, .appeared:
                break
            }
        }
        guard predicateExpectation.result != .satisfied,
              !predicateExpectation.hasMatchedTemporalBaseline,
              canPrepareTarget else {
            leaf.phase = .observing(expectation)
            running.activeLeaf = .wait(leaf)
            return .wait
        }
        leaf.phase = .exploring(expectation)
        return update(.wait(leaf), performing: .explore(leaf.id, leaf.predicate))
    }

    mutating func finish(
        action leaf: HeistExecution.ActionLeaf,
        exitPosition: Navigation.ViewportExitPosition
    ) -> HeistExecution.Decision {
        var leaf = leaf
        guard let dispatch = leaf.phase.dispatch else {
            return .wait
        }
        guard let expectation = leaf.phase.expectation else {
            preconditionFailure("An action expectation exists after observation begins")
        }
        let requestID = nextID()
        leaf.phase = .finishingObservation(
            requestID,
            expectation: expectation,
            dispatch: dispatch
        )
        return update(
            .action(leaf),
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
                running.activeLeaf = .action(leaf)
                return .wait
            }
            return .wait
        case .observing(let current, let dispatch):
            let evaluated = expectation(
                current,
                evaluating: event
            )
            guard evaluated.result == .satisfied else {
                if leaf.expectation.authoredPredicate?.resolved.watchTarget != nil,
                   !evaluated.isWaitingOnlyForNoChange,
                   shouldExplore(after: event, for: leaf.expectation.authoredPredicate) {
                    guard let predicate = leaf.expectation.authoredPredicate else {
                        preconditionFailure("An observing action without a predicate cannot request discovery")
                    }
                    leaf.phase = .exploring(evaluated, dispatch: dispatch)
                    return update(
                        .action(leaf),
                        performing: .explore(leaf.id, predicate)
                    )
                }
                leaf.phase = .observing(evaluated, dispatch: dispatch)
                running.activeLeaf = .action(leaf)
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
                running.activeLeaf = .action(leaf)
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
        guard let predicate = leaf.expectation.authoredPredicate,
              !predicate.isNotification,
              predicate.resolved.watchTarget != nil else {
            running.activeLeaf = .action(leaf)
            return .wait
        }
        leaf.phase = .exploring(expectation, dispatch: dispatch)
        return update(
            .action(leaf),
            performing: .explore(leaf.id, predicate)
        )
    }

    mutating func finish(
        wait leaf: HeistExecution.WaitLeaf,
        exitPosition: Navigation.ViewportExitPosition
    ) -> HeistExecution.Decision {
        var leaf = leaf
        guard let expectation = leaf.phase.expectation else {
            preconditionFailure("A wait expectation exists after observation begins")
        }
        let requestID = nextID()
        leaf.phase = .finishingObservation(
            requestID,
            expectation: expectation
        )
        return update(
            .wait(leaf),
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
                        .wait(leaf),
                        performing: .explore(leaf.id, leaf.predicate)
                    )
                }
                leaf.phase = .observing(evaluated)
                running.activeLeaf = .wait(leaf)
                return .wait
            }
            leaf.phase = .observing(evaluated)
            return finish(wait: leaf, exitPosition: .current)
        case .exploring(let current):
            let evaluated = expectation(current, evaluating: event)
            leaf.phase = .exploring(evaluated)
            guard evaluated.result == .satisfied else {
                running.activeLeaf = .wait(leaf)
                return .wait
            }
            return finish(wait: leaf, exitPosition: .current)
        case .beginningObservation:
            return .wait
        }
    }

    mutating func update(
        _ leaf: HeistExecution.ActiveLeaf,
        performing request: HeistExecution.MainActorRequest
    ) -> HeistExecution.Decision {
        running.activeLeaf = leaf
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
        expectation.evaluating(event)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
