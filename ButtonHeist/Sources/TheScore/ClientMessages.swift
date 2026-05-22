import Foundation
import CoreGraphics

// MARK: - Request Envelope

/// Wraps a client message with an optional request ID for response correlation.
/// When `requestId` is present, the server echoes it in the corresponding response
/// so the client can match request-response pairs. Push broadcasts have no requestId.
public struct RequestEnvelope: Codable, Sendable {
    /// Client's `buttonHeistVersion`. The handshake requires exact equality
    /// with the server's `buttonHeistVersion` — there is no separate wire
    /// protocol version.
    public let buttonHeistVersion: String
    public let requestId: String?
    public let message: ClientMessage

    public init(
        buttonHeistVersion: String = TheScore.buttonHeistVersion,
        requestId: String? = nil,
        message: ClientMessage
    ) {
        self.buttonHeistVersion = buttonHeistVersion
        self.requestId = requestId
        self.message = message
    }

    /// Decode a request envelope from JSON data. Returns nil on decode failure.
    public static func decoded(from data: Data) throws -> RequestEnvelope {
        try JSONDecoder().decode(RequestEnvelope.self, from: data)
    }
}

// MARK: - Client -> Server Messages

/// Messages sent from a connected client to the Inside Job server.
public enum ClientMessage: Codable, Sendable {
    /// Version-negotiation hello sent immediately after receiving serverHello.
    case clientHello

    /// Authenticate with a token (sent after clientHello handshake completes)
    case authenticate(AuthenticatePayload)

    /// Request current semantic interface (app accessibility state)
    case requestInterface(InterfaceQuery)

    /// Ping for keepalive
    case ping

    /// Lightweight status command (identity + availability) for authenticated clients.
    case status

    // MARK: - Action Commands

    /// Activate an element
    case activate(ElementTarget)

    /// Increment an adjustable element (e.g., slider)
    case increment(ElementTarget)

    /// Decrement an adjustable element
    case decrement(ElementTarget)

    /// Perform a custom action on an element
    case performCustomAction(CustomActionTarget)

    /// Move through a custom accessibility rotor.
    case rotor(RotorTarget)

    // MARK: - Touch Gesture Commands

    /// Tap at a point or element
    case touchTap(TouchTapTarget)

    /// Long press at a point or element
    case touchLongPress(LongPressTarget)

    /// Swipe from one point to another
    case touchSwipe(SwipeTarget)

    /// Drag from one point to another
    case touchDrag(DragTarget)

    /// Pinch/zoom gesture
    case touchPinch(PinchTarget)

    /// Rotation gesture
    case touchRotate(RotateTarget)

    /// Two-finger tap
    case touchTwoFingerTap(TwoFingerTapTarget)

    /// Draw along a path (sequence of points)
    case touchDrawPath(DrawPathTarget)

    /// Draw along a bezier curve (sampled to polyline server-side)
    case touchDrawBezier(DrawBezierTarget)

    /// Type text character-by-character by tapping keyboard keys
    case typeText(TypeTextTarget)

    /// Perform a standard edit action (copy, paste, cut, select, selectAll, delete) on the first responder
    case editAction(EditActionTarget)

    /// Scroll via accessibility scroll action (bubbles up to nearest scroll view)
    case scroll(ScrollTarget)

    /// One-shot scroll: jump to a known element's position in its scroll view.
    /// Fails if the element has no recorded content-space position.
    case scrollToVisible(ScrollToVisibleTarget)

    /// Iterative search: page through scroll content looking for an element.
    /// Used when the element has never been seen (not in the registry).
    case elementSearch(ElementSearchTarget)

    /// Scroll the nearest scroll view ancestor to an edge (top, bottom, left, right)
    case scrollToEdge(ScrollToEdgeTarget)

    /// Resign first responder (dismiss keyboard)
    case resignFirstResponder

    /// Write text to the general pasteboard (in-app, avoids paste dialog for subsequent reads)
    case setPasteboard(SetPasteboardTarget)

    /// Read text from the general pasteboard
    case getPasteboard

    /// Wait for all animations to complete, then return the settled interface
    case waitForIdle(WaitForIdleTarget)

    /// Wait for an element matching a predicate to appear (or disappear)
    case waitFor(WaitForTarget)

    /// Wait for the UI to change in a way that matches an expectation.
    /// With no expectation: returns on any tree change.
    /// With expect: rides through intermediate states until the expectation is met.
    case waitForChange(WaitForChangeTarget)

    /// Execute a typed batch plan using semantic targets. Source heistIds in
    /// the plan are recording metadata only; executable element identity is
    /// carried by matcher fields.
    case batchExecutionPlan(BatchPlan)

    /// Request a capture of the current screen
    case requestScreen

    /// Explore the current screen — scroll all containers to discover every element
    case explore

    // MARK: - Recording Commands

    /// Start recording the screen
    case startRecording(RecordingConfig)

    /// Stop an in-progress recording
    case stopRecording

    /// Canonical snake-case wire name for this message, suitable for log
    /// output and command-name diagnostics. Stable across the codebase: the
    /// same string the CLI accepts on argv and MCP tools advertise as their
    /// command discriminator.
    public var canonicalName: String {
        switch self {
        case .clientHello: return "client_hello"
        case .authenticate: return "authenticate"
        case .requestInterface: return "request_interface"
        case .ping: return "ping"
        case .status: return "status"
        case .requestScreen: return "request_screen"
        case .activate: return "activate"
        case .increment: return "increment"
        case .decrement: return "decrement"
        case .performCustomAction: return "perform_custom_action"
        case .rotor: return "rotor"
        case .editAction: return "edit_action"
        case .setPasteboard: return "set_pasteboard"
        case .getPasteboard: return "get_pasteboard"
        case .resignFirstResponder: return "resign_first_responder"
        case .touchTap: return "touch_tap"
        case .touchLongPress: return "touch_long_press"
        case .touchSwipe: return "touch_swipe"
        case .touchDrag: return "touch_drag"
        case .touchPinch: return "touch_pinch"
        case .touchRotate: return "touch_rotate"
        case .touchTwoFingerTap: return "touch_two_finger_tap"
        case .touchDrawPath: return "touch_draw_path"
        case .touchDrawBezier: return "touch_draw_bezier"
        case .typeText: return "type_text"
        case .scroll: return "scroll"
        case .scrollToVisible: return "scroll_to_visible"
        case .elementSearch: return "element_search"
        case .scrollToEdge: return "scroll_to_edge"
        case .waitForIdle: return "wait_for_idle"
        case .waitFor: return "wait_for"
        case .waitForChange: return "wait_for_change"
        case .batchExecutionPlan: return "batch_execution_plan"
        case .explore: return "explore"
        case .startRecording: return "start_recording"
        case .stopRecording: return "stop_recording"
        }
    }

