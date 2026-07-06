public protocol HeistActionContent: HeistContent {
    var command: HeistActionCommand { get }
    var expectationPolicy: ActionExpectationPolicy { get }
    var expectationValidationDiagnostics: [HeistBuildDiagnostic] { get }
}

public let defaultActionExpectationTimeout: Double = 1

public extension HeistActionContent {
    var expectationValidationDiagnostics: [HeistBuildDiagnostic] { [] }

    var heistBuildDiagnostics: [HeistBuildDiagnostic] {
        expectationValidationDiagnostics
    }

    var heistSteps: [HeistStep] {
        guard expectationValidationDiagnostics.isEmpty else { return [] }
        return [makeActionStep(
            command,
            expectationPolicy: expectationPolicy
        )]
    }

    func expect(
        _ predicate: AccessibilityPredicateExpr,
        timeout: Double? = nil
    ) -> ActionContent {
        let priorExplicitTimeout = (self as? ActionContent)?.explicitExpectationTimeout
        let existingExpectation = expectationPolicy.expectedStep
        let timeoutResult = composeExpectationTimeout(
            existing: existingExpectation,
            existingExplicit: priorExplicitTimeout,
            nextExplicit: timeout
        )
        let predicateResult = existingExpectation.map {
            composeExpectationPredicates(existing: $0.predicate, next: predicate)
        } ?? ExpectationPredicateComposition(predicate: predicate, diagnostics: [])
        let validationDiagnostics = expectationValidationDiagnostics
            + predicateResult.diagnostics
            + timeoutResult.diagnostics

        return ActionContent(
            command: command,
            expectationPolicy: .expect(ActionExpectation(predicate: predicateResult.predicate, timeout: timeoutResult.timeout)),
            explicitExpectationTimeout: timeoutResult.explicitTimeout,
            expectationValidationDiagnostics: validationDiagnostics.map {
                $0.withPath(command.wireType.rawValue)
            }
        )
    }

    func expect(timeout: Double? = nil) -> ActionContent {
        expect(.change(.elements()), timeout: timeout)
    }

    @_disfavoredOverload
    func expect(
        _ predicate: AccessibilityPredicate,
        timeout: Double? = nil
    ) -> ActionContent {
        expect(.predicate(predicate), timeout: timeout)
    }

    func withoutExpectation(_ reason: String) -> ActionContent {
        let waiver: ActionExpectationWaiver
        do {
            waiver = try ActionExpectationWaiver(reason)
        } catch {
            preconditionFailure("ButtonHeistDSL constructed unsupported expectation waiver: \(error)")
        }
        return ActionContent(
            command: command,
            expectationPolicy: .waived(waiver),
            explicitExpectationTimeout: nil,
            expectationValidationDiagnostics: []
        )
    }

    func until(
        _ predicate: AccessibilityPredicateExpr,
        timeout: Double = defaultWaitTimeout
    ) -> RepeatActionUntilContent {
        RepeatActionUntilContent(
            command: command,
            expectationPolicy: expectationPolicy,
            expectationValidationDiagnostics: expectationValidationDiagnostics,
            predicate: predicate,
            timeout: timeout
        )
    }

    @_disfavoredOverload
    func until(
        _ predicate: AccessibilityPredicate,
        timeout: Double = defaultWaitTimeout
    ) -> RepeatActionUntilContent {
        until(.predicate(predicate), timeout: timeout)
    }
}

public struct ActionContent: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy
    public let expectationValidationDiagnostics: [HeistBuildDiagnostic]
    let explicitExpectationTimeout: Double?

    init(
        command: HeistActionCommand,
        expectationPolicy: ActionExpectationPolicy = .default,
        explicitExpectationTimeout: Double? = nil,
        expectationValidationDiagnostics: [HeistBuildDiagnostic] = []
    ) {
        self.command = command
        self.expectationPolicy = expectationPolicy
        self.explicitExpectationTimeout = explicitExpectationTimeout
        self.expectationValidationDiagnostics = expectationValidationDiagnostics
    }
}

