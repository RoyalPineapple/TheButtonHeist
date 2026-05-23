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
        let contract = ActionContract.required(for: kind)
        self.init(
            kind: kind,
            actionMethod: contract.actionMethod,
            fulfillsOwnExpectation: contract.fulfillsOwnExpectation,
            defaultExpectation: contract.defaultExpectation,
            defaultDeadline: contract.defaultDeadline
        )
    }

    public init(kind: Kind, defaultExpectation: ActionExpectation, defaultDeadline: Deadline) {
        let contract = ActionContract.required(for: kind)
        self.init(
            kind: kind,
            actionMethod: contract.actionMethod,
            fulfillsOwnExpectation: contract.fulfillsOwnExpectation,
            defaultExpectation: defaultExpectation,
            defaultDeadline: defaultDeadline
        )
    }
}

private extension ActionDescriptor {
    init(kind: Kind, actionMethod: ActionMethod, fulfillsOwnExpectation: Bool, defaultExpectation: ActionExpectation, defaultDeadline: Deadline) {
        self.kind = kind
        self.canonicalName = kind.rawValue
        self.actionMethod = actionMethod
        self.fulfillsOwnExpectation = fulfillsOwnExpectation
        self.defaultExpectation = defaultExpectation
        self.defaultDeadline = defaultDeadline
    }
}

private struct ActionContract: Sendable {
    let kind: ActionDescriptor.Kind
    let actionMethod: ActionMethod
    let fulfillsOwnExpectation: Bool
    let defaultExpectation: ActionExpectation
    let defaultDeadline: Deadline
    let decodeAction: @Sendable (Decoder) throws -> Action
    let projectAction: @Sendable (Action) -> ActionProjection?
}

private extension ActionContract {
    typealias DescriptorOverride<T> = @Sendable (T) -> (expectation: ActionExpectation, deadline: Deadline)?