    /// Extract the element target from any action command, if present.
    ///
    /// Returns `nil` for commands that don't carry one directly — either because
    /// the command targets coordinates instead (`.oneFingerTap` with pointX/pointY),
    /// has no target at all (`.getInterface`, `.getScreen`), or wraps a multi-target
    /// payload (`.drag`, `.pinch`, `.drawPath`).
    public var actionTarget: ElementTarget? {
        switch self {
        case .activate(let t), .increment(let t), .decrement(let t):
            return t
        case .scrollToVisible(let t):
            return t.elementTarget
        case .elementSearch(let t):
            return t.elementTarget
        case .performCustomAction(let t):
            return t.elementTarget
        case .rotor(let t):
            return t.elementTarget
        case .editAction:
            return nil
        case .touchTap(let t):
            return t.elementTarget
        case .touchLongPress(let t):
            return t.elementTarget
        case .touchSwipe(let t):
            return t.elementTarget
        case .touchDrag(let t):
            return t.elementTarget
        case .touchPinch(let t):
            return t.elementTarget
        case .touchRotate(let t):
            return t.elementTarget
        case .touchTwoFingerTap(let t):
            return t.elementTarget
        case .touchDrawPath:
            return nil
        case .touchDrawBezier:
            return nil
        case .typeText(let t):
            return t.elementTarget
        case .scroll(let t):
            return t.elementTarget
        case .scrollToEdge(let t):
            return t.elementTarget
        case .waitFor(let t):
            return t.elementTarget
        case .batchExecutionPlan:
            return nil
        default:
            return nil
        }
    }
}

extension ClientMessage: CustomStringConvertible {
    public var description: String {
        switch self {
        case .clientHello, .ping, .status, .requestScreen, .explore, .stopRecording,
             .resignFirstResponder, .getPasteboard:
            return canonicalName
        case .authenticate:
            return "\(canonicalName)(token=<redacted>)"
        case .requestInterface(let query):
            return "\(canonicalName)(\(query))"
        case .activate(let target), .increment(let target), .decrement(let target):
            return "\(canonicalName)(\(target))"
        case .performCustomAction(let target):
            return "\(canonicalName)(\(target))"
        case .rotor(let target):
            return "\(canonicalName)(\(target))"
        case .touchTap(let target):
            return "\(canonicalName)(\(target))"
        case .touchLongPress(let target):
            return "\(canonicalName)(\(target))"
        case .touchSwipe(let target):
            return "\(canonicalName)(\(target))"
        case .touchDrag(let target):
            return "\(canonicalName)(\(target))"
        case .touchPinch(let target):
            return "\(canonicalName)(\(target))"
        case .touchRotate(let target):
            return "\(canonicalName)(\(target))"
        case .touchTwoFingerTap(let target):
            return "\(canonicalName)(\(target))"
        case .touchDrawPath(let target):
            return "\(canonicalName)(\(target))"
        case .touchDrawBezier(let target):
            return "\(canonicalName)(\(target))"
        case .typeText(let target):
            return "\(canonicalName)(\(target))"
        case .editAction(let target):
            return "\(canonicalName)(\(target))"
        case .scroll(let target):
            return "\(canonicalName)(\(target))"
        case .scrollToVisible(let target):
            return "\(canonicalName)(\(target))"
        case .elementSearch(let target):
            return "\(canonicalName)(\(target))"
        case .scrollToEdge(let target):
            return "\(canonicalName)(\(target))"
        case .setPasteboard(let target):
            return "\(canonicalName)(\(target))"
        case .waitForIdle(let target):
            return "\(canonicalName)(\(target))"
        case .waitFor(let target):
            return "\(canonicalName)(\(target))"
        case .waitForChange(let target):
            return "\(canonicalName)(\(target))"
        case .batchExecutionPlan(let plan):
            return "\(canonicalName)(\(plan))"
        case .startRecording(let config):
            return "\(canonicalName)(\(config))"
        }
    }
}

// MARK: - Batch Execution Plan

/// Policy for executing an InsideJob-owned typed batch plan.
public enum BatchExecutionPolicy: String, Codable, CaseIterable, Sendable {
    case stopOnError = "stop_on_error"
    case continueOnError = "continue_on_error"
}

extension BatchExecutionPolicy: CustomStringConvertible {
    public var description: String { rawValue }
}

/// A typed batch execution plan for InsideJob.
///
/// This is intentionally a domain model, not a list of public command
/// dictionaries. Element identity in batch targets is semantic: `sourceHeistId`
/// records where the target came from, while `matcher`/`ordinal` are the
/// executable selector.
public struct BatchPlan: Sendable {
    public let steps: [BatchStep]
    public let policy: BatchExecutionPolicy

    public init(
        steps: [BatchStep],
        policy: BatchExecutionPolicy = .stopOnError
    ) {
        self.steps = steps
        self.policy = policy
    }
}

extension BatchPlan: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("batchExecutionPlan", [
            ScoreDescription.valueField("policy", policy),
            "steps=\(steps.count)",
        ].compactMap { $0 })
    }
}

extension BatchPlan: Codable {
    private enum CodingKeys: String, CodingKey {
        case steps, policy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        steps = try container.decode([BatchStep].self, forKey: .steps)
        policy = try container.decodeIfPresent(BatchExecutionPolicy.self, forKey: .policy) ?? .stopOnError
        guard !steps.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .steps,
                in: container,
                debugDescription: "BatchPlan requires at least one step"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
        try container.encode(policy, forKey: .policy)
    }
}

public typealias BatchExecutionPlan = BatchPlan

