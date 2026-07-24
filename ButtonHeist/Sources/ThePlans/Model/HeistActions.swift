public let defaultActionExpectationTimeout: WaitTimeout = 1

public struct Action {
    let command: HeistActionCommand
    let expectation: AuthoredActionExpectation

    init(
        command: HeistActionCommand,
        expectation: AuthoredActionExpectation = .default
    ) {
        self.command = command
        self.expectation = expectation
    }

    var heistContent: HeistContent {
        guard expectation.diagnostics.isEmpty else {
            return HeistContent(diagnostics: expectation.diagnostics.map {
                $0.withPath(command.wireType.rawValue)
            })
        }
        return HeistContent([.action(ActionStep(
            command: command,
            expectationPolicy: expectation.policy
        ))])
    }

    public func expect(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout? = nil
    ) -> Action {
        return Action(
            command: command,
            expectation: expectation.appending(predicate, timeout: timeout)
        )
    }

    public func withoutExpectation(_ waiver: ActionExpectationWaiver) -> Action {
        Action(
            command: command,
            expectation: .waived(waiver)
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
            expectation: expectation,
            predicate: predicate,
            timeout: timeout
        )
    }

    public struct Repeated {
        let command: HeistActionCommand
        let expectation: AuthoredActionExpectation
        let predicate: AccessibilityPredicate
        let timeout: WaitTimeout

        var heistContent: HeistContent {
            guard expectation.diagnostics.isEmpty else {
                return HeistContent(diagnostics: expectation.diagnostics.map {
                    $0.withPath(command.wireType.rawValue)
                })
            }
            return HeistContent([.repeatUntil(RepeatUntilStep(
                predicate: predicate,
                timeout: timeout,
                firstBodyStep: .action(ActionStep(command: command, expectationPolicy: expectation.policy))
            ))])
        }
    }
}

enum AuthoredActionExpectation: Sendable, Equatable {
    case `default`
    case expect(
        WaitStep,
        explicitTimeout: WaitTimeout?,
        diagnostics: [HeistBuildDiagnostic]
    )
    case waived(ActionExpectationWaiver)

    var waitStep: WaitStep? {
        guard case .expect(let step, _, _) = self else { return nil }
        return step
    }

    var diagnostics: [HeistBuildDiagnostic] {
        guard case .expect(_, _, let diagnostics) = self else { return [] }
        return diagnostics
    }

    var policy: ActionExpectationPolicy {
        switch self {
        case .default:
            return .default
        case .expect(let step, _, _):
            return .expect(ActionExpectation(predicate: step.predicate, timeout: step.timeout))
        case .waived(let waiver):
            return .waived(waiver)
        }
    }

    func appending(
        _ nextPredicate: AccessibilityPredicate,
        timeout nextExplicitTimeout: WaitTimeout?
    ) -> Self {
        let existingStep: WaitStep?
        let existingExplicitTimeout: WaitTimeout?
        var diagnostics: [HeistBuildDiagnostic]
        switch self {
        case .expect(let step, let explicitTimeout, let existingDiagnostics):
            existingStep = step
            existingExplicitTimeout = explicitTimeout
            diagnostics = existingDiagnostics
        case .default, .waived:
            existingStep = nil
            existingExplicitTimeout = nil
            diagnostics = []
        }

        guard let existingStep else {
            return .expect(
                WaitStep(
                    predicate: nextPredicate,
                    timeout: nextExplicitTimeout ?? defaultActionExpectationTimeout
                ),
                explicitTimeout: nextExplicitTimeout,
                diagnostics: diagnostics
            )
        }

        let predicate: AccessibilityPredicate
        switch (existingStep.predicate.core, nextPredicate.core) {
        case (.changed(.screen(let assertions)), .presence(let presence)),
             (.presence(let presence), .changed(.screen(let assertions))):
            predicate = AccessibilityPredicate(
                core: .changed(.screen(assertions + [.presence(presence)]))
            )
        default:
            predicate = existingStep.predicate
            diagnostics.append(.dslBuild(
                code: .dslInvalidActionExpectation,
                message: "unsupported expectation composition: \(existingStep.predicate) + \(nextPredicate)",
                hint: "Use one canonical predicate per expectation, or add current-tree assertions inside .changed(.screen(...))."
            ))
        }

        let timeout: WaitTimeout
        let explicitTimeout: WaitTimeout?
        switch (existingExplicitTimeout, nextExplicitTimeout) {
        case (nil, nil):
            timeout = existingStep.timeout
            explicitTimeout = nil
        case (nil, .some(let requestedTimeout)):
            timeout = requestedTimeout
            explicitTimeout = requestedTimeout
        case (.some(let requestedTimeout), nil):
            timeout = existingStep.timeout
            explicitTimeout = requestedTimeout
        case (.some(let existingTimeout), .some(let nextTimeout)):
            if existingTimeout == nextTimeout {
                timeout = nextTimeout
                explicitTimeout = nextTimeout
            } else {
                timeout = existingStep.timeout
                explicitTimeout = existingTimeout
                diagnostics.append(.dslBuild(
                    code: .dslInvalidActionExpectation,
                    message: "multiple explicit expectation timeouts in one chain: \(existingTimeout) and \(nextTimeout)",
                    hint: "Use one explicit timeout for the composed expectation."
                ))
            }
        }

        return .expect(
            WaitStep(predicate: predicate, timeout: timeout),
            explicitTimeout: explicitTimeout,
            diagnostics: diagnostics
        )
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
