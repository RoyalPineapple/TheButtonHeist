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

/// The explicit wire and execution contract for a batch `Action`.
public struct ActionDescriptor: Sendable, Equatable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
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
        case scroll
        case scrollToVisible = "scroll_to_visible"
        case elementSearch = "element_search"
        case scrollToEdge = "scroll_to_edge"
        case waitForIdle = "wait_for_idle"
        case waitForElement = "wait_for"
        case waitForChange = "wait_for_change"
        case explore
        case resignFirstResponder = "resign_first_responder"
    }

    public let kind: Kind
    public let actionMethod: ActionMethod
    public let fulfillsOwnExpectation: Bool
    public let defaultExpectation: ActionExpectation
    public let defaultDeadline: Deadline

    public var canonicalName: String {
        kind.rawValue
    }

    public init(
        kind: Kind,
        defaultExpectation: ActionExpectation = .delivery,
        defaultDeadline: Deadline = Deadline()
    ) {
        self.kind = kind
        self.actionMethod = kind.actionMethod
        self.fulfillsOwnExpectation = kind.fulfillsOwnExpectation
        self.defaultExpectation = defaultExpectation
        self.defaultDeadline = defaultDeadline
    }
}

private extension ActionDescriptor.Kind {
    var actionMethod: ActionMethod {
        switch self {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .performCustomAction: return .customAction
        case .rotor: return .rotor
        case .touchTap: return .syntheticTap
        case .touchLongPress: return .syntheticLongPress
        case .touchSwipe: return .syntheticSwipe
        case .touchDrag: return .syntheticDrag
        case .touchPinch: return .syntheticPinch
        case .touchRotate: return .syntheticRotate
        case .touchTwoFingerTap: return .syntheticTwoFingerTap
        case .touchDrawPath, .touchDrawBezier: return .syntheticDrawPath
        case .typeText: return .typeText
        case .editAction: return .editAction
        case .setPasteboard: return .setPasteboard
        case .scroll: return .scroll
        case .scrollToVisible: return .scrollToVisible
        case .elementSearch: return .elementSearch
        case .scrollToEdge: return .scrollToEdge
        case .waitForIdle: return .waitForIdle
        case .waitForElement: return .waitFor
        case .waitForChange: return .waitForChange
        case .explore: return .explore
        case .resignFirstResponder: return .resignFirstResponder
        }
    }

    var fulfillsOwnExpectation: Bool {
        switch self {
        case .waitForElement, .waitForChange:
            return true
        default:
            return false
        }
    }
}

/// One executable non-read operation in a batch plan.
public struct BatchStep: Sendable {
    public let action: Action
    public let expectation: ActionExpectation
    public let deadline: Deadline

    public init(
        action: Action,
        expectation: ActionExpectation,
        deadline: Deadline
    ) {
        self.action = action
        self.expectation = expectation
        self.deadline = deadline
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
}

extension BatchStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("step", [
            "action=\(action)",
            "expect=\(expectation)",
            "deadline=\(deadline)",
        ])
    }
}

extension BatchStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case action, expect, deadline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(Action.self, forKey: .action)
        self.init(
            action: action,
            expectation: try container.decodeIfPresent(ActionExpectation.self, forKey: .expect)
                ?? action.defaultExpectation,
            deadline: try container.decodeIfPresent(Deadline.self, forKey: .deadline)
                ?? action.defaultDeadline
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encode(expectation, forKey: .expect)
        try container.encode(deadline, forKey: .deadline)
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
    case explore
    case resignFirstResponder
}

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
        case .explore: return "explore"
        case .resignFirstResponder: return "resign_first_responder"
        }
    }
}