/// Semantic element target used by batch execution plans.
///
/// `sourceHeistId` is diagnostic source metadata from the capture that produced
/// the matcher. It is never the executable identity. Execution should resolve
/// `matcher` and `ordinal` against fresh live geometry.
public struct BatchExecutionTarget: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case sourceHeistId, matcher, ordinal
    }

    public let sourceHeistId: HeistId?
    public let matcher: ElementMatcher
    public let ordinal: Int?

    public init(
        sourceHeistId: HeistId? = nil,
        matcher: ElementMatcher,
        ordinal: Int? = nil
    ) {
        self.sourceHeistId = sourceHeistId ?? matcher.heistId
        self.matcher = ElementMatcher(
            label: matcher.label,
            identifier: matcher.identifier,
            value: matcher.value,
            traits: matcher.traits,
            excludeTraits: matcher.excludeTraits
        )
        self.ordinal = ordinal
    }

    public init(_ minimumMatcher: MinimumMatcher) {
        self.init(
            sourceHeistId: minimumMatcher.element.heistId,
            matcher: minimumMatcher.matcher,
            ordinal: minimumMatcher.ordinal
        )
    }

    /// The executable target for existing action implementations. This always
    /// uses matcher semantics, never direct heistId lookup.
    public var executableTarget: ElementTarget {
        .matcher(matcher, ordinal: ordinal)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceHeistId = try container.decodeIfPresent(HeistId.self, forKey: .sourceHeistId)
        let matcher = try container.decode(ElementMatcher.self, forKey: .matcher)
        let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        if let ordinal, ordinal < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .ordinal,
                in: container,
                debugDescription: "ordinal must be non-negative, got \(ordinal)"
            )
        }
        self.init(sourceHeistId: sourceHeistId, matcher: matcher, ordinal: ordinal)
        guard self.matcher.hasPredicates || ordinal != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .matcher,
                in: container,
                debugDescription: "BatchExecutionTarget requires matcher predicates or an ordinal fallback; sourceHeistId is metadata only"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        guard matcher.hasPredicates || ordinal != nil else {
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "BatchExecutionTarget requires matcher predicates or an ordinal fallback; sourceHeistId is metadata only"
            ))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(sourceHeistId, forKey: .sourceHeistId)
        try container.encode(matcher, forKey: .matcher)
        try container.encodeIfPresent(ordinal, forKey: .ordinal)
    }
}

extension BatchExecutionTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("batchTarget", [
            ScoreDescription.stringField("sourceHeistId", sourceHeistId),
            matcher.description,
            ScoreDescription.valueField("ordinal", ordinal),
        ].compactMap { $0 })
    }
}

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

    public static func wait(_ wait: BatchExecutionWait) -> BatchStep {
        BatchStep(
            action: wait.action,
            expectation: wait.defaultExpectation,
            deadline: wait.defaultDeadline
        )
    }

    public static func checkpoint(_ checkpoint: BatchExecutionCheckpoint) -> BatchStep {
        BatchStep(
            action: .checkpoint(CheckpointAction(name: checkpoint.name)),
            expectation: checkpoint.expect,
            deadline: Deadline(timeout: checkpoint.timeout)
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
        case kind, action, wait, checkpoint, expect, deadline
    }

    private enum Kind: String, Codable {
        case action, wait, checkpoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.action) {
            let action = try container.decode(Action.self, forKey: .action)
            self.init(
                action: action,
                expectation: try container.decodeIfPresent(ActionExpectation.self, forKey: .expect)
                    ?? action.defaultExpectation,
                deadline: try container.decodeIfPresent(Deadline.self, forKey: .deadline)
                    ?? action.defaultDeadline
            )
            return
        }

        switch try container.decode(Kind.self, forKey: .kind) {
        case .action:
            let action = try container.decode(Action.self, forKey: .action)
            self.init(
                action: action,
                expectation: try container.decodeIfPresent(ActionExpectation.self, forKey: .expect)
                    ?? action.defaultExpectation,
                deadline: try container.decodeIfPresent(Deadline.self, forKey: .deadline)
                    ?? action.defaultDeadline
            )
        case .wait:
            self = .wait(try container.decode(BatchExecutionWait.self, forKey: .wait))
        case .checkpoint:
            self = .checkpoint(try container.decode(BatchExecutionCheckpoint.self, forKey: .checkpoint))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encode(expectation, forKey: .expect)
        try container.encode(deadline, forKey: .deadline)
    }
}

public typealias BatchExecutionStep = BatchStep

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

public struct BatchCustomActionTarget: Codable, Sendable {
    public let target: BatchExecutionTarget
    public let actionName: String

    public init(target: BatchExecutionTarget, actionName: String) {
        self.target = target
        self.actionName = actionName
    }
}

extension BatchCustomActionTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("customAction", [
            target.description,
            ScoreDescription.stringField("action", actionName),
        ].compactMap { $0 })
    }
}

public struct BatchRotorTarget: Codable, Sendable {
    public let target: BatchExecutionTarget
    public let rotor: String?
    public let rotorIndex: Int?
    public let direction: RotorDirection?
    public let currentSourceHeistId: HeistId?
    public let currentTextRange: TextRangeReference?

    public init(
        target: BatchExecutionTarget,
        rotor: String? = nil,
        rotorIndex: Int? = nil,
        direction: RotorDirection? = nil,
        currentSourceHeistId: HeistId? = nil,
        currentTextRange: TextRangeReference? = nil
    ) {
        self.target = target
        self.rotor = rotor
        self.rotorIndex = rotorIndex
        self.direction = direction
        self.currentSourceHeistId = currentSourceHeistId
        self.currentTextRange = currentTextRange
    }
}

extension BatchRotorTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("rotor", [
            target.description,
            ScoreDescription.stringField("name", rotor),
            ScoreDescription.valueField("index", rotorIndex),
            ScoreDescription.valueField("direction", direction),
            ScoreDescription.stringField("currentSourceHeistId", currentSourceHeistId),
            currentTextRange?.description,
        ].compactMap { $0 })
    }
}

public struct BatchTouchTapTarget: Codable, Sendable {
    public let target: BatchExecutionTarget?
    public let pointX: Double?
    public let pointY: Double?

    public init(target: BatchExecutionTarget? = nil, pointX: Double? = nil, pointY: Double? = nil) {
        self.target = target
        self.pointX = pointX
        self.pointY = pointY
    }
}