public struct RepeatActionUntilContent: HeistContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy
    public let expectationValidationDiagnostics: [HeistBuildDiagnostic]
    public let predicate: AccessibilityPredicateExpr
    public let timeout: Double

    public var heistSteps: [HeistStep] {
        guard heistBuildDiagnostics.isEmpty else { return [] }
        let progressPolicy: ActionExpectationPolicy
        switch expectationPolicy {
        case .default:
            progressPolicy = .expect(ActionExpectation(
                predicate: .change(),
                timeout: defaultActionExpectationTimeout
            ))
        case .expect, .waived:
            progressPolicy = expectationPolicy
        }
        do {
            return [
                .repeatUntil(try RepeatUntilStep(
                    predicate: predicate,
                    timeout: timeout,
                    body: [
                        makeActionStep(
                            command,
                            expectationPolicy: progressPolicy
                        ),
                    ]
                )),
            ]
        } catch {
            preconditionFailure("ButtonHeistDSL constructed unsupported action .until: \(error)")
        }
    }

    public var heistBuildDiagnostics: [HeistBuildDiagnostic] {
        var diagnostics = expectationValidationDiagnostics
        if timeout < 0 {
            diagnostics.append(.dslBuild(
                code: .dslInvalidActionUntil,
                message: "action until timeout must be non-negative"
            ))
        }
        return diagnostics
    }
}

public struct Activate: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init(_ target: ElementTarget) {
        self.init(.target(target))
    }

    @_disfavoredOverload
    public init(_ target: ElementTargetExpr) {
        self.init(command: .activate(target))
    }

    init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
        self.command = command
        self.expectationPolicy = expectationPolicy
    }
}

public struct Increment: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init(_ target: ElementTarget) {
        self.init(.target(target))
    }

    @_disfavoredOverload
    public init(_ target: ElementTargetExpr) {
        self.init(command: .increment(target))
    }

    init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
        self.command = command
        self.expectationPolicy = expectationPolicy
    }
}

public struct Decrement: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init(_ target: ElementTarget) {
        self.init(.target(target))
    }

    @_disfavoredOverload
    public init(_ target: ElementTargetExpr) {
        self.init(command: .decrement(target))
    }

    init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
        self.command = command
        self.expectationPolicy = expectationPolicy
    }
}

public struct TypeText: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init(_ text: String, into target: ElementTarget? = nil) {
        self.init(text, into: target, replacingExisting: false)
    }

    public init(
        _ text: String,
        into target: ElementTarget? = nil,
        replacingExisting: Bool
    ) {
        self.init(.literal(text), into: target.map(ElementTargetExpr.target), replacingExisting: replacingExisting)
    }

    public init(_ text: StringExpr, into target: ElementTarget) {
        self.init(text, into: target, replacingExisting: false)
    }

    public init(
        _ text: StringExpr,
        into target: ElementTarget,
        replacingExisting: Bool
    ) {
        self.init(text, into: .target(target), replacingExisting: replacingExisting)
    }

    @_disfavoredOverload
    public init(_ text: String, into target: ElementTargetExpr) {
        self.init(text, into: target, replacingExisting: false)
    }

    @_disfavoredOverload
    public init(
        _ text: String,
        into target: ElementTargetExpr,
        replacingExisting: Bool
    ) {
        self.init(.literal(text), into: target, replacingExisting: replacingExisting)
    }

    @_disfavoredOverload
    public init(_ text: StringExpr, into target: ElementTargetExpr? = nil) {
        self.init(text, into: target, replacingExisting: false)
    }

    @_disfavoredOverload
    public init(
        _ text: StringExpr,
        into target: ElementTargetExpr? = nil,
        replacingExisting: Bool
    ) {
        self.init(command: .typeText(
            text: text,
            target: target,
            replacingExisting: replacingExisting
        ))
    }

    init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
        self.command = command
        self.expectationPolicy = expectationPolicy
    }
}

public struct ClearText: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init(_ target: ElementTarget) {
        self.init(.target(target))
    }

    @_disfavoredOverload
    public init(_ target: ElementTargetExpr) {
        self.init(command: .typeText(
            text: .literal(""),
            target: target,
            replacingExisting: true
        ))
    }

    init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
        self.command = command
        self.expectationPolicy = expectationPolicy
    }
}

public struct CustomAction: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init(_ name: String, on target: ElementTarget) {
        self.init(name, on: .target(target))
    }

    @_disfavoredOverload
    public init(_ name: String, on target: ElementTargetExpr) {
        self.init(command: .customAction(name: name, target: target))
    }

    init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
        self.command = command
        self.expectationPolicy = expectationPolicy
    }
}

public struct Rotor: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init(_ name: String, on target: ElementTarget, direction: RotorDirection = .next) {
        self.init(name, on: .target(target), direction: direction)
    }

    @_disfavoredOverload
    public init(_ name: String, on target: ElementTargetExpr, direction: RotorDirection = .next) {
        self.init(command: .rotor(selection: .named(name), target: target, direction: direction))
    }

    init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
        self.command = command
        self.expectationPolicy = expectationPolicy
    }
}

