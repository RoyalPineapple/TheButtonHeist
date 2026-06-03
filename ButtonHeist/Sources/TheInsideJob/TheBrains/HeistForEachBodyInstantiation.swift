#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

enum HeistForEachBodyInstantiationError: Error, Equatable, Sendable, CustomStringConvertible {
    case nestedForEachUnsupported

    var description: String {
        switch self {
        case .nestedForEachUnsupported:
            return "nested runtime for_each is not supported"
        }
    }
}

enum HeistForEachBodyInstantiation {
    static func instantiate(
        steps: [HeistStep],
        templateElement: ElementTarget,
        currentElement: ElementTarget
    ) throws -> [HeistStep] {
        try steps.map {
            try $0.instantiatingForEachElement(templateElement, with: currentElement)
        }
    }
}

private extension ElementTarget {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) -> ElementTarget {
        self == templateElement ? currentElement : self
    }
}

private extension HeistStep {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) throws -> HeistStep {
        switch self {
        case .action(let step):
            return .action(try step.instantiatingForEachElement(templateElement, with: currentElement))
        case .wait(let step):
            return .wait(step.instantiatingForEachElement(templateElement, with: currentElement))
        case .conditional(let step):
            return .conditional(try step.instantiatingForEachElement(templateElement, with: currentElement))
        case .waitForCases(let step):
            return .waitForCases(try step.instantiatingForEachElement(templateElement, with: currentElement))
        case .forEach:
            throw HeistForEachBodyInstantiationError.nestedForEachUnsupported
        case .warn, .fail:
            return self
        }
    }
}

private extension ActionStep {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) throws -> ActionStep {
        try ActionStep(
            command: command.instantiatingForEachElement(templateElement, with: currentElement),
            expectation: expectation?.instantiatingForEachElement(templateElement, with: currentElement),
            expectationWaiver: expectationWaiver
        )
    }
}

private extension WaitStep {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) -> WaitStep {
        WaitStep(
            predicate: predicate.instantiatingForEachElement(templateElement, with: currentElement),
            timeout: timeout
        )
    }
}

private extension ConditionalStep {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) throws -> ConditionalStep {
        try ConditionalStep(
            cases: cases.map {
                try $0.instantiatingForEachElement(templateElement, with: currentElement)
            },
            elseSteps: elseSteps.map { steps in
                try steps.map {
                    try $0.instantiatingForEachElement(templateElement, with: currentElement)
                }
            }
        )
    }
}

private extension WaitForCasesStep {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) throws -> WaitForCasesStep {
        try WaitForCasesStep(
            timeout: timeout,
            cases: cases.map {
                try $0.instantiatingForEachElement(templateElement, with: currentElement)
            },
            elseSteps: elseSteps.map { steps in
                try steps.map {
                    try $0.instantiatingForEachElement(templateElement, with: currentElement)
                }
            }
        )
    }
}

private extension PredicateCase {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) throws -> PredicateCase {
        PredicateCase(
            predicate: predicate.instantiatingForEachElement(templateElement, with: currentElement),
            steps: try steps.map {
                try $0.instantiatingForEachElement(templateElement, with: currentElement)
            }
        )
    }
}