extension BatchTouchTapTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("tap", [
            target?.description,
            pointX.map { "x=\(ScoreDescription.decimal($0))" },
            pointY.map { "y=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct BatchLongPressTarget: Codable, Sendable {
    public let target: BatchExecutionTarget?
    public let pointX: Double?
    public let pointY: Double?
    public let duration: Double

    public init(
        target: BatchExecutionTarget? = nil,
        pointX: Double? = nil,
        pointY: Double? = nil,
        duration: Double = 0.5
    ) {
        self.target = target
        self.pointX = pointX
        self.pointY = pointY
        self.duration = duration
    }
}

extension BatchLongPressTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("longPress", [
            target?.description,
            pointX.map { "x=\(ScoreDescription.decimal($0))" },
            pointY.map { "y=\(ScoreDescription.decimal($0))" },
            "duration=\(ScoreDescription.decimal(duration))",
        ].compactMap { $0 })
    }
}

public struct BatchSwipeTarget: Codable, Sendable {
    public let target: BatchExecutionTarget?
    public let startX: Double?
    public let startY: Double?
    public let endX: Double?
    public let endY: Double?
    public let direction: SwipeDirection?
    public let duration: Double?
    public let start: UnitPoint?
    public let end: UnitPoint?

    public init(
        target: BatchExecutionTarget? = nil,
        startX: Double? = nil,
        startY: Double? = nil,
        endX: Double? = nil,
        endY: Double? = nil,
        direction: SwipeDirection? = nil,
        duration: Double? = nil,
        start: UnitPoint? = nil,
        end: UnitPoint? = nil
    ) {
        self.target = target
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.direction = direction
        self.duration = duration
        self.start = start
        self.end = end
    }
}

extension BatchSwipeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("swipe", [
            target?.description,
            startX.map { "startX=\(ScoreDescription.decimal($0))" },
            startY.map { "startY=\(ScoreDescription.decimal($0))" },
            endX.map { "endX=\(ScoreDescription.decimal($0))" },
            endY.map { "endY=\(ScoreDescription.decimal($0))" },
            ScoreDescription.valueField("direction", direction),
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
            start.map { "start=\($0)" },
            end.map { "end=\($0)" },
        ].compactMap { $0 })
    }
}

public struct BatchDragTarget: Codable, Sendable {
    public let target: BatchExecutionTarget?
    public let startX: Double?
    public let startY: Double?
    public let endX: Double
    public let endY: Double
    public let duration: Double?

    public init(
        target: BatchExecutionTarget? = nil,
        startX: Double? = nil,
        startY: Double? = nil,
        endX: Double,
        endY: Double,
        duration: Double? = nil
    ) {
        self.target = target
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.duration = duration
    }
}

