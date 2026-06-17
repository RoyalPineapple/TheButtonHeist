public protocol HeistActionContent: HeistContent {
    var command: HeistActionCommand { get }
    var expectation: WaitStep? { get }
    var expectationWaiver: String? { get }
    var expectationValidationFailure: String? { get }
}

public extension HeistActionContent {
    var expectationValidationFailure: String? { nil }

    var heistSteps: [HeistStep] {
        [makeActionStep(
            command,
            expectation: expectation,
            expectationWaiver: expectationWaiver,
            expectationValidationFailure: expectationValidationFailure
        )]
    }

    func expect(
        _ predicate: AccessibilityPredicateExpr,
        timeout: Double? = nil
    ) -> ActionContent {
        let priorExplicitTimeout = (self as? ActionContent)?.explicitExpectationTimeout
        let timeoutResult = composeExpectationTimeout(
            existing: expectation,
            existingExplicit: priorExplicitTimeout,
            nextExplicit: timeout
        )
        let predicateResult = expectation.map {
            composeExpectationPredicates(existing: $0.predicate, next: predicate)
        } ?? ExpectationPredicateComposition(predicate: predicate, failure: nil)
        let validationFailure = [
            expectationValidationFailure,
            predicateResult.failure,
            timeoutResult.failure,
        ].compactMap { $0 }.joined(separator: "; ")

        return ActionContent(
            command: command,
            expectation: WaitStep(predicate: predicateResult.predicate, timeout: timeoutResult.timeout),
            expectationWaiver: nil,
            explicitExpectationTimeout: timeoutResult.explicitTimeout,
            expectationValidationFailure: validationFailure.isEmpty ? nil : validationFailure
        )
    }

    func expect(timeout: Double? = nil) -> ActionContent {
        expect(.changed(.elements), timeout: timeout)
    }

    @_disfavoredOverload
    func expect(
        _ predicate: AccessibilityPredicate,
        timeout: Double? = nil
    ) -> ActionContent {
        expect(.predicate(predicate), timeout: timeout)
    }

    func withoutExpectation(_ reason: String) -> ActionContent {
        ActionContent(
            command: command,
            expectation: nil,
            expectationWaiver: reason,
            explicitExpectationTimeout: nil,
            expectationValidationFailure: nil
        )
    }
}

public struct ActionContent: HeistActionContent {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?
    public let expectationValidationFailure: String?
    let explicitExpectationTimeout: Double?

    init(
        command: HeistActionCommand,
        expectation: WaitStep? = nil,
        expectationWaiver: String? = nil,
        explicitExpectationTimeout: Double? = nil,
        expectationValidationFailure: String? = nil
    ) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
        self.explicitExpectationTimeout = explicitExpectationTimeout
        self.expectationValidationFailure = expectationValidationFailure
    }
}

public struct Activate: HeistActionContent {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    @_disfavoredOverload
    public init(_ target: ElementTarget) {
        self.init(.target(target))
    }

    public init(_ target: ElementTargetExpr) {
        self.init(command: .activate(target), expectation: nil)
    }

