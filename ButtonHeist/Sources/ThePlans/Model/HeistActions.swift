public protocol HeistActionContent: HeistContent {
    associatedtype ExpectedContent: HeistActionContent
    associatedtype WaivedContent: HeistActionContent
    associatedtype RepeatedContent: HeistContent

    func expect(_ predicate: AccessibilityPredicate, timeout: WaitTimeout?) -> ExpectedContent
    func withoutExpectation(_ waiver: ActionExpectationWaiver) -> WaivedContent
    func until(_ predicate: AccessibilityPredicate, timeout: WaitTimeout) -> RepeatedContent
}

public let defaultActionExpectationTimeout: WaitTimeout = 1

public extension HeistActionContent {
    func expect(_ predicate: AccessibilityPredicate) -> ExpectedContent {
        expect(predicate, timeout: nil)
    }

    func until(_ predicate: AccessibilityPredicate) -> RepeatedContent {
        until(predicate, timeout: defaultWaitTimeout)
    }
}

struct ActionContent: HeistActionContent {
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

    var heistBuildDiagnostics: [HeistBuildDiagnostic] {
        expectationValidationDiagnostics
    }

    var heistSteps: [HeistStep] {
        guard expectationValidationDiagnostics.isEmpty else { return [] }
        return [.action(ActionStep(command: command, expectationPolicy: expectationPolicy))]
    }

    func expect(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout?
    ) -> ActionContent {
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
        ActionContent(
            command: command,
            expectationPolicy: .waived(waiver),
            explicitExpectationTimeout: nil,
            expectationValidationDiagnostics: []
        )
    }