extension BatchDragTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("drag", [
            target?.description,
            startX.map { "startX=\(ScoreDescription.decimal($0))" },
            startY.map { "startY=\(ScoreDescription.decimal($0))" },
            "endX=\(ScoreDescription.decimal(endX))",
            "endY=\(ScoreDescription.decimal(endY))",
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct BatchPinchTarget: Codable, Sendable {
    public let target: BatchExecutionTarget?
    public let centerX: Double?
    public let centerY: Double?
    public let scale: Double
    public let spread: Double?
    public let duration: Double?

    public init(
        target: BatchExecutionTarget? = nil,
        centerX: Double? = nil,
        centerY: Double? = nil,
        scale: Double,
        spread: Double? = nil,
        duration: Double? = nil
    ) {
        self.target = target
        self.centerX = centerX
        self.centerY = centerY
        self.scale = scale
        self.spread = spread
        self.duration = duration
    }
}

extension BatchPinchTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("pinch", [
            target?.description,
            centerX.map { "centerX=\(ScoreDescription.decimal($0))" },
            centerY.map { "centerY=\(ScoreDescription.decimal($0))" },
            "scale=\(ScoreDescription.decimal(scale))",
            spread.map { "spread=\(ScoreDescription.decimal($0))" },
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct BatchRotateTarget: Codable, Sendable {
    public let target: BatchExecutionTarget?
    public let centerX: Double?
    public let centerY: Double?
    public let angle: Double
    public let radius: Double?
    public let duration: Double?

    public init(
        target: BatchExecutionTarget? = nil,
        centerX: Double? = nil,
        centerY: Double? = nil,
        angle: Double,
        radius: Double? = nil,
        duration: Double? = nil
    ) {
        self.target = target
        self.centerX = centerX
        self.centerY = centerY
        self.angle = angle
        self.radius = radius
        self.duration = duration
    }
}

extension BatchRotateTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("rotate", [
            target?.description,
            centerX.map { "centerX=\(ScoreDescription.decimal($0))" },
            centerY.map { "centerY=\(ScoreDescription.decimal($0))" },
            "angle=\(ScoreDescription.decimal(angle))",
            radius.map { "radius=\(ScoreDescription.decimal($0))" },
            duration.map { "duration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct BatchTwoFingerTapTarget: Codable, Sendable {
    public let target: BatchExecutionTarget?
    public let centerX: Double?
    public let centerY: Double?
    public let spread: Double?

    public init(
        target: BatchExecutionTarget? = nil,
        centerX: Double? = nil,
        centerY: Double? = nil,
        spread: Double? = nil
    ) {
        self.target = target
        self.centerX = centerX
        self.centerY = centerY
        self.spread = spread
    }
}

extension BatchTwoFingerTapTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("twoFingerTap", [
            target?.description,
            centerX.map { "centerX=\(ScoreDescription.decimal($0))" },
            centerY.map { "centerY=\(ScoreDescription.decimal($0))" },
            spread.map { "spread=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

public struct BatchTypeTextTarget: Codable, Sendable {
    public let text: String
    public let target: BatchExecutionTarget?

    public init(text: String, target: BatchExecutionTarget? = nil) {
        self.text = text
        self.target = target
    }
}

extension BatchTypeTextTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("typeText", [
            ScoreDescription.stringField("text", text),
            target?.description,
        ].compactMap { $0 })
    }
}

public struct BatchScrollTarget: Codable, Sendable {
    public let target: BatchExecutionTarget?
    public let direction: ScrollDirection

    public init(target: BatchExecutionTarget? = nil, direction: ScrollDirection) {
        self.target = target
        self.direction = direction
    }
}

extension BatchScrollTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scroll", [
            target?.description,
            ScoreDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

public struct BatchScrollToVisibleTarget: Codable, Sendable {
    public let target: BatchExecutionTarget?

    public init(target: BatchExecutionTarget? = nil) {
        self.target = target
    }
}

extension BatchScrollToVisibleTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scrollToVisible", [
            target?.description,
        ].compactMap { $0 })
    }
}

public struct BatchElementSearchTarget: Codable, Sendable {
    public let target: BatchExecutionTarget?
    public let direction: ScrollSearchDirection?

    public init(target: BatchExecutionTarget? = nil, direction: ScrollSearchDirection? = nil) {
        self.target = target
        self.direction = direction
    }
}

extension BatchElementSearchTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("elementSearch", [
            target?.description,
            ScoreDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

public struct BatchScrollToEdgeTarget: Codable, Sendable {
    public let target: BatchExecutionTarget?
    public let edge: ScrollEdge

    public init(target: BatchExecutionTarget? = nil, edge: ScrollEdge) {
        self.target = target
        self.edge = edge
    }
}

extension BatchScrollToEdgeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scrollToEdge", [
            target?.description,
            ScoreDescription.valueField("edge", edge),
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

public struct BatchWaitForTarget: Codable, Sendable {
    public let target: BatchExecutionTarget
    public let absent: Bool?
    public let timeout: Double?

    public init(target: BatchExecutionTarget, absent: Bool? = nil, timeout: Double? = nil) {
        self.target = target
        self.absent = absent
        self.timeout = timeout
    }

    public var resolvedAbsent: Bool { absent ?? false }
    public var resolvedTimeout: Double { min(timeout ?? 10, 30) }
}

extension BatchWaitForTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("waitFor", [
            target.description,
            ScoreDescription.valueField("absent", absent),
            timeout.map { "timeout=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
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

// MARK: - Action Targets

/// Target for element actions.
/// Two resolution strategies: heistId (current-hierarchy token from
/// get_interface) or matcher (describe the element by accessibility
/// properties). HeistId takes priority when both are present.
/// Use heistId for immediate follow-up actions in the current capture; use
/// minimum matchers for durable replay. Matcher fields use case-insensitive
/// equality with typography folding — exact-or-miss.
/// On miss, the resolver returns structured suggestions; there is no
/// substring fallback.
public enum ElementTarget: Sendable, Equatable {
    /// Current-hierarchy handle assigned by get_interface — fast O(1) lookup.
    case heistId(HeistId)
    /// Predicate matcher: label, identifier, value, traits, excludeTraits.
    /// `ordinal` is a 0-based selection index into the list of matches
    /// after semantic narrowing. When nil, requires a unique match and reports
    /// ambiguity on 2+ hits. When set, selects the Nth narrowed match.
    /// This is a disambiguator for match results, NOT durable identity.
    case matcher(ElementMatcher, ordinal: Int? = nil)

    /// Convenience: build from optional fields. HeistId wins if present.
    /// Returns nil if both matcher and ordinal are empty.
    public init?(heistId: HeistId? = nil, matcher: ElementMatcher, ordinal: Int? = nil) {
        if let heistId {
            self = .heistId(heistId)
        } else if let match = matcher.nonEmpty {
            self = .matcher(match, ordinal: ordinal)
        } else if ordinal != nil {
            self = .matcher(matcher, ordinal: ordinal)
        } else {
            return nil
        }
    }
}

extension ElementTarget: CustomStringConvertible {
    public var description: String {
        switch self {
        case .heistId(let heistId):
            return ScoreDescription.call("target", [
                ScoreDescription.stringField("heistId", heistId),
            ].compactMap { $0 })
        case .matcher(let matcher, let ordinal):
            return ScoreDescription.call("target", [
                matcher.description,
                ScoreDescription.valueField("ordinal", ordinal),
            ].compactMap { $0 })
        }
    }
}

// MARK: - ElementTarget Codable (flat wire format)

extension ElementTarget: Codable {
    fileprivate enum CodingKeys: String, CodingKey {
        case heistId
        case label, identifier, value, traits, excludeTraits
        case ordinal

        /// The matcher / heistId keys whose presence in a parent container
        /// indicates an `ElementTarget` is flattened at that level.
        static let allInlineKeys: [CodingKeys] = [
            .heistId, .label, .identifier, .value, .traits, .excludeTraits, .ordinal,
        ]
    }

    /// Wire keys whose presence (anywhere on a JSON object) indicates an
    /// `ElementTarget` is encoded inline at that level. Used by wrapper
    /// targets (`WaitForTarget`, `ScrollToVisibleTarget`,
    /// `ElementSearchTarget`) that flatten an `ElementTarget` alongside their
    /// own fields.
    public static let inlineWireKeys: [String] = [
        "heistId", "label", "identifier", "value", "traits", "excludeTraits", "ordinal",
    ]

    /// Decode an optional `ElementTarget` flattened into the same JSON object
    /// the decoder is currently reading. Returns `nil` when none of the
    /// matcher / heistId keys are present; throws if at least one key is
    /// present but the resulting target fails ElementTarget's own validation.
    public static func decodeInlineIfPresent(from decoder: Decoder) throws -> ElementTarget? {
        let probe = try decoder.container(keyedBy: CodingKeys.self)
        let hasTargetFields = CodingKeys.allInlineKeys.contains { probe.contains($0) }
        guard hasTargetFields else { return nil }
        return try ElementTarget(from: decoder)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let heistId = try container.decodeIfPresent(HeistId.self, forKey: .heistId) {
            self = .heistId(heistId)
            return
        }
        let matcher = ElementMatcher(
            label: try container.decodeIfPresent(String.self, forKey: .label),
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier),
            value: try container.decodeIfPresent(String.self, forKey: .value),
            traits: try container.decodeIfPresent([HeistTrait].self, forKey: .traits),
            excludeTraits: try container.decodeIfPresent([HeistTrait].self, forKey: .excludeTraits)
        )
        let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        if let ordinal, ordinal < 0 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "ordinal must be non-negative, got \(ordinal)"
            ))
        }
        if let match = matcher.nonEmpty {
            self = .matcher(match, ordinal: ordinal)
        } else if ordinal != nil {
            self = .matcher(matcher, ordinal: ordinal)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "ElementTarget requires heistId, ordinal, or at least one matcher field (label, identifier, value, traits, excludeTraits)"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heistId(let id):
            try container.encode(id, forKey: .heistId)
        case .matcher(let matcher, let ordinal):
            try container.encodeIfPresent(matcher.label, forKey: .label)
            try container.encodeIfPresent(matcher.identifier, forKey: .identifier)
            try container.encodeIfPresent(matcher.value, forKey: .value)
            try container.encodeIfPresent(matcher.traits, forKey: .traits)
            try container.encodeIfPresent(matcher.excludeTraits, forKey: .excludeTraits)
            try container.encodeIfPresent(ordinal, forKey: .ordinal)
        }
    }
}

/// Target for custom actions
public struct CustomActionTarget: Codable, Sendable {
    public let elementTarget: ElementTarget
    public let actionName: String

    public init(elementTarget: ElementTarget, actionName: String) {
        self.elementTarget = elementTarget
        self.actionName = actionName
    }
}

extension CustomActionTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("customAction", [
            elementTarget.description,
            ScoreDescription.stringField("action", actionName),
        ].compactMap { $0 })
    }
}

/// Direction for a rotor step.
public enum RotorDirection: String, Codable, Sendable, CaseIterable {
    case next
    case previous
}

extension RotorDirection: CustomStringConvertible {
    public var description: String { rawValue }
}

/// Text-range cursor for continuing through rotor results inside one text input.
public struct TextRangeReference: Codable, Equatable, Hashable, Sendable {
    public let startOffset: Int
    public let endOffset: Int

    public init(startOffset: Int, endOffset: Int) {
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

extension TextRangeReference: CustomStringConvertible {
    public var description: String {
        "textRange(\(startOffset)..<\(endOffset))"
    }
}

/// Target for moving through a rotor.
public struct RotorTarget: Sendable {
    /// Element whose `accessibilityCustomRotors` should be used.
    public let elementTarget: ElementTarget
    /// Select a rotor by display/name. When omitted, `rotorIndex` is used.
    public let rotor: String?
    /// Select a rotor by zero-based index when the name is omitted or ambiguous.
    public let rotorIndex: Int?
    /// Direction to move. Defaults to `.next`.
    public let direction: RotorDirection?
    /// Optional heistId for the current rotor item. Use the previous result's
    /// heistId to continue moving through a rotor like a VoiceOver user.
    public let currentHeistId: HeistId?
    /// Optional text-range cursor for continuing through text-range rotor
    /// results inside the element identified by `currentHeistId`.
    public let currentTextRange: TextRangeReference?

    public init(
        elementTarget: ElementTarget,
        rotor: String? = nil,
        rotorIndex: Int? = nil,
        direction: RotorDirection? = nil,
        currentHeistId: HeistId? = nil,
        currentTextRange: TextRangeReference? = nil
    ) {
        self.elementTarget = elementTarget
        self.rotor = rotor
        self.rotorIndex = rotorIndex
        self.direction = direction
        self.currentHeistId = currentHeistId
        self.currentTextRange = currentTextRange
    }

    public var resolvedDirection: RotorDirection { direction ?? .next }
}

extension RotorTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("rotor", [
            elementTarget.description,
            ScoreDescription.stringField("name", rotor),
            ScoreDescription.valueField("index", rotorIndex),
            ScoreDescription.valueField("direction", direction),
            ScoreDescription.stringField("currentHeistId", currentHeistId),
            currentTextRange?.description,
        ].compactMap { $0 })
    }
}

extension RotorTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case rotor
        case rotorIndex
        case direction
        case currentHeistId
        case currentTextRange
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        elementTarget = try ElementTarget(from: decoder)
        rotor = try container.decodeIfPresent(String.self, forKey: .rotor)
        rotorIndex = try container.decodeIfPresent(Int.self, forKey: .rotorIndex)
        direction = try container.decodeIfPresent(RotorDirection.self, forKey: .direction)
        currentHeistId = try container.decodeIfPresent(HeistId.self, forKey: .currentHeistId)
        currentTextRange = try container.decodeIfPresent(TextRangeReference.self, forKey: .currentTextRange)
        if let rotorIndex, rotorIndex < 0 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "rotorIndex must be non-negative, got \(rotorIndex)"
            ))
        }
        if let currentTextRange {
            guard currentTextRange.startOffset >= 0,
                  currentTextRange.endOffset >= currentTextRange.startOffset else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath + [CodingKeys.currentTextRange],
                    debugDescription: "currentTextRange must use non-negative offsets with endOffset >= startOffset"
                ))
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        try elementTarget.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(rotor, forKey: .rotor)
        try container.encodeIfPresent(rotorIndex, forKey: .rotorIndex)
        try container.encodeIfPresent(direction, forKey: .direction)
        try container.encodeIfPresent(currentHeistId, forKey: .currentHeistId)
        try container.encodeIfPresent(currentTextRange, forKey: .currentTextRange)
    }
}

