import Foundation

public enum HeistActionCommandType: String, Codable, Sendable, CaseIterable, Equatable, CustomStringConvertible {
    case activate, increment, decrement, performCustomAction, rotor
    case dismiss, magicTap
    case oneFingerTap, longPress, swipe, drag
    case typeText, editAction, setPasteboard, takeScreenshot
    case scroll, scrollToVisible, scrollToEdge, resignFirstResponder

    public var description: String { rawValue }
}

package enum HeistActionCommandCore: Sendable, Equatable {
    case activate(AccessibilityTarget)
    case increment(AccessibilityTarget)
    case decrement(AccessibilityTarget)
    case customAction(name: CustomActionName, target: AccessibilityTarget)
    case rotor(selection: RotorSelection, target: AccessibilityTarget, direction: RotorDirection)
    case dismiss
    case magicTap
    case typeText(TypeTextTarget)
    case mechanicalTap(TapTarget)
    case mechanicalLongPress(LongPressTarget)
    case mechanicalSwipe(SwipeTarget)
    case mechanicalDrag(DragTarget)
    case viewportScroll(ScrollTarget)
    case viewportScrollToVisible(AccessibilityTarget)
    case viewportScrollToEdge(ScrollToEdgeTarget)
    case editAction(EditActionTarget)
    case setPasteboard(SetPasteboardTarget)
    case takeScreenshot
    case dismissKeyboard
}

public struct HeistActionCommand: Codable, Sendable, Equatable {
    package let core: HeistActionCommandCore

    package init(core: HeistActionCommandCore) {
        self.core = core
    }

    public static func activate(_ target: AccessibilityTarget) -> Self { Self(core: .activate(target)) }
    public static func increment(_ target: AccessibilityTarget) -> Self { Self(core: .increment(target)) }
    public static func decrement(_ target: AccessibilityTarget) -> Self { Self(core: .decrement(target)) }
    public static func customAction(name: CustomActionName, target: AccessibilityTarget) -> Self {
        Self(core: .customAction(name: name, target: target))
    }
    public static func rotor(
        selection: RotorSelection,
        target: AccessibilityTarget,
        direction: RotorDirection
    ) -> Self {
        Self(core: .rotor(selection: selection, target: target, direction: direction))
    }
    public static var dismiss: Self { Self(core: .dismiss) }
    public static var magicTap: Self { Self(core: .magicTap) }
    public static func typeText(
        text: TextInputText,
        target: AccessibilityTarget?
    ) -> Self {
        Self(core: .typeText(TypeTextTarget(text: text, target: target)))
    }
    public static func typeText(
        reference: HeistReferenceName,
        target: AccessibilityTarget?,
        mode: TextInputText.Mode = .append
    ) -> Self {
        Self(core: .typeText(TypeTextTarget(reference: reference, mode: mode, target: target)))
    }
    public static func mechanicalTap(_ target: TapTarget) -> Self { Self(core: .mechanicalTap(target)) }
    public static func mechanicalLongPress(_ target: LongPressTarget) -> Self {
        Self(core: .mechanicalLongPress(target))
    }
    public static func mechanicalSwipe(_ target: SwipeTarget) -> Self { Self(core: .mechanicalSwipe(target)) }
    public static func mechanicalDrag(_ target: DragTarget) -> Self { Self(core: .mechanicalDrag(target)) }
    public static func viewportScroll(_ target: ScrollTarget) -> Self { Self(core: .viewportScroll(target)) }
    public static func viewportScrollToVisible(_ target: AccessibilityTarget) -> Self {
        Self(core: .viewportScrollToVisible(target))
    }
    public static func viewportScrollToEdge(_ target: ScrollToEdgeTarget) -> Self {
        Self(core: .viewportScrollToEdge(target))
    }
    public static func editAction(_ target: EditActionTarget) -> Self { Self(core: .editAction(target)) }
    public static func setPasteboard(_ target: SetPasteboardTarget) -> Self { Self(core: .setPasteboard(target)) }
    public static var takeScreenshot: Self { Self(core: .takeScreenshot) }
    public static var dismissKeyboard: Self { Self(core: .dismissKeyboard) }

