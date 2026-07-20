public let defaultActionExpectationTimeout: WaitTimeout = 1

public struct Action {
    let command: HeistActionCommand
    let expectationPolicy: ActionExpectationPolicy
    let explicitExpectationTimeout: WaitTimeout?
    let expectationValidationDiagnostics: [HeistBuildDiagnostic]

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

    var heistContent: HeistContent {
        guard expectationValidationDiagnostics.isEmpty else {
            return HeistContent(diagnostics: expectationValidationDiagnostics)
        }
        return HeistContent([.action(ActionStep(
            command: command,
            expectationPolicy: expectationPolicy
        ))])
    }

    public func expect(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout? = nil
    ) -> Action {
        let existingExpectation = expectationPolicy.expectedStep
        let timeoutResult = composeExpectationTimeout(
            existing: existingExpectation,
            existingExplicit: explicitExpectationTimeout,
            nextExplicit: timeout
        )
        let predicateResult = existingExpectation.map {
            composeExpectationPredicates(existing: $0.predicate, next: predicate)
        } ?? ExpectationPredicateComposition(predicate: predicate, diagnostics: [])
        let validationDiagnostics = expectationValidationDiagnostics
            + predicateResult.diagnostics
            + timeoutResult.diagnostics

        return Action(
            command: command,
            expectationPolicy: .expect(ActionExpectation(predicate: predicateResult.predicate, timeout: timeoutResult.timeout)),
            explicitExpectationTimeout: timeoutResult.explicitTimeout,
            expectationValidationDiagnostics: validationDiagnostics.map {
                $0.withPath(command.wireType.rawValue)
            }
        )
    }

    public func withoutExpectation(_ waiver: ActionExpectationWaiver) -> Action {
        Action(
            command: command,
            expectationPolicy: .waived(waiver),
            explicitExpectationTimeout: nil,
            expectationValidationDiagnostics: []
        )
    }

    public func until(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout = defaultWaitTimeout
    ) -> Repeated {
        repeated(until: predicate, timeout: timeout)
    }

    func repeated(
        until predicate: AccessibilityPredicate,
        timeout: WaitTimeout
    ) -> Repeated {
        Repeated(
            command: command,
            expectationPolicy: expectationPolicy,
            expectationValidationDiagnostics: expectationValidationDiagnostics,
            predicate: predicate,
            timeout: timeout
        )
    }

    public struct Repeated {
        let command: HeistActionCommand
        let expectationPolicy: ActionExpectationPolicy
        let expectationValidationDiagnostics: [HeistBuildDiagnostic]
        let predicate: AccessibilityPredicate
        let timeout: WaitTimeout

        var heistContent: HeistContent {
            guard expectationValidationDiagnostics.isEmpty else {
                return HeistContent(diagnostics: expectationValidationDiagnostics)
            }
            return HeistContent([.repeatUntil(RepeatUntilStep(
                predicate: predicate,
                timeout: timeout,
                firstBodyStep: .action(ActionStep(command: command, expectationPolicy: expectationPolicy))
            ))])
        }
    }
}

public func Activate(_ target: AccessibilityTarget) -> Action {
    Action(command: .activate(target))
}

public func Increment(_ target: AccessibilityTarget) -> Action {
    Action(command: .increment(target))
}

public func Decrement(_ target: AccessibilityTarget) -> Action {
    Action(command: .decrement(target))
}

public func TypeText(
    _ text: TextInputText,
    into target: AccessibilityTarget? = nil
) -> Action {
    Action(command: .typeText(
        text: text,
        target: target
    ))
}

@_disfavoredOverload
public func TypeText(
    _ reference: HeistReferenceName,
    into target: AccessibilityTarget? = nil,
    mode: TextInputText.Mode = .append
) -> Action {
    Action(command: .typeText(
        reference: reference,
        target: target,
        mode: mode
    ))
}

public func ClearText(_ target: AccessibilityTarget) -> Action {
    Action(command: .typeText(
        text: .replacing(""),
        target: target
    ))
}

public func CustomAction(_ name: CustomActionName, on target: AccessibilityTarget) -> Action {
    Action(command: .customAction(name: name, target: target))
}

public func Rotor(
    _ name: RotorName,
    on target: AccessibilityTarget,
    direction: RotorDirection = .next
) -> Action {
    Action(command: .rotor(selection: .named(name), target: target, direction: direction))
}

public func SetPasteboard(_ text: PasteboardText) -> Action {
    Action(command: .setPasteboard(SetPasteboardTarget(text: text)))
}

public func TakeScreenshot() -> Action {
    Action(command: .takeScreenshot)
}

public func Edit(_ editAction: EditAction) -> Action {
    Action(command: .editAction(EditActionTarget(action: editAction)))
}

public func dismissKeyboard() -> Action {
    Action(command: .dismissKeyboard)
}

public enum ScreenActions {
    public static func Dismiss() -> Action {
        Action(command: .dismiss)
    }

    public static func MagicTap() -> Action {
        Action(command: .magicTap)
    }
}

@_disfavoredOverload
public func oneFingerTap(_ target: AccessibilityTarget) -> Action {
    Action(command: .oneFingerTap(TapTarget(selection: .element(target))))
}

public func oneFingerTap(_ point: ScreenPoint) -> Action {
    Action(command: .oneFingerTap(TapTarget(selection: .coordinate(point))))
}

public func oneFingerTap(_ target: AccessibilityTarget, at point: UnitPoint) -> Action {
    Action(command: .oneFingerTap(TapTarget(selection: .elementUnitPoint(target, point))))
}

public func longPress(
    _ target: AccessibilityTarget,
    duration: GestureDuration = .longPressDefault
) -> Action {
    Action(command: .longPress(LongPressTarget(selection: .element(target), duration: duration)))
}

public func longPress(
    _ point: ScreenPoint,
    duration: GestureDuration = .longPressDefault
) -> Action {
    Action(command: .longPress(LongPressTarget(selection: .coordinate(point), duration: duration)))
}

public func longPress(
    _ target: AccessibilityTarget,
    at point: UnitPoint,
    duration: GestureDuration = .longPressDefault
) -> Action {
    Action(command: .longPress(LongPressTarget(selection: .elementUnitPoint(target, point), duration: duration)))
}

public func swipe(_ target: AccessibilityTarget, _ direction: SwipeDirection) -> Action {
    Action(command: .swipe(SwipeTarget(selection: .elementDirection(target, direction))))
}

public func swipe(
    _ target: AccessibilityTarget,
    from start: UnitPoint,
    to end: UnitPoint
) -> Action {
    Action(command: .swipe(SwipeTarget(selection: .unitElement(target, start: start, end: end))))
}

public func swipe(from start: ScreenPoint, to end: ScreenPoint) -> Action {
    Action(command: .swipe(SwipeTarget(selection: .pointToPoint(start: start, end: end))))
}

public func swipe(from start: ScreenPoint, _ direction: SwipeDirection) -> Action {
    Action(command: .swipe(SwipeTarget(selection: .pointDirection(start: start, direction: direction))))
}

public func drag(_ target: AccessibilityTarget, to end: ScreenPoint) -> Action {
    Action(command: .drag(DragTarget(start: .element(target), end: end)))
}

public func drag(
    _ target: AccessibilityTarget,
    from start: UnitPoint,
    to end: ScreenPoint
) -> Action {
    Action(command: .drag(DragTarget(start: .elementUnitPoint(target, start), end: end)))
}

public func drag(from start: ScreenPoint, to end: ScreenPoint) -> Action {
    Action(command: .drag(DragTarget(start: .coordinate(start), end: end)))
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