/// Target for typing non-empty text character-by-character via keyboard key taps.
public struct TypeTextTarget: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case text
        case elementTarget
        case deleteCount
        case clearFirst
    }

    /// Text to type (each character is tapped individually).
    public let text: String
    /// Optional element to tap first to bring up keyboard (text field).
    /// Also used to read back the current value after typing.
    public let elementTarget: ElementTarget?

    public init(text: String, elementTarget: ElementTarget? = nil) {
        self.text = text
        self.elementTarget = elementTarget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.deleteCount) || container.contains(.clearFirst) {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "typeText no longer accepts deleteCount or clearFirst; use editAction for destructive edits"
            ))
        }
        text = try container.decode(String.self, forKey: .text)
        guard !text.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [CodingKeys.text],
                debugDescription: "text must be non-empty"
            ))
        }
        elementTarget = try container.decodeIfPresent(ElementTarget.self, forKey: .elementTarget)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(elementTarget, forKey: .elementTarget)
    }
}

extension TypeTextTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("typeText", [
            ScoreDescription.stringField("text", text),
            elementTarget?.description,
        ].compactMap { $0 })
    }
}

/// Standard edit actions that can be dispatched via the responder chain.
public enum EditAction: String, Codable, Sendable, CaseIterable {
    case copy, paste, cut, select, selectAll, delete
}

