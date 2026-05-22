import Foundation

/// Per-operation execution deadline. The timeout may be omitted when execution
/// should use the receiver's default action timeout.
public struct Deadline: Codable, Sendable, Equatable {
    public let timeout: Double?

    public init(timeout: Double? = nil) {
        self.timeout = timeout
    }
}

extension Deadline: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("deadline", [
            timeout.map { "timeout=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

/// One executable non-read operation in a batch plan.
public struct BatchStep: Sendable {
    public let operation: BatchOperation
    public let expectation: ActionExpectation
    public let deadline: Deadline

    public init(
        operation: BatchOperation,
        expectation: ActionExpectation,
        deadline: Deadline
    ) {
        self.operation = operation
        self.expectation = expectation
        self.deadline = deadline
    }

    public init(
        action: Action,
        expectation: ActionExpectation,
        deadline: Deadline
    ) {
        self.init(
            operation: BatchOperation(legacyAction: action),
            expectation: expectation,
            deadline: deadline
        )
    }

    /// Compatibility projection for callers that still inspect the legacy
    /// action-shaped wire value. Runtime execution should use `operation`.
    public var action: Action {
        operation.legacyAction
    }

    public var userAction: Action? {
        guard case .action(let action) = operation else { return nil }
        return action
    }

    public static func action(
        _ action: Action,
        expect expectation: ActionExpectation? = nil,
        deadline: Deadline? = nil
    ) -> BatchStep {
        BatchStep(
            action: action,
            expectation: expectation ?? action.defaultExpectation,
            deadline: deadline ?? action.defaultDeadline
        )
    }

    public static func wait(_ wait: BatchExecutionWait) -> BatchStep {
        BatchStep(
            action: wait.action,
            expectation: wait.defaultExpectation,
            deadline: wait.defaultDeadline
        )
    }

    public static func checkpoint(_ checkpoint: BatchExecutionCheckpoint) -> BatchStep {
        BatchStep(
            operation: .checkpoint(CheckpointAction(name: checkpoint.name)),
            expectation: checkpoint.expect,
            deadline: Deadline(timeout: checkpoint.timeout)
        )
    }
}

extension BatchStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("step", [
            "operation=\(operation)",
            "expect=\(expectation)",
            "deadline=\(deadline)",
        ])
    }
}

extension BatchStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, action, wait, checkpoint, expect, deadline
    }

    private enum Kind: String, Codable {
        case action, wait, checkpoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.action) {
            let action = try container.decode(Action.self, forKey: .action)
            let operation = BatchOperation(legacyAction: action)
            self.init(
                operation: operation,
                expectation: try container.decodeIfPresent(ActionExpectation.self, forKey: .expect)
                    ?? operation.defaultExpectation,
                deadline: try container.decodeIfPresent(Deadline.self, forKey: .deadline)
                    ?? operation.defaultDeadline
            )
            return
        }

        switch try container.decode(Kind.self, forKey: .kind) {
        case .action:
            let action = try container.decode(Action.self, forKey: .action)
            let operation = BatchOperation(legacyAction: action)
            self.init(
                operation: operation,
                expectation: try container.decodeIfPresent(ActionExpectation.self, forKey: .expect)
                    ?? operation.defaultExpectation,
                deadline: try container.decodeIfPresent(Deadline.self, forKey: .deadline)
                    ?? operation.defaultDeadline
            )
        case .wait:
            self = .wait(try container.decode(BatchExecutionWait.self, forKey: .wait))
        case .checkpoint:
            self = .checkpoint(try container.decode(BatchExecutionCheckpoint.self, forKey: .checkpoint))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operation.legacyAction, forKey: .action)
        try container.encode(expectation, forKey: .expect)
        try container.encode(deadline, forKey: .deadline)
    }
}

public typealias BatchExecutionStep = BatchStep

/// Executable operation carried by a batch step. Checkpoints are distinct from
/// user actions so execution never has to fake a successful tap just to wait on
/// an expectation.
public enum BatchOperation: Sendable {
    case action(Action)
    case checkpoint(CheckpointAction)
}

extension BatchOperation {
    init(legacyAction: Action) {
        switch legacyAction {
        case .checkpoint(let checkpoint):
            self = .checkpoint(checkpoint)
        default:
            self = .action(legacyAction)
        }
    }

    var legacyAction: Action {
        switch self {
        case .action(let action):
            return action
        case .checkpoint(let checkpoint):
            return .checkpoint(checkpoint)
        }
    }

    public var defaultExpectation: ActionExpectation {
        switch self {
        case .action(let action):
            return action.defaultExpectation
        case .checkpoint:
            return .delivery
        }
    }

    public var defaultDeadline: Deadline {
        switch self {
        case .action(let action):
            return action.defaultDeadline
        case .checkpoint:
            return Deadline()
        }
    }
}