public struct SetPasteboard: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init(_ text: String) {
        self.init(command: .setPasteboard(SetPasteboardTarget(text: text)))
    }

    init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
        self.command = command
        self.expectationPolicy = expectationPolicy
    }
}

public struct TakeScreenshot: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init() {
        self.init(command: .takeScreenshot)
    }

    init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
        self.command = command
        self.expectationPolicy = expectationPolicy
    }
}

public struct Edit: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init(_ action: EditAction) {
        self.init(command: .editAction(EditActionTarget(action: action)))
    }

    init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
        self.command = command
        self.expectationPolicy = expectationPolicy
    }
}

public struct DismissKeyboard: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init() {
        self.init(command: .dismissKeyboard)
    }

    init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
        self.command = command
        self.expectationPolicy = expectationPolicy
    }
}

public enum ScreenActions {
    public struct Dismiss: HeistActionContent {
        public let command: HeistActionCommand
        public let expectationPolicy: ActionExpectationPolicy

        public init() {
            self.init(command: .dismiss)
        }

        init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
            self.command = command
            self.expectationPolicy = expectationPolicy
        }
    }

    public struct MagicTap: HeistActionContent {
        public let command: HeistActionCommand
        public let expectationPolicy: ActionExpectationPolicy

        public init() {
            self.init(command: .magicTap)
        }

        init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
            self.command = command
            self.expectationPolicy = expectationPolicy
        }
    }
}

public enum Mechanical {
    public struct Tap: HeistActionContent {
        public let command: HeistActionCommand
        public let expectationPolicy: ActionExpectationPolicy

        @_disfavoredOverload
        public init(_ target: ElementTarget) {
            self.init(command: .mechanicalTap(TapTarget(selection: .element(target))))
        }

        public init(_ point: ScreenPoint) {
            self.init(command: .mechanicalTap(TapTarget(selection: .coordinate(point))))
        }

        public init(_ target: ElementTarget, at point: UnitPoint) {
            self.init(command: .mechanicalTap(TapTarget(selection: .elementUnitPoint(target, point))))
        }

        init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
            self.command = command
            self.expectationPolicy = expectationPolicy
        }
    }

    public struct LongPress: HeistActionContent {
        public let command: HeistActionCommand
        public let expectationPolicy: ActionExpectationPolicy

        public init(_ target: ElementTarget, duration: GestureDuration = .longPressDefault) {
            self.init(command: .mechanicalLongPress(LongPressTarget(selection: .element(target), duration: duration)))
        }

        public init(_ point: ScreenPoint, duration: GestureDuration = .longPressDefault) {
            self.init(
                command: .mechanicalLongPress(
                    LongPressTarget(
                        selection: .coordinate(point),
                        duration: duration
                    )
                )
            )
        }

        public init(_ target: ElementTarget, at point: UnitPoint, duration: GestureDuration = .longPressDefault) {
            self.init(
                command: .mechanicalLongPress(
                    LongPressTarget(
                        selection: .elementUnitPoint(target, point),
                        duration: duration
                    )
                )
            )
        }

        init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
            self.command = command
            self.expectationPolicy = expectationPolicy
        }
    }

    public struct Swipe: HeistActionContent {
        public let command: HeistActionCommand
        public let expectationPolicy: ActionExpectationPolicy

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

        init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
            self.command = command
            self.expectationPolicy = expectationPolicy
        }
    }

    public struct Drag: HeistActionContent {
        public let command: HeistActionCommand
        public let expectationPolicy: ActionExpectationPolicy

        public init(_ target: ElementTarget, to end: ScreenPoint) {
            self.init(command: .mechanicalDrag(DragTarget(start: .element(target), end: end)))
        }

        public init(_ target: ElementTarget, from start: UnitPoint, to end: ScreenPoint) {
            self.init(command: .mechanicalDrag(DragTarget(start: .elementUnitPoint(target, start), end: end)))
        }

        public init(from start: ScreenPoint, to end: ScreenPoint) {
            self.init(command: .mechanicalDrag(DragTarget(start: .coordinate(start), end: end)))
        }

        init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
            self.command = command
            self.expectationPolicy = expectationPolicy
        }
    }
}

private func makeActionStep(
    _ command: HeistActionCommand,
    expectationPolicy: ActionExpectationPolicy = .default
) -> HeistStep {
    do {
        return .action(try ActionStep(
            command: command,
            expectationPolicy: expectationPolicy
        ))
    } catch {
        preconditionFailure("ButtonHeistDSL constructed unsupported action command: \(command.wireType.rawValue)")
    }
}

struct ExpectationTimeoutComposition {
    let timeout: Double
    let explicitTimeout: Double?
    let diagnostics: [HeistBuildDiagnostic]
}

