import TheScore

public protocol HeistActionContent: HeistContent {
    var command: ClientMessage { get }
    var expectation: WaitStep? { get }
    var expectationWaiver: String? { get }
}

public extension HeistActionContent {
    var heistSteps: [HeistStep] {
        [makeActionStep(command, expectation: expectation, expectationWaiver: expectationWaiver)]
    }

    func expect(
        _ predicate: AccessibilityPredicate,
        timeout: Double = 0
    ) -> ActionContent {
        ActionContent(
            command: command,
            expectation: WaitStep(predicate: predicate, timeout: timeout),
            expectationWaiver: nil
        )
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
    public let command: ClientMessage
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct Activate: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    public init(_ target: ElementTarget) {
        self.init(command: .activate(target), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct Increment: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    public init(_ target: ElementTarget) {
        self.init(command: .increment(target), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct Decrement: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    public init(_ target: ElementTarget) {
        self.init(command: .decrement(target), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct TypeText: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    public init(_ text: String, into target: ElementTarget? = nil) {
        self.init(command: .typeText(TypeTextTarget(text: text, elementTarget: target)), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct CustomAction: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    public init(_ name: String, on target: ElementTarget) {
        self.init(command: .performCustomAction(CustomActionTarget(elementTarget: target, actionName: name)))
    }

    init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public struct Rotor: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    public init(_ name: String, on target: ElementTarget, direction: RotorDirection = .next) {
        self.init(command: .rotor(RotorTarget(elementTarget: target, selection: .named(name), direction: direction)))
    }

    init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }
}

public enum Mechanical {
    public struct Tap: HeistActionContent {
        public let command: ClientMessage
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        public init(_ target: ElementTarget) {
            self.init(command: .oneFingerTap(TapTarget(selection: .element(target))))
        }

        public init(x: Double, y: Double) {
            self.init(command: .oneFingerTap(TapTarget(selection: .coordinate(ScreenPoint(x: x, y: y)))))
        }

        init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }

    public struct LongPress: HeistActionContent {
        public let command: ClientMessage
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        public init(_ target: ElementTarget) {
            self.init(command: .longPress(LongPressTarget(selection: .element(target))))
        }

        public init(x: Double, y: Double, duration: GestureDuration = .longPressDefault) {
            self.init(
                command: .longPress(
                    LongPressTarget(
                        selection: .coordinate(ScreenPoint(x: x, y: y)),
                        duration: duration
                    )
                )
            )
        }

        init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }

    public struct Swipe: HeistActionContent {
        public let command: ClientMessage
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        public init(_ target: ElementTarget, _ direction: SwipeDirection) {
            self.init(command: .swipe(SwipeTarget(selection: .elementDirection(target, direction))))
        }

        public init(from start: ScreenPoint, to end: ScreenPoint) {
            self.init(command: .swipe(SwipeTarget(selection: .point(start: .coordinate(start), destination: .coordinate(end)))))
        }

        public init(from start: ScreenPoint, _ direction: SwipeDirection) {
            self.init(command: .swipe(SwipeTarget(selection: .point(start: .coordinate(start), destination: .direction(direction)))))
        }

        init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }

    public struct Drag: HeistActionContent {
        public let command: ClientMessage
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        public init(_ target: ElementTarget, to end: ScreenPoint) {
            self.init(command: .drag(DragTarget(start: .element(target), end: end)))
        }

        public init(from start: ScreenPoint, to end: ScreenPoint) {
            self.init(command: .drag(DragTarget(start: .coordinate(start), end: end)))
        }

        init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }
}

public enum Viewport {
    public struct Scroll: HeistActionContent {
        public let command: ClientMessage
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        public init(_ direction: ScrollDirection) {
            self.init(command: .scroll(ScrollTarget(direction: direction)))
        }

        public init(_ direction: ScrollDirection, in target: ElementTarget) {
            self.init(command: .scroll(ScrollTarget(elementTarget: target, direction: direction)))
        }

        init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }

    public struct ScrollToVisible: HeistActionContent {
        public let command: ClientMessage
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        public init(_ target: ElementTarget) {
            self.init(command: .scrollToVisible(ScrollToVisibleTarget(elementTarget: target)))
        }

        init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }

    public struct ScrollToEdge: HeistActionContent {
        public let command: ClientMessage
        public let expectation: WaitStep?
        public let expectationWaiver: String?

        public init(_ edge: ScrollEdge) {
            self.init(command: .scrollToEdge(ScrollToEdgeTarget(edge: edge)))
        }

        public init(_ edge: ScrollEdge, in target: ElementTarget) {
            self.init(command: .scrollToEdge(ScrollToEdgeTarget(elementTarget: target, edge: edge)))
        }

        init(command: ClientMessage, expectation: WaitStep? = nil, expectationWaiver: String? = nil) {
            self.command = command
            self.expectation = expectation
            self.expectationWaiver = expectationWaiver
        }
    }
}

private func makeActionStep(
    _ command: ClientMessage,
    expectation: WaitStep? = nil,
    expectationWaiver: String? = nil
) -> HeistStep {
    do {
        return .action(try ActionStep(command: command, expectation: expectation, expectationWaiver: expectationWaiver))
    } catch {
        preconditionFailure("ButtonHeistDSL constructed unsupported action command: \(command.wireType.rawValue)")
    }
}