    public var wireType: HeistActionCommandType { core.wireType }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedHeistActionCommand {
        try core.resolve(in: environment)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case type, payload }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist action command")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = HeistActionCommandType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "command \"\(typeString)\" is not a heist action command"
            )
        }
        let payloadDecoder = container.contains(.payload) ? try container.superDecoder(forKey: .payload) : nil
        func payload() throws -> Decoder {
            guard let payloadDecoder else {
                throw DecodingError.keyNotFound(
                    CodingKeys.payload,
                    .init(
                        codingPath: container.codingPath,
                        debugDescription: "Missing payload for heist action command type \(type.rawValue)"
                    )
                )
            }
            return payloadDecoder
        }
        switch type {
        case .activate: core = .activate(try TargetPayload(from: payload()).target)
        case .increment: core = .increment(try TargetPayload(from: payload()).target)
        case .decrement: core = .decrement(try TargetPayload(from: payload()).target)
        case .performCustomAction:
            let payload = try CustomActionPayload(from: payload())
            core = .customAction(name: payload.actionName, target: payload.target)
        case .rotor:
            let payload = try RotorPayload(from: payload())
            core = .rotor(selection: payload.selection, target: payload.target, direction: payload.direction)
        case .dismiss:
            try Self.rejectPayload(payloadDecoder, for: type)
            core = .dismiss
        case .magicTap:
            try Self.rejectPayload(payloadDecoder, for: type)
            core = .magicTap
        case .typeText:
            core = .typeText(try TypeTextTarget(from: payload()))
        case .oneFingerTap: core = .mechanicalTap(try TapTarget(from: payload()))
        case .longPress: core = .mechanicalLongPress(try LongPressTarget(from: payload()))
        case .swipe: core = .mechanicalSwipe(try SwipeTarget(from: payload()))
        case .drag: core = .mechanicalDrag(try DragTarget(from: payload()))
        case .scroll: core = .viewportScroll(try ScrollTarget(from: payload()))
        case .scrollToVisible: core = .viewportScrollToVisible(try TargetPayload(from: payload()).target)
        case .scrollToEdge: core = .viewportScrollToEdge(try ScrollToEdgeTarget(from: payload()))
        case .editAction: core = .editAction(try EditActionTarget(from: payload()))
        case .setPasteboard: core = .setPasteboard(try SetPasteboardTarget(from: payload()))
        case .takeScreenshot:
            try Self.rejectPayload(payloadDecoder, for: type)
            core = .takeScreenshot
        case .resignFirstResponder:
            try Self.rejectPayload(payloadDecoder, for: type)
            core = .dismissKeyboard
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wireType, forKey: .type)
        switch core {
        case .activate(let target), .increment(let target), .decrement(let target),
             .viewportScrollToVisible(let target):
            try TargetPayload(target: target).encode(to: container.superEncoder(forKey: .payload))
        case .customAction(let name, let target):
            try CustomActionPayload(actionName: name, target: target)
                .encode(to: container.superEncoder(forKey: .payload))
        case .rotor(let selection, let target, let direction):
            try RotorPayload(selection: selection, target: target, direction: direction)
                .encode(to: container.superEncoder(forKey: .payload))
        case .typeText(let target):
            try target.encode(to: container.superEncoder(forKey: .payload))
        case .mechanicalTap(let target): try target.encode(to: container.superEncoder(forKey: .payload))
        case .mechanicalLongPress(let target): try target.encode(to: container.superEncoder(forKey: .payload))
        case .mechanicalSwipe(let target): try target.encode(to: container.superEncoder(forKey: .payload))
        case .mechanicalDrag(let target): try target.encode(to: container.superEncoder(forKey: .payload))
        case .viewportScroll(let target): try target.encode(to: container.superEncoder(forKey: .payload))
        case .viewportScrollToEdge(let target): try target.encode(to: container.superEncoder(forKey: .payload))
        case .editAction(let target): try target.encode(to: container.superEncoder(forKey: .payload))
        case .setPasteboard(let target): try target.encode(to: container.superEncoder(forKey: .payload))
        case .dismiss, .magicTap, .takeScreenshot, .dismissKeyboard:
            break
        }
    }

    private static func rejectPayload(_ decoder: Decoder?, for type: HeistActionCommandType) throws {
        guard let decoder else { return }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "\(type.rawValue) must not include a payload"
        ))
    }
}