private extension ClientMessage {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) -> ClientMessage {
        switch self {
        case .activate(let target):
            return .activate(target.instantiatingForEachElement(templateElement, with: currentElement))
        case .increment(let target):
            return .increment(target.instantiatingForEachElement(templateElement, with: currentElement))
        case .decrement(let target):
            return .decrement(target.instantiatingForEachElement(templateElement, with: currentElement))
        case .performCustomAction(let target):
            return .performCustomAction(CustomActionTarget(
                elementTarget: target.elementTarget.instantiatingForEachElement(templateElement, with: currentElement),
                actionName: target.actionName
            ))
        case .rotor(let target):
            return .rotor(RotorTarget(
                elementTarget: target.elementTarget.instantiatingForEachElement(templateElement, with: currentElement),
                selection: target.selection,
                direction: target.direction
            ))
        case .oneFingerTap(let target):
            return .oneFingerTap(TapTarget(
                selection: target.selection.instantiatingForEachElement(templateElement, with: currentElement)
            ))
        case .longPress(let target):
            return .longPress(LongPressTarget(
                selection: target.selection.instantiatingForEachElement(templateElement, with: currentElement),
                duration: target.duration
            ))
        case .swipe(let target):
            return .swipe(SwipeTarget(
                selection: target.selection.instantiatingForEachElement(templateElement, with: currentElement),
                duration: target.duration
            ))
        case .drag(let target):
            return .drag(DragTarget(
                start: target.start.instantiatingForEachElement(templateElement, with: currentElement),
                end: target.end,
                duration: target.duration
            ))
        case .typeText(let target):
            return .typeText(TypeTextTarget(
                text: target.text,
                elementTarget: target.elementTarget.map {
                    $0.instantiatingForEachElement(templateElement, with: currentElement)
                }
            ))
        case .scroll(let target):
            return .scroll(ScrollTarget(
                selection: target.selection.instantiatingForEachElement(templateElement, with: currentElement),
                direction: target.direction
            ))
        case .scrollToVisible(let target):
            return .scrollToVisible(ScrollToVisibleTarget(
                elementTarget: target.elementTarget.instantiatingForEachElement(templateElement, with: currentElement)
            ))
        case .scrollToEdge(let target):
            return .scrollToEdge(ScrollToEdgeTarget(
                selection: target.selection.instantiatingForEachElement(templateElement, with: currentElement),
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
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) -> GesturePointSelection {
        switch self {
        case .element(let target):
            return .element(target.instantiatingForEachElement(templateElement, with: currentElement))
        case .coordinate:
            return self
        }
    }
}

private extension SwipeGestureSelection {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) -> SwipeGestureSelection {
        switch self {
        case .unitElement(let target, let start, let end):
            return .unitElement(
                target.instantiatingForEachElement(templateElement, with: currentElement),
                start: start,
                end: end
            )
        case .elementDirection(let target, let direction):
            return .elementDirection(
                target.instantiatingForEachElement(templateElement, with: currentElement),
                direction
            )
        case .point(let start, let destination):
            return .point(
                start: start.instantiatingForEachElement(templateElement, with: currentElement),
                destination: destination
            )
        }
    }
}

private extension ScrollContainerSelection {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) -> ScrollContainerSelection {
        switch self {
        case .element(let target):
            return .element(target.instantiatingForEachElement(templateElement, with: currentElement))
        case .visibleContainer:
            return self
        }
    }
}

private extension AccessibilityPredicate {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) -> AccessibilityPredicate {
        switch self {
        case .state(let state):
            return .state(state.instantiatingForEachElement(templateElement, with: currentElement))
        case .changed(let change):
            return .changed(change.instantiatingForEachElement(templateElement, with: currentElement))
        }
    }
}

private extension AccessibilityPredicate.State {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) -> AccessibilityPredicate.State {
        switch self {
        case .present, .absent:
            return self
        case .presentTarget(let target):
            return .presentTarget(target.instantiatingForEachElement(templateElement, with: currentElement))
        case .absentTarget(let target):
            return .absentTarget(target.instantiatingForEachElement(templateElement, with: currentElement))
        case .all(let states):
            return .all(states.map {
                $0.instantiatingForEachElement(templateElement, with: currentElement)
            })
        }
    }
}

private extension AccessibilityPredicate.Change {
    func instantiatingForEachElement(
        _ templateElement: ElementTarget,
        with currentElement: ElementTarget
    ) -> AccessibilityPredicate.Change {
        switch self {
        case .screen(let state):
            return .screen(where: state?.instantiatingForEachElement(templateElement, with: currentElement))
        case .elements, .appeared, .disappeared, .updated:
            return self
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
