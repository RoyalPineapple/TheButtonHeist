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

private enum ActionCodingKeys: String, CodingKey {
    case type
    case target
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
    public let canonicalName: String
    public let actionMethod: ActionMethod
    public let fulfillsOwnExpectation: Bool
    public let defaultExpectation: ActionExpectation
    public let defaultDeadline: Deadline

    public init(kind: Kind) {
        let contract = kind.contract
        self.kind = kind
        self.canonicalName = kind.rawValue
        self.actionMethod = contract.actionMethod
        self.fulfillsOwnExpectation = contract.fulfillsOwnExpectation
        self.defaultExpectation = contract.defaultExpectation
        self.defaultDeadline = contract.defaultDeadline
    }

    public init(
        kind: Kind,
        defaultExpectation: ActionExpectation,
        defaultDeadline: Deadline
    ) {
        let contract = kind.contract
        self.kind = kind
        self.canonicalName = kind.rawValue
        self.actionMethod = contract.actionMethod
        self.fulfillsOwnExpectation = contract.fulfillsOwnExpectation
        self.defaultExpectation = defaultExpectation
        self.defaultDeadline = defaultDeadline
    }
}

private extension ActionDescriptor.Kind {
    struct Contract {
        let actionMethod: ActionMethod
        let fulfillsOwnExpectation: Bool
        let defaultExpectation: ActionExpectation
        let defaultDeadline: Deadline
        let decodeAction: (Decoder) throws -> Action

        init(
            _ actionMethod: ActionMethod,
            fulfillsOwnExpectation: Bool = false,
            defaultExpectation: ActionExpectation = .delivery,
            defaultDeadline: Deadline = Deadline(),
            decode: @escaping (Decoder) throws -> Action
        ) {
            self.actionMethod = actionMethod
            self.fulfillsOwnExpectation = fulfillsOwnExpectation
            self.defaultExpectation = defaultExpectation
            self.defaultDeadline = defaultDeadline
            self.decodeAction = decode
        }
    }

    var contract: Contract {
        switch self {
        case .activate:
            return Contract(.activate, decode: Self.decodeTarget(BatchExecutionTarget.self, Action.activate))
        case .increment:
            return Contract(.increment, decode: Self.decodeTarget(BatchExecutionTarget.self, Action.increment))
        case .decrement:
            return Contract(.decrement, decode: Self.decodeTarget(BatchExecutionTarget.self, Action.decrement))
        case .performCustomAction:
            return Contract(
                .customAction,
                decode: Self.decodeInline(BatchCustomActionTarget.self, Action.performCustomAction)
            )
        case .rotor:
            return Contract(.rotor, decode: Self.decodeInline(BatchRotorTarget.self, Action.rotor))
        case .touchTap:
            return Contract(.syntheticTap, decode: Self.decodeInline(BatchTouchTapTarget.self, Action.touchTap))
        case .touchLongPress:
            return Contract(
                .syntheticLongPress,
                decode: Self.decodeInline(BatchLongPressTarget.self, Action.touchLongPress)
            )
        case .touchSwipe:
            return Contract(.syntheticSwipe, decode: Self.decodeInline(BatchSwipeTarget.self, Action.touchSwipe))
        case .touchDrag:
            return Contract(.syntheticDrag, decode: Self.decodeInline(BatchDragTarget.self, Action.touchDrag))
        case .touchPinch:
            return Contract(.syntheticPinch, decode: Self.decodeInline(BatchPinchTarget.self, Action.touchPinch))
        case .touchRotate:
            return Contract(.syntheticRotate, decode: Self.decodeInline(BatchRotateTarget.self, Action.touchRotate))
        case .touchTwoFingerTap:
            return Contract(
                .syntheticTwoFingerTap,
                decode: Self.decodeInline(BatchTwoFingerTapTarget.self, Action.touchTwoFingerTap)
            )
        case .touchDrawPath:
            return Contract(
                .syntheticDrawPath,
                decode: Self.decodeTarget(DrawPathTarget.self, Action.touchDrawPath)
            )
        case .touchDrawBezier:
            return Contract(
                .syntheticDrawPath,
                decode: Self.decodeTarget(DrawBezierTarget.self, Action.touchDrawBezier)
            )
        case .typeText:
            return Contract(.typeText, decode: Self.decodeInline(BatchTypeTextTarget.self, Action.typeText))
        case .editAction:
            return Contract(.editAction, decode: Self.decodeTarget(EditActionTarget.self, Action.editAction))
        case .setPasteboard:
            return Contract(
                .setPasteboard,
                decode: Self.decodeTarget(SetPasteboardTarget.self, Action.setPasteboard)
            )
        case .scroll:
            return Contract(.scroll, decode: Self.decodeInline(BatchScrollTarget.self, Action.scroll))
        case .scrollToVisible:
            return Contract(
                .scrollToVisible,
                decode: Self.decodeInline(BatchScrollToVisibleTarget.self, Action.scrollToVisible)
            )
        case .elementSearch:
            return Contract(
                .elementSearch,
                decode: Self.decodeInline(BatchElementSearchTarget.self, Action.elementSearch)
            )
        case .scrollToEdge:
            return Contract(
                .scrollToEdge,
                decode: Self.decodeInline(BatchScrollToEdgeTarget.self, Action.scrollToEdge)
            )
        case .waitForIdle:
            return Contract(
                .waitForIdle,
                defaultDeadline: Deadline(timeout: 5),
                decode: Self.decodeTarget(WaitForIdleTarget.self, Action.waitForIdle)
            )
        case .waitForElement:
            return Contract(
                .waitFor,
                fulfillsOwnExpectation: true,
                defaultDeadline: Deadline(timeout: 30),
                decode: Self.decodeTarget(BatchWaitForTarget.self, Action.waitForElement)
            )
        case .waitForChange:
            return Contract(
                .waitForChange,
                fulfillsOwnExpectation: true,
                defaultExpectation: .screenChanged,
                defaultDeadline: Deadline(timeout: 30),
                decode: Self.decodeTarget(WaitForChangeTarget.self, Action.waitForChange)
            )
        case .explore:
            return Contract(.explore, decode: Self.decodeNoPayload(.explore))
        case .resignFirstResponder:
            return Contract(
                .resignFirstResponder,
                decode: Self.decodeNoPayload(.resignFirstResponder)
            )
        }
    }