extension BatchOperation: CustomStringConvertible {
    public var description: String {
        switch self {
        case .action(let action):
            return action.description
        case .checkpoint(let checkpoint):
            return checkpoint.description
        }
    }
}

extension BatchOperation: Codable {
    private enum CodingKeys: String, CodingKey {
        case action, checkpoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.checkpoint) {
            self = .checkpoint(try container.decode(CheckpointAction.self, forKey: .checkpoint))
        } else {
            self = .action(try container.decode(Action.self, forKey: .action))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let action):
            try container.encode(action, forKey: .action)
        case .checkpoint(let checkpoint):
            try container.encode(checkpoint, forKey: .checkpoint)
        }
    }
}

/// A batch-executable action primitive. Targeted variants use
/// `BatchExecutionTarget`, so heistId can only appear as source metadata.
public enum Action: Sendable {
    case activate(BatchExecutionTarget)
    case increment(BatchExecutionTarget)
    case decrement(BatchExecutionTarget)
    case performCustomAction(BatchCustomActionTarget)
    case rotor(BatchRotorTarget)
    case touchTap(BatchTouchTapTarget)
    case touchLongPress(BatchLongPressTarget)
    case touchSwipe(BatchSwipeTarget)
    case touchDrag(BatchDragTarget)
    case touchPinch(BatchPinchTarget)
    case touchRotate(BatchRotateTarget)
    case touchTwoFingerTap(BatchTwoFingerTapTarget)
    case touchDrawPath(DrawPathTarget)
    case touchDrawBezier(DrawBezierTarget)
    case typeText(BatchTypeTextTarget)
    case editAction(EditActionTarget)
    case setPasteboard(SetPasteboardTarget)
    case scroll(BatchScrollTarget)
    case scrollToVisible(BatchScrollToVisibleTarget)
    case elementSearch(BatchElementSearchTarget)
    case scrollToEdge(BatchScrollToEdgeTarget)
    case waitForIdle(WaitForIdleTarget)
    case waitForElement(BatchWaitForTarget)
    case waitForChange(WaitForChangeTarget)
    case checkpoint(CheckpointAction)
    case explore
    case resignFirstResponder
}

public typealias BatchExecutionAction = Action

extension Action: CustomStringConvertible {
    public var description: String {
        switch self {
        case .activate(let target): return ScoreDescription.call("activate", [target.description])
        case .increment(let target): return ScoreDescription.call("increment", [target.description])
        case .decrement(let target): return ScoreDescription.call("decrement", [target.description])
        case .performCustomAction(let target): return target.description
        case .rotor(let target): return target.description
        case .touchTap(let target): return target.description
        case .touchLongPress(let target): return target.description
        case .touchSwipe(let target): return target.description
        case .touchDrag(let target): return target.description
        case .touchPinch(let target): return target.description
        case .touchRotate(let target): return target.description
        case .touchTwoFingerTap(let target): return target.description
        case .touchDrawPath(let target): return target.description
        case .touchDrawBezier(let target): return target.description
        case .typeText(let target): return target.description
        case .editAction(let target): return target.description
        case .setPasteboard(let target): return target.description
        case .scroll(let target): return target.description
        case .scrollToVisible(let target): return target.description
        case .elementSearch(let target): return target.description
        case .scrollToEdge(let target): return target.description
        case .waitForIdle(let target): return target.description
        case .waitForElement(let target): return target.description
        case .waitForChange(let target): return target.description
        case .checkpoint(let target): return target.description
        case .explore: return "explore"
        case .resignFirstResponder: return "resignFirstResponder"
        }
    }
}

