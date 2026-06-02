#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    func executeForEachStep(
        _ step: ForEachStep,
        index: Int,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime
    ) async -> HeistExecutionStepResult {
        guard let observation = await runtime.observeSemanticState(.discovery, nil, nil) else {
            return HeistExecutionStepResult(
                index: index,
                kind: .forEach,
                message: "Could not observe settled semantic hierarchy before evaluating for_each",
                durationMs: elapsedMilliseconds(since: start),
                stopsHeist: true,
                forEachResult: HeistForEachResult(
                    matchedCount: 0,
                    limit: step.limit,
                    iterationCount: 0,
                    failureReason: "semantic hierarchy unavailable"
                )
            )
        }

        var matchSignature = ForEachMatchSignature(
            matching: step.matching,
            elements: observation.state.interface.projectedElements
        )
        let matchedCount = matchSignature.count
        if matchedCount > step.limit {
            let reason = "matched \(matchedCount) element(s), exceeding for_each limit \(step.limit)"
            return HeistExecutionStepResult(
                index: index,
                kind: .forEach,
                message: reason,
                durationMs: elapsedMilliseconds(since: start),
                stopsHeist: true,
                forEachResult: HeistForEachResult(
                    matchedCount: matchedCount,
                    limit: step.limit,
                    iterationCount: 0,
                    failureReason: reason
                )
            )
        }

        var childResults: [HeistExecutionStepResult] = []
        var failureReason: String?
        var iterationCount = 0
        var nextOrdinal = 0
        var observedSequence = observation.event.sequence

        while iterationCount < matchedCount {
            let iterationSteps: [HeistStep]
            do {
                iterationSteps = try step.steps(forOrdinal: nextOrdinal)
            } catch {
                failureReason = "iteration \(iterationCount) ordinal expansion failed: \(error)"
                break
            }

            let iterationResults = await executeHeistSteps(iterationSteps, runtime: runtime)
            iterationCount += 1

            for result in iterationResults {
                childResults.append(result.reindexed(childResults.count))
            }

            if iterationResults.contains(where: \.isFailure) {
                failureReason = "iteration \(iterationCount - 1) failed"
                break
            }

            guard iterationCount < matchedCount else { break }
            guard let afterObservation = await runtime.observeSemanticState(
                .discovery,
                observedSequence,
                nil
            ) else {
                failureReason = "iteration \(iterationCount - 1) post-observation unavailable"
                break
            }
            observedSequence = afterObservation.event.sequence
            let nextSignature = ForEachMatchSignature(
                matching: step.matching,
                elements: afterObservation.state.interface.projectedElements
            )
            if nextSignature == matchSignature {
                nextOrdinal += 1
            } else {
                matchSignature = nextSignature
                nextOrdinal = 0
            }
        }

        return HeistExecutionStepResult(
            index: index,
            kind: .forEach,
            message: forEachMessage(
                matchedCount: matchedCount,
                iterationCount: iterationCount,
                failureReason: failureReason
            ),
            durationMs: elapsedMilliseconds(since: start),
            stopsHeist: failureReason != nil,
            forEachResult: HeistForEachResult(
                matchedCount: matchedCount,
                limit: step.limit,
                iterationCount: iterationCount,
                failureReason: failureReason
            ),
            childResults: childResults.isEmpty ? nil : childResults
        )
    }

    private func forEachMessage(
        matchedCount: Int,
        iterationCount: Int,
        failureReason: String?
    ) -> String {
        if let failureReason {
            return "for_each stopped after \(iterationCount) of \(matchedCount) iteration(s): \(failureReason)"
        }
        return "for_each completed \(iterationCount) iteration(s) from \(matchedCount) matched element(s)"
    }
}

private struct ForEachMatchSignature: Equatable {
    let keys: [String]

    var count: Int { keys.count }

    init(matching: ElementPredicate, elements: [HeistElement]) {
        keys = elements
            .filter { matching.matches($0) }
            .map(Self.key)
    }

    private static func key(for element: HeistElement) -> String {
        AccessibilityPolicy.matcherIdentityFacts(for: element)
            .map(factKey)
            .joined(separator: "\u{1F}")
    }