    static func decodeTarget<T: Decodable>(
        _ type: T.Type,
        _ build: @escaping (T) -> Action
    ) -> (Decoder) throws -> Action {
        { decoder in
            let container = try decoder.container(keyedBy: ActionCodingKeys.self)
            return build(try container.decode(type, forKey: .target))
        }
    }

    static func decodeInline<T: Decodable>(
        _ type: T.Type,
        _ build: @escaping (T) -> Action
    ) -> (Decoder) throws -> Action {
        { decoder in
            build(try type.init(from: decoder))
        }
    }

    static func decodeNoPayload(_ action: Action) -> (Decoder) throws -> Action {
        { _ in action }
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

private struct ActionProjection {
    let descriptor: ActionDescriptor
    let description: String
    let payload: ActionPayloadEncoding

    init(
        kind: ActionDescriptor.Kind,
        description: String,
        payload: ActionPayloadEncoding
    ) {
        self.descriptor = ActionDescriptor(kind: kind)
        self.description = description
        self.payload = payload
    }

    init(
        descriptor: ActionDescriptor,
        description: String,
        payload: ActionPayloadEncoding
    ) {
        self.descriptor = descriptor
        self.description = description
        self.payload = payload
    }
}

private struct ActionPayloadEncoding {
    let encode: (Encoder, inout KeyedEncodingContainer<ActionCodingKeys>) throws -> Void

    static var none: ActionPayloadEncoding {
        ActionPayloadEncoding { _, _ in }
    }

    static func keyedTarget<T: Encodable>(_ value: T) -> ActionPayloadEncoding {
        ActionPayloadEncoding { _, container in
            try container.encode(value, forKey: .target)
        }
    }

    static func inline<T: Encodable>(_ value: T) -> ActionPayloadEncoding {
        ActionPayloadEncoding { encoder, _ in
            try value.encode(to: encoder)
        }
    }
}

private extension Action {
    var projection: ActionProjection {
        switch self {
        case .activate(let target):
            return ActionProjection(
                kind: .activate,
                description: ScoreDescription.call("activate", [target.description]),
                payload: .keyedTarget(target)
            )
        case .increment(let target):
            return ActionProjection(
                kind: .increment,
                description: ScoreDescription.call("increment", [target.description]),
                payload: .keyedTarget(target)
            )
        case .decrement(let target):
            return ActionProjection(
                kind: .decrement,
                description: ScoreDescription.call("decrement", [target.description]),
                payload: .keyedTarget(target)
            )
        case .performCustomAction(let target):
            return ActionProjection(kind: .performCustomAction, description: target.description, payload: .inline(target))
        case .rotor(let target):
            return ActionProjection(kind: .rotor, description: target.description, payload: .inline(target))
        case .touchTap(let target):
            return ActionProjection(kind: .touchTap, description: target.description, payload: .inline(target))
        case .touchLongPress(let target):
            return ActionProjection(kind: .touchLongPress, description: target.description, payload: .inline(target))
        case .touchSwipe(let target):
            return ActionProjection(kind: .touchSwipe, description: target.description, payload: .inline(target))
        case .touchDrag(let target):
            return ActionProjection(kind: .touchDrag, description: target.description, payload: .inline(target))
        case .touchPinch(let target):
            return ActionProjection(kind: .touchPinch, description: target.description, payload: .inline(target))
        case .touchRotate(let target):
            return ActionProjection(kind: .touchRotate, description: target.description, payload: .inline(target))
        case .touchTwoFingerTap(let target):
            return ActionProjection(kind: .touchTwoFingerTap, description: target.description, payload: .inline(target))
        case .touchDrawPath(let target):
            return ActionProjection(kind: .touchDrawPath, description: target.description, payload: .keyedTarget(target))
        case .touchDrawBezier(let target):
            return ActionProjection(kind: .touchDrawBezier, description: target.description, payload: .keyedTarget(target))
        case .typeText(let target):
            return ActionProjection(kind: .typeText, description: target.description, payload: .inline(target))
        case .editAction(let target):
            return ActionProjection(kind: .editAction, description: target.description, payload: .keyedTarget(target))
        case .setPasteboard(let target):
            return ActionProjection(kind: .setPasteboard, description: target.description, payload: .keyedTarget(target))
        case .scroll(let target):
            return ActionProjection(kind: .scroll, description: target.description, payload: .inline(target))
        case .scrollToVisible(let target):
            return ActionProjection(kind: .scrollToVisible, description: target.description, payload: .inline(target))
        case .elementSearch(let target):
            return ActionProjection(kind: .elementSearch, description: target.description, payload: .inline(target))
        case .scrollToEdge(let target):
            return ActionProjection(kind: .scrollToEdge, description: target.description, payload: .inline(target))
        case .waitForIdle(let target):
            return ActionProjection(
                descriptor: ActionDescriptor(
                    kind: .waitForIdle,
                    defaultExpectation: .delivery,
                    defaultDeadline: Deadline(timeout: target.timeout ?? 5)
                ),
                description: target.description,
                payload: .keyedTarget(target)
            )
        case .waitForElement(let target):
            return ActionProjection(
                descriptor: ActionDescriptor(
                    kind: .waitForElement,
                    defaultExpectation: target.resolvedAbsent
                        ? .elementDisappeared(target.target.matcher)
                        : .elementAppeared(target.target.matcher),
                    defaultDeadline: Deadline(timeout: target.resolvedTimeout)
                ),
                description: target.description,
                payload: .keyedTarget(target)
            )
        case .waitForChange(let target):
            return ActionProjection(
                descriptor: ActionDescriptor(
                    kind: .waitForChange,
                    defaultExpectation: target.expect ?? .screenChanged,
                    defaultDeadline: Deadline(timeout: target.resolvedTimeout)
                ),
                description: target.description,
                payload: .keyedTarget(target)
            )
        case .explore:
            return ActionProjection(kind: .explore, description: "explore", payload: .none)
        case .resignFirstResponder:
            return ActionProjection(
                kind: .resignFirstResponder,
                description: "resign_first_responder",
                payload: .none
            )
        }
    }
}

extension Action: CustomStringConvertible {
    public var description: String {
        projection.description
    }
}

extension Action {
    public var descriptor: ActionDescriptor {
        projection.descriptor
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
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ActionCodingKeys.self)
        let canonicalName = try container.decode(String.self, forKey: .type)
        guard let kind = ActionDescriptor.Kind(rawValue: canonicalName) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown batch action type: \(canonicalName)"
            )
        }
        self = try kind.contract.decodeAction(decoder)
    }

    public func encode(to encoder: Encoder) throws {
        let projection = projection
        var container = encoder.container(keyedBy: ActionCodingKeys.self)
        try container.encode(projection.descriptor.canonicalName, forKey: .type)
        try projection.payload.encode(encoder, &container)
    }
}