extension Action: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case target
    }

    private enum WireType: String, Codable {
        case activate
        case increment
        case decrement
        case performCustomAction = "perform_custom_action"
        case rotor
        case touchTap = "touch_tap"
        case touchLongPress = "touch_long_press"
        case touchSwipe = "touch_swipe"
        case touchDrag = "touch_drag"
        case touchPinch = "touch_pinch"
        case touchRotate = "touch_rotate"
        case touchTwoFingerTap = "touch_two_finger_tap"
        case touchDrawPath = "touch_draw_path"
        case touchDrawBezier = "touch_draw_bezier"
        case typeText = "type_text"
        case editAction = "edit_action"
        case setPasteboard = "set_pasteboard"
        case getPasteboard = "get_pasteboard"
        case scroll
        case scrollToVisible = "scroll_to_visible"
        case elementSearch = "element_search"
        case scrollToEdge = "scroll_to_edge"
        case waitForIdle = "wait_for_idle"
        case waitForElement = "wait_for"
        case waitForChange = "wait_for_change"
        case checkpoint
        case explore
        case resignFirstResponder = "resign_first_responder"
    }

    public var defaultExpectation: ActionExpectation {
        switch self {
        case .waitForElement(let target):
            return target.resolvedAbsent
                ? .elementDisappeared(target.target.matcher)
                : .elementAppeared(target.target.matcher)
        case .waitForChange(let target):
            return target.expect ?? .screenChanged
        default:
            return .delivery
        }
    }

    public var defaultDeadline: Deadline {
        switch self {
        case .waitForIdle(let target):
            return Deadline(timeout: target.timeout ?? 5)
        case .waitForElement(let target):
            return Deadline(timeout: target.resolvedTimeout)
        case .waitForChange(let target):
            return Deadline(timeout: target.resolvedTimeout)
        default:
            return Deadline()
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(WireType.self, forKey: .type) {
        case .activate:
            self = .activate(try container.decode(BatchExecutionTarget.self, forKey: .target))
        case .increment:
            self = .increment(try container.decode(BatchExecutionTarget.self, forKey: .target))
        case .decrement:
            self = .decrement(try container.decode(BatchExecutionTarget.self, forKey: .target))
        case .performCustomAction:
            self = .performCustomAction(try BatchCustomActionTarget(from: decoder))
        case .rotor:
            self = .rotor(try BatchRotorTarget(from: decoder))
        case .touchTap:
            self = .touchTap(try BatchTouchTapTarget(from: decoder))
        case .touchLongPress:
            self = .touchLongPress(try BatchLongPressTarget(from: decoder))
        case .touchSwipe:
            self = .touchSwipe(try BatchSwipeTarget(from: decoder))
        case .touchDrag:
            self = .touchDrag(try BatchDragTarget(from: decoder))
        case .touchPinch:
            self = .touchPinch(try BatchPinchTarget(from: decoder))
        case .touchRotate:
            self = .touchRotate(try BatchRotateTarget(from: decoder))
        case .touchTwoFingerTap:
            self = .touchTwoFingerTap(try BatchTwoFingerTapTarget(from: decoder))
        case .touchDrawPath:
            self = .touchDrawPath(try container.decode(DrawPathTarget.self, forKey: .target))
        case .touchDrawBezier:
            self = .touchDrawBezier(try container.decode(DrawBezierTarget.self, forKey: .target))
        case .typeText:
            self = .typeText(try BatchTypeTextTarget(from: decoder))
        case .editAction:
            self = .editAction(try container.decode(EditActionTarget.self, forKey: .target))
        case .setPasteboard:
            self = .setPasteboard(try container.decode(SetPasteboardTarget.self, forKey: .target))
        case .getPasteboard:
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "get_pasteboard is a read operation and is not a batch Action"
            ))
        case .scroll:
            self = .scroll(try BatchScrollTarget(from: decoder))
        case .scrollToVisible:
            self = .scrollToVisible(try BatchScrollToVisibleTarget(from: decoder))
        case .elementSearch:
            self = .elementSearch(try BatchElementSearchTarget(from: decoder))
        case .scrollToEdge:
            self = .scrollToEdge(try BatchScrollToEdgeTarget(from: decoder))
        case .waitForIdle:
            self = .waitForIdle(try container.decode(WaitForIdleTarget.self, forKey: .target))
        case .waitForElement:
            self = .waitForElement(try container.decode(BatchWaitForTarget.self, forKey: .target))
        case .waitForChange:
            self = .waitForChange(try container.decode(WaitForChangeTarget.self, forKey: .target))
        case .checkpoint:
            self = .checkpoint(try CheckpointAction(from: decoder))
        case .explore:
            self = .explore
        case .resignFirstResponder:
            self = .resignFirstResponder
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .activate(let target):
            try container.encode(WireType.activate, forKey: .type)
            try container.encode(target, forKey: .target)
        case .increment(let target):
            try container.encode(WireType.increment, forKey: .type)
            try container.encode(target, forKey: .target)
        case .decrement(let target):
            try container.encode(WireType.decrement, forKey: .type)
            try container.encode(target, forKey: .target)
        case .performCustomAction(let target):
            try container.encode(WireType.performCustomAction, forKey: .type)
            try target.encode(to: encoder)
        case .rotor(let target):
            try container.encode(WireType.rotor, forKey: .type)
            try target.encode(to: encoder)
        case .touchTap(let target):
            try container.encode(WireType.touchTap, forKey: .type)
            try target.encode(to: encoder)
        case .touchLongPress(let target):
            try container.encode(WireType.touchLongPress, forKey: .type)
            try target.encode(to: encoder)
        case .touchSwipe(let target):
            try container.encode(WireType.touchSwipe, forKey: .type)
            try target.encode(to: encoder)
        case .touchDrag(let target):
            try container.encode(WireType.touchDrag, forKey: .type)
            try target.encode(to: encoder)
        case .touchPinch(let target):
            try container.encode(WireType.touchPinch, forKey: .type)
            try target.encode(to: encoder)
        case .touchRotate(let target):
            try container.encode(WireType.touchRotate, forKey: .type)
            try target.encode(to: encoder)
        case .touchTwoFingerTap(let target):
            try container.encode(WireType.touchTwoFingerTap, forKey: .type)
            try target.encode(to: encoder)
        case .touchDrawPath(let target):
            try container.encode(WireType.touchDrawPath, forKey: .type)
            try container.encode(target, forKey: .target)
        case .touchDrawBezier(let target):
            try container.encode(WireType.touchDrawBezier, forKey: .type)
            try container.encode(target, forKey: .target)
        case .typeText(let target):
            try container.encode(WireType.typeText, forKey: .type)
            try target.encode(to: encoder)
        case .editAction(let target):
            try container.encode(WireType.editAction, forKey: .type)
            try container.encode(target, forKey: .target)
        case .setPasteboard(let target):
            try container.encode(WireType.setPasteboard, forKey: .type)
            try container.encode(target, forKey: .target)
        case .scroll(let target):
            try container.encode(WireType.scroll, forKey: .type)
            try target.encode(to: encoder)
        case .scrollToVisible(let target):
            try container.encode(WireType.scrollToVisible, forKey: .type)
            try target.encode(to: encoder)
        case .elementSearch(let target):
            try container.encode(WireType.elementSearch, forKey: .type)
            try target.encode(to: encoder)
        case .scrollToEdge(let target):
            try container.encode(WireType.scrollToEdge, forKey: .type)
            try target.encode(to: encoder)
        case .waitForIdle(let target):
            try container.encode(WireType.waitForIdle, forKey: .type)
            try container.encode(target, forKey: .target)
        case .waitForElement(let target):
            try container.encode(WireType.waitForElement, forKey: .type)
            try container.encode(target, forKey: .target)
        case .waitForChange(let target):
            try container.encode(WireType.waitForChange, forKey: .type)
            try container.encode(target, forKey: .target)
        case .checkpoint(let target):
            try container.encode(WireType.checkpoint, forKey: .type)
            try target.encode(to: encoder)
        case .explore:
            try container.encode(WireType.explore, forKey: .type)
        case .resignFirstResponder:
            try container.encode(WireType.resignFirstResponder, forKey: .type)
        }
    }
}