    private static func factKey(_ fact: AccessibilityMatcherFact) -> String {
        switch fact {
        case .identifier(let identifier):
            return "identifier=\(identifier)"
        case .label(let label):
            return "label=\(label)"
        case .value(let value):
            return "value=\(value)"
        case .trait(let trait):
            return "trait=\(trait.rawValue)"
        case .excludedTrait(let trait):
            return "excludeTrait=\(trait.rawValue)"
        }
    }
}

private extension ForEachStep {
    func steps(forOrdinal index: Int) throws -> [HeistStep] {
        try steps.map {
            try $0.replacingForEachTarget(matching: matching, ordinal: index)
        }
    }
}

private extension ElementTarget {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) -> ElementTarget {
        switch self {
        case .predicate(let predicate, let ordinal?) where predicate == matching && ordinal == 0:
            return .predicate(matching, ordinal: ordinal)
        case .predicate:
            return self
        }
    }
}

private extension HeistStep {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) throws -> HeistStep {
        switch self {
        case .action(let step):
            return .action(try step.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .wait(let step):
            return .wait(step.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .conditional(let step):
            return .conditional(try step.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .waitForCases(let step):
            return .waitForCases(try step.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .forEach(let step):
            return .forEach(try step.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .warn, .fail:
            return self
        }
    }
}

private extension ActionStep {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) throws -> ActionStep {
        try ActionStep(
            command: command.replacingForEachTarget(matching: matching, ordinal: ordinal),
            expectation: expectation?.replacingForEachTarget(matching: matching, ordinal: ordinal)
        )
    }
}

private extension WaitStep {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) -> WaitStep {
        WaitStep(
            predicate: predicate.replacingForEachTarget(matching: matching, ordinal: ordinal),
            timeout: timeout
        )
    }
}

private extension ConditionalStep {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) throws -> ConditionalStep {
        try ConditionalStep(
            cases: cases.map {
                try $0.replacingForEachTarget(matching: matching, ordinal: ordinal)
            },
            elseSteps: elseSteps.map { steps in
                try steps.map {
                    try $0.replacingForEachTarget(matching: matching, ordinal: ordinal)
                }
            }
        )
    }
}

private extension WaitForCasesStep {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) throws -> WaitForCasesStep {
        try WaitForCasesStep(
            timeout: timeout,
            cases: cases.map {
                try $0.replacingForEachTarget(matching: matching, ordinal: ordinal)
            },
            elseSteps: elseSteps.map { steps in
                try steps.map {
                    try $0.replacingForEachTarget(matching: matching, ordinal: ordinal)
                }
            }
        )
    }
}

private extension PredicateCase {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) throws -> PredicateCase {
        PredicateCase(
            predicate: predicate.replacingForEachTarget(matching: matching, ordinal: ordinal),
            steps: try steps.map {
                try $0.replacingForEachTarget(matching: matching, ordinal: ordinal)
            }
        )
    }
}

private extension ForEachStep {
    func replacingForEachTarget(matching outerMatching: ElementPredicate, ordinal: Int) throws -> ForEachStep {
        try ForEachStep(
            matching: matching,
            limit: limit,
            steps: try steps.map {
                try $0.replacingForEachTarget(matching: outerMatching, ordinal: ordinal)
            }
        )
    }
}