    static let all: [ActionContract] = [
        .keyedTarget(.activate, method: .activate, build: Action.activate, extract: {
            if case .activate(let value) = $0 { value } else { nil }
        }, describe: { ScoreDescription.call("activate", [$0.description]) }),
        .keyedTarget(.increment, method: .increment, build: Action.increment, extract: {
            if case .increment(let value) = $0 { value } else { nil }
        }, describe: { ScoreDescription.call("increment", [$0.description]) }),
        .keyedTarget(.decrement, method: .decrement, build: Action.decrement, extract: {
            if case .decrement(let value) = $0 { value } else { nil }
        }, describe: { ScoreDescription.call("decrement", [$0.description]) }),
        .inline(.performCustomAction, method: .customAction, build: Action.performCustomAction, extract: {
            if case .performCustomAction(let value) = $0 { value } else { nil }
        }),
        .inline(.rotor, method: .rotor, build: Action.rotor, extract: { if case .rotor(let value) = $0 { value } else { nil } }),
        .inline(.touchTap, method: .syntheticTap, build: Action.touchTap, extract: { if case .touchTap(let value) = $0 { value } else { nil } }),
        .inline(.touchLongPress, method: .syntheticLongPress, build: Action.touchLongPress, extract: {
            if case .touchLongPress(let value) = $0 { value } else { nil }
        }),
        .inline(.touchSwipe, method: .syntheticSwipe, build: Action.touchSwipe, extract: { if case .touchSwipe(let value) = $0 { value } else { nil } }),
        .inline(.touchDrag, method: .syntheticDrag, build: Action.touchDrag, extract: { if case .touchDrag(let value) = $0 { value } else { nil } }),
        .inline(.touchPinch, method: .syntheticPinch, build: Action.touchPinch, extract: { if case .touchPinch(let value) = $0 { value } else { nil } }),
        .inline(.touchRotate, method: .syntheticRotate, build: Action.touchRotate, extract: { if case .touchRotate(let value) = $0 { value } else { nil } }),
        .inline(.touchTwoFingerTap, method: .syntheticTwoFingerTap, build: Action.touchTwoFingerTap, extract: {
            if case .touchTwoFingerTap(let value) = $0 { value } else { nil }
        }),
        .keyedTarget(.touchDrawPath, method: .syntheticDrawPath, build: Action.touchDrawPath, extract: {
            if case .touchDrawPath(let value) = $0 { value } else { nil }
        }),
        .keyedTarget(.touchDrawBezier, method: .syntheticDrawPath, build: Action.touchDrawBezier, extract: {
            if case .touchDrawBezier(let value) = $0 { value } else { nil }
        }),
        .inline(.typeText, method: .typeText, build: Action.typeText, extract: { if case .typeText(let value) = $0 { value } else { nil } }),
        .keyedTarget(.editAction, method: .editAction, build: Action.editAction, extract: { if case .editAction(let value) = $0 { value } else { nil } }),
        .keyedTarget(.setPasteboard, method: .setPasteboard, build: Action.setPasteboard, extract: {
            if case .setPasteboard(let value) = $0 { value } else { nil }
        }),
        .inline(.scroll, method: .scroll, build: Action.scroll, extract: { if case .scroll(let value) = $0 { value } else { nil } }),
        .inline(.scrollToVisible, method: .scrollToVisible, build: Action.scrollToVisible, extract: {
            if case .scrollToVisible(let value) = $0 { value } else { nil }
        }),
        .inline(.elementSearch, method: .elementSearch, build: Action.elementSearch, extract: {
            if case .elementSearch(let value) = $0 { value } else { nil }
        }),
        .inline(.scrollToEdge, method: .scrollToEdge, build: Action.scrollToEdge, extract: { if case .scrollToEdge(let value) = $0 { value } else { nil } }),
        .keyedTarget(.waitForIdle, method: .waitForIdle, defaultDeadline: Deadline(timeout: 5), build: Action.waitForIdle, extract: {
            if case .waitForIdle(let value) = $0 { value } else { nil }
        }, override: { Deadline(timeout: $0.timeout ?? 5).asOverride() }),
        .keyedTarget(
            .waitForElement,
            method: .waitFor,
            fulfillsOwnExpectation: true,
            defaultDeadline: Deadline(timeout: 30),
            build: Action.waitForElement,
            extract: {
                if case .waitForElement(let value) = $0 { value } else { nil }
            }, override: {
                (
                    $0.resolvedAbsent ? .elementDisappeared($0.target.matcher) : .elementAppeared($0.target.matcher),
                    Deadline(timeout: $0.resolvedTimeout)
                )
            }
        ),
        .keyedTarget(
            .waitForChange,
            method: .waitForChange,
            fulfillsOwnExpectation: true,
            defaultExpectation: .screenChanged,
            defaultDeadline: Deadline(timeout: 30),
            build: Action.waitForChange,
            extract: {
                if case .waitForChange(let value) = $0 { value } else { nil }
            }, override: {
                ($0.expect ?? .screenChanged, Deadline(timeout: $0.resolvedTimeout))
            }
        ),
        .noPayload(.explore, method: .explore, action: .explore, description: "explore", matches: {
            if case .explore = $0 { true } else { false }
        }),
        .noPayload(.resignFirstResponder, method: .resignFirstResponder, action: .resignFirstResponder, description: "resign_first_responder", matches: {
            if case .resignFirstResponder = $0 { true } else { false }
        }),
    ]

    static func required(for kind: ActionDescriptor.Kind) -> ActionContract {
        guard let contract = byKind[kind] else {
            preconditionFailure("Missing batch action contract for \(kind.rawValue)")
        }
        return contract
    }

    static func projection(for action: Action) -> ActionProjection {
        for contract in all {
            if let projection = contract.projectAction(action) {
                return projection
            }
        }
        preconditionFailure("Missing batch action projection for \(action)")
    }