extension EditAction: CustomStringConvertible {
    public var description: String { rawValue }
}

/// Target for writing text to the general pasteboard.
public struct SetPasteboardTarget: Codable, Sendable {
    /// Text to write to the pasteboard
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

extension SetPasteboardTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("pasteboard", [
            ScoreDescription.stringField("text", text),
        ].compactMap { $0 })
    }
}

/// Target for edit actions dispatched via the responder chain
public struct EditActionTarget: Codable, Sendable {
    /// The edit action to perform
    public let action: EditAction

    public init(action: EditAction) {
        self.action = action
    }
}

extension EditActionTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("editAction", [
            ScoreDescription.valueField("action", action),
        ].compactMap { $0 })
    }
}

/// Target for waitForIdle command
public struct WaitForIdleTarget: Codable, Sendable {
    /// Maximum time to wait in seconds (default 5.0)
    public let timeout: Double?

    public init(timeout: Double? = nil) {
        self.timeout = timeout
    }
}

extension WaitForIdleTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("waitForIdle", [
            timeout.map { "timeout=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

/// Target for wait_for_change command — wait for the UI to change in a way
/// that matches an expectation. With no expectation, returns on any tree change.
public struct WaitForChangeTarget: Codable, Sendable {
    /// The change to wait for. When nil, any tree change satisfies the wait.
    public let expect: ActionExpectation?
    /// Maximum time to wait in seconds (default: 30, max: 30)
    public let timeout: Double?

    public init(expect: ActionExpectation? = nil, timeout: Double? = nil) {
        self.expect = expect
        self.timeout = timeout
    }

    public var resolvedTimeout: Double { min(timeout ?? 30, 30) }
}

extension WaitForChangeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("waitForChange", [
            expect?.description,
            timeout.map { "timeout=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

/// Target for wait_for command — wait for an element to appear or disappear.
/// Uses ElementTarget so both heistId and matcher predicates work.
public struct WaitForTarget: Sendable {
    /// Element to wait for — by heistId or matcher predicate.
    public let elementTarget: ElementTarget
    /// When true, wait for the element to NOT exist
    public let absent: Bool?
    /// Maximum time to wait in seconds (default: 10, max: 30)
    public let timeout: Double?

    public init(elementTarget: ElementTarget, absent: Bool? = nil, timeout: Double? = nil) {
        self.elementTarget = elementTarget
        self.absent = absent
        self.timeout = timeout
    }

    public var resolvedAbsent: Bool { absent ?? false }
    public var resolvedTimeout: Double { min(timeout ?? 10, 30) }
}

extension WaitForTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("waitFor", [
            elementTarget.description,
            ScoreDescription.valueField("absent", absent),
            timeout.map { "timeout=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

extension WaitForTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case absent, timeout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // WaitForTarget requires an inline ElementTarget — defer to ElementTarget's
        // own validation (it throws when no matcher/heistId keys are present).
        self.elementTarget = try ElementTarget(from: decoder)
        self.absent = try container.decodeIfPresent(Bool.self, forKey: .absent)
        self.timeout = try container.decodeIfPresent(Double.self, forKey: .timeout)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try elementTarget.encode(to: encoder)
        try container.encodeIfPresent(absent, forKey: .absent)
        try container.encodeIfPresent(timeout, forKey: .timeout)
    }
}

/// Payload for authenticate message
public struct AuthenticatePayload: Codable, Sendable {
    public let token: String
    /// Unique driver identity for session locking. When set, the server uses this
    /// (instead of the auth token) to distinguish drivers. Set via BUTTONHEIST_DRIVER_ID.
    public let driverId: String?
    public init(token: String, driverId: String? = nil) {
        self.token = token
        self.driverId = driverId
    }
}

/// Information about the active session that is blocking this connection
public struct SessionLockedPayload: Codable, Sendable {
    public let message: String
    public let activeConnections: Int

    public init(message: String, activeConnections: Int) {
        self.message = message
        self.activeConnections = activeConnections
    }
}

/// Configuration for screen recording
public struct RecordingConfig: Sendable {
    /// Frames per second (default: 8, range: 1-15)
    public let fps: Int?
    /// Resolution scale relative to native pixels (0.25-1.0).
    /// Default: nil — uses 1x point resolution (native pixels / screen scale).
    /// 1.0 = full native resolution (no reduction).
    public let scale: Double?
    /// Optional early-stop timeout in seconds — auto-stop when no screen changes
    /// and no commands are received for this duration. When omitted,
    /// inactivity auto-stop is disabled.
    public let inactivityTimeout: Double?
    /// Maximum recording duration in seconds as a hard safety cap (default: 60.0)
    public let maxDuration: Double?

    public init(
        fps: Int? = nil,
        scale: Double? = nil,
        inactivityTimeout: Double? = nil,
        maxDuration: Double? = nil
    ) {
        self.fps = fps
        self.scale = scale
        self.inactivityTimeout = inactivityTimeout
        self.maxDuration = maxDuration
    }
}

extension RecordingConfig: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("recordingConfig", [
            ScoreDescription.valueField("fps", fps),
            scale.map { "scale=\(ScoreDescription.decimal($0))" },
            inactivityTimeout.map { "inactivityTimeout=\(ScoreDescription.decimal($0))" },
            maxDuration.map { "maxDuration=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

extension RecordingConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case fps, scale, inactivityTimeout, maxDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fps = try container.decodeIfPresent(Int.self, forKey: .fps)
        let scale = try container.decodeIfPresent(Double.self, forKey: .scale)
        if let fps, fps < 1 || fps > 15 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "fps must be between 1 and 15, got \(fps)"
            ))
        }
        if let scale, scale < 0.25 || scale > 1.0 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "scale must be between 0.25 and 1.0, got \(scale)"
            ))
        }
        self.fps = fps
        self.scale = scale
        self.inactivityTimeout = try container.decodeIfPresent(Double.self, forKey: .inactivityTimeout)
        self.maxDuration = try container.decodeIfPresent(Double.self, forKey: .maxDuration)
    }
}

/// Direction for swipe gestures
public enum SwipeDirection: String, Codable, Sendable, CaseIterable {
    case up, down, left, right

    /// Default unit-point start for this cardinal direction
    public var defaultStart: UnitPoint {
        switch self {
        case .left:  UnitPoint(x: 0.8, y: 0.5)
        case .right: UnitPoint(x: 0.2, y: 0.5)
        case .up:    UnitPoint(x: 0.5, y: 0.8)
        case .down:  UnitPoint(x: 0.5, y: 0.2)
        }
    }

    /// Default unit-point end for this cardinal direction
    public var defaultEnd: UnitPoint {
        switch self {
        case .left:  UnitPoint(x: 0.2, y: 0.5)
        case .right: UnitPoint(x: 0.8, y: 0.5)
        case .up:    UnitPoint(x: 0.5, y: 0.2)
        case .down:  UnitPoint(x: 0.5, y: 0.8)
        }
    }
}

extension SwipeDirection: CustomStringConvertible {
    public var description: String { rawValue }
}

/// Direction for scroll actions
public enum ScrollDirection: String, Codable, Sendable, CaseIterable {
    case up, down, left, right, next, previous
}

extension ScrollDirection: CustomStringConvertible {
    public var description: String { rawValue }
}

/// Target for container-moving scroll commands.
public struct ScrollContainerTarget: Codable, Sendable, Equatable {
    /// Stable container id returned by get_interface.
    public let stableId: HeistContainer?
    /// Capture-local container ref, for clients that retain a local capture handle.
    public let captureLocalRef: String?

    public init(stableId: HeistContainer? = nil, captureLocalRef: String? = nil) {
        self.stableId = stableId
        self.captureLocalRef = captureLocalRef
    }
}

extension ScrollContainerTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("container", [
            ScoreDescription.stringField("stableId", stableId),
            ScoreDescription.stringField("captureLocalRef", captureLocalRef),
        ].compactMap { $0 })
    }
}

