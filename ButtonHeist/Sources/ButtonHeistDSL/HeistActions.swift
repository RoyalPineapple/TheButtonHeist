import TheScore

public protocol HeistActionContent: HeistContent {
    var command: HeistActionCommand { get }
    var expectation: WaitStep? { get }
    var expectationWaiver: String? { get }
}

public extension HeistActionContent {
    var heistSteps: [HeistStep] {
        [makeActionStep(command, expectation: expectation, expectationWaiver: expectationWaiver)]
    }

    func expect(
        _ predicate: AccessibilityPredicateExpr,
        timeout: Double = 0
    ) -> ActionContent {
        ActionContent(
            command: command,
            expectation: WaitStep(predicate: predicate, timeout: timeout),
            expectationWaiver: nil
        )
    }

    @_disfavoredOverload
    func expect(
        _ predicate: AccessibilityPredicate,
        timeout: Double = 0
    ) -> ActionContent {
        expect(.predicate(predicate), timeout: timeout)
    }

    func withoutExpectation(_ reason: String) -> ActionContent {
        ActionContent(
            command: command,
            expectation: nil,
            expectationWaiver: reason
        )
    }
}

public struct ActionContent: HeistActionContent {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
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

public enum Viewport {
    public struct Scroll: HeistActionContent {
        public let command: HeistActionCommand
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        public init(_ direction: ScrollDirection) {
            self.init(command: .viewportScroll(ScrollTarget(direction: direction)))
        }

        public init(_ direction: ScrollDirection, in target: ElementTarget) {
            self.init(command: .viewportScroll(ScrollTarget(elementTarget: target, direction: direction)))
        }

        init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }

    public struct ScrollToVisible: HeistActionContent {
        public let command: HeistActionCommand
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        @_disfavoredOverload
        public init(_ target: ElementTarget) {
            self.init(.target(target))
        }

        public init(_ target: ElementTargetExpr) {
            self.init(command: .viewportScrollToVisible(target))
        }

        init(command: HeistActionCommand, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }

    public struct ScrollToEdge: HeistActionContent {
        public let command: HeistActionCommand
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        public init(_ edge: ScrollEdge) {
            self.init(command: .viewportScrollToEdge(ScrollToEdgeTarget(edge: edge)))
        }

        public init(_ edge: ScrollEdge, in target: ElementTarget) {
            self.init(command: .viewportScrollToEdge(ScrollToEdgeTarget(elementTarget: target, edge: edge)))
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
    expectationWaiver: String? = nil
) -> HeistStep {
    do {
        return .action(try ActionStep(command: command, expectation: expectation, expectationWaiver: expectationWaiver))
    } catch {
        preconditionFailure("ButtonHeistDSL constructed unsupported action command: \(command.wireType.rawValue)")
    }
}