    init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct Increment: HeistActionContent {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    @_disfavoredOverload
    public init(_ target: ElementTarget) {
        self.init(.target(target))
    }

    public init(_ target: ElementTargetExpr) {
        self.init(command: .increment(target), expectation: nil)
    }

    init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct Decrement: HeistActionContent {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    @_disfavoredOverload
    public init(_ target: ElementTarget) {
        self.init(.target(target))
    }

    public init(_ target: ElementTargetExpr) {
        self.init(command: .decrement(target), expectation: nil)
    }

    init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct TypeText: HeistActionContent {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    @_disfavoredOverload
    public init(_ text: String, into target: ElementTarget? = nil) {
        self.init(.literal(text), into: target.map(ElementTargetExpr.target))
    }

    @_disfavoredOverload
    public init(_ text: StringExpr, into target: ElementTarget) {
        self.init(text, into: .target(target))
    }

    public init(_ text: String, into target: ElementTargetExpr) {
        self.init(.literal(text), into: target)
    }

    public init(_ text: StringExpr, into target: ElementTargetExpr? = nil) {
        self.init(command: .typeText(text: text, target: target), expectation: nil)
    }

    init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct CustomAction: HeistActionContent {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    @_disfavoredOverload
    public init(_ name: String, on target: ElementTarget) {
        self.init(name, on: .target(target))
    }

    public init(_ name: String, on target: ElementTargetExpr) {
        self.init(command: .customAction(name: name, target: target))
    }

    init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct Rotor: HeistActionContent {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    @_disfavoredOverload
    public init(_ name: String, on target: ElementTarget, direction: RotorDirection = .next) {
        self.init(name, on: .target(target), direction: direction)
    }

    public init(_ name: String, on target: ElementTargetExpr, direction: RotorDirection = .next) {
        self.init(command: .rotor(selection: .named(name), target: target, direction: direction))
    }

    init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct SetPasteboard: HeistActionContent {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    public init(_ text: String) {
        self.init(command: .setPasteboard(SetPasteboardTarget(text: text)))
    }

    init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct Edit: HeistActionContent {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    public init(_ action: EditAction) {
        self.init(command: .editAction(EditActionTarget(action: action)))
    }

    init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct DismissKeyboard: HeistActionContent {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    public init() {
        self.init(command: .dismissKeyboard)
    }

    init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public enum Mechanical {
    public struct Tap: HeistActionContent {
        public let command: HeistActionCommand
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        @_disfavoredOverload
        public init(_ target: ElementTarget) {
            self.init(command: .mechanicalTap(TapTarget(selection: .element(target))))
        }

        public init(x: Double, y: Double) {
            self.init(command: .mechanicalTap(TapTarget(selection: .coordinate(ScreenPoint(x: x, y: y)))))
        }

        init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }

    public struct LongPress: HeistActionContent {
        public let command: HeistActionCommand
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        public init(_ target: ElementTarget) {
            self.init(command: .mechanicalLongPress(LongPressTarget(selection: .element(target))))
        }

        public init(x: Double, y: Double, duration: GestureDuration = .longPressDefault) {
            self.init(
                command: .mechanicalLongPress(
                    LongPressTarget(
                        selection: .coordinate(ScreenPoint(x: x, y: y)),
                        duration: duration
                    )
                )
            )
        }

        init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }

    public struct Swipe: HeistActionContent {
        public let command: HeistActionCommand
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        public init(_ target: ElementTarget, _ direction: SwipeDirection) {
            self.init(command: .mechanicalSwipe(SwipeTarget(selection: .elementDirection(target, direction))))
        }

        public init(_ target: ElementTarget, from start: UnitPoint, to end: UnitPoint) {
            self.init(command: .mechanicalSwipe(SwipeTarget(selection: .unitElement(target, start: start, end: end))))
        }

        public init(from start: ScreenPoint, to end: ScreenPoint) {
            self.init(command: .mechanicalSwipe(SwipeTarget(selection: .point(start: .coordinate(start), destination: .coordinate(end)))))
        }

        public init(from start: ScreenPoint, _ direction: SwipeDirection) {
            self.init(command: .mechanicalSwipe(SwipeTarget(selection: .point(start: .coordinate(start), destination: .direction(direction)))))
        }

        init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }

    public struct Drag: HeistActionContent {
        public let command: HeistActionCommand
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        public init(_ target: ElementTarget, to end: ScreenPoint) {
            self.init(command: .mechanicalDrag(DragTarget(start: .element(target), end: end)))
        }

        public init(from start: ScreenPoint, to end: ScreenPoint) {
            self.init(command: .mechanicalDrag(DragTarget(start: .coordinate(start), end: end)))
        }

        init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }
}

private func makeActionStep(
    _ command: HeistActionCommand,
    expectation: WaitStep? = nil,
    expectationWaiver: String? = nil,
    expectationValidationFailure: String? = nil
) -> HeistStep {
    do {
        return .action(try ActionStep(
            command: command,
            expectation: expectation,
            expectationWaiver: expectationWaiver,
            expectationValidationFailure: expectationValidationFailure
        ))
    } catch {
        preconditionFailure("ButtonHeistDSL constructed unsupported action command: \(command.wireType.rawValue)")
    }
}

private struct ExpectationTimeoutComposition {
    let timeout: Double
    let explicitTimeout: Double?
    let failure: String?
}

private func composeExpectationTimeout(
    existing: WaitStep?,
    existingExplicit: Double?,
    nextExplicit: Double?
) -> ExpectationTimeoutComposition {
    guard let existing else {
        return ExpectationTimeoutComposition(
            timeout: nextExplicit ?? 0,
            explicitTimeout: nextExplicit,
            failure: nil
        )
    }

    switch (existingExplicit, nextExplicit) {
    case (nil, nil):
        return ExpectationTimeoutComposition(timeout: existing.timeout, explicitTimeout: nil, failure: nil)
    case (nil, .some(let timeout)):
        return ExpectationTimeoutComposition(timeout: timeout, explicitTimeout: timeout, failure: nil)
    case (.some(let timeout), nil):
        return ExpectationTimeoutComposition(timeout: existing.timeout, explicitTimeout: timeout, failure: nil)
    case (.some(let existingTimeout), .some(let nextTimeout)):
        guard existingTimeout == nextTimeout else {
            return ExpectationTimeoutComposition(
                timeout: existing.timeout,
                explicitTimeout: existingTimeout,
                failure: "multiple explicit expectation timeouts in one chain: \(existingTimeout) and \(nextTimeout)"
            )
        }
        return ExpectationTimeoutComposition(timeout: nextTimeout, explicitTimeout: nextTimeout, failure: nil)
    }
}

private struct ExpectationPredicateComposition {
    let predicate: AccessibilityPredicateExpr
    let failure: String?
}

private func composeExpectationPredicates(
    existing: AccessibilityPredicateExpr,
    next: AccessibilityPredicateExpr
) -> ExpectationPredicateComposition {
    if let composed = composeScreenChangeAndState(existing, next) {
        return ExpectationPredicateComposition(predicate: composed, failure: nil)
    }

    if let existingState = stateExpression(existing),
       let nextState = stateExpression(next) {
        return ExpectationPredicateComposition(
            predicate: .state(allState([existingState, nextState])),
            failure: nil
        )
    }

    let failure = "unsupported expectation composition: \(existing) + \(next)"
    return ExpectationPredicateComposition(predicate: existing, failure: failure)
}

private func composeScreenChangeAndState(
    _ lhs: AccessibilityPredicateExpr,
    _ rhs: AccessibilityPredicateExpr
) -> AccessibilityPredicateExpr? {
    if let screenChange = screenChangeExpectation(lhs),
       let state = stateExpression(rhs) {
        return .changed(.screen(where: allState([screenChange.state, state].compactMap { $0 })))
    }

    if let state = stateExpression(lhs),
       let screenChange = screenChangeExpectation(rhs) {
        return .changed(.screen(where: allState([screenChange.state, state].compactMap { $0 })))
    }

    return nil
}

private struct ScreenChangeExpectation {
    let state: StatePredicateExpr?
}

private func screenChangeExpectation(_ predicate: AccessibilityPredicateExpr) -> ScreenChangeExpectation? {
    switch predicate {
    case .changed(.screen(let state)):
        return ScreenChangeExpectation(state: state)
    case .predicate(.changed(.screen(let state))):
        return ScreenChangeExpectation(state: state.map(StatePredicateExpr.init))
    case .predicate, .state, .changed:
        return nil
    }
}

private func stateExpression(_ predicate: AccessibilityPredicateExpr) -> StatePredicateExpr? {
    switch predicate {
    case .state(let state):
        return state
    case .predicate(.state(let state)):
        return StatePredicateExpr(state)
    case .predicate, .changed:
        return nil
    }
}

private func allState(_ states: [StatePredicateExpr]) -> StatePredicateExpr {
    let flattened = states.flatMap { state -> [StatePredicateExpr] in
        if case .all(let children) = state { return children }
        return [state]
    }
    guard !flattened.isEmpty else { return .all([]) }
    guard flattened.count > 1 else { return flattened[0] }
    return .all(flattened)
}