    private static let byKind: [ActionDescriptor.Kind: ActionContract] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.kind, $0) }
    )

    static func keyedTarget<T: Codable & CustomStringConvertible & Sendable>(
        _ kind: ActionDescriptor.Kind,
        method: ActionMethod,
        fulfillsOwnExpectation: Bool = false,
        defaultExpectation: ActionExpectation = .delivery,
        defaultDeadline: Deadline = Deadline(),
        build: @escaping @Sendable (T) -> Action,
        extract: @escaping @Sendable (Action) -> T?,
        describe: @escaping @Sendable (T) -> String = { $0.description },
        override: @escaping DescriptorOverride<T> = { _ in nil }
    ) -> ActionContract {
        ActionContract(
            kind: kind,
            actionMethod: method,
            fulfillsOwnExpectation: fulfillsOwnExpectation,
            defaultExpectation: defaultExpectation,
            defaultDeadline: defaultDeadline,
            decodeAction: { decoder in
                let container = try decoder.container(keyedBy: ActionCodingKeys.self)
                return build(try container.decode(T.self, forKey: .target))
            },
            projectAction: { action in
                guard let value = extract(action) else { return nil }
                let descriptor = Self.descriptor(
                    kind: kind,
                    method: method,
                    fulfillsOwnExpectation: fulfillsOwnExpectation,
                    defaultExpectation: defaultExpectation,
                    defaultDeadline: defaultDeadline,
                    override: override(value)
                )
                return ActionProjection(
                    descriptor: descriptor,
                    description: describe(value),
                    payload: .keyedTarget(value)
                )
            }
        )
    }

    static func inline<T: Codable & CustomStringConvertible & Sendable>(
        _ kind: ActionDescriptor.Kind,
        method: ActionMethod,
        fulfillsOwnExpectation: Bool = false,
        defaultExpectation: ActionExpectation = .delivery,
        defaultDeadline: Deadline = Deadline(),
        build: @escaping @Sendable (T) -> Action,
        extract: @escaping @Sendable (Action) -> T?,
        override: @escaping DescriptorOverride<T> = { _ in nil }
    ) -> ActionContract {
        ActionContract(
            kind: kind,
            actionMethod: method,
            fulfillsOwnExpectation: fulfillsOwnExpectation,
            defaultExpectation: defaultExpectation,
            defaultDeadline: defaultDeadline,
            decodeAction: { decoder in
                build(try T(from: decoder))
            },
            projectAction: { action in
                guard let value = extract(action) else { return nil }
                let descriptor = Self.descriptor(
                    kind: kind,
                    method: method,
                    fulfillsOwnExpectation: fulfillsOwnExpectation,
                    defaultExpectation: defaultExpectation,
                    defaultDeadline: defaultDeadline,
                    override: override(value)
                )
                return ActionProjection(
                    descriptor: descriptor,
                    description: value.description,
                    payload: .inline(value)
                )
            }
        )
    }

    static func noPayload(
        _ kind: ActionDescriptor.Kind,
        method: ActionMethod,
        action: Action,
        description: String,
        matches: @escaping @Sendable (Action) -> Bool
    ) -> ActionContract {
        ActionContract(
            kind: kind,
            actionMethod: method,
            fulfillsOwnExpectation: false,
            defaultExpectation: .delivery,
            defaultDeadline: Deadline(),
            decodeAction: { _ in action },
            projectAction: { candidate in
                guard matches(candidate) else { return nil }
                return ActionProjection(
                    descriptor: ActionDescriptor(
                        kind: kind,
                        actionMethod: method,
                        fulfillsOwnExpectation: false,
                        defaultExpectation: .delivery,
                        defaultDeadline: Deadline()
                    ),
                    description: description,
                    payload: .none
                )
            }
        )
    }

    private static func descriptor(
        kind: ActionDescriptor.Kind,
        method: ActionMethod,
        fulfillsOwnExpectation: Bool,
        defaultExpectation: ActionExpectation,
        defaultDeadline: Deadline,
        override: (expectation: ActionExpectation, deadline: Deadline)?
    ) -> ActionDescriptor {
        ActionDescriptor(
            kind: kind,
            actionMethod: method,
            fulfillsOwnExpectation: fulfillsOwnExpectation,
            defaultExpectation: override?.expectation ?? defaultExpectation,
            defaultDeadline: override?.deadline ?? defaultDeadline
        )
    }
}

private extension Deadline {
    func asOverride() -> (expectation: ActionExpectation, deadline: Deadline) {
        (.delivery, self)
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

private struct ActionProjection: Sendable {
    let descriptor: ActionDescriptor
    let description: String
    let payload: ActionPayloadEncoding
}

private struct ActionPayloadEncoding: Sendable {
    let encode: @Sendable (Encoder, inout KeyedEncodingContainer<ActionCodingKeys>) throws -> Void

    static var none: ActionPayloadEncoding {
        ActionPayloadEncoding { _, _ in }
    }

    static func keyedTarget<T: Encodable & Sendable>(_ value: T) -> ActionPayloadEncoding {
        ActionPayloadEncoding { _, container in
            try container.encode(value, forKey: .target)
        }
    }

    static func inline<T: Encodable & Sendable>(_ value: T) -> ActionPayloadEncoding {
        ActionPayloadEncoding { encoder, _ in
            try value.encode(to: encoder)
        }
    }
}

private extension Action {
    var projection: ActionProjection {
        ActionContract.projection(for: self)
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
        self = try ActionContract.required(for: kind).decodeAction(decoder)
    }

    public func encode(to encoder: Encoder) throws {
        let projection = projection
        var container = encoder.container(keyedBy: ActionCodingKeys.self)
        try container.encode(projection.descriptor.canonicalName, forKey: .type)
        try projection.payload.encode(encoder, &container)
    }
}