/// Target for one-page scroll command.
public struct ScrollTarget: Sendable {
    /// Explicit scroll container to move.
    public let containerTarget: ScrollContainerTarget?
    /// Compatibility: element whose owning scroll container should move.
    public let elementTarget: ElementTarget?
    /// Scroll direction
    public let direction: ScrollDirection

    public init(
        elementTarget: ElementTarget? = nil,
        containerTarget: ScrollContainerTarget? = nil,
        direction: ScrollDirection = .down
    ) {
        self.elementTarget = elementTarget
        self.containerTarget = containerTarget
        self.direction = direction
    }
}

extension ScrollTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scroll", [
            containerTarget?.description,
            elementTarget?.description,
            ScoreDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

extension ScrollTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case direction
        case container
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.containerTarget = try container.decodeIfPresent(ScrollContainerTarget.self, forKey: .container)
        self.elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        self.direction = try container.decodeIfPresent(ScrollDirection.self, forKey: .direction) ?? .down
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(containerTarget, forKey: .container)
        try container.encode(direction, forKey: .direction)
    }
}

/// Direction for scroll search
public enum ScrollSearchDirection: String, Codable, Sendable, CaseIterable {
    case down, up, left, right
}

extension ScrollSearchDirection: CustomStringConvertible {
    public var description: String { rawValue }
}

/// Target for one-shot scroll-to-visible.
/// The element must be known (in the registry with a content-space position).
/// Jumps directly to the element's position — no iterative search.
public struct ScrollToVisibleTarget: Sendable {
    /// Element to scroll into view. Must be a known element with a recorded position.
    public let elementTarget: ElementTarget?
    public init(elementTarget: ElementTarget? = nil) {
        self.elementTarget = elementTarget
    }
}

extension ScrollToVisibleTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scrollToVisible", [
            elementTarget?.description,
        ].compactMap { $0 })
    }
}

/// Target for iterative element search.
/// Pages through scroll content looking for an element that may not be in the registry.
public struct ElementSearchTarget: Sendable {
    /// Element to search for while scrolling.
    public let elementTarget: ElementTarget?
    /// Starting scroll direction (default: .down)
    public let direction: ScrollSearchDirection?
    public init(
        elementTarget: ElementTarget? = nil,
        direction: ScrollSearchDirection? = nil
    ) {
        self.elementTarget = elementTarget
        self.direction = direction
    }

    public var resolvedDirection: ScrollSearchDirection { direction ?? .down }
}

extension ElementSearchTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("elementSearch", [
            elementTarget?.description,
            ScoreDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

extension ScrollToVisibleTarget: Codable {
    public init(from decoder: Decoder) throws {
        self.elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
    }
}

extension ElementSearchTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case direction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        self.direction = try container.decodeIfPresent(ScrollSearchDirection.self, forKey: .direction)
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(direction, forKey: .direction)
    }
}

/// Edge for scroll-to-edge commands
public enum ScrollEdge: String, Codable, Sendable, CaseIterable {
    case top, bottom, left, right
}

extension ScrollEdge: CustomStringConvertible {
    public var description: String { rawValue }
}

/// Target for scroll-to-edge command
public struct ScrollToEdgeTarget: Sendable {
    /// Explicit scroll container to move.
    public let containerTarget: ScrollContainerTarget?
    /// Compatibility: element whose scrollable container to scroll.
    public let elementTarget: ElementTarget?
    /// Which edge to scroll to
    public let edge: ScrollEdge

    public init(
        elementTarget: ElementTarget? = nil,
        containerTarget: ScrollContainerTarget? = nil,
        edge: ScrollEdge = .top
    ) {
        self.elementTarget = elementTarget
        self.containerTarget = containerTarget
        self.edge = edge
    }
}

extension ScrollToEdgeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scrollToEdge", [
            containerTarget?.description,
            elementTarget?.description,
            ScoreDescription.valueField("edge", edge),
        ].compactMap { $0 })
    }
}

extension ScrollToEdgeTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case edge
        case container
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.containerTarget = try container.decodeIfPresent(ScrollContainerTarget.self, forKey: .container)
        self.elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        self.edge = try container.decodeIfPresent(ScrollEdge.self, forKey: .edge) ?? .top
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(containerTarget, forKey: .container)
        try container.encode(edge, forKey: .edge)
    }
}
