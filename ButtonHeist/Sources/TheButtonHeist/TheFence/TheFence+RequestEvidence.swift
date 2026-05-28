import Foundation

import TheScore

private let evidenceTargetKeys: Set<String> = [
    "heistId", "label", "identifier", "value", "traits", "excludeTraits",
    "ordinal", "elementTarget",
]

extension HeistValue {
    static func encoded<T: Encodable>(_ value: T) throws -> HeistValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(HeistValue.self, from: data)
    }
}

private extension Encodable {
    func heistEvidenceArguments(renaming renamedKeys: [String: String] = [:]) throws -> [String: HeistValue] {
        guard case .object(let encoded) = try HeistValue.encoded(self) else {
            throw DecodingError.typeMismatch(
                [String: HeistValue].self,
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Heist evidence projection must encode \(Self.self) as an object"
                )
            )
        }
        var arguments = encoded.reduce(into: [String: HeistValue]()) { result, pair in
            guard !evidenceTargetKeys.contains(pair.key) else { return }
            result[renamedKeys[pair.key] ?? pair.key] = pair.value
        }
        arguments.flattenRotorTextRange()
        return arguments
    }
}

private extension Dictionary where Key == String, Value == HeistValue {
    mutating func flattenRotorTextRange() {
        guard case .object(let textRange)? = removeValue(forKey: "currentTextRange") else { return }
        if let startOffset = textRange["startOffset"] {
            self["currentTextStartOffset"] = startOffset
        }
        if let endOffset = textRange["endOffset"] {
            self["currentTextEndOffset"] = endOffset
        }
    }
}

private struct ActivateEvidenceArguments: Encodable {
    let action: String?
    let count: Int?
}

private struct HeistRecordingProjection {
    let arguments: [String: HeistValue]
    let elementTarget: ElementTarget?
    let coordinateOnly: Bool

    static let empty = HeistRecordingProjection(arguments: [:])

    static func target(
        arguments: [String: HeistValue] = [:],
        elementTarget: ElementTarget?,
        coordinateOnly: Bool = false
    ) -> Self {
        Self(arguments: arguments, elementTarget: elementTarget, coordinateOnly: coordinateOnly)
    }

    init(
        arguments: [String: HeistValue] = [:],
        elementTarget: ElementTarget? = nil,
        coordinateOnly: Bool = false
    ) {
        self.arguments = arguments
        self.elementTarget = elementTarget
        self.coordinateOnly = coordinateOnly
    }
}

extension TheFence.ParsedRequest {
    func heistRecordingElementTarget() throws -> ElementTarget? {
        try heistRecordingProjection().elementTarget
    }

    func heistRecordingCoordinateOnly() throws -> Bool {
        try heistRecordingProjection().coordinateOnly
    }

    func heistRecordingArguments() throws -> [String: HeistValue] {
        try heistRecordingProjection().arguments
    }

    private func heistRecordingProjection() throws -> HeistRecordingProjection {
        guard let messages = executableMessages else { return .empty }
        guard command == .activate else {
            return try messages.first?.heistRecordingProjection() ?? .empty
        }
        return try .activate(messages)
    }
}

private extension HeistRecordingProjection {
    static func activate(_ messages: [ClientMessage]) throws -> HeistRecordingProjection {
        guard let first = messages.first else { return .empty }
        switch first {
        case .activate(let target):
            return .target(elementTarget: target)
        case .increment(let target):
            return .target(
                arguments: try ActivateEvidenceArguments(
                    action: ElementAction.increment.description,
                    count: messages.count > 1 ? messages.count : nil
                ).heistEvidenceArguments(),
                elementTarget: target
            )
        case .decrement(let target):
            return .target(
                arguments: try ActivateEvidenceArguments(
                    action: ElementAction.decrement.description,
                    count: messages.count > 1 ? messages.count : nil
                ).heistEvidenceArguments(),
                elementTarget: target
            )
        case .performCustomAction(let target):
            return .target(
                arguments: try ActivateEvidenceArguments(action: target.actionName, count: nil)
                    .heistEvidenceArguments(),
                elementTarget: target.elementTarget
            )
        default:
            return try first.heistRecordingProjection()
        }
    }
}