package extension HeistActionCommandCore {
    var wireType: HeistActionCommandType {
        switch self {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .customAction: return .performCustomAction
        case .rotor: return .rotor
        case .dismiss: return .dismiss
        case .magicTap: return .magicTap
        case .typeText: return .typeText
        case .mechanicalTap: return .oneFingerTap
        case .mechanicalLongPress: return .longPress
        case .mechanicalSwipe: return .swipe
        case .mechanicalDrag: return .drag
        case .viewportScroll: return .scroll
        case .viewportScrollToVisible: return .scrollToVisible
        case .viewportScrollToEdge: return .scrollToEdge
        case .editAction: return .editAction
        case .setPasteboard: return .setPasteboard
        case .takeScreenshot: return .takeScreenshot
        case .dismissKeyboard: return .resignFirstResponder
        }
    }

    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedHeistActionCommand {
        switch self {
        case .activate(let target): return .activate(try target.resolve(in: environment))
        case .increment(let target): return .increment(try target.resolve(in: environment))
        case .decrement(let target): return .decrement(try target.resolve(in: environment))
        case .customAction(let name, let target):
            return .customAction(name: name, target: try target.resolve(in: environment))
        case .rotor(let selection, let target, let direction):
            return .rotor(
                selection: selection,
                target: try target.resolve(in: environment),
                direction: direction
            )
        case .dismiss: return .dismiss
        case .magicTap: return .magicTap
        case .typeText(let payload):
            return .typeText(ResolvedTypeTextTarget(
                text: try payload.source.resolve(in: environment),
                target: try payload.target?.resolve(in: environment)
            ))
        case .mechanicalTap(let target):
            return .mechanicalTap(try target.resolve(in: environment))
        case .mechanicalLongPress(let target):
            return .mechanicalLongPress(try target.resolve(in: environment))
        case .mechanicalSwipe(let target):
            return .mechanicalSwipe(try target.resolve(in: environment))
        case .mechanicalDrag(let target):
            return .mechanicalDrag(try target.resolve(in: environment))
        case .viewportScroll(let target):
            return .viewportScroll(try target.resolve(in: environment))
        case .viewportScrollToVisible(let target):
            return .viewportScrollToVisible(try target.resolve(in: environment))
        case .viewportScrollToEdge(let target):
            return .viewportScrollToEdge(try target.resolve(in: environment))
        case .editAction(let target): return .editAction(target)
        case .setPasteboard(let target): return .setPasteboard(target)
        case .takeScreenshot: return .takeScreenshot
        case .dismissKeyboard: return .dismissKeyboard
        }
    }
}

package enum ResolvedHeistActionCommand: Sendable, Equatable {
    case activate(ResolvedAccessibilityTarget)
    case increment(ResolvedAccessibilityTarget)
    case decrement(ResolvedAccessibilityTarget)
    case customAction(name: CustomActionName, target: ResolvedAccessibilityTarget)
    case rotor(selection: RotorSelection, target: ResolvedAccessibilityTarget, direction: RotorDirection)
    case dismiss
    case magicTap
    case typeText(ResolvedTypeTextTarget)
    case mechanicalTap(ResolvedTapTarget)
    case mechanicalLongPress(ResolvedLongPressTarget)
    case mechanicalSwipe(ResolvedSwipeTarget)
    case mechanicalDrag(ResolvedDragTarget)
    case viewportScroll(ResolvedScrollTarget)
    case viewportScrollToVisible(ResolvedAccessibilityTarget)
    case viewportScrollToEdge(ResolvedScrollToEdgeTarget)
    case editAction(EditActionTarget)
    case setPasteboard(SetPasteboardTarget)
    case takeScreenshot
    case dismissKeyboard
}

package struct ResolvedTypeTextTarget: Sendable, Equatable {
    package let text: TextInputText
    package let target: ResolvedAccessibilityTarget?
}

package enum ResolvedGesturePointSelection: Sendable, Equatable {
    case element(ResolvedAccessibilityTarget)
    case elementUnitPoint(ResolvedAccessibilityTarget, UnitPoint)
    case coordinate(ScreenPoint)
}

package struct ResolvedTapTarget: Sendable, Equatable {
    package let selection: ResolvedGesturePointSelection
}

package struct ResolvedLongPressTarget: Sendable, Equatable {
    package let selection: ResolvedGesturePointSelection
    package let duration: GestureDuration
}

package enum ResolvedSwipeGestureSelection: Sendable, Equatable {
    case unitElement(ResolvedAccessibilityTarget, start: UnitPoint, end: UnitPoint)
    case elementDirection(ResolvedAccessibilityTarget, SwipeDirection)
    case pointToPoint(start: ScreenPoint, end: ScreenPoint)
    case pointDirection(start: ScreenPoint, direction: SwipeDirection)
}

package struct ResolvedSwipeTarget: Sendable, Equatable {
    package let selection: ResolvedSwipeGestureSelection
    package let duration: GestureDuration?
}

package enum ResolvedDragGestureSelection: Sendable, Equatable {
    case elementToPoint(ResolvedAccessibilityTarget, start: UnitPoint?, end: ScreenPoint)
    case pointToPoint(start: ScreenPoint, end: ScreenPoint)
}

package struct ResolvedDragTarget: Sendable, Equatable {
    package let selection: ResolvedDragGestureSelection
    package let duration: GestureDuration?
}

package enum ResolvedScrollContainerSelection: Sendable, Equatable {
    case visibleContainer
    case element(ResolvedAccessibilityTarget)
    case container(ContainerName)
}

package struct ResolvedScrollTarget: Sendable, Equatable {
    package let selection: ResolvedScrollContainerSelection
    package let direction: ScrollDirection
}