public struct CheckpointAction: Codable, Sendable, Equatable {
    public let name: String?

    public init(name: String? = nil) {
        self.name = name
    }
}

extension CheckpointAction: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("checkpoint", [
            ScoreDescription.stringField("name", name),
        ].compactMap { $0 })
    }
}

public enum BatchExecutionWait: Sendable {
    case idle(WaitForIdleTarget)
    case element(BatchWaitForTarget)
    case change(WaitForChangeTarget)
}

extension BatchExecutionWait: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle(let target): return target.description
        case .element(let target): return target.description
        case .change(let target): return target.description
        }
    }
}

extension BatchExecutionWait: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, target
    }

    private enum WireType: String, Codable {
        case idle = "wait_for_idle"
        case element = "wait_for"
        case change = "wait_for_change"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(WireType.self, forKey: .type) {
        case .idle:
            self = .idle(try container.decode(WaitForIdleTarget.self, forKey: .target))
        case .element:
            self = .element(try container.decode(BatchWaitForTarget.self, forKey: .target))
        case .change:
            self = .change(try container.decode(WaitForChangeTarget.self, forKey: .target))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle(let target):
            try container.encode(WireType.idle, forKey: .type)
            try container.encode(target, forKey: .target)
        case .element(let target):
            try container.encode(WireType.element, forKey: .type)
            try container.encode(target, forKey: .target)
        case .change(let target):
            try container.encode(WireType.change, forKey: .type)
            try container.encode(target, forKey: .target)
        }
    }
}

extension BatchExecutionWait {
    public var action: Action {
        switch self {
        case .idle(let target):
            return .waitForIdle(target)
        case .element(let target):
            return .waitForElement(target)
        case .change(let target):
            return .waitForChange(target)
        }
    }

    public var defaultExpectation: ActionExpectation {
        action.defaultExpectation
    }

    public var defaultDeadline: Deadline {
        action.defaultDeadline
    }
}

public struct BatchExecutionCheckpoint: Codable, Sendable {
    public let name: String?
    public let expect: ActionExpectation
    public let timeout: Double?

    public init(name: String? = nil, expect: ActionExpectation, timeout: Double? = nil) {
        self.name = name
        self.expect = expect
        self.timeout = timeout
    }
}

extension BatchExecutionCheckpoint: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("checkpoint", [
            ScoreDescription.stringField("name", name),
            "expect=\(expect)",
            timeout.map { "timeout=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}