private extension ClientMessage {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) -> ClientMessage {
        switch self {
        case .activate(let target):
            return .activate(target.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .increment(let target):
            return .increment(target.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .decrement(let target):
            return .decrement(target.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .performCustomAction(let target):
            return .performCustomAction(CustomActionTarget(
                elementTarget: target.elementTarget.replacingForEachTarget(
                    matching: matching,
                    ordinal: ordinal
                ),
                actionName: target.actionName
            ))
        case .rotor(let target):
            return .rotor(RotorTarget(
                elementTarget: target.elementTarget.replacingForEachTarget(
                    matching: matching,
                    ordinal: ordinal
                ),
                selection: target.selection,
                direction: target.direction
            ))
        case .oneFingerTap(let target):
            return .oneFingerTap(TapTarget(
                selection: target.selection.replacingForEachTarget(
                    matching: matching,
                    ordinal: ordinal
                )
            ))
        case .longPress(let target):
            return .longPress(LongPressTarget(
                selection: target.selection.replacingForEachTarget(
                    matching: matching,
                    ordinal: ordinal
                ),
                duration: target.duration
            ))
        case .swipe(let target):
            return .swipe(SwipeTarget(
                selection: target.selection.replacingForEachTarget(
                    matching: matching,
                    ordinal: ordinal
                ),
                duration: target.duration
            ))
        case .drag(let target):
            return .drag(DragTarget(
                start: target.start.replacingForEachTarget(matching: matching, ordinal: ordinal),
                end: target.end,
                duration: target.duration
            ))
        case .typeText(let target):
            return .typeText(TypeTextTarget(
                text: target.text,
                elementTarget: target.elementTarget.map {
                    $0.replacingForEachTarget(matching: matching, ordinal: ordinal)
                }
            ))
        case .scroll(let target):
            return .scroll(ScrollTarget(
                selection: target.selection.replacingForEachTarget(
                    matching: matching,
                    ordinal: ordinal
                ),
                direction: target.direction
            ))
        case .scrollToVisible(let target):
            return .scrollToVisible(ScrollToVisibleTarget(
                elementTarget: target.elementTarget.replacingForEachTarget(
                    matching: matching,
                    ordinal: ordinal
                )
            ))
        case .elementSearch(let target):
            return .elementSearch(ElementSearchTarget(
                elementTarget: target.elementTarget.replacingForEachTarget(
                    matching: matching,
                    ordinal: ordinal
                ),
                direction: target.direction
            ))
        case .scrollToEdge(let target):
            return .scrollToEdge(ScrollToEdgeTarget(
                selection: target.selection.replacingForEachTarget(
                    matching: matching,
                    ordinal: ordinal
                ),
                edge: target.edge
            ))
        case .clientHello, .authenticate, .requestInterface, .ping, .status,
             .editAction, .setPasteboard, .resignFirstResponder,
             .getPasteboard, .wait, .heistPlan, .requestScreen:
            return self
        }
    }
}

private extension GesturePointSelection {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) -> GesturePointSelection {
        switch self {
        case .element(let target):
            return .element(target.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .coordinate:
            return self
        }
    }
}

private extension SwipeGestureSelection {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) -> SwipeGestureSelection {
        switch self {
        case .unitElement(let target, let start, let end):
            return .unitElement(
                target.replacingForEachTarget(matching: matching, ordinal: ordinal),
                start: start,
                end: end
            )
        case .elementDirection(let target, let direction):
            return .elementDirection(
                target.replacingForEachTarget(matching: matching, ordinal: ordinal),
                direction
            )
        case .point(let start, let destination):
            return .point(
                start: start.replacingForEachTarget(matching: matching, ordinal: ordinal),
                destination: destination
            )
        }
    }
}

private extension ScrollContainerSelection {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) -> ScrollContainerSelection {
        switch self {
        case .element(let target):
            return .element(target.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .visibleContainer, .container:
            return self
        }
    }
}

private extension AccessibilityPredicate {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) -> AccessibilityPredicate {
        switch self {
        case .state(let state):
            return .state(state.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .changed(let change):
            return .changed(change.replacingForEachTarget(matching: matching, ordinal: ordinal))
        }
    }
}

private extension AccessibilityPredicate.State {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) -> AccessibilityPredicate.State {
        switch self {
        case .present, .absent:
            return self
        case .presentTarget(let target):
            return .presentTarget(target.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .absentTarget(let target):
            return .absentTarget(target.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .all(let states):
            return .all(states.map {
                $0.replacingForEachTarget(matching: matching, ordinal: ordinal)
            })
        }
    }
}

private extension AccessibilityPredicate.Change {
    func replacingForEachTarget(matching: ElementPredicate, ordinal: Int) -> AccessibilityPredicate.Change {
        switch self {
        case .screen(let state):
            return .screen(where: state?.replacingForEachTarget(matching: matching, ordinal: ordinal))
        case .elements, .appeared, .disappeared, .updated:
            return self
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