package struct ResolvedScrollToEdgeTarget: Sendable, Equatable {
    package let selection: ResolvedScrollContainerSelection
    package let edge: ScrollEdge
}

package extension GesturePointSelection {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedGesturePointSelection {
        switch self {
        case .element(let target):
            return .element(try target.resolve(in: environment))
        case .elementUnitPoint(let target, let point):
            return .elementUnitPoint(try target.resolve(in: environment), point)
        case .coordinate(let point):
            return .coordinate(point)
        }
    }
}

package extension TapTarget {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedTapTarget {
        ResolvedTapTarget(selection: try selection.resolve(in: environment))
    }
}

package extension LongPressTarget {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedLongPressTarget {
        ResolvedLongPressTarget(
            selection: try selection.resolve(in: environment),
            duration: duration
        )
    }
}

package extension SwipeTarget {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedSwipeTarget {
        let resolvedSelection: ResolvedSwipeGestureSelection
        switch selection {
        case .unitElement(let target, let start, let end):
            resolvedSelection = .unitElement(
                try target.resolve(in: environment),
                start: start,
                end: end
            )
        case .elementDirection(let target, let direction):
            resolvedSelection = .elementDirection(
                try target.resolve(in: environment),
                direction
            )
        case .pointToPoint(let start, let end):
            resolvedSelection = .pointToPoint(start: start, end: end)
        case .pointDirection(let start, let direction):
            resolvedSelection = .pointDirection(start: start, direction: direction)
        }
        return ResolvedSwipeTarget(selection: resolvedSelection, duration: duration)
    }
}

package extension DragTarget {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedDragTarget {
        let resolvedSelection: ResolvedDragGestureSelection
        switch selection {
        case .elementToPoint(let target, let start, let end):
            resolvedSelection = .elementToPoint(
                try target.resolve(in: environment),
                start: start,
                end: end
            )
        case .pointToPoint(let start, let end):
            resolvedSelection = .pointToPoint(start: start, end: end)
        }
        return ResolvedDragTarget(selection: resolvedSelection, duration: duration)
    }
}

package extension ScrollContainerSelection {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedScrollContainerSelection {
        switch self {
        case .visibleContainer:
            return .visibleContainer
        case .element(let target):
            return .element(try target.resolve(in: environment))
        case .container(let name):
            return .container(name)
        }
    }
}

package extension ScrollTarget {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedScrollTarget {
        ResolvedScrollTarget(
            selection: try selection.resolve(in: environment),
            direction: direction
        )
    }
}

package extension ScrollToEdgeTarget {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedScrollToEdgeTarget {
        ResolvedScrollToEdgeTarget(
            selection: try selection.resolve(in: environment),
            edge: edge
        )
    }
}

private struct TargetPayload: Codable, Sendable, Equatable {
    let target: AccessibilityTarget
    private enum CodingKeys: String, CodingKey, CaseIterable { case target }

    init(target: AccessibilityTarget) { self.target = target }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist action command payload")
        target = try decoder.container(keyedBy: CodingKeys.self).decode(AccessibilityTarget.self, forKey: .target)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
    }
}

private struct CustomActionPayload: Codable, Sendable, Equatable {
    let actionName: CustomActionName
    let target: AccessibilityTarget
    private enum CodingKeys: String, CodingKey, CaseIterable { case actionName, target }

    init(actionName: CustomActionName, target: AccessibilityTarget) {
        self.actionName = actionName
        self.target = target
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist action command payload")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actionName = try container.decode(CustomActionName.self, forKey: .actionName)
        target = try container.decode(AccessibilityTarget.self, forKey: .target)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionName, forKey: .actionName)
        try container.encode(target, forKey: .target)
    }
}

private struct RotorPayload: Codable, Sendable, Equatable {
    let selection: RotorSelection
    let target: AccessibilityTarget
    let direction: RotorDirection
    private enum CodingKeys: String, CodingKey, CaseIterable { case rotor, rotorIndex, direction, target }

    init(selection: RotorSelection, target: AccessibilityTarget, direction: RotorDirection) {
        self.selection = selection
        self.target = target
        self.direction = direction
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist action command payload")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selection = try RotorSelection.decode(
            name: container.decodeIfPresent(RotorName.self, forKey: .rotor),
            index: container.decodeIfPresent(Int.self, forKey: .rotorIndex),
            codingPath: container.codingPath
        )
        direction = try container.decodeIfPresent(RotorDirection.self, forKey: .direction) ?? .next
        target = try container.decode(AccessibilityTarget.self, forKey: .target)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try selection.encode(to: &container, nameKey: .rotor, indexKey: .rotorIndex)
        try container.encode(direction, forKey: .direction)
        try container.encode(target, forKey: .target)
    }
}
