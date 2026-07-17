public protocol HeistActionContent: HeistContent {
    var command: HeistActionCommand { get }
    var expectationPolicy: ActionExpectationPolicy { get }
    var expectationValidationDiagnostics: [HeistBuildDiagnostic] { get }
}

public let defaultActionExpectationTimeout: WaitTimeout = 1

public extension HeistActionContent {
    var expectationValidationDiagnostics: [HeistBuildDiagnostic] { [] }

    var heistBuildDiagnostics: [HeistBuildDiagnostic] {
        expectationValidationDiagnostics
    }

    var heistSteps: [HeistStep] {
        guard expectationValidationDiagnostics.isEmpty else { return [] }
        return [.action(ActionStep(command: command, expectationPolicy: expectationPolicy))]
    }

    func expect(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout? = nil
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

    func withoutExpectation(_ waiver: ActionExpectationWaiver) -> ActionContent {
        return ActionContent(
            command: command,
            expectationPolicy: .waived(waiver),
            explicitExpectationTimeout: nil,
            expectationValidationDiagnostics: []
        )
    }

    func until(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout = defaultWaitTimeout
    ) -> RepeatActionUntilContent {
        RepeatActionUntilContent(
            command: command,
            expectationPolicy: expectationPolicy,
            expectationValidationDiagnostics: expectationValidationDiagnostics,
            predicate: predicate,
            timeout: timeout
        )
    }

}

public struct ActionContent: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy
    public let expectationValidationDiagnostics: [HeistBuildDiagnostic]
    let explicitExpectationTimeout: WaitTimeout?

    init(
        command: HeistActionCommand,
        expectationPolicy: ActionExpectationPolicy = .default,
        explicitExpectationTimeout: WaitTimeout? = nil,
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
    public let predicate: AccessibilityPredicate
    public let timeout: WaitTimeout

    public var heistSteps: [HeistStep] {
        guard heistBuildDiagnostics.isEmpty else { return [] }
        let progressPolicy: ActionExpectationPolicy
        switch expectationPolicy {
        case .default:
            progressPolicy = .default
        case .expect, .waived:
            progressPolicy = expectationPolicy
        }
        do {
            return [
                .repeatUntil(try RepeatUntilStep(
                    predicate: predicate,
                    timeout: timeout,
                    body: [
                        .action(ActionStep(command: command, expectationPolicy: progressPolicy)),
                    ]
                )),
            ]
        } catch {
            preconditionFailure("ThePlans constructed unsupported action .until: \(error)")
        }
    }

    public var heistBuildDiagnostics: [HeistBuildDiagnostic] { expectationValidationDiagnostics }
}

public struct Activate: HeistActionContent {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init(_ target: AccessibilityTarget) {
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

    public init(_ target: AccessibilityTarget) {
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

    public init(_ target: AccessibilityTarget) {
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

    public init(_ text: TextInputText, into target: AccessibilityTarget? = nil) {
        self.init(command: .typeText(
            text: text,
            target: target
        ))
    }

    @_disfavoredOverload
    public init(
        _ reference: HeistReferenceName,
        into target: AccessibilityTarget? = nil,
        mode: TextInputText.Mode = .append
    ) {
        self.init(command: .typeText(
            reference: reference,
            target: target,
            mode: mode
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

    public init(_ target: AccessibilityTarget) {
        self.init(command: .typeText(
            text: .replacing(""),
            target: target
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

    public init(_ name: CustomActionName, on target: AccessibilityTarget) {
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

    public init(_ name: RotorName, on target: AccessibilityTarget, direction: RotorDirection = .next) {
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

    public init(_ text: PasteboardText) {
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
        public init(_ target: AccessibilityTarget) {
            self.init(command: .mechanicalTap(TapTarget(selection: .element(target))))
        }

        public init(_ point: ScreenPoint) {
            self.init(command: .mechanicalTap(TapTarget(selection: .coordinate(point))))
        }

        public init(_ target: AccessibilityTarget, at point: UnitPoint) {
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

        public init(_ target: AccessibilityTarget, duration: GestureDuration = .longPressDefault) {
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

        public init(_ target: AccessibilityTarget, at point: UnitPoint, duration: GestureDuration = .longPressDefault) {
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

        public init(_ target: AccessibilityTarget, _ direction: SwipeDirection) {
            self.init(command: .mechanicalSwipe(SwipeTarget(selection: .elementDirection(target, direction))))
        }

        public init(_ target: AccessibilityTarget, from start: UnitPoint, to end: UnitPoint) {
            self.init(command: .mechanicalSwipe(SwipeTarget(selection: .unitElement(target, start: start, end: end))))
        }

        public init(from start: ScreenPoint, to end: ScreenPoint) {
            self.init(command: .mechanicalSwipe(SwipeTarget(selection: .pointToPoint(start: start, end: end))))
        }

        public init(from start: ScreenPoint, _ direction: SwipeDirection) {
            self.init(command: .mechanicalSwipe(SwipeTarget(selection: .pointDirection(start: start, direction: direction))))
        }

        init(command: HeistActionCommand, expectationPolicy: ActionExpectationPolicy = .default) {
            self.command = command
            self.expectationPolicy = expectationPolicy
        }
    }

    public struct Drag: HeistActionContent {
        public let command: HeistActionCommand
        public let expectationPolicy: ActionExpectationPolicy

        public init(_ target: AccessibilityTarget, to end: ScreenPoint) {
            self.init(command: .mechanicalDrag(DragTarget(start: .element(target), end: end)))
        }

        public init(_ target: AccessibilityTarget, from start: UnitPoint, to end: ScreenPoint) {
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

struct ExpectationTimeoutComposition {
    let timeout: WaitTimeout
    let explicitTimeout: WaitTimeout?
    let diagnostics: [HeistBuildDiagnostic]
}

func composeExpectationTimeout(
    existing: WaitStep?,
    existingExplicit: WaitTimeout?,
    nextExplicit: WaitTimeout?
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
    let predicate: AccessibilityPredicate
    let diagnostics: [HeistBuildDiagnostic]
}

func composeExpectationPredicates(
    existing: AccessibilityPredicate,
    next: AccessibilityPredicate
) -> ExpectationPredicateComposition {
    if let composed = composeScreenDeltaAndCurrentTree(existing, next)
        ?? composeScreenDeltaAndCurrentTree(next, existing) {
        return ExpectationPredicateComposition(predicate: composed, diagnostics: [])
    }

    return ExpectationPredicateComposition(
        predicate: existing,
        diagnostics: [.dslBuild(
            code: .dslInvalidActionExpectation,
            message: "unsupported expectation composition: \(existing) + \(next)",
            hint: "Use one canonical predicate per expectation, or add current-tree assertions inside .changed(.screen(...))."
        )]
    )
}

private func composeScreenDeltaAndCurrentTree(
    _ changed: AccessibilityPredicate,
    _ currentTree: AccessibilityPredicate
) -> AccessibilityPredicate? {
    guard case .changed(.screen(let assertions)) = changed.core else { return nil }
    switch currentTree.core {
    case .presence(let presence):
        return AccessibilityPredicate(
            core: .changed(.screen(assertions + [.presence(presence)]))
        )
    case .announcement, .changed, .noChange:
        return nil
    }

}
