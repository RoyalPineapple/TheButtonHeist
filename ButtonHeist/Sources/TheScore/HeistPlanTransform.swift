import Foundation

public enum HeistPlanTransformError: Error, Equatable, Sendable, CustomStringConvertible {
    case nestedForEachBinding

    public var description: String {
        switch self {
        case .nestedForEachBinding:
            return "nested runtime for_each requires named bindings before it can be lowered safely"
        }
    }
}

public enum HeistPlanTransform {
    /// Lowers the implicit semantic `ForEach` body target for one iteration.
    ///
    /// Sentinel rule: inside a semantic `ForEach`, the body target emitted by the
    /// DSL is `ElementTarget.predicate(matching, ordinal: 0)`. Binding an
    /// iteration replaces only that exact sentinel with the current ordinal.
    /// Runtime `ForEach` nesting is rejected until the plan has named bindings;
    /// static Swift `ForEach` has already compiled away before this transform.
    public static func bindingForEachTarget(
        matching: ElementPredicate,
        ordinal: Int,
        in steps: [HeistStep]
    ) throws -> [HeistStep] {
        try steps.map {
            try $0.bindingForEachTarget(matching: matching, ordinal: ordinal)
        }
    }
}

private extension ElementTarget {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) -> ElementTarget {
        switch self {
        case .predicate(let predicate, let currentOrdinal?) where predicate == matching && currentOrdinal == 0:
            return .predicate(matching, ordinal: ordinal)
        case .predicate:
            return self
        }
    }
}

private extension HeistStep {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) throws -> HeistStep {
        switch self {
        case .action(let step):
            return .action(try step.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .wait(let step):
            return .wait(step.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .conditional(let step):
            return .conditional(try step.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .waitForCases(let step):
            return .waitForCases(try step.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .forEach:
            throw HeistPlanTransformError.nestedForEachBinding
        case .warn, .fail:
            return self
        }
    }
}

private extension ActionStep {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) throws -> ActionStep {
        try ActionStep(
            command: command.bindingForEachTarget(matching: matching, ordinal: ordinal),
            expectation: expectation?.bindingForEachTarget(matching: matching, ordinal: ordinal)
        )
    }
}

private extension WaitStep {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) -> WaitStep {
        WaitStep(
            predicate: predicate.bindingForEachTarget(matching: matching, ordinal: ordinal),
            timeout: timeout
        )
    }
}

private extension ConditionalStep {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) throws -> ConditionalStep {
        try ConditionalStep(
            cases: cases.map {
                try $0.bindingForEachTarget(matching: matching, ordinal: ordinal)
            },
            elseSteps: elseSteps.map { steps in
                try steps.map {
                    try $0.bindingForEachTarget(matching: matching, ordinal: ordinal)
                }
            }
        )
    }
}

private extension WaitForCasesStep {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) throws -> WaitForCasesStep {
        try WaitForCasesStep(
            timeout: timeout,
            cases: cases.map {
                try $0.bindingForEachTarget(matching: matching, ordinal: ordinal)
            },
            elseSteps: elseSteps.map { steps in
                try steps.map {
                    try $0.bindingForEachTarget(matching: matching, ordinal: ordinal)
                }
            }
        )
    }
}

private extension PredicateCase {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) throws -> PredicateCase {
        PredicateCase(
            predicate: predicate.bindingForEachTarget(matching: matching, ordinal: ordinal),
            steps: try steps.map {
                try $0.bindingForEachTarget(matching: matching, ordinal: ordinal)
            }
        )
    }
}