    func until(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout
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

struct RepeatActionUntilContent: HeistContent {
    let command: HeistActionCommand
    let expectationPolicy: ActionExpectationPolicy
    let expectationValidationDiagnostics: [HeistBuildDiagnostic]
    let predicate: AccessibilityPredicate
    let timeout: WaitTimeout

    var heistSteps: [HeistStep] {
        guard heistBuildDiagnostics.isEmpty else { return [] }
        do {
            return [
                .repeatUntil(try RepeatUntilStep(
                    predicate: predicate,
                    timeout: timeout,
                    body: [
                        .action(ActionStep(command: command, expectationPolicy: expectationPolicy)),
                    ]
                )),
            ]
        } catch {
            preconditionFailure("ThePlans constructed unsupported action .until: \(error)")
        }
    }

    var heistBuildDiagnostics: [HeistBuildDiagnostic] { expectationValidationDiagnostics }
}

protocol ActionContentProviding {
    var actionContent: ActionContent { get }
}

extension ActionContentProviding {
    public var heistSteps: [HeistStep] { actionContent.heistSteps }

    public func expect(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout?
    ) -> some HeistActionContent {
        actionContent.expect(predicate, timeout: timeout)
    }

    public func withoutExpectation(_ waiver: ActionExpectationWaiver) -> some HeistActionContent {
        actionContent.withoutExpectation(waiver)
    }

    public func until(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout
    ) -> some HeistContent {
        actionContent.until(predicate, timeout: timeout)
    }
}

public struct Activate: HeistActionContent, ActionContentProviding {
    let actionContent: ActionContent

    public init(_ target: AccessibilityTarget) {
        actionContent = ActionContent(command: .activate(target))
    }
}

public struct Increment: HeistActionContent, ActionContentProviding {
    let actionContent: ActionContent

    public init(_ target: AccessibilityTarget) {
        actionContent = ActionContent(command: .increment(target))
    }
}

public struct Decrement: HeistActionContent, ActionContentProviding {
    let actionContent: ActionContent

    public init(_ target: AccessibilityTarget) {
        actionContent = ActionContent(command: .decrement(target))
    }
}

public struct TypeText: HeistActionContent, ActionContentProviding {
    let actionContent: ActionContent

    public init(
        _ text: TextInputText,
        into target: AccessibilityTarget? = nil
    ) {
        actionContent = ActionContent(command: .typeText(
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
        actionContent = ActionContent(command: .typeText(
            reference: reference,
            target: target,
            mode: mode
        ))
    }
}

public struct ClearText: HeistActionContent, ActionContentProviding {
    let actionContent: ActionContent

    public init(_ target: AccessibilityTarget) {
        actionContent = ActionContent(command: .typeText(
            text: .replacing(""),
            target: target
        ))
    }
}

public struct CustomAction: HeistActionContent, ActionContentProviding {
    let actionContent: ActionContent

    public init(_ name: CustomActionName, on target: AccessibilityTarget) {
        actionContent = ActionContent(command: .customAction(name: name, target: target))
    }
}

public struct Rotor: HeistActionContent, ActionContentProviding {
    let actionContent: ActionContent

    public init(_ name: RotorName, on target: AccessibilityTarget, direction: RotorDirection = .next) {
        actionContent = ActionContent(command: .rotor(selection: .named(name), target: target, direction: direction))
    }
}

public struct SetPasteboard: HeistActionContent, ActionContentProviding {
    let actionContent: ActionContent

    public init(_ text: PasteboardText) {
        actionContent = ActionContent(command: .setPasteboard(SetPasteboardTarget(text: text)))
    }
}

public struct TakeScreenshot: HeistActionContent, ActionContentProviding {
    let actionContent: ActionContent

    public init() {
        actionContent = ActionContent(command: .takeScreenshot)
    }
}

public struct Edit: HeistActionContent, ActionContentProviding {
    let actionContent: ActionContent

    public init(_ action: EditAction) {
        actionContent = ActionContent(command: .editAction(EditActionTarget(action: action)))
    }
}

public struct DismissKeyboard: HeistActionContent, ActionContentProviding {
    let actionContent: ActionContent

    public init() {
        actionContent = ActionContent(command: .dismissKeyboard)
    }
}

public enum ScreenActions {
    public struct Dismiss: HeistActionContent, ActionContentProviding {
        let actionContent: ActionContent

        public init() {
            actionContent = ActionContent(command: .dismiss)
        }
    }

    public struct MagicTap: HeistActionContent, ActionContentProviding {
        let actionContent: ActionContent

        public init() {
            actionContent = ActionContent(command: .magicTap)
        }
    }
}

public enum Mechanical {
    public struct Tap: HeistActionContent, ActionContentProviding {
        let actionContent: ActionContent

        @_disfavoredOverload
        public init(_ target: AccessibilityTarget) {
            actionContent = ActionContent(command: .mechanicalTap(TapTarget(selection: .element(target))))
        }

        public init(_ point: ScreenPoint) {
            actionContent = ActionContent(command: .mechanicalTap(TapTarget(selection: .coordinate(point))))
        }

        public init(_ target: AccessibilityTarget, at point: UnitPoint) {
            actionContent = ActionContent(command: .mechanicalTap(TapTarget(selection: .elementUnitPoint(target, point))))
        }
    }

    public struct LongPress: HeistActionContent, ActionContentProviding {
        let actionContent: ActionContent

        public init(_ target: AccessibilityTarget, duration: GestureDuration = .longPressDefault) {
            actionContent = ActionContent(
                command: .mechanicalLongPress(LongPressTarget(selection: .element(target), duration: duration))
            )
        }

        public init(_ point: ScreenPoint, duration: GestureDuration = .longPressDefault) {
            actionContent = ActionContent(
                command: .mechanicalLongPress(LongPressTarget(selection: .coordinate(point), duration: duration))
            )
        }

        public init(
            _ target: AccessibilityTarget,
            at point: UnitPoint,
            duration: GestureDuration = .longPressDefault
        ) {
            actionContent = ActionContent(command: .mechanicalLongPress(
                LongPressTarget(selection: .elementUnitPoint(target, point), duration: duration)
            ))
        }
    }

    public struct Swipe: HeistActionContent, ActionContentProviding {
        let actionContent: ActionContent

        public init(_ target: AccessibilityTarget, _ direction: SwipeDirection) {
            actionContent = ActionContent(
                command: .mechanicalSwipe(SwipeTarget(selection: .elementDirection(target, direction)))
            )
        }

        public init(_ target: AccessibilityTarget, from start: UnitPoint, to end: UnitPoint) {
            actionContent = ActionContent(
                command: .mechanicalSwipe(SwipeTarget(selection: .unitElement(target, start: start, end: end)))
            )
        }

        public init(from start: ScreenPoint, to end: ScreenPoint) {
            actionContent = ActionContent(
                command: .mechanicalSwipe(SwipeTarget(selection: .pointToPoint(start: start, end: end)))
            )
        }

        public init(from start: ScreenPoint, _ direction: SwipeDirection) {
            actionContent = ActionContent(
                command: .mechanicalSwipe(SwipeTarget(selection: .pointDirection(start: start, direction: direction)))
            )
        }
    }

    public struct Drag: HeistActionContent, ActionContentProviding {
        let actionContent: ActionContent

        public init(_ target: AccessibilityTarget, to end: ScreenPoint) {
            actionContent = ActionContent(command: .mechanicalDrag(DragTarget(start: .element(target), end: end)))
        }

        public init(_ target: AccessibilityTarget, from start: UnitPoint, to end: ScreenPoint) {
            actionContent = ActionContent(
                command: .mechanicalDrag(DragTarget(start: .elementUnitPoint(target, start), end: end))
            )
        }

        public init(from start: ScreenPoint, to end: ScreenPoint) {
            actionContent = ActionContent(command: .mechanicalDrag(DragTarget(start: .coordinate(start), end: end)))
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