extension Action {
    public var descriptor: ActionDescriptor {
        switch self {
        case .activate:
            return ActionDescriptor(kind: .activate)
        case .increment:
            return ActionDescriptor(kind: .increment)
        case .decrement:
            return ActionDescriptor(kind: .decrement)
        case .performCustomAction:
            return ActionDescriptor(kind: .performCustomAction)
        case .rotor:
            return ActionDescriptor(kind: .rotor)
        case .touchTap:
            return ActionDescriptor(kind: .touchTap)
        case .touchLongPress:
            return ActionDescriptor(kind: .touchLongPress)
        case .touchSwipe:
            return ActionDescriptor(kind: .touchSwipe)
        case .touchDrag:
            return ActionDescriptor(kind: .touchDrag)
        case .touchPinch:
            return ActionDescriptor(kind: .touchPinch)
        case .touchRotate:
            return ActionDescriptor(kind: .touchRotate)
        case .touchTwoFingerTap:
            return ActionDescriptor(kind: .touchTwoFingerTap)
        case .touchDrawPath:
            return ActionDescriptor(kind: .touchDrawPath)
        case .touchDrawBezier:
            return ActionDescriptor(kind: .touchDrawBezier)
        case .typeText:
            return ActionDescriptor(kind: .typeText)
        case .editAction:
            return ActionDescriptor(kind: .editAction)
        case .setPasteboard:
            return ActionDescriptor(kind: .setPasteboard)
        case .scroll:
            return ActionDescriptor(kind: .scroll)
        case .scrollToVisible:
            return ActionDescriptor(kind: .scrollToVisible)
        case .elementSearch:
            return ActionDescriptor(kind: .elementSearch)
        case .scrollToEdge:
            return ActionDescriptor(kind: .scrollToEdge)
        case .waitForIdle(let target):
            return ActionDescriptor(
                kind: .waitForIdle,
                defaultDeadline: Deadline(timeout: target.timeout ?? 5)
            )
        case .waitForElement(let target):
            return ActionDescriptor(
                kind: .waitForElement,
                defaultExpectation: target.resolvedAbsent
                    ? .elementDisappeared(target.target.matcher)
                    : .elementAppeared(target.target.matcher),
                defaultDeadline: Deadline(timeout: target.resolvedTimeout)
            )
        case .waitForChange(let target):
            return ActionDescriptor(
                kind: .waitForChange,
                defaultExpectation: target.expect ?? .screenChanged,
                defaultDeadline: Deadline(timeout: target.resolvedTimeout)
            )
        case .explore:
            return ActionDescriptor(kind: .explore)
        case .resignFirstResponder:
            return ActionDescriptor(kind: .resignFirstResponder)
        }
    }

    public var canonicalName: String {
        descriptor.canonicalName
    }

    public var actionMethod: ActionMethod {
        descriptor.actionMethod
    }

    public var fulfillsOwnExpectation: Bool {
        descriptor.fulfillsOwnExpectation
    }

    public var defaultExpectation: ActionExpectation {
        descriptor.defaultExpectation
    }

    public var defaultDeadline: Deadline {
        descriptor.defaultDeadline
    }
}

extension Action: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ActionDescriptor.Kind.self, forKey: .type) {
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
        case .explore:
            self = .explore
        case .resignFirstResponder:
            self = .resignFirstResponder
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(descriptor.kind, forKey: .type)
        switch self {
        case .activate(let target):
            try container.encode(target, forKey: .target)
        case .increment(let target):
            try container.encode(target, forKey: .target)
        case .decrement(let target):
            try container.encode(target, forKey: .target)
        case .performCustomAction(let target):
            try target.encode(to: encoder)
        case .rotor(let target):
            try target.encode(to: encoder)
        case .touchTap(let target):
            try target.encode(to: encoder)
        case .touchLongPress(let target):
            try target.encode(to: encoder)
        case .touchSwipe(let target):
            try target.encode(to: encoder)
        case .touchDrag(let target):
            try target.encode(to: encoder)
        case .touchPinch(let target):
            try target.encode(to: encoder)
        case .touchRotate(let target):
            try target.encode(to: encoder)
        case .touchTwoFingerTap(let target):
            try target.encode(to: encoder)
        case .touchDrawPath(let target):
            try container.encode(target, forKey: .target)
        case .touchDrawBezier(let target):
            try container.encode(target, forKey: .target)
        case .typeText(let target):
            try target.encode(to: encoder)
        case .editAction(let target):
            try container.encode(target, forKey: .target)
        case .setPasteboard(let target):
            try container.encode(target, forKey: .target)
        case .scroll(let target):
            try target.encode(to: encoder)
        case .scrollToVisible(let target):
            try target.encode(to: encoder)
        case .elementSearch(let target):
            try target.encode(to: encoder)
        case .scrollToEdge(let target):
            try target.encode(to: encoder)
        case .waitForIdle(let target):
            try container.encode(target, forKey: .target)
        case .waitForElement(let target):
            try container.encode(target, forKey: .target)
        case .waitForChange(let target):
            try container.encode(target, forKey: .target)
        case .explore, .resignFirstResponder:
            break
        }
    }
}
