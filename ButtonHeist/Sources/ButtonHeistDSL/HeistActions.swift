import TheScore

public protocol HeistActionContent: HeistContent {
    var command: ClientMessage { get }
    var expectation: WaitStep? { get }
}

public extension HeistActionContent {
    var heistSteps: [HeistStep] {
        [makeActionStep(command, expectation: expectation)]
    }

    func expect(
        _ predicate: AccessibilityPredicate,
        timeout: Double = 0
    ) -> ActionContent {
        ActionContent(
            command: command,
            expectation: WaitStep(predicate: predicate, timeout: timeout)
        )
    }
}

public struct ActionContent: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?

    init(command: ClientMessage, expectation: WaitStep? = nil) {
        self.command = command
        self.expectation = expectation
    }
}

public struct Activate: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?

    public init(_ target: ElementTarget) {
        self.init(command: .activate(target), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil) {
        self.command = command
        self.expectation = expectation
    }
}

public struct Increment: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?

    public init(_ target: ElementTarget) {
        self.init(command: .increment(target), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil) {
        self.command = command
        self.expectation = expectation
    }
}

public struct Decrement: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?

    public init(_ target: ElementTarget) {
        self.init(command: .decrement(target), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil) {
        self.command = command
        self.expectation = expectation
    }
}

public struct TypeText: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?

    public init(_ text: String, into target: ElementTarget? = nil) {
        self.init(command: .typeText(TypeTextTarget(text: text, elementTarget: target)), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil) {
        self.command = command
        self.expectation = expectation
    }
}

public struct Tap: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?

    public init(_ target: ElementTarget) {
        self.init(command: .oneFingerTap(TapTarget(selection: .element(target))), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil) {
        self.command = command
        self.expectation = expectation
    }
}

public struct LongPress: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?

    public init(_ target: ElementTarget) {
        self.init(command: .longPress(LongPressTarget(selection: .element(target))), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil) {
        self.command = command
        self.expectation = expectation
    }
}

public struct Swipe: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?

    public init(_ target: ElementTarget, _ direction: SwipeDirection) {
        self.init(command: .swipe(SwipeTarget(selection: .elementDirection(target, direction))), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil) {
        self.command = command
        self.expectation = expectation
    }
}

public struct Scroll: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?

    public init(_ direction: ScrollDirection) {
        self.init(command: .scroll(ScrollTarget(direction: direction)), expectation: nil)
    }

    public init(_ direction: ScrollDirection, in target: ElementTarget) {
        self.init(command: .scroll(ScrollTarget(elementTarget: target, direction: direction)), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil) {
        self.command = command
        self.expectation = expectation
    }
}

public struct ScrollToVisible: HeistActionContent {
    public let command: ClientMessage
    public let expectation: WaitStep?

    public init(_ target: ElementTarget) {
        self.init(command: .scrollToVisible(ScrollToVisibleTarget(elementTarget: target)), expectation: nil)
    }

    init(command: ClientMessage, expectation: WaitStep? = nil) {
        self.command = command
        self.expectation = expectation
    }
}

private func makeActionStep(_ command: ClientMessage, expectation: WaitStep? = nil) -> HeistStep {
    do {
        return .action(try ActionStep(command: command, expectation: expectation))
    } catch {
        preconditionFailure("ButtonHeistDSL constructed unsupported action command: \(command.wireType.rawValue)")
    }
}