private extension ClientMessage {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        switch self {
        case .activate(let target), .increment(let target), .decrement(let target):
            return .target(elementTarget: target)
        case .performCustomAction(let target):
            return .target(
                arguments: try target.heistEvidenceArguments(),
                elementTarget: target.elementTarget
            )
        case .rotor(let target):
            return try .target(arguments: target.heistEvidenceArguments(), elementTarget: target.elementTarget)
        case .typeText(let target):
            return try .target(arguments: target.heistEvidenceArguments(), elementTarget: target.elementTarget)
        case .editAction(let target):
            return try HeistRecordingProjection(arguments: target.heistEvidenceArguments())
        case .setPasteboard(let target):
            return try HeistRecordingProjection(arguments: target.heistEvidenceArguments())
        case .oneFingerTap(let target):
            return try target.heistRecordingProjection()
        case .longPress(let target):
            return try target.heistRecordingProjection()
        case .swipe(let target):
            return try target.heistRecordingProjection()
        case .drag(let target):
            return try target.heistRecordingProjection()
        case .pinch(let target):
            return try target.heistRecordingProjection()
        case .rotate(let target):
            return try target.heistRecordingProjection()
        case .twoFingerTap(let target):
            return try target.heistRecordingProjection()
        case .drawPath(let target):
            return try HeistRecordingProjection(arguments: target.heistEvidenceArguments(), coordinateOnly: true)
        case .drawBezier(let target):
            return try HeistRecordingProjection(arguments: target.heistEvidenceArguments(), coordinateOnly: true)
        case .scroll(let target):
            return try .target(arguments: target.heistEvidenceArguments(), elementTarget: target.elementTarget)
        case .scrollToVisible(let target):
            return .target(elementTarget: target.elementTarget)
        case .elementSearch(let target):
            return try .target(arguments: target.heistEvidenceArguments(), elementTarget: target.elementTarget)
        case .scrollToEdge(let target):
            return try .target(arguments: target.heistEvidenceArguments(), elementTarget: target.elementTarget)
        case .waitFor(let target):
            return try .target(arguments: target.heistEvidenceArguments(), elementTarget: target.elementTarget)
        case .waitForChange(let target):
            return try HeistRecordingProjection(arguments: target.heistEvidenceArguments())
        default:
            return .empty
        }
    }
}

private extension TapTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(renaming: ["pointX": "x", "pointY": "y"]),
            elementTarget: selection.elementTarget,
            coordinateOnly: selection.screenPoint != nil
        )
    }
}

private extension LongPressTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(renaming: ["pointX": "x", "pointY": "y"]),
            elementTarget: selection.elementTarget,
            coordinateOnly: selection.screenPoint != nil
        )
    }
}

private extension SwipeTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(),
            elementTarget: selection.bookKeeperElementTarget,
            coordinateOnly: selection.bookKeeperElementTarget == nil
        )
    }
}

private extension DragTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(),
            elementTarget: start.elementTarget,
            coordinateOnly: start.elementTarget == nil
        )
    }
}

private extension PinchTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(),
            elementTarget: center.elementTarget,
            coordinateOnly: center.elementTarget == nil
        )
    }
}

private extension RotateTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(),
            elementTarget: center.elementTarget,
            coordinateOnly: center.elementTarget == nil
        )
    }
}

private extension TwoFingerTapTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(),
            elementTarget: center.elementTarget,
            coordinateOnly: center.elementTarget == nil
        )
    }
}

private extension SwipeGestureSelection {
    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .unitElement(let target, _, _, _):
            return target
        case .point(let start, _):
            return start.elementTarget
        }
    }
}
