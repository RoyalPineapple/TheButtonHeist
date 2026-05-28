import Foundation

import TheScore

private let evidenceTargetKeys: Set<String> = [
    "heistId", "label", "identifier", "value", "traits", "excludeTraits",
    "ordinal", "elementTarget",
]

extension HeistValue {
    static func encoded<T: Encodable>(_ value: T) -> HeistValue {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(HeistValue.self, from: data)
        } catch {
            return .object([
                "type": .string("encoding_failed"),
                "error": .string(String(describing: error)),
            ])
        }
    }
}

private extension Encodable {
    func heistEvidenceArguments(renaming renamedKeys: [String: String] = [:]) -> [String: HeistValue] {
        guard case .object(let encoded) = HeistValue.encoded(self) else { return [:] }
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

private struct AccessibilityEvidenceArguments: Encodable {
    let action: String?
    let count: Int?
}

extension TheFence.RequestEvidence {
    static func target(
        arguments: [String: HeistValue],
        elementTarget: ElementTarget?
    ) -> Self {
        Self(arguments: arguments, elementTarget: elementTarget)
    }
}

extension Encodable {
    func heistEvidenceArguments() -> [String: HeistValue] {
        heistEvidenceArguments(renaming: [:])
    }
}

extension TheFence.GesturePayload {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(
            arguments: heistEvidenceArguments,
            elementTarget: bookKeeperElementTarget,
            coordinateOnly: bookKeeperCoordinateOnly
        )
    }

    private var heistEvidenceArguments: [String: HeistValue] {
        switch self {
        case .oneFingerTap(let payload):
            return payload.target.heistEvidenceArguments(renaming: ["pointX": "x", "pointY": "y"])
        case .longPress(let payload):
            return payload.target.heistEvidenceArguments(renaming: ["pointX": "x", "pointY": "y"])
        case .swipe(let payload):
            return payload.target.heistEvidenceArguments()
        case .drag(let payload):
            return payload.target.heistEvidenceArguments()
        case .pinch(let payload):
            return payload.target.heistEvidenceArguments()
        case .rotate(let payload):
            return payload.target.heistEvidenceArguments()
        case .twoFingerTap(let payload):
            return payload.target.heistEvidenceArguments()
        case .drawPath(let payload):
            return payload.target.heistEvidenceArguments()
        case .drawBezier(let payload):
            return payload.target.heistEvidenceArguments()
        }
    }

    private var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .oneFingerTap(let payload):
            return payload.selection.elementTarget
        case .longPress(let payload):
            return payload.selection.elementTarget
        case .swipe(let payload):
            return payload.target.selection.bookKeeperElementTarget
        case .drag(let payload):
            return payload.target.start.elementTarget
        case .pinch(let payload):
            return payload.center.elementTarget
        case .rotate(let payload):
            return payload.center.elementTarget
        case .twoFingerTap(let payload):
            return payload.center.elementTarget
        case .drawPath, .drawBezier:
            return nil
        }
    }

    private var bookKeeperCoordinateOnly: Bool {
        switch self {
        case .oneFingerTap(let payload):
            return payload.selection.screenPoint != nil
        case .longPress(let payload):
            return payload.selection.screenPoint != nil
        case .swipe(let payload):
            return payload.target.selection.bookKeeperElementTarget == nil
        case .drag(let payload):
            return payload.target.start.elementTarget == nil
        case .pinch(let payload):
            return payload.center.elementTarget == nil
        case .rotate(let payload):
            return payload.center.elementTarget == nil
        case .twoFingerTap(let payload):
            return payload.center.elementTarget == nil
        case .drawPath, .drawBezier:
            return true
        }
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

extension TheFence.ScrollPayload {
    var requestEvidence: TheFence.RequestEvidence {
        TheFence.RequestEvidence(
            arguments: heistEvidenceArguments,
            elementTarget: bookKeeperElementTarget
        )
    }

    private var heistEvidenceArguments: [String: HeistValue] {
        switch self {
        case .scroll(let target):
            return target.heistEvidenceArguments()
        case .scrollToVisible:
            return [:]
        case .elementSearch(let target):
            return target.heistEvidenceArguments()
        case .scrollToEdge(let target):
            return target.heistEvidenceArguments()
        }
    }

    private var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .scroll(let target):
            return target.elementTarget
        case .scrollToVisible(let target):
            return target.elementTarget
        case .elementSearch(let target):
            return target.elementTarget
        case .scrollToEdge(let target):
            return target.elementTarget
        }
    }
}

extension TheFence.AccessibilityPayload {
    var requestEvidence: TheFence.RequestEvidence {
        switch self {
        case .activate(let target, let actionName, let count):
            return TheFence.RequestEvidence(
                arguments: AccessibilityEvidenceArguments(action: actionName, count: count.value)
                    .heistEvidenceArguments(),
                elementTarget: target
            )
        }
    }
}