private extension ClientMessage {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) -> ClientMessage {
        switch self {
        case .activate(let target):
            return .activate(target.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .increment(let target):
            return .increment(target.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .decrement(let target):
            return .decrement(target.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .performCustomAction(let target):
            return .performCustomAction(CustomActionTarget(
                elementTarget: target.elementTarget.bindingForEachTarget(matching: matching, ordinal: ordinal),
                actionName: target.actionName
            ))
        case .rotor(let target):
            return .rotor(RotorTarget(
                elementTarget: target.elementTarget.bindingForEachTarget(matching: matching, ordinal: ordinal),
                selection: target.selection,
                direction: target.direction
            ))
        case .oneFingerTap(let target):
            return .oneFingerTap(TapTarget(
                selection: target.selection.bindingForEachTarget(matching: matching, ordinal: ordinal)
            ))
        case .longPress(let target):
            return .longPress(LongPressTarget(
                selection: target.selection.bindingForEachTarget(matching: matching, ordinal: ordinal),
                duration: target.duration
            ))
        case .swipe(let target):
            return .swipe(SwipeTarget(
                selection: target.selection.bindingForEachTarget(matching: matching, ordinal: ordinal),
                duration: target.duration
            ))
        case .drag(let target):
            return .drag(DragTarget(
                start: target.start.bindingForEachTarget(matching: matching, ordinal: ordinal),
                end: target.end,
                duration: target.duration
            ))
        case .typeText(let target):
            return .typeText(TypeTextTarget(
                text: target.text,
                elementTarget: target.elementTarget.map {
                    $0.bindingForEachTarget(matching: matching, ordinal: ordinal)
                }
            ))
        case .scroll(let target):
            return .scroll(ScrollTarget(
                selection: target.selection.bindingForEachTarget(matching: matching, ordinal: ordinal),
                direction: target.direction
            ))
        case .scrollToVisible(let target):
            return .scrollToVisible(ScrollToVisibleTarget(
                elementTarget: target.elementTarget.bindingForEachTarget(matching: matching, ordinal: ordinal)
            ))
        case .scrollToEdge(let target):
            return .scrollToEdge(ScrollToEdgeTarget(
                selection: target.selection.bindingForEachTarget(matching: matching, ordinal: ordinal),
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
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) -> GesturePointSelection {
        switch self {
        case .element(let target):
            return .element(target.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .coordinate:
            return self
        }
    }
}

private extension SwipeGestureSelection {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) -> SwipeGestureSelection {
        switch self {
        case .unitElement(let target, let start, let end):
            return .unitElement(
                target.bindingForEachTarget(matching: matching, ordinal: ordinal),
                start: start,
                end: end
            )
        case .elementDirection(let target, let direction):
            return .elementDirection(target.bindingForEachTarget(matching: matching, ordinal: ordinal), direction)
        case .point(let start, let destination):
            return .point(start: start.bindingForEachTarget(matching: matching, ordinal: ordinal), destination: destination)
        }
    }
}

private extension ScrollContainerSelection {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) -> ScrollContainerSelection {
        switch self {
        case .element(let target):
            return .element(target.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .visibleContainer:
            return self
        }
    }
}

private extension AccessibilityPredicate {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) -> AccessibilityPredicate {
        switch self {
        case .state(let state):
            return .state(state.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .changed(let change):
            return .changed(change.bindingForEachTarget(matching: matching, ordinal: ordinal))
        }
    }
}

private extension AccessibilityPredicate.State {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) -> AccessibilityPredicate.State {
        switch self {
        case .present, .absent:
            return self
        case .presentTarget(let target):
            return .presentTarget(target.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .absentTarget(let target):
            return .absentTarget(target.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .all(let states):
            return .all(states.map {
                $0.bindingForEachTarget(matching: matching, ordinal: ordinal)
            })
        }
    }
}

private extension AccessibilityPredicate.Change {
    func bindingForEachTarget(matching: ElementPredicate, ordinal: Int) -> AccessibilityPredicate.Change {
        switch self {
        case .screen(let state):
            return .screen(where: state?.bindingForEachTarget(matching: matching, ordinal: ordinal))
        case .elements, .appeared, .disappeared, .updated:
            return self
        }
    }
}
