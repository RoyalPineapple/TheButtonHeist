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

        let matchedCount = observation.state.interface.projectedElements.count { step.matching.matches($0) }
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

        for iterationIndex in 0..<matchedCount {
            let iterationSteps: [HeistStep]
            do {
                iterationSteps = try step.boundSteps(forIteration: iterationIndex)
            } catch {
                failureReason = "iteration \(iterationIndex) binding failed: \(error)"
                break
            }

            let iterationResults = await executeHeistSteps(iterationSteps, runtime: runtime)
            iterationCount += 1

            for result in iterationResults {
                childResults.append(result.reindexed(childResults.count))
            }

            if iterationResults.contains(where: \.isFailure) {
                failureReason = "iteration \(iterationIndex) failed"
                break
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

private extension ForEachStep {
    func boundSteps(forIteration index: Int) throws -> [HeistStep] {
        try steps.map {
            try $0.replacingForEachTarget(matching: matching, iterationOrdinal: index)
        }
    }
}

private extension ElementTarget {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) -> ElementTarget {
        switch self {
        case .predicate(let predicate, let ordinal?) where predicate == matching && ordinal == 0:
            return .predicate(matching, ordinal: iterationOrdinal)
        case .predicate:
            return self
        }
    }
}

private extension HeistStep {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) throws -> HeistStep {
        switch self {
        case .action(let step):
            return .action(try step.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .wait(let step):
            return .wait(step.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .conditional(let step):
            return .conditional(try step.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .waitForCases(let step):
            return .waitForCases(try step.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .forEach(let step):
            return .forEach(try step.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .warn, .fail:
            return self
        }
    }
}

private extension ActionStep {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) throws -> ActionStep {
        try ActionStep(
            command: command.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal),
            expectation: expectation?.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal)
        )
    }
}

private extension WaitStep {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) -> WaitStep {
        WaitStep(
            predicate: predicate.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal),
            timeout: timeout
        )
    }
}

private extension ConditionalStep {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) throws -> ConditionalStep {
        try ConditionalStep(
            cases: cases.map {
                try $0.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal)
            },
            elseSteps: elseSteps.map { steps in
                try steps.map {
                    try $0.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal)
                }
            }
        )
    }
}

private extension WaitForCasesStep {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) throws -> WaitForCasesStep {
        try WaitForCasesStep(
            timeout: timeout,
            cases: cases.map {
                try $0.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal)
            },
            elseSteps: elseSteps.map { steps in
                try steps.map {
                    try $0.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal)
                }
            }
        )
    }
}

private extension PredicateCase {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) throws -> PredicateCase {
        PredicateCase(
            predicate: predicate.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal),
            steps: try steps.map {
                try $0.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal)
            }
        )
    }
}

private extension ForEachStep {
    func replacingForEachTarget(matching outerMatching: ElementPredicate, iterationOrdinal: Int) throws -> ForEachStep {
        try ForEachStep(
            matching: matching,
            limit: limit,
            steps: try steps.map {
                try $0.replacingForEachTarget(matching: outerMatching, iterationOrdinal: iterationOrdinal)
            }
        )
    }
}

private extension ClientMessage {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) -> ClientMessage {
        switch self {
        case .activate(let target):
            return .activate(target.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .increment(let target):
            return .increment(target.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .decrement(let target):
            return .decrement(target.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .performCustomAction(let target):
            return .performCustomAction(CustomActionTarget(
                elementTarget: target.elementTarget.replacingForEachTarget(
                    matching: matching,
                    iterationOrdinal: iterationOrdinal
                ),
                actionName: target.actionName
            ))
        case .rotor(let target):
            return .rotor(RotorTarget(
                elementTarget: target.elementTarget.replacingForEachTarget(
                    matching: matching,
                    iterationOrdinal: iterationOrdinal
                ),
                selection: target.selection,
                direction: target.direction
            ))
        case .oneFingerTap(let target):
            return .oneFingerTap(TapTarget(
                selection: target.selection.replacingForEachTarget(
                    matching: matching,
                    iterationOrdinal: iterationOrdinal
                )
            ))
        case .longPress(let target):
            return .longPress(LongPressTarget(
                selection: target.selection.replacingForEachTarget(
                    matching: matching,
                    iterationOrdinal: iterationOrdinal
                ),
                duration: target.duration
            ))
        case .swipe(let target):
            return .swipe(SwipeTarget(
                selection: target.selection.replacingForEachTarget(
                    matching: matching,
                    iterationOrdinal: iterationOrdinal
                ),
                duration: target.duration
            ))
        case .drag(let target):
            return .drag(DragTarget(
                start: target.start.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal),
                end: target.end,
                duration: target.duration
            ))
        case .typeText(let target):
            return .typeText(TypeTextTarget(
                text: target.text,
                elementTarget: target.elementTarget.map {
                    $0.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal)
                }
            ))
        case .scroll(let target):
            return .scroll(ScrollTarget(
                selection: target.selection.replacingForEachTarget(
                    matching: matching,
                    iterationOrdinal: iterationOrdinal
                ),
                direction: target.direction
            ))
        case .scrollToVisible(let target):
            return .scrollToVisible(ScrollToVisibleTarget(
                elementTarget: target.elementTarget.replacingForEachTarget(
                    matching: matching,
                    iterationOrdinal: iterationOrdinal
                )
            ))
        case .elementSearch(let target):
            return .elementSearch(ElementSearchTarget(
                elementTarget: target.elementTarget.replacingForEachTarget(
                    matching: matching,
                    iterationOrdinal: iterationOrdinal
                ),
                direction: target.direction
            ))
        case .scrollToEdge(let target):
            return .scrollToEdge(ScrollToEdgeTarget(
                selection: target.selection.replacingForEachTarget(
                    matching: matching,
                    iterationOrdinal: iterationOrdinal
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
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) -> GesturePointSelection {
        switch self {
        case .element(let target):
            return .element(target.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .coordinate:
            return self
        }
    }
}

private extension SwipeGestureSelection {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) -> SwipeGestureSelection {
        switch self {
        case .unitElement(let target, let start, let end):
            return .unitElement(
                target.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal),
                start: start,
                end: end
            )
        case .elementDirection(let target, let direction):
            return .elementDirection(
                target.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal),
                direction
            )
        case .point(let start, let destination):
            return .point(
                start: start.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal),
                destination: destination
            )
        }
    }
}

private extension ScrollContainerSelection {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) -> ScrollContainerSelection {
        switch self {
        case .element(let target):
            return .element(target.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .visibleContainer, .container:
            return self
        }
    }
}

private extension AccessibilityPredicate {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) -> AccessibilityPredicate {
        switch self {
        case .state(let state):
            return .state(state.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .changed(let change):
            return .changed(change.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        }
    }
}

private extension AccessibilityPredicate.State {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) -> AccessibilityPredicate.State {
        switch self {
        case .present, .absent:
            return self
        case .presentTarget(let target):
            return .presentTarget(target.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .absentTarget(let target):
            return .absentTarget(target.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .all(let states):
            return .all(states.map {
                $0.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal)
            })
        }
    }
}

private extension AccessibilityPredicate.Change {
    func replacingForEachTarget(matching: ElementPredicate, iterationOrdinal: Int) -> AccessibilityPredicate.Change {
        switch self {
        case .screen(let state):
            return .screen(where: state?.replacingForEachTarget(matching: matching, iterationOrdinal: iterationOrdinal))
        case .elements, .appeared, .disappeared, .updated:
            return self
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