func composeExpectationTimeout(
    existing: WaitStep?,
    existingExplicit: Double?,
    nextExplicit: Double?
) -> ExpectationTimeoutComposition {
    guard let existing else {
        return ExpectationTimeoutComposition(
            timeout: nextExplicit ?? defaultActionExpectationTimeout,
            explicitTimeout: nextExplicit,
            diagnostics: []
        )
    }

    switch (existingExplicit, nextExplicit) {
    case (nil, nil):
        return ExpectationTimeoutComposition(timeout: existing.timeout, explicitTimeout: nil, diagnostics: [])
    case (nil, .some(let timeout)):
        return ExpectationTimeoutComposition(timeout: timeout, explicitTimeout: timeout, diagnostics: [])
    case (.some(let timeout), nil):
        return ExpectationTimeoutComposition(timeout: existing.timeout, explicitTimeout: timeout, diagnostics: [])
    case (.some(let existingTimeout), .some(let nextTimeout)):
        guard existingTimeout == nextTimeout else {
            return ExpectationTimeoutComposition(
                timeout: existing.timeout,
                explicitTimeout: existingTimeout,
                diagnostics: [.dslBuild(
                    code: .dslInvalidActionExpectation,
                    message: "multiple explicit expectation timeouts in one chain: \(existingTimeout) and \(nextTimeout)",
                    hint: "Use one explicit timeout for the composed expectation."
                )]
            )
        }
        return ExpectationTimeoutComposition(timeout: nextTimeout, explicitTimeout: nextTimeout, diagnostics: [])
    }
}

struct ExpectationPredicateComposition {
    let predicate: AccessibilityPredicateExpr
    let diagnostics: [HeistBuildDiagnostic]
}

func composeExpectationPredicates(
    existing: AccessibilityPredicateExpr,
    next: AccessibilityPredicateExpr
) -> ExpectationPredicateComposition {
    if let composed = composeScreenChangeAndState(existing, next) {
        return ExpectationPredicateComposition(predicate: composed, diagnostics: [])
    }

    if let existingState = stateExpression(existing),
       let nextState = stateExpression(next),
       let state = allState([existingState, nextState]) {
        return ExpectationPredicateComposition(
            predicate: .state(state),
            diagnostics: []
        )
    }

    return ExpectationPredicateComposition(
        predicate: existing,
        diagnostics: [.dslBuild(
            code: .dslInvalidActionExpectation,
            message: "unsupported expectation composition: \(existing) + \(next)",
            hint: "Use one change predicate plus optional state predicates, or split unrelated waits into explicit WaitFor steps."
        )]
    )
}

private func composeScreenChangeAndState(
    _ lhs: AccessibilityPredicateExpr,
    _ rhs: AccessibilityPredicateExpr
) -> AccessibilityPredicateExpr? {
    if let screenChange = screenChangeExpectation(lhs),
       let state = stateExpression(rhs),
       let assertion = allState([screenChange.state, state].compactMap { $0 }) {
        return .change(.screen(assertion))
    }

    if let state = stateExpression(lhs),
       let screenChange = screenChangeExpectation(rhs),
       let assertion = allState([screenChange.state, state].compactMap { $0 }) {
        return .change(.screen(assertion))
    }

    return nil
}

private struct ScreenChangeExpectation {
    let state: StatePredicateExpr?
}

private func screenChangeExpectation(_ predicate: AccessibilityPredicateExpr) -> ScreenChangeExpectation? {
    switch predicate {
    case .changePredicate(.screenScope(let states)):
        return ScreenChangeExpectation(state: allState(states))
    case .predicate(.changePredicate(.screenScope(let states))):
        return ScreenChangeExpectation(state: allState(states.map(StatePredicateExpr.init)))
    case .predicate, .state, .changePredicate, .noChangePredicate:
        return nil
    }
}

private func stateExpression(_ predicate: AccessibilityPredicateExpr) -> StatePredicateExpr? {
    switch predicate {
    case .state(let state):
        return state
    case .predicate(.state(let state)):
        return StatePredicateExpr(state)
    case .predicate, .changePredicate, .noChangePredicate:
        return nil
    }
}

private func allState(_ states: [StatePredicateExpr]) -> StatePredicateExpr? {
    let flattened = states.flatMap { state -> [StatePredicateExpr] in
        if case .all(let children) = state { return children.elements }
        return [state]
    }
    guard !flattened.isEmpty else { return nil }
    guard flattened.count > 1 else { return flattened[0] }
    return .all(NonEmptyArray(flattened[0], rest: Array(flattened.dropFirst())))
}
